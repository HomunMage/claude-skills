#!/bin/bash
# bee.sh — Sequential pipeline: each step is a fresh llm_run() call
# Usage: bash bee.sh <project_dir> <worker_id> [task_description]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
if [ -f "${ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi
source "${SCRIPT_DIR}/llm.sh"

PROJECT_DIR="${1:?Usage: bee.sh <project_dir> <worker_id> [task_description]}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
REPO_ROOT="$(git -C "${PROJECT_DIR}" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${PROJECT_DIR}")"
export SKILLS_DIR="${SKILLS_DIR:-${REPO_ROOT}/.agent-skills}"
export LLM_PROVIDER="${LLM_PROVIDER:-${LLM_BACKEND:-claude}}"
# The queen passes the persistent story worktree, never the repository root.
# Keep provider commands in that same worktree so each ticket sees every prior
# commit for its story.
export LLM_PROJECT_DIR="${LLM_PROJECT_DIR:-$PROJECT_DIR}"
source "${SKILLS_DIR}/developing/project-management/pm_tool.sh"
WORKER_ID="${2:?Worker ID required}"
TASK_DESC="${3:-}"
PM_USER="${PM_USER:-claude}"
PM_PASS="${PM_PASS:-}"
# row_id is parsed out of TASK_DESC below (`row_id=NN`) so each ticket
# gets its own log file: worker_<wid>_<row_id>.log. Easier to triage a
# specific failure than scrolling through a shared worker_<wid>.log.
ROW_ID=$(echo "$TASK_DESC" | grep -oP 'row_id=\K[0-9]+' || echo "0")
LOG_FILE="${PROJECT_DIR}/.tmp/out/worker_${WORKER_ID}_${ROW_ID}.log"
GIT_LOCK="${PROJECT_DIR}/_git.lock"

mkdir -p "${PROJECT_DIR}/.tmp/out"

log() {
  echo "$(date '+%H:%M:%S') [W${WORKER_ID}] $1" | tee -a "$LOG_FILE"
}

step() {
  local step_name="$1"
  local prompt="$2"
  log "Step: ${step_name}..."
  # llm_run() streams progress from the configured LLM_PROVIDER into
  # $LOG_FILE. Provider changes stay inside llm.sh.
  #
  # Watchdog: the backend has been observed to hang silently after a few
  # minutes (Agent/Explore sub-agent stall or API hangup that doesn't
  # surface in the pipe). Sample the log file every 30s; kill the
  # process if it hasn't grown for 120s. ERR trap then flips the row
  # to `debugging` and the queen advances — trading 120s detection for
  # 780s of otherwise-wasted budget.
  llm_run "${prompt}" "$LOG_FILE" &
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
          llm_stop "$pipe_pid" TERM
          sleep 2
          llm_stop "$pipe_pid" KILL
          break
        fi
      else
        last=$cur
        stuck=0
      fi
    done
  ) &
  local watchdog_pid=$!

  local llm_status=0
  wait "$pipe_pid" 2>/dev/null || llm_status=$?
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  return "$llm_status"
}

# If any step fails, signal BLOCKED and exit
trap 'log "Pipeline failed."; pm_set_status "${ROW_ID}" "debugging"; pm_append_doc "${ROW_ID}" "W${WORKER_ID} BLOCKED — pipeline failed"; exit 1' ERR

log "Worker ${WORKER_ID} starting..."
[ -n "$TASK_DESC" ] && log "Task: ${TASK_DESC}"

# ─── Phase 1: Extract row_id from task desc ────────────────────────────────
cd "$PROJECT_DIR" || exit 1
ROW_ID=$(echo "$TASK_DESC" | grep -oP 'row_id=\K[0-9]+' || echo "")

if [ -z "$ROW_ID" ]; then
  log "ERROR: No row_id in task desc"
  echo "BLOCKED" > "$TRIGGER_FILE"
  exit 1
fi

# ─── Phase 2: Rule-based PM context gate (before any worktree mutation) ────
# pm_tool.sh uses lc_api.sh's curl wrapper. It rejects an orphan issue, a
# non-story parent, or a ticket/story document missing the required design
# evidence. No LLM sees or compensates for an invalid ticket.
if ! PARENT_RN=$(pm_require_hive_context "${ROW_ID}"); then
  log "ERROR: invalid hive ticket context; refusing claim"
  pm_set_status "${ROW_ID}" "debugging"
  pm_append_doc "${ROW_ID}" "W${WORKER_ID} BLOCKED — missing verified story parent or required planning context"
  exit 1
fi
EXPECTED_STORY_BRANCH="story/story-${PARENT_RN}"
if [ "$(git branch --show-current)" != "$EXPECTED_STORY_BRANCH" ]; then
  log "ERROR: verified parent requires ${EXPECTED_STORY_BRANCH} story worktree"
  pm_set_status "${ROW_ID}" "debugging"
  exit 1
fi
TICKET_DOC=$(pm_read_ticket_doc "${ROW_ID}")
STORY_DOC=$(pm_read_ticket_doc "${PARENT_RN}")
log "Issue ${ROW_ID} and parent story ${PARENT_RN} docs verified"

# ─── Phase 3: Clean only after verified scope + dependency ──────────────────
log "Cleaning verified story worktree..."
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  git reset --hard HEAD 2>&1 | tee -a "$LOG_FILE"
  git clean -fd 2>&1 | tee -a "$LOG_FILE"
  log "Clean slate restored."
