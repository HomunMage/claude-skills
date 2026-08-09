#!/bin/bash
# bee.sh — Sequential pipeline: each step is a fresh provider-neutral work() call
# Usage: bash bee.sh <project_dir> <worker_id> [task_description]

set -euo pipefail

# shellcheck disable=SC1091
# Self-source config.sh — bees spawn in tmux windows that may not inherit
# env from the queen (existing tmux server case).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/worker.sh"

PROJECT_DIR="${1:?Usage: bee.sh <project_dir> <worker_id> [task_description]}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
WORKER_ID="${2:?Worker ID required}"
TASK_DESC="${3:-}"
# row_id is parsed out of TASK_DESC below (`row_id=NN`) so each ticket
# gets its own log file: worker_<wid>_<row_id>.log. Easier to triage a
# specific failure than scrolling through a shared worker_<wid>.log.
ROW_ID=$(echo "$TASK_DESC" | grep -oP 'row_id=\K[0-9]+' || echo "0")
LOG_FILE="${PROJECT_DIR}/.tmp/out/worker_${WORKER_ID}_${ROW_ID}.log"
GIT_LOCK="${PROJECT_DIR}/_git.lock"
PM_URL="${LC_API%/api/v1}"
TABLE_ID="${TABLE_ID:-}"

mkdir -p "${PROJECT_DIR}/.tmp/out"

log() {
  echo "$(date '+%H:%M:%S') [W${WORKER_ID}] $1" | tee -a "$LOG_FILE"
}

# ─── PM helpers (pure bash, no LLM) ─────────────────────────────────────────
STATUS_COL=$(python3 -c "import json; print(json.load(open('${PROJECT_DIR}/.tmp/agentic-hive/_col_cache.json')).get('Status',''))" 2>/dev/null || echo "")

pm_set_status() {
  local new_status="$1"
  [ -z "$ROW_ID" ] || [ -z "$TABLE_ID" ] && return
  local cur
  cur=$(curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${ROW_ID}" \
    -H "$LC_AUTH_HEADER" | \
    python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['row_data']))" 2>/dev/null)
  local updated
  updated=$(echo "$cur" | python3 -c "import sys,json; d=json.load(sys.stdin); d['${STATUS_COL}']='${new_status}'; print(json.dumps(d))")
  curl -s -X PUT "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${ROW_ID}" \
    -H "$LC_AUTH_HEADER" -H "Content-Type: application/json" \
    -d "{\"row_data\": ${updated}}" > /dev/null
  log "Status → ${new_status} (row ${ROW_ID})"
}

pm_read_doc() {
  [ -z "$ROW_ID" ] || [ -z "$TABLE_ID" ] && return
  curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${ROW_ID}/doc" \
    -H "$LC_AUTH_HEADER" 2>/dev/null || echo ""
}

