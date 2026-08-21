#!/bin/bash
# checkpoint.sh — Git commit current state as a checkpoint
# Usage: bash checkpoint.sh <project_dir> "message"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
if [ -f "${ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

PROJECT_DIR="${1:?Usage: checkpoint.sh <project_dir> [message]}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
MSG="${2:-auto checkpoint}"
GIT_LOCK="${PROJECT_DIR}/_git.lock"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

cd "$PROJECT_DIR" || exit 1

# Acquire git lock
while ! mkdir "$GIT_LOCK" 2>/dev/null; do
  echo "Waiting for git lock..."
  sleep 2
done

git add -A
git commit -m "checkpoint: ${MSG} [${TIMESTAMP}]" --no-verify 2>/dev/null || echo "Nothing to commit."

# Release lock
rmdir "$GIT_LOCK"

echo "Checkpoint saved: ${MSG}"
