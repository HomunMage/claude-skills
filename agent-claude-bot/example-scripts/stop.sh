#!/bin/bash
# stop.sh — Stop the tmux orchestrator session and all workers
# Usage: bash stop.sh [project_dir]

PROJECT_DIR="${1:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd || echo "$PROJECT_DIR")"
SESSION="$(basename "$PROJECT_DIR")"

echo "Stopping tmux session: ${SESSION}"
tmux kill-session -t "$SESSION" 2>/dev/null && echo "Stopped." || echo "No session found."

# Clean up orphan files
rm -f "${PROJECT_DIR}/_trigger_"* "${PROJECT_DIR}/_task_queue"
rmdir "${PROJECT_DIR}/_git.lock" 2>/dev/null || true

echo "Cleanup complete."
