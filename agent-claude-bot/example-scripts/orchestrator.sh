#!/bin/bash
# orchestrator.sh — pure rule-based, NO LLM
#
# PSEUDO CODE:
#   loop (max_cycles):
#     1. query PM for todo tasks (type=task/bug, status=todo)
#     2. if none → ALL DONE, exit
#     3. spawn N workers in tmux windows
#     4. wait_finish: poll PM every 10s until ALL spawned rows
#        leave (todo, in_progress, testing) → become (done, debugging, review, merged)
#        - "todo" means worker hasn't picked it up yet — KEEP WAITING
#        - "in_progress" means worker is coding — KEEP WAITING
#        - "testing" means worker is testing — KEEP WAITING
#        - anything else means worker is done — STOP WAITING
#        timeout after 900s → kill worker windows
#     5. kill worker tmux windows (cleanup)
#     6. sleep 3 → next cycle

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${1:?Usage: orchestrator.sh <project_dir> [max_cycles] [num_workers]}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
MAX_CYCLES="${2:-50}"
NUM_WORKERS="${3:-1}"
SESSION="$(basename "$PROJECT_DIR")"
LOG_FILE="${PROJECT_DIR}/.tmp/out/orchestrator.log"
CYCLE=0

PM_URL="http://localhost:13491"
TABLE_ID="${TABLE_ID:?Set TABLE_ID}"
AUTH="Authorization: Bearer claude"

mkdir -p "${PROJECT_DIR}/.tmp/out"

log() { echo "$(date '+%H:%M:%S') [ORCH] $1" | tee -a "$LOG_FILE"; }

# Get column ID by name — queries PM directly, no cache
col() {
  curl -s "${PM_URL}/api/tables/${TABLE_ID}" -H "$AUTH" 2>/dev/null | \
  python3 -c "import sys,json; t=json.load(sys.stdin); print(next((c['column_id'] for c in t['columns'] if c['name']=='$1'),''))" 2>/dev/null
}

# ─── Step 1: Query PM for todo tasks (pure bash+python, NO LLM) ──────────────
get_todo() {
  local SID; SID=$(col Status)
  local FILTER; FILTER=$(python3 -c "import urllib.parse; print(urllib.parse.quote('{\"${SID}\":\"todo\"}'))")
  curl -s "${PM_URL}/api/tables/${TABLE_ID}/rows?limit=100&filter_json=${FILTER}" -H "$AUTH" 2>/dev/null | python3 -c "
import sys, json
rows = json.load(sys.stdin)
tyid = '$(col Type)'; tid = '$(col Title)'; pid = '$(col Parent)'
todo = [r for r in rows if r['row_data'].get(tyid) in ('task', 'bug')]
todo.sort(key=lambda x: x['row_number'])
if not todo:
    print('ALL_DONE')
else:
    for i in range(${NUM_WORKERS}):
        if i < len(todo):
            r = todo[i]; d = r['row_data']
            print(f'TASK{i+1}: {d.get(tid,\"?\")} (row_number={r[\"row_number\"]} parent={d.get(pid,\"\")})')
        else:
            print(f'TASK{i+1}: IDLE')
" 2>/dev/null
}

# ─── Step 3: Spawn worker in tmux window ──────────────────────────────────────
spawn_worker() {
  local WID=$1 TASK="$2"
  # Escape single quotes in TASK to prevent shell injection in tmux command
  local SAFE_TASK="${TASK//\'/\'\\\'\'}"
  log "Spawn W${WID}: ${TASK}"
  tmux new-window -t "${SESSION}" -n "w${WID}" \
    "TABLE_ID='${TABLE_ID}' bash ${SCRIPT_DIR}/worker.sh '${PROJECT_DIR}' ${WID} '${SAFE_TASK}'"
}

# ─── Step 4: Wait for ALL workers to FINISH ───────────────────────────────────
# "Finish" = PM status is NOT in (todo, in_progress, testing)
# i.e. status became: done, debugging, review, merged
# IMPORTANT: "todo" means worker hasn't started yet — must keep waiting!
wait_finish() {
  local ROW_NUMBERS="$1"
  local TIMEOUT=900 ELAPSED=0
  local SID; SID=$(col Status)

  log "Waiting for rows [${ROW_NUMBERS}] to finish (timeout ${TIMEOUT}s)..."

  while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    sleep 10; ELAPSED=$((ELAPSED + 10))

    local STILL_WORKING
    STILL_WORKING=$(curl -s "${PM_URL}/api/tables/${TABLE_ID}/rows?limit=500&sort=asc" -H "$AUTH" 2>/dev/null | python3 -c "
import sys, json
rows = json.load(sys.stdin)
active = '${ROW_NUMBERS}'.split()
working = []
for rn in active:
    r = next((r for r in rows if str(r['row_number']) == rn), None)
    if r:
        s = r['row_data'].get('${SID}', '')
        if s in ('todo', 'in_progress', 'testing'):
            working.append(rn)
print(' '.join(working) if working else 'NONE')
" 2>/dev/null)

    if [ "$STILL_WORKING" = "NONE" ]; then
      log "All workers finished."
      return 0
    fi

    [ $((ELAPSED % 60)) -eq 0 ] && log "Still working: [${STILL_WORKING}] (${ELAPSED}s)"
  done

  log "TIMEOUT after ${TIMEOUT}s — killing worker windows"
  return 1
}

# ─── Main loop ────────────────────────────────────────────────────────────────
log "=== Orchestrator started (table: ${TABLE_ID}) ==="

while [ "$CYCLE" -lt "$MAX_CYCLES" ]; do
  CYCLE=$((CYCLE + 1))
  log "=== Cycle ${CYCLE}/${MAX_CYCLES} ==="
  rmdir "${PROJECT_DIR}/_git.lock" 2>/dev/null || true

  # Step 1: Get tasks
  TASKS=$(get_todo)
  echo "$TASKS" | grep -q "ALL_DONE" && { log "ALL DONE!"; exit 0; }

  # Step 2+3: Spawn workers
  ACTIVE="" RNS=""
  for i in $(seq 1 "$NUM_WORKERS"); do
    T=$(echo "$TASKS" | grep "^TASK${i}:" | sed "s/^TASK${i}: //")
    if [ -n "$T" ] && [ "$T" != "IDLE" ]; then
      RN=$(echo "$T" | grep -oP 'row_number=\K[0-9]+' || echo "")
      spawn_worker "$i" "$T"
      ACTIVE="${ACTIVE} ${i}"; RNS="${RNS} ${RN}"
    else
      log "W${i}: IDLE"
    fi
  done

  [ -z "$ACTIVE" ] && { sleep 15; continue; }

  # Step 4: Wait for ALL workers to finish
  wait_finish "$RNS"

  # Step 5: Cleanup worker windows
  for i in $ACTIVE; do
    tmux kill-window -t "${SESSION}:w${i}" 2>/dev/null || true
  done

  sleep 3
done
log "Max cycles reached."
