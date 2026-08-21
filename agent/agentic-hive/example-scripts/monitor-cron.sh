#!/usr/bin/env bash
# monitor-cron.sh — cron entrypoint: log hive health, then resume Codex chat.
# Usage: bash monitor-cron.sh <project_dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
if [ -f "${ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

PROJECT_DIR="${1:?Usage: monitor-cron.sh <project_dir>}"
PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"
: "${MONITOR_CODEX_SESSION_ID:?MONITOR_CODEX_SESSION_ID must be set in .env}"

OUT_DIR="${PROJECT_DIR}/.tmp/out"
LOCK_FILE="${OUT_DIR}/hive-monitor.lock"
RUN_LOG="${OUT_DIR}/hive-monitor-cron.log"
mkdir -p "${OUT_DIR}"

exec 9>"${LOCK_FILE}"
flock -n 9 || exit 0

STAMP="$(date '+%Y-%m-%d %H:%M:%S %z')"
PROMPT="Check ${OUT_DIR}/hive-monitor.log and ${OUT_DIR}/queen.log, then report the current hive status in this chat. Trigger time: ${STAMP}."
printf '%s cron resume session=%s\n' "${STAMP}" "${MONITOR_CODEX_SESSION_ID}" >> "${RUN_LOG}"

# Do not use tmux send-keys or C-m: terminal input cannot prove submit.
cd "${PROJECT_DIR}"
printf '%s\n' "${PROMPT}" \
  | codex exec resume --json --output-last-message "${OUT_DIR}/hive-monitor-last.md" \
      "${MONITOR_CODEX_SESSION_ID}" - >> "${RUN_LOG}" 2>&1
