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

# ─── Task Planning ───────────────────────────────────────────────────────────
# Reads project status files, asks Haiku to assign N tasks (one per worker)
plan_tasks() {
  local CONTEXT_FILES=""

  # Build context from available files
  for f in ".tmp/llm.plan.status" ".tmp/llm.working.log" "CLAUDE.md" "README.md"; do
    if [ -f "${PROJECT_DIR}/${f}" ]; then
      CONTEXT_FILES="${CONTEXT_FILES}
--- ${f} ---
$(cat "${PROJECT_DIR}/${f}")
"
    fi
  done

  # Also include .tmp/llm.working.notes if it exists
  if [ -f "${PROJECT_DIR}/.tmp/llm.working.notes" ]; then
    CONTEXT_FILES="${CONTEXT_FILES}
--- .tmp/llm.working.notes ---
$(cat "${PROJECT_DIR}/.tmp/llm.working.notes")
"
  fi

  CLAUDECODE= claude -p \
    --dangerously-skip-permissions \
    --model haiku \
    "You are the task planner for an autonomous dev team.
Project dir: ${PROJECT_DIR}

Here are the project files:
${CONTEXT_FILES}

There are ${NUM_WORKERS} workers available.

YOUR JOB:
1. Read .tmp/llm.plan.status — find tickets marked [ ] (not yet done)
2. Assign ONE small ticket to each worker
3. Ensure workers won't conflict (different files/features)
4. If fewer tickets than workers, assign IDLE to extra workers

OUTPUT FORMAT (only output this, nothing else):
TASK1: <ticket description for worker 1, or IDLE>
TASK2: <ticket description for worker 2, or IDLE>
...up to TASK${NUM_WORKERS}

If ALL tickets are [x] (done), output only:
ALL_DONE
" 2>/dev/null | grep -E '^(TASK[0-9]+:|ALL_DONE)' > "${PROJECT_DIR}/_task_queue"
}

# ─── Spawn Worker ────────────────────────────────────────────────────────────
spawn_worker() {
  local WORKER_ID=$1
  local TASK="$2"
  local WINDOW_NAME="worker-${WORKER_ID}"

  log "Spawning worker ${WORKER_ID}: ${TASK}"

  rm -f "${PROJECT_DIR}/_trigger_${WORKER_ID}"

  tmux new-window -t "${SESSION}" -n "${WINDOW_NAME}" \
    "bash ${SCRIPT_DIR}/worker.sh '${PROJECT_DIR}' ${WORKER_ID} '${TASK}'; echo 'Worker ${WORKER_ID} done. Press enter.'; read"
}

# ─── Wait for Workers ────────────────────────────────────────────────────────
# Poll trigger files, kill workers that exceed 900s timeout
wait_for_workers() {
  local ACTIVE_WORKERS="$1"
  local TIMEOUT=900
  local ELAPSED=0
  local ALL_DONE=false

  while [ "$ELAPSED" -lt "$TIMEOUT" ] && [ "$ALL_DONE" = "false" ]; do
    ALL_DONE=true
    for i in $ACTIVE_WORKERS; do
      if [ ! -f "${PROJECT_DIR}/_trigger_${i}" ]; then
        ALL_DONE=false
        break
      fi
    done

    if [ "$ALL_DONE" = "false" ]; then
      sleep 10
      ELAPSED=$((ELAPSED + 10))

      # Status log every 60s
      if [ $((ELAPSED % 60)) -eq 0 ]; then
        local STATUS=""
        for i in $ACTIVE_WORKERS; do
          if [ -f "${PROJECT_DIR}/_trigger_${i}" ]; then
            STATUS="${STATUS} W${i}:$(cat "${PROJECT_DIR}/_trigger_${i}")"
          else
            STATUS="${STATUS} W${i}:running"
          fi
        done
        log "Status (${ELAPSED}s):${STATUS}"
      fi
    fi
  done

  # Kill any workers that didn't finish in time
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    log "TIMEOUT (${TIMEOUT}s): Killing remaining workers"
    for i in $ACTIVE_WORKERS; do
      if [ ! -f "${PROJECT_DIR}/_trigger_${i}" ]; then
        log "Killing worker ${i} (timed out)"
        tmux kill-window -t "${SESSION}:worker-${i}" 2>/dev/null || true
        echo "TIMEOUT" > "${PROJECT_DIR}/_trigger_${i}"
      fi
    done
  fi
}

# ─── Collect Results ─────────────────────────────────────────────────────────
collect_results() {
  local ACTIVE_WORKERS="$1"
  local HAS_BLOCKED=false
  local HAS_ALL_COMPLETE=false

  for i in $ACTIVE_WORKERS; do
    local TRIGGER="${PROJECT_DIR}/_trigger_${i}"
    if [ -f "$TRIGGER" ]; then
      local RESULT
      RESULT=$(cat "$TRIGGER")
      log "Worker ${i} result: ${RESULT}"
      case "$RESULT" in
        BLOCKED) HAS_BLOCKED=true ;;
        ALL_COMPLETE) HAS_ALL_COMPLETE=true ;;
        TIMEOUT) HAS_BLOCKED=true ;;
      esac
    else
      log "Worker ${i}: no trigger file (crashed?)"
      HAS_BLOCKED=true
    fi
    rm -f "$TRIGGER"
    tmux kill-window -t "${SESSION}:worker-${i}" 2>/dev/null || true
  done

  if [ "$HAS_ALL_COMPLETE" = "true" ]; then
    return 2
  elif [ "$HAS_BLOCKED" = "true" ]; then
    return 1
  fi
  return 0
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