fi

# ─── Phase 4: Claim, then build context ─────────────────────────────────────
pm_set_status "${ROW_ID}" "in_progress"
pm_append_doc "${ROW_ID}" "Picked up by W${WORKER_ID}; issue and parent story ${PARENT_RN} context verified"

CONTEXT=""

for f in AGENT.md AGENTS.md CLAUDE.md README.md; do
  [ -f "${PROJECT_DIR}/${f}" ] && CONTEXT="${CONTEXT}
--- ${f} ---
$(head -200 "${PROJECT_DIR}/${f}")
"
done

# Skill gate: skills are loaded into the first provider prompt before the bee
# is allowed to inspect application code.  A ticket's doc determines the
# additional specialist skills; the complete skill folder is included so the
# worker reads its references, not only the SKILL.md heading.
read_skill_first() {
  # Split these assignments: with set -u, Bash expands skill_dir before
  # the same local command assigns skill.
  local skill="$1"
  local skill_dir="${SKILLS_DIR}/${skill}"
  [ -d "$skill_dir" ] || { log "ERROR: required skill missing: ${skill}"; exit 1; }
  CONTEXT="${CONTEXT}
===== REQUIRED SKILL FIRST: ${skill} ====="
  while IFS= read -r -d '' file; do
    CONTEXT="${CONTEXT}
--- ${file#${SKILLS_DIR}/} ---
$(cat "$file")"
  done < <(find "$skill_dir" -type f \( -name '*.md' -o -name '*.sh' \) -print0 | sort -z)
}

# Every implementation worker reads these before any repository source.
read_skill_first "agent/agentic-hive"
read_skill_first "developing/programming"
read_skill_first "developing/project-management"

# Add the specialist rule set before implementation whenever the ticket scope
# names that surface. The task doc is the authoritative specification.
scope_text="${TASK_DESC} ${TICKET_DOC}"
case "${scope_text,,}" in
  *frontend*|*svelte*|*.svelte*|*.ts*) read_skill_first "developing/svelte" ;;
esac
case "${scope_text,,}" in
  *backend*|*fastapi*|*.py*) read_skill_first "developing/fastapi" ;;
esac
case "${scope_text,,}" in
  *migration*|*postgres*|*sql*) read_skill_first "developing/db-sql" ;;
esac
case "${scope_text,,}" in
  *e2e*|*playwright*|*snapshot*) read_skill_first "developing/e2e" ;;
esac

for f in "${PROJECT_DIR}"/.tmp/llm*.md; do
  [ -f "$f" ] || continue
  CONTEXT="${CONTEXT}
--- $(basename "$f") ---
$(head -200 "$f")
"
done

SHARED="You are Worker ${WORKER_ID}. Dir: ${PROJECT_DIR}

${CONTEXT}

TICKET DOC:
${TICKET_DOC}

PARENT STORY DOC:
${STORY_DOC}

TASK: ${TASK_DESC}

RULES:
- REQUIRED SKILLS ABOVE ARE FIRST. Read every supplied skill section before
  reading or editing repository source; do not begin implementation otherwise.
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

pm_append_doc "${ROW_ID}" "Implementation step completed"

# Step 2: Test, format, lint
pm_set_status "${ROW_ID}" "testing"
pm_append_doc "${ROW_ID}" "Running tests"

step "test" "${SHARED}

Run tests:
1. Frontend: cd ${PROJECT_DIR}/frontend && npx svelte-check 2>&1 | head -50
2. Frontend: cd ${PROJECT_DIR}/frontend && npm run build 2>&1 | tail -30
3. Backend: python -c 'import ast; ast.parse(open(\"<file>\").read())' for each .py
4. Fix any errors found.
Do NOT commit yet."

pm_append_doc "${ROW_ID}" "Tests completed"

# Step 3: Commit + merge (bash, not LLM)
pm_set_status "${ROW_ID}" "review"

while ! mkdir "$GIT_LOCK" 2>/dev/null; do sleep 2; done

TICKET_TITLE=$(echo "$TASK_DESC" | sed 's/ (row_id=.*//' | cut -c1-72)
TYPE_COL=$(python3 -c "import json; print(json.load(open('${PROJECT_DIR}/.tmp/agentic-hive/_col_cache.json')).get('Type',''))" 2>/dev/null || echo "")
TICKET_TYPE=$(pm_row_type "${ROW_ID}" 2>/dev/null || echo "task")

git add -A 2>/dev/null || true
git reset HEAD .tmp/ 2>/dev/null || true

if git diff --cached --quiet; then
  log "No changes to commit"
  pm_append_doc "${ROW_ID}" "No changes needed"
else
  git commit -m "${TICKET_TYPE}-${ROW_ID}: ${TICKET_TITLE}"
  log "Committed ${TICKET_TYPE}-${ROW_ID}"
  pm_append_doc "${ROW_ID}" "Committed ${TICKET_TYPE}-${ROW_ID}"
fi

rmdir "$GIT_LOCK" 2>/dev/null || true

# Step 4: Mark merged
pm_set_status "${ROW_ID}" "merged"
pm_append_doc "${ROW_ID}" "W${WORKER_ID} finished"

# ─── Signal complete ─────────────────────────────────────────────────────────
# PM status already set to merged — orchestrator will detect via poll
log "W${WORKER_ID} finished: DONE"
