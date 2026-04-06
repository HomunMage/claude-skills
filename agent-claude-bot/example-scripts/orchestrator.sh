#!/bin/bash
# orchestrator.sh — Main loop: plan → spawn workers → monitor → collect → repeat
# Usage: bash orchestrator.sh <project_dir> [max_cycles] [num_workers]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${1:?Usage: orchestrator.sh <project_dir> [max_cycles] [num_workers]}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
MAX_CYCLES="${2:-50}"
NUM_WORKERS="${3:-2}"
SESSION="$(basename "$PROJECT_DIR")"
LOG_FILE="${PROJECT_DIR}/.tmp/out/orchestrator.log"
CYCLE=0

mkdir -p "${PROJECT_DIR}/.tmp/out"

log() {
  echo "$(date '+%H:%M:%S') [ORCH] $1" | tee -a "$LOG_FILE"
}

# ─── Task Planning (pure bash+python, NO LLM) ────────────────────────────────
# NEVER use haiku/LLM here — it hallucinates ALL_DONE
plan_tasks() {
  local COLS_JSON
  COLS_JSON=$(cat "${PROJECT_DIR}/.tmp/claude-bot/_col_cache.json" 2>/dev/null || echo '{}')
  local SID
  SID=$(echo "$COLS_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('Status',''))" 2>/dev/null)
  local FILTER
  FILTER=$(python3 -c "import urllib.parse; print(urllib.parse.quote('{\"${SID}\":\"todo\"}'))" 2>/dev/null)

  curl -s "${PM_URL}/api/tables/${TABLE_ID}/rows?offset=0&limit=100&filter_json=${FILTER}" -H "$AUTH" 2>/dev/null | python3 -c "
import sys, json
rows = json.load(sys.stdin)
cols = json.loads(open('${PROJECT_DIR}/.tmp/claude-bot/_col_cache.json').read())
kid=cols.get('Key',''); tid=cols.get('Title',''); tyid=cols.get('Type',''); pid=cols.get('Parent','')
NUM_WORKERS = ${NUM_WORKERS}

todo = [r for r in rows if r['row_data'].get(tyid) in ('task','bug')]
todo.sort(key=lambda x: x['row_number'])

if not todo:
    print('ALL_DONE')
else:
    for i in range(NUM_WORKERS):
        if i < len(todo):
            r = todo[i]
            d = r['row_data']
            print(f'TASK{i+1}: {d.get(kid,\"?\")} {d.get(tid,\"(untitled)\")} (row_number={r[\"row_number\"]} parent={d.get(pid,\"\")})')
        else:
            print(f'TASK{i+1}: IDLE')
" > "${PROJECT_DIR}/_task_queue" 2>/dev/null
}

# ─── Spawn Worker ────────────────────────────────────────────────────────────
spawn_worker() {
  local WORKER_ID=$1
  local TASK="$2"
  local WINDOW_NAME="worker-${WORKER_ID}"

  log "Spawning worker ${WORKER_ID}: ${TASK}"

  

  tmux new-window -t "${SESSION}" -n "${WINDOW_NAME}" \
    "bash ${SCRIPT_DIR}/worker.sh '${PROJECT_DIR}' ${WORKER_ID} '${TASK}'; echo 'Worker ${WORKER_ID} done. Press enter.'; read"
}

# ─── Wait for Workers (poll PM status, no trigger files) ─────────────────────
# Workers set PM status to done/debugging when finished. Poll PM to detect.
wait_for_workers() {
  local ACTIVE_ROW_NUMBERS="$1"
  local TIMEOUT=900
  local ELAPSED=0

  while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    # Check if all active tickets are no longer in_progress
    local ALL_DONE
    ALL_DONE=$(curl -s "${PM_URL}/api/tables/${TABLE_ID}/rows?limit=500&sort=asc" -H "$AUTH" 2>/dev/null | python3 -c "
import sys, json
rows = json.load(sys.stdin)
cols = json.loads(open('${PROJECT_DIR}/.tmp/claude-bot/_col_cache.json').read())
sid = cols.get('Status','')
active = '${ACTIVE_ROW_NUMBERS}'.split()
all_done = True
for rn in active:
    r = next((r for r in rows if str(r['row_number']) == rn), None)
    if r and r['row_data'].get(sid) == 'in_progress':
        all_done = False
        break
print('yes' if all_done else 'no')
" 2>/dev/null)

    if [ "$ALL_DONE" = "yes" ]; then
      log "All workers finished."
      return 0
    fi

    sleep 10
    ELAPSED=$((ELAPSED + 10))
    [ $((ELAPSED % 60)) -eq 0 ] && log "Waiting... (${ELAPSED}s)"
  done

  log "TIMEOUT (${TIMEOUT}s): Killing remaining workers"
  for rn in $ACTIVE_ROW_NUMBERS; do
    tmux kill-window -t "${SESSION}:worker-*" 2>/dev/null || true
  done
}

# ─── Main Loop ───────────────────────────────────────────────────────────────

log "========================================="
log "${SESSION} orchestrator started"
log "Project:    ${PROJECT_DIR}"
log "Max cycles: ${MAX_CYCLES}"
log "Workers:    ${NUM_WORKERS}"
log "========================================="

while [ "$CYCLE" -lt "$MAX_CYCLES" ]; do
  CYCLE=$((CYCLE + 1))
  log ""
  log "=== Cycle ${CYCLE}/${MAX_CYCLES} ==="

  # Clean stale git lock
  rmdir "${PROJECT_DIR}/_git.lock" 2>/dev/null || true

  # Plan tasks
  log "Planning tasks..."
  plan_tasks

  if grep -q "ALL_DONE" "${PROJECT_DIR}/_task_queue" 2>/dev/null; then
    log "ALL TICKETS COMPLETE! Exiting."
    exit 0
  fi

  # Parse tasks and spawn workers
  ACTIVE_WORKERS=""
  for i in $(seq 1 "$NUM_WORKERS"); do
    TASK=$(grep "^TASK${i}:" "${PROJECT_DIR}/_task_queue" 2>/dev/null | sed "s/^TASK${i}: //")

    if [ -n "$TASK" ] && [ "$TASK" != "IDLE" ]; then
      spawn_worker "$i" "$TASK"
      ACTIVE_WORKERS="${ACTIVE_WORKERS} ${i}"
    else
      log "Worker ${i}: IDLE (no task assigned)"
    fi
  done

  if [ -z "$ACTIVE_WORKERS" ]; then
    log "All workers IDLE. Retrying in 15s..."
    sleep 15
    continue
  fi

  # Wait and monitor
  log "Active workers:${ACTIVE_WORKERS}. Waiting (timeout: 900s)..."
  wait_for_workers "$ACTIVE_WORKERS"

  # Collect results
  collect_results "$ACTIVE_WORKERS"
  RESULT=$?

  case $RESULT in
    0) log "Cycle ${CYCLE} complete. All workers succeeded." ;;
    1) log "Some workers blocked/timed out. Continuing..." ; sleep 10 ;;
    2) log "ALL TICKETS COMPLETE! Exiting." ; exit 0 ;;
  esac

  sleep 5
done

log "Max cycles (${MAX_CYCLES}) reached. Stopping."
