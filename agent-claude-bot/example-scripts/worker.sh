#!/bin/bash
# worker.sh — Sequential pipeline: each step is a fresh claude -p call
# Usage: bash worker.sh <project_dir> <worker_id> [task_description]

set -euo pipefail

PROJECT_DIR="${1:?Usage: worker.sh <project_dir> <worker_id> [task_description]}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
WORKER_ID="${2:?Worker ID required}"
TASK_DESC="${3:-}"
TRIGGER_FILE="${PROJECT_DIR}/_trigger_${WORKER_ID}"
LOG_FILE="${PROJECT_DIR}/.tmp/out/worker_${WORKER_ID}.log"
GIT_LOCK="${PROJECT_DIR}/_git.lock"
PM_URL="http://localhost:13491"
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
  cur=$(curl -s "${PM_URL}/api/tables/${TABLE_ID}/rows?limit=500&sort=asc" \
    -H "Authorization: Bearer claude" | \
    python3 -c "import sys,json; rows=json.load(sys.stdin); r=next((r for r in rows if r['row_number']==${ROW_NUMBER}),None); print(json.dumps(r['row_data']) if r else '{}')" 2>/dev/null)
  local updated
  updated=$(echo "$cur" | python3 -c "import sys,json; d=json.load(sys.stdin); d['${STATUS_COL}']='${new_status}'; print(json.dumps(d))")
  curl -s -X PUT "${PM_URL}/api/tables/${TABLE_ID}/rows/${ROW_NUMBER}" \
    -H "Authorization: Bearer claude" -H "Content-Type: application/json" \
    -d "{\"row_data\": ${updated}}" > /dev/null
  log "Status → ${new_status} (row ${ROW_NUMBER})"
}

pm_append_doc() {
  local msg="$1"
  [ -z "$ROW_NUMBER" ] || [ -z "$TABLE_ID" ] && return
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local current
  current=$(curl -s "${PM_URL}/api/tables/${TABLE_ID}/rows/${ROW_NUMBER}/doc" \
    -H "Authorization: Bearer claude" 2>/dev/null || echo "")
  local updated="${current}
- ${ts} ${msg}"
  curl -s -X PUT "${PM_URL}/api/tables/${TABLE_ID}/rows/${ROW_NUMBER}/doc" \
    -H "Authorization: Bearer claude" -H "Content-Type: text/plain" \
    --data-raw "$updated" > /dev/null
}

step() {
  local step_name="$1"
  local prompt="$2"
  log "Step: ${step_name}..."
  CLAUDECODE= claude -p \
    --dangerously-skip-permissions \
    --model sonnet \
    "${prompt}" 2>&1 | tee -a "$LOG_FILE"
}

# If any step fails, signal BLOCKED and exit
trap 'log "Pipeline failed. Writing BLOCKED."; pm_set_status "debugging"; pm_append_doc "W${WORKER_ID} BLOCKED — pipeline failed"; git stash 2>/dev/null; echo "BLOCKED" > "$TRIGGER_FILE"; exit 1' ERR

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

# ─── Phase 2: Extract row_number from task desc ─────────────────────────────
ROW_NUMBER=$(echo "$TASK_DESC" | grep -oP 'row_number=\K[0-9]+' || echo "")
PARENT_RN=$(echo "$TASK_DESC" | grep -oP 'parent=\K[0-9]+' || echo "")

if [ -z "$ROW_NUMBER" ]; then
  log "ERROR: No row_number in task desc"
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
  sf="$(find "${PROJECT_DIR}/.claude/skills" -path "*/${skill}" 2>/dev/null | head -1)"
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

# Read ticket doc for implementation instructions
TICKET_DOC=""
if [ -n "$ROW_NUMBER" ] && [ -n "$TABLE_ID" ]; then
  TICKET_DOC=$(curl -s "${PM_URL}/api/tables/${TABLE_ID}/rows/${ROW_NUMBER}/doc" \
    -H "Authorization: Bearer claude" 2>/dev/null || echo "")
fi

SHARED="You are Worker ${WORKER_ID}. Dir: ${PROJECT_DIR}

${CONTEXT}

TICKET DOC:
${TICKET_DOC}

TASK: ${TASK_DESC}

RULES:
- ONLY write application code. Do NOT run curl commands to any API or service.
- Status updates are handled by the bash wrapper — never update ticket status yourself.
- Focus ONLY on reading code and implementing the ticket.
- Commit message: ticket-${ROW_NUMBER}: <short description>"

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

TICKET_TITLE=$(echo "$TASK_DESC" | sed 's/ (row_number=.*//' | head -c 72)

git add -A 2>/dev/null || true
git reset HEAD .tmp/ 2>/dev/null || true

if git diff --cached --quiet; then
  log "No changes to commit"
  pm_append_doc "No changes needed"
else
  git commit -m "ticket-${ROW_NUMBER}: ${TICKET_TITLE}"
  log "Committed ticket-${ROW_NUMBER}"
  pm_append_doc "Committed ticket-${ROW_NUMBER}"
fi

rmdir "$GIT_LOCK" 2>/dev/null || true

# Step 4: Mark done
pm_set_status "done"
pm_append_doc "W${WORKER_ID} finished"

# ─── Signal done ─────────────────────────────────────────────────────────────
echo "DONE" > "$TRIGGER_FILE"
log "W${WORKER_ID} finished: DONE"
