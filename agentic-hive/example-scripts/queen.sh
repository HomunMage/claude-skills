#!/bin/bash
# queen.sh — pure rule-based, NO LLM
#
# PSEUDO CODE:
#   startup:
#     - cache column IDs to _col_cache.json (worker reads this)
#     - recover orphans: if in_progress tickets exist but no tmux worker windows → reset to todo
#   loop (max_cycles):
#     1. query PM for todo tasks (type=task/bug, status=todo) using filter_json
#     2. if none → ALL DONE, exit
#     3. spawn N workers in tmux windows (pass TABLE_ID env, escape quotes in task)
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
# shellcheck disable=SC1091
# Sourcing config.sh here makes queen.sh self-sufficient regardless of
# whether it inherits env from start.sh. Critical when tmux new-session
# attaches to an already-running tmux server whose env predates this run.
source "${SCRIPT_DIR}/config.sh"

PROJECT_DIR="${1:?Usage: queen.sh <project_dir> [max_cycles] [num_workers]}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
MAX_CYCLES="${2:-50}"
NUM_WORKERS="${3:-1}"
SESSION="$(basename "$PROJECT_DIR")"
LOG_FILE="${PROJECT_DIR}/.tmp/out/queen.log"
CYCLE=0

PM_URL="${LC_API%/api/v1}"
TABLE_ID="${TABLE_ID:?Set TABLE_ID}"
AUTH="${LC_AUTH_HEADER}"

mkdir -p "${PROJECT_DIR}/.tmp/out"

log() { echo "$(date '+%H:%M:%S') [ORCH] $1" | tee -a "$LOG_FILE"; }

# Cache column IDs at startup — worker reads this file
curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}" -H "$AUTH" 2>/dev/null | python3 -c "
import sys, json
t = json.load(sys.stdin)
json.dump({c['name']: c['column_id'] for c in t['columns']}, open('${PROJECT_DIR}/.tmp/agentic-hive/_col_cache.json', 'w'))
" 2>/dev/null

