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

# ─── Phase 2: Build context ─────────────────────────────────────────────────
CONTEXT=""

for f in CLAUDE.md README.md; do
  [ -f "${PROJECT_DIR}/${f}" ] && CONTEXT="${CONTEXT}
--- ${f} ---
$(head -200 "${PROJECT_DIR}/${f}")
"
done

for f in .tmp/llm.plan.status .tmp/llm.working.log .tmp/llm.working.notes; do
  [ -f "${PROJECT_DIR}/${f}" ] && CONTEXT="${CONTEXT}
--- ${f} ---
$(tail -100 "${PROJECT_DIR}/${f}")
"
done

for f in "${PROJECT_DIR}"/.tmp/llm*.md; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  case "$BASENAME" in llm.plan.status|llm.working.log|llm.working.notes) continue ;; esac
  CONTEXT="${CONTEXT}
--- ${BASENAME} ---
$(head -200 "$f")
"
done

if [ -n "$TASK_DESC" ]; then
  TASK_PROMPT="YOUR ASSIGNED TASK: ${TASK_DESC}"
else
  TASK_PROMPT="Pick the first unchecked [ ] ticket from .tmp/llm.plan.status."
fi

SHARED_CONTEXT="You are Worker ${WORKER_ID}. Working directory: ${PROJECT_DIR}
${CONTEXT}
${TASK_PROMPT}"

# ─── Pipeline: each step is a fresh claude -p call ───────────────────────────
# set -e ensures failure at any step stops the pipeline

# Step 1: Understand + Implement
step "implement" "${SHARED_CONTEXT}

Read the relevant source files, then implement the ticket.
Keep changes minimal and focused. ONE ticket only."

# Step 2: Test + Format + Lint (Skill(programming) developing.md)
step "test-format-lint" "${SHARED_CONTEXT}

Run the post-code workflow — Use Skill(developing-programming) developing.md:
1. Auto-detect project type and run tests. All tests MUST pass.
2. Auto-detect and run formatter.
3. Auto-detect and run linter.
Do NOT commit yet. Just ensure code is clean."

# Step 3: Commit (with git lock)
step "commit" "${SHARED_CONTEXT}

Commit the changes:
1. Acquire git lock: while ! mkdir ${GIT_LOCK} 2>/dev/null; do sleep 2; done
2. git add -A && git reset HEAD .tmp/ 2>/dev/null || true
3. git commit -m 'ticket: <short description>'
4. Release lock: rmdir ${GIT_LOCK}
Never commit .tmp/ files."

# Step 4: Update status
step "update-status" "${SHARED_CONTEXT}

Update status files:
1. Edit .tmp/llm.plan.status: change [ ] to [x] for the completed ticket
2. Append to .tmp/llm.working.log: [W${WORKER_ID}] <what was done> — <files changed>
3. Commit status:
   while ! mkdir ${GIT_LOCK} 2>/dev/null; do sleep 2; done
   git add .tmp/llm.plan.status .tmp/llm.working.log
   git commit -m 'status: mark ticket done [W${WORKER_ID}]'
   rmdir ${GIT_LOCK}"

# ─── Signal done ─────────────────────────────────────────────────────────────
echo "DONE" > "$TRIGGER_FILE"
log "Worker ${WORKER_ID} finished. Result: DONE"
