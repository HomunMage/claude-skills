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

# Run a pipeline step with claude -p
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
trap 'log "Pipeline failed. Writing BLOCKED."; git stash 2>/dev/null; echo "BLOCKED" > "$TRIGGER_FILE"; exit 1' ERR

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

# ─── Phase 2: Extract IDs from task desc ────────────────────────────────────
ROW_ID=$(echo "$TASK_DESC" | grep -oP 'row_id=\K[a-f0-9-]+' || echo "")
PARENT_ROW_ID=$(echo "$TASK_DESC" | grep -oP 'parent=\K[a-f0-9-]+' || echo "")

# ─── Phase 3: Resolve story branch ──────────────────────────────────────────
STORY_BRANCH="main"
if [ -n "$PARENT_ROW_ID" ] && [ -n "$TABLE_ID" ]; then
  KEY_COL=$(python3 -c "import json; d=json.load(open('${PROJECT_DIR}/.tmp/claude-bot/_col_cache.json')); print(d.get('Key',''))" 2>/dev/null || echo "")
  if [ -n "$KEY_COL" ]; then
    STORY_KEY=$(curl -s "${PM_URL}/api/tables/${TABLE_ID}/rows?limit=200" \
      -H "Authorization: Bearer claude" | \
      python3 -c "
import json, sys
rows = json.load(sys.stdin)
for r in rows:
    if r['row_id'] == '${PARENT_ROW_ID}':
        print(r['row_data'].get('${KEY_COL}', ''))
        break
" 2>/dev/null || echo "")
    if [ -n "$STORY_KEY" ]; then
      STORY_BRANCH="story/$(echo "$STORY_KEY" | tr '[:upper:]' '[:lower:]')"
      # Ensure story branch exists (create from main if not)
      git checkout "$STORY_BRANCH" 2>/dev/null || git checkout -b "$STORY_BRANCH" main
      git checkout - 2>/dev/null || true
      log "Story branch: ${STORY_BRANCH}"
    fi
  fi
fi

# ─── Phase 4: Build context ──────────────────────────────────────────────────
CONTEXT=""

for f in CLAUDE.md README.md; do
  [ -f "${PROJECT_DIR}/${f}" ] && CONTEXT="${CONTEXT}
--- ${f} ---
$(head -200 "${PROJECT_DIR}/${f}")
"
done

# Skills
for skill in developing-programming/developing.md developing-project-management/SKILL.md; do
  sf="$(find "${PROJECT_DIR}/.claude/skills" -path "*/${skill}" 2>/dev/null | head -1)"
  [ -n "$sf" ] && CONTEXT="${CONTEXT}
--- Skill: $(basename $(dirname $sf)) ---
$(cat "$sf")
"
done

for f in "${PROJECT_DIR}"/.tmp/llm*.md; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  CONTEXT="${CONTEXT}
--- ${BASENAME} ---
$(head -200 "$f")
"
done

if [ -n "$TASK_DESC" ]; then
  TASK_PROMPT="YOUR ASSIGNED TASK: ${TASK_DESC}"
else
  TASK_PROMPT="Query LatticeCast PM (${PM_URL}) for the first todo ticket in this repo's PM table. Use Bearer claude auth."
fi

SHARED_CONTEXT="You are Worker ${WORKER_ID}. Working directory: ${PROJECT_DIR}
PM: ${PM_URL}/api  Table: ${TABLE_ID}  Auth: Bearer claude
Row ID: ${ROW_ID}
Col cache: ${PROJECT_DIR}/.tmp/claude-bot/_col_cache.json
Story branch: ${STORY_BRANCH}

${CONTEXT}

${TASK_PROMPT}

RULES:
- Update ticket status in LatticeCast PM via curl at each phase
- Append work log to ticket MinIO doc via PUT /api/tables/\${TABLE_ID}/rows/\${ROW_ID}/doc
  Example:
    CURRENT=\$(curl -s ${PM_URL}/api/tables/\${TABLE_ID}/rows/\${ROW_ID}/doc -H 'Authorization: Bearer claude')
    ENTRY='- \$(date -u +%Y-%m-%dT%H:%M:%SZ) <message>'
    if echo \"\$CURRENT\" | grep -q '## Work Log'; then UPDATED=\"\${CURRENT}\${ENTRY}\"
    else UPDATED=\"\${CURRENT}## Work Log\${ENTRY}\"; fi
    curl -s -X PUT ${PM_URL}/api/tables/\${TABLE_ID}/rows/\${ROW_ID}/doc \\
      -H 'Authorization: Bearer claude' -H 'Content-Type: text/plain' --data-raw \"\$UPDATED\" > /dev/null
- All PKs: workspace_id, table_id, row_id, user_id, column_id
- Row data field: row_data
- Backend: flat imports, SQLModel, async
- Frontend: Svelte 5 runes, Tailwind CSS 4"

# ─── Pipeline: each step is a fresh claude -p call ───────────────────────────

# Step 1: Set in_progress + implement
step "implement" "${SHARED_CONTEXT}

1. Update PM ticket status to 'in_progress' via curl PUT row (read Status col ID from col cache)
2. Append to doc: started message
3. Read the relevant source files, then implement the ticket.
   Branch from '${STORY_BRANCH}' (NOT main):
     git checkout ${STORY_BRANCH}
     git checkout -b feat/<TICKET_KEY>/<short-slug> ${STORY_BRANCH}
4. Keep changes minimal and focused. ONE ticket only.
5. Append to doc: implementation complete message"

# Step 2: Test + Format + Lint
step "test-format-lint" "${SHARED_CONTEXT}

1. Update PM status to 'testing' via curl PUT row
2. Append to doc: running tests message
3. Frontend: cd ${PROJECT_DIR}/frontend && npx svelte-check 2>&1 | head -50
4. Frontend: cd ${PROJECT_DIR}/frontend && npm run build 2>&1 | tail -30
5. Backend: python -c 'import ast; ast.parse(open(\"<file>\").read())' for each .py changed
6. Auto-detect and run formatter (prettier / ruff / cargo fmt)
7. Auto-detect and run linter (eslint / ruff check / cargo clippy)
8. If errors: update PM to 'debugging', fix, re-check, update PM back to 'testing'
9. Append to doc: tests passed message
Do NOT commit yet."

# Step 3: Commit + merge to story branch
step "commit" "${SHARED_CONTEXT}

Commit and merge into story branch (NOT main):
1. Acquire git lock: while ! mkdir ${GIT_LOCK} 2>/dev/null; do sleep 2; done
2. git add specific files (NOT .tmp/)
3. git commit -m 'ticket: <short description>'
4. Merge into '${STORY_BRANCH}':
   git checkout ${STORY_BRANCH}
   git merge <feature-branch>
   git branch -d <feature-branch>
5. Update PM status to 'review' via curl PUT row
6. Release lock: rmdir ${GIT_LOCK}
7. Append to doc: committed and merged message"

# Step 4: Update PM status to merged
step "update-status" "${SHARED_CONTEXT}

1. Update ticket status in LatticeCast PM to 'merged' via curl PUT row
2. Append to doc via PUT doc endpoint: merged message and Files Changed section with list of changed files"

# ─── Signal done ─────────────────────────────────────────────────────────────
echo "DONE" > "$TRIGGER_FILE"
log "Worker ${WORKER_ID} finished. Result: DONE"