pm_append_doc() {
  local msg="$1"
  [ -z "$ROW_ID" ] || [ -z "$TABLE_ID" ] && return
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local current
  current=$(curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${ROW_ID}/doc" \
    -H "$LC_AUTH_HEADER" 2>/dev/null || echo "")
  local updated="${current}
- ${ts} ${msg}"
  curl -s -X PUT "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${ROW_ID}/doc" \
    -H "$LC_AUTH_HEADER" -H "Content-Type: text/plain" \
    --data-raw "$updated" > /dev/null
}

step() {
  local step_name="$1"
  local prompt="$2"
  log "Step: ${step_name}..."
  # work() (worker.sh) delegates to llm.sh, which streams progress from the
  # configured LLM_PROVIDER into $LOG_FILE. Provider changes do not touch
  # this orchestration layer.
  #
  # Watchdog: the backend has been observed to hang silently after a few
  # minutes (Agent/Explore sub-agent stall or API hangup that doesn't
  # surface in the pipe). Sample the log file every 30s; kill the
  # process if it hasn't grown for 120s. ERR trap then flips the row
  # to `debugging` and the queen advances — trading 120s detection for
  # 780s of otherwise-wasted budget.
  work "${prompt}" "$LOG_FILE" &
  local pipe_pid=$!

  (
    local last=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    local stuck=0
    while kill -0 "$pipe_pid" 2>/dev/null; do
      sleep 30
      local cur=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
      if [ "$cur" -eq "$last" ]; then
        stuck=$((stuck + 30))
        if [ "$stuck" -ge 120 ]; then
          log "Watchdog: no log growth for 120s — killing ${LLM_PROVIDER} provider"
          work_stop "$pipe_pid" TERM
          sleep 2
          work_stop "$pipe_pid" KILL
          break
        fi
      else
        last=$cur
        stuck=0
      fi
    done
  ) &
  local watchdog_pid=$!

  local work_status=0
  wait "$pipe_pid" 2>/dev/null || work_status=$?
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  return "$work_status"
}

# If any step fails, signal BLOCKED and exit
trap 'log "Pipeline failed."; pm_set_status "debugging"; pm_append_doc "W${WORKER_ID} BLOCKED — pipeline failed"; exit 1' ERR

log "Worker ${WORKER_ID} starting..."
[ -n "$TASK_DESC" ] && log "Task: ${TASK_DESC}"

# ─── Phase 1: Clean ─────────────────────────────────────────────────────────
log "Cleaning working tree..."
cd "$PROJECT_DIR" || exit 1

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  git reset --hard HEAD 2>&1 | tee -a "$LOG_FILE"
  git clean -fd 2>&1 | tee -a "$LOG_FILE"
  log "Clean slate restored."
fi

# ─── Phase 2: Extract row_id from task desc ─────────────────────────────
ROW_ID=$(echo "$TASK_DESC" | grep -oP 'row_id=\K[0-9]+' || echo "")
PARENT_RN=$(echo "$TASK_DESC" | grep -oP 'parent=\K[0-9]+' || echo "")

if [ -z "$ROW_ID" ]; then
  log "ERROR: No row_id in task desc"
  echo "BLOCKED" > "$TRIGGER_FILE"
  exit 1
fi

# ─── Phase 3: Set in_progress IMMEDIATELY (bash, not LLM) ──────────────────
pm_set_status "in_progress"
pm_append_doc "Picked up by W${WORKER_ID}"

# ─── Phase 4: Build context ─────────────────────────────────────────────────
CONTEXT=""

for f in AGENTS.md CLAUDE.md README.md; do
  [ -f "${PROJECT_DIR}/${f}" ] && CONTEXT="${CONTEXT}
--- ${f} ---
$(head -200 "${PROJECT_DIR}/${f}")
"
done

# Only load programming skill — NOT project-management (PM API docs cause LLM to create junk rows)
for skill in developing/programming/developing.md; do
  # NB: find | head -1 SIGPIPEs find when head closes the pipe → with `set -euo pipefail`
  # + `trap ERR` the worker dies in clean phase before any code runs. Use -print -quit.
  sf="$(find "${PROJECT_DIR}/.agent-skills" -path "*/${skill}" -print -quit 2>/dev/null || true)"
  [ -n "$sf" ] && CONTEXT="${CONTEXT}
--- Skill: $(basename $(dirname "$sf")) ---
$(cat "$sf")
"
done

for f in "${PROJECT_DIR}"/.tmp/llm*.md; do
  [ -f "$f" ] || continue
  CONTEXT="${CONTEXT}
--- $(basename "$f") ---
$(head -200 "$f")
"
done

# Read ticket doc FIRST — doc has all implementation detail, title is just a summary
TICKET_DOC=$(pm_read_doc)
log "Doc length: ${#TICKET_DOC} chars"

SHARED="You are Worker ${WORKER_ID}. Dir: ${PROJECT_DIR}

${CONTEXT}

TICKET DOC:
${TICKET_DOC}

TASK: ${TASK_DESC}

RULES:
- ONLY write application code. Do NOT run curl commands to any API or service.
- Status updates are handled by the bash wrapper — never update ticket status yourself.
- Focus ONLY on reading code and implementing the ticket.
- Commit message: <type>-${ROW_ID}: <short description> (e.g. task-42: add feature)"

# ─── Pipeline ────────────────────────────────────────────────────────────────

# Step 1: Implement
step "implement" "${SHARED}

Read relevant source files, then implement the ticket.
Keep changes minimal. ONE ticket only. Follow existing patterns.
After each file change, log what you did."

pm_append_doc "Implementation step completed"

# Step 2: Test, format, lint
pm_set_status "testing"
pm_append_doc "Running tests"

step "test" "${SHARED}

Run tests:
1. Frontend: cd ${PROJECT_DIR}/frontend && npx svelte-check 2>&1 | head -50
2. Frontend: cd ${PROJECT_DIR}/frontend && npm run build 2>&1 | tail -30
3. Backend: python -c 'import ast; ast.parse(open(\"<file>\").read())' for each .py
4. Fix any errors found.
Do NOT commit yet."

pm_append_doc "Tests completed"

# Step 3: Commit + merge (bash, not LLM)
pm_set_status "review"

while ! mkdir "$GIT_LOCK" 2>/dev/null; do sleep 2; done

TICKET_TITLE=$(echo "$TASK_DESC" | sed 's/ (row_id=.*//' | cut -c1-72)
TYPE_COL=$(python3 -c "import json; print(json.load(open('${PROJECT_DIR}/.tmp/agentic-hive/_col_cache.json')).get('Type',''))" 2>/dev/null || echo "")
TICKET_TYPE=$(curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${ROW_ID}" \
  -H "$LC_AUTH_HEADER" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['row_data'].get('${TYPE_COL}','task'))" 2>/dev/null || echo "task")

git add -A 2>/dev/null || true
git reset HEAD .tmp/ 2>/dev/null || true

if git diff --cached --quiet; then
  log "No changes to commit"
  pm_append_doc "No changes needed"
else
  git commit -m "${TICKET_TYPE}-${ROW_ID}: ${TICKET_TITLE}"
  log "Committed ${TICKET_TYPE}-${ROW_ID}"
  pm_append_doc "Committed ${TICKET_TYPE}-${ROW_ID}"
fi

rmdir "$GIT_LOCK" 2>/dev/null || true

# Step 4: Mark merged
pm_set_status "merged"
pm_append_doc "W${WORKER_ID} finished"

# ─── Signal complete ─────────────────────────────────────────────────────────
# PM status already set to merged — orchestrator will detect via poll
log "W${WORKER_ID} finished: DONE"