# ─── Recovery: reset orphaned in_progress tickets ─────────────────────────────
# If tmux has no worker window for a ticket → it's orphaned (bot crashed) → reset to todo
# Human in_progress tickets are safe — humans don't use tmux windows named w{N}
recover_orphans() {
  local SID; SID=$(python3 -c "import json; print(json.load(open('${PROJECT_DIR}/.tmp/agentic-hive/_col_cache.json')).get('Status',''))" 2>/dev/null)
  [ -z "$SID" ] && return

  # Get all in_progress tickets
  local FILTER; FILTER=$(python3 -c "import urllib.parse; print(urllib.parse.quote('{\"${SID}\":\"in_progress\"}'))")
  local ORPHANS
  ORPHANS=$(curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows?limit=100&filter_json=${FILTER}" -H "$AUTH" 2>/dev/null | python3 -c "
import sys, json
rows = json.load(sys.stdin)
for r in rows:
    print(r['row_id'])
" 2>/dev/null)

  [ -z "$ORPHANS" ] && return

  # Check each: does a tmux worker window exist for it?
  local ACTIVE_WINDOWS
  ACTIVE_WINDOWS=$(tmux list-windows -t "${SESSION}" -F '#{window_name}' 2>/dev/null || echo "")

  for rn in $ORPHANS; do
    # Worker windows are named w{N}-{type}-{rn} e.g. w1-task-182
    # Check if any window contains this row_id
    if ! echo "$ACTIVE_WINDOWS" | grep -q "\-${rn}$"; then
      # No worker windows at all → this ticket is orphaned
      local cur
      cur=$(curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows?limit=500&sort=asc" -H "$AUTH" | \
        python3 -c "import sys,json; rows=json.load(sys.stdin); r=next((r for r in rows if r['row_id']==${rn}),None); print(json.dumps(r['row_data']) if r else '{}')" 2>/dev/null)
      local upd
      upd=$(echo "$cur" | python3 -c "import sys,json; d=json.load(sys.stdin); d['${SID}']='todo'; print(json.dumps(d))")
      curl -s -X PUT "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${rn}" \
        -H "$AUTH" -H "Content-Type: application/json" \
        -d "{\"row_data\": ${upd}}" > /dev/null
      log "Recovery: rn=${rn} in_progress → todo (no worker window)"
    fi
  done
}

recover_orphans

# Get column ID by name — queries PM directly, no cache
col() {
  curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}" -H "$AUTH" 2>/dev/null | \
  python3 -c "import sys,json; t=json.load(sys.stdin); print(next((c['column_id'] for c in t['columns'] if c['name']=='$1'),''))" 2>/dev/null
}

# ─── Step 1: Query PM for todo tasks (pure bash+python, NO LLM) ──────────────
get_todo() {
  local SID; SID=$(col Status)
  local FILTER; FILTER=$(python3 -c "import urllib.parse; print(urllib.parse.quote('{\"${SID}\":\"todo\"}'))")
  curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows?limit=100&filter_json=${FILTER}" -H "$AUTH" 2>/dev/null | python3 -c "
import sys, json
rows = json.load(sys.stdin)
tyid = '$(col Type)'; tid = '$(col Title)'; pid = '$(col Parent)'
todo = [r for r in rows if r['row_data'].get(tyid) in ('task', 'bug')]
todo.sort(key=lambda x: x['row_id'])
if not todo:
    print('ALL_DONE')
else:
    for i in range(${NUM_WORKERS}):
        if i < len(todo):
            r = todo[i]; d = r['row_data']
            print(f'TASK{i+1}: {d.get(tid,\"?\")} (row_id={r[\"row_id\"]} parent={d.get(pid,\"\")})')
        else:
            print(f'TASK{i+1}: IDLE')
" 2>/dev/null
}

# ─── Step 3: Spawn worker in tmux window ──────────────────────────────────────
spawn_worker() {
  local WID=$1 TASK="$2"
  # Escape single quotes in TASK to prevent shell injection in tmux command
  local SAFE_TASK="${TASK//\'/\'\\\'\'}"
  local RN=$(echo "$TASK" | grep -oP 'row_id=\K[0-9]+' || echo "?")
  local TTYPE=$(echo "$TASK" | head -c 20 | tr ' ' '-' | tr -cd 'a-z0-9-')
  log "Spawn W${WID}: ${TASK}"
  tmux new-window -t "${SESSION}" -n "w${WID}-${TTYPE}-${RN}" \
    "TABLE_ID='${TABLE_ID}' bash ${SCRIPT_DIR}/bee.sh '${PROJECT_DIR}' ${WID} '${SAFE_TASK}' 2>&1 | tee -a ${PROJECT_DIR}/.tmp/out/worker_${WID}_${RN}.log"
}

# ─── Step 4: Wait for ALL workers to FINISH ───────────────────────────────────
# "Finish" = PM status is NOT in (todo, in_progress, testing)
# i.e. status became: done, debugging, review, merged
# IMPORTANT: "todo" means worker hasn't started yet — must keep waiting!
# 900s is Non-negotiable, if you want set larger than 900s, means your task too large, spilt
wait_finish() {
  local ROW_NUMBERS="$1"
  local TIMEOUT=900 ELAPSED=0
  local SID; SID=$(col Status)

  log "Waiting for rows [${ROW_NUMBERS}] to finish (timeout ${TIMEOUT}s)..."

  while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    sleep 10; ELAPSED=$((ELAPSED + 10))

    # Every 30s, check if any worker tmux windows still exist — if none, workers died
    if [ $((ELAPSED % 30)) -eq 0 ]; then
    local WORKER_WINDOWS
    WORKER_WINDOWS=$(tmux list-windows -t "${SESSION}" -F '#{window_name}' 2>/dev/null | grep "^w[0-9]" || true)
    if [ -z "$WORKER_WINDOWS" ]; then
      log "No worker windows alive — resetting stuck tickets to todo"
      for rn in $ROW_NUMBERS; do
        local cur_status
        cur_status=$(curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows?limit=500&sort=asc" -H "$AUTH" 2>/dev/null | \
          python3 -c "import sys,json; rows=json.load(sys.stdin); r=next((r for r in rows if str(r['row_id'])=='${rn}'),None); print(r['row_data'].get('${SID}','') if r else '')" 2>/dev/null)
        if [ "$cur_status" = "in_progress" ] || [ "$cur_status" = "testing" ]; then
          local cur
          cur=$(curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows?limit=500&sort=asc" -H "$AUTH" | \
            python3 -c "import sys,json; rows=json.load(sys.stdin); r=next((r for r in rows if str(r['row_id'])=='${rn}'),None); print(json.dumps(r['row_data']) if r else '{}')" 2>/dev/null)
          local upd
          upd=$(echo "$cur" | python3 -c "import sys,json; d=json.load(sys.stdin); d['${SID}']='todo'; print(json.dumps(d))")
          curl -s -X PUT "${PM_URL}/api/v1/tables/${TABLE_ID}/rows/${rn}" \
            -H "$AUTH" -H "Content-Type: application/json" \
            -d "{\"row_data\": ${upd}}" > /dev/null
          log "Reset rn=${rn} ${cur_status} → todo (worker window gone)"
        fi
      done
      return 0
    fi
    fi

    local STILL_WORKING
    STILL_WORKING=$(curl -s "${PM_URL}/api/v1/tables/${TABLE_ID}/rows?limit=500&sort=asc" -H "$AUTH" 2>/dev/null | python3 -c "
import sys, json
rows = json.load(sys.stdin)
active = '${ROW_NUMBERS}'.split()
working = []
for rn in active:
    r = next((r for r in rows if str(r['row_id']) == rn), None)
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
      RN=$(echo "$T" | grep -oP 'row_id=\K[0-9]+' || echo "")
      spawn_worker "$i" "$T"
      ACTIVE="${ACTIVE} ${i}"; RNS="${RNS} ${RN}"
    else
      log "W${i}: IDLE"
    fi
  done

  [ -z "$ACTIVE" ] && { sleep 15; continue; }

  # Step 4: Wait for ALL workers to finish
  wait_finish "$RNS"

  # Step 5: Cleanup worker windows (match w{N}-* pattern)
  for i in $ACTIVE; do
    for win in $(tmux list-windows -t "${SESSION}" -F '#{window_name}' 2>/dev/null | grep "^w${i}-"); do
      tmux kill-window -t "${SESSION}:${win}" 2>/dev/null || true
    done
  done

  sleep 3
done
log "Max cycles reached."
