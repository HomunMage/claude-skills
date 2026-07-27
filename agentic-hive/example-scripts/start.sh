#!/bin/bash
# start.sh — Start the multi-worker orchestrator in a tmux session
# Usage: bash start.sh <project_dir> [max_cycles] [num_workers]
# Monitor: tmux attach -t <project_folder_name>
# Stop: bash stop.sh <project_dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${1:?Usage: bash start.sh <project_dir> [max_cycles] [num_workers]}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
MAX_CYCLES="${2:-50}"
NUM_WORKERS="${3:-2}"
SESSION="$(basename "$PROJECT_DIR")"

# Validate LatticeCast PM is running
if ! curl -s http://localhost:13491/api/v1/status 2>/dev/null | grep -q '"ok"'; then
  echo "ERROR: LatticeCast PM is not running."
  echo "Start it: cd <LatticeCast-repo> && docker compose up -d backend frontend"
  echo "Or clone: git clone https://github.com/LatticeMage/LatticeCast.git"
  exit 1
fi

if [ ! -f "${PROJECT_DIR}/CLAUDE.md" ]; then
  echo "WARNING: ${PROJECT_DIR}/CLAUDE.md not found."
  echo "Consider copying the template: cp CLAUDE.md ${PROJECT_DIR}/"
fi

# Kill existing session if any
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Clean up stale files
rmdir "${PROJECT_DIR}/_git.lock" 2>/dev/null || true

mkdir -p "${PROJECT_DIR}/.tmp/out"

# Create tmux session with queen in window 0
tmux new-session -d -s "$SESSION" -n "queen" \
  "bash ${SCRIPT_DIR}/queen.sh '${PROJECT_DIR}' ${MAX_CYCLES} ${NUM_WORKERS}; echo 'Queen ended. Press enter.'; read"

echo "========================================="
echo " ${SESSION} started"
echo "========================================="
echo ""
echo " Project:       ${PROJECT_DIR}"
echo " tmux session:  ${SESSION}"
echo " Monitor:       tmux attach -t ${SESSION}"
echo " Stop:          bash ${SCRIPT_DIR}/stop.sh ${PROJECT_DIR}"
echo " Max cycles:    ${MAX_CYCLES}"
echo " Workers:       ${NUM_WORKERS}"
echo ""
echo " Window layout:"
echo "   0: queen — task planner + coordinator"
echo "   1-${NUM_WORKERS}: bees — each in its own tmux window"
echo ""
echo " Logs:"
echo "   ${PROJECT_DIR}/.tmp/out/queen.log"
echo "   ${PROJECT_DIR}/.tmp/out/worker_1.log .. worker_${NUM_WORKERS}.log"
echo ""
