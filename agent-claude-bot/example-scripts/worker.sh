#!/bin/bash
# worker.sh — Sequential pipeline: each step is a fresh claude -p call
# Usage: bash worker.sh <project_dir> <worker_id> [task_description]

set -euo pipefail

# shellcheck disable=SC1091
# Self-source config.sh — workers spawn in tmux windows that may not inherit
# env from the orchestrator (existing tmux server case).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

PROJECT_DIR="${1:?Usage: worker.sh <project_dir> <worker_id> [task_description]}"
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
STATUS_COL=$(python3 -c "import json; print(json.load(open('${PROJECT_DIR}/.tmp/claude-bot/_col_cache.json')).get('Status',''))" 2>/dev/null || echo "")

pm_set_status() {
  local new_status="$1"
  [ -z "$ROW_NUMBER" ] || [ -z "$TABLE_ID" ] && return
  local cur
  cur=$(curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows?limit=500&sort=asc" \
    -H "Authorization: Bearer claude" | \
    python3 -c "import sys,json; rows=json.load(sys.stdin); r=next((r for r in rows if r['row_id']==${ROW_NUMBER}),None); print(json.dumps(r['row_data']) if r else '{}')" 2>/dev/null)
  local updated
  updated=$(echo "$cur" | python3 -c "import sys,json; d=json.load(sys.stdin); d['${STATUS_COL}']='${new_status}'; print(json.dumps(d))")
  curl -s -X PUT "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${ROW_NUMBER}" \
    -H "Authorization: Bearer claude" -H "Content-Type: application/json" \
    -d "{\"row_data\": ${updated}}" > /dev/null
  log "Status → ${new_status} (row ${ROW_NUMBER})"
}

pm_read_doc() {
  [ -z "$ROW_NUMBER" ] || [ -z "$TABLE_ID" ] && return
  curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${ROW_NUMBER}/doc" \
    -H "Authorization: Bearer claude" 2>/dev/null || echo ""
}

pm_append_doc() {
  local msg="$1"
  [ -z "$ROW_NUMBER" ] || [ -z "$TABLE_ID" ] && return
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local current
  current=$(curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${ROW_NUMBER}/doc" \
    -H "Authorization: Bearer claude" 2>/dev/null || echo "")
  local updated="${current}
- ${ts} ${msg}"
  curl -s -X PUT "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${ROW_NUMBER}/doc" \
    -H "Authorization: Bearer claude" -H "Content-Type: text/plain" \
    --data-raw "$updated" > /dev/null
}

step() {
  local step_name="$1"
  local prompt="$2"
  log "Step: ${step_name}..."
  # stream-json + verbose = live event stream (thinking, tool_use,
  # tool_result, final result). format_claude_stream.py renders each
  # event as one human-readable line so `tmux attach` shows progress
  # in real time instead of waiting for the final blob.
  #
  # Watchdog: claude -p has been observed to hang silently after a few
  # minutes (Agent/Explore sub-agent stall or API hangup that doesn't
  # surface in the pipe). Sample the log file every 30s; kill the
  # process if it hasn't grown for 120s. ERR trap then flips the row
  # to `debugging` and the orchestrator advances — trading 120s
  # detection for 780s of otherwise-wasted budget.
  CLAUDECODE= claude -p \
    --dangerously-skip-permissions \
    --model sonnet \
    --output-format=stream-json --verbose \
    "${prompt}" 2>&1 \
  | python3 -u "${SCRIPT_DIR}/format_claude_stream.py" \
  | tee -a "$LOG_FILE" &
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
          log "Watchdog: no log growth for 120s — killing claude -p"
          pkill -TERM -P $$ -f "claude -p" 2>/dev/null || true
          sleep 2
          pkill -KILL -P $$ -f "claude -p" 2>/dev/null || true
          break
        fi
      else
        last=$cur
        stuck=0
      fi
    done
  ) &
  local watchdog_pid=$!

  wait "$pipe_pid" 2>/dev/null
  kill "$watchdog_pid" 2>/dev/null || true
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
ROW_NUMBER=$(echo "$TASK_DESC" | grep -oP 'row_id=\K[0-9]+' || echo "")
PARENT_RN=$(echo "$TASK_DESC" | grep -oP 'parent=\K[0-9]+' || echo "")

if [ -z "$ROW_NUMBER" ]; then
  log "ERROR: No row_id in task desc"
  echo "BLOCKED" > "$TRIGGER_FILE"
  exit 1
fi

# ─── Phase 3: Set in_progress IMMEDIATELY (bash, not LLM) ──────────────────
pm_set_status "in_progress"
pm_append_doc "Picked up by W${WORKER_ID}"

# ─── Phase 4: Build context ─────────────────────────────────────────────────
CONTEXT=""

for f in CLAUDE.md README.md; do
  [ -f "${PROJECT_DIR}/${f}" ] && CONTEXT="${CONTEXT}
--- ${f} ---
$(head -200 "${PROJECT_DIR}/${f}")
"
done

# Only load programming skill — NOT project-management (PM API docs cause LLM to create junk rows)
for skill in developing-programming/developing.md; do
  # NB: find | head -1 SIGPIPEs find when head closes the pipe → with `set -euo pipefail`
  # + `trap ERR` the worker dies in clean phase before any code runs. Use -print -quit.
  sf="$(find "${PROJECT_DIR}/.claude/skills" -path "*/${skill}" -print -quit 2>/dev/null || true)"
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
- Commit message: <type>-${ROW_NUMBER}: <short description> (e.g. task-42: add feature)"

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
TYPE_COL=$(python3 -c "import json; print(json.load(open('${PROJECT_DIR}/.tmp/claude-bot/_col_cache.json')).get('Type',''))" 2>/dev/null || echo "")
TICKET_TYPE=$(curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows?limit=500&sort=asc" \
  -H "Authorization: Bearer claude" | \
  python3 -c "import sys,json; rows=json.load(sys.stdin); r=next((r for r in rows if r['row_id']==${ROW_NUMBER}),None); print(r['row_data'].get('${TYPE_COL}','task') if r else 'task')" 2>/dev/null || echo "task")

git add -A 2>/dev/null || true
git reset HEAD .tmp/ 2>/dev/null || true

if git diff --cached --quiet; then
  log "No changes to commit"
  pm_append_doc "No changes needed"
else
  git commit -m "${TICKET_TYPE}-${ROW_NUMBER}: ${TICKET_TITLE}"
  log "Committed ${TICKET_TYPE}-${ROW_NUMBER}"
  pm_append_doc "Committed ${TICKET_TYPE}-${ROW_NUMBER}"
fi

rmdir "$GIT_LOCK" 2>/dev/null || true

# Step 4: Mark done
pm_set_status "done"
pm_append_doc "W${WORKER_ID} finished"

# ─── Signal done ─────────────────────────────────────────────────────────────
# PM status already set to done — orchestrator will detect via poll
log "W${WORKER_ID} finished: DONE"
