#!/bin/bash
# rollback.sh — Reset to last checkpoint or specific commit
# Usage: bash rollback.sh <project_dir> [commit-hash]

set -uo pipefail

PROJECT_DIR="${1:?Usage: rollback.sh <project_dir> [commit-hash]}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

cd "$PROJECT_DIR" || exit 1

if [ -n "${2:-}" ]; then
  echo "Rolling back to: $2"
  git reset --hard "$2"
else
  echo "Rolling back to last commit (HEAD)"
  git reset --hard HEAD
fi

# Clean untracked files
git clean -fd

echo ""
echo "Rollback complete. Current state:"
git log --oneline -5
