#!/usr/bin/env bash
# seo-bot/run.sh — Entry point. Sources config + lc_api, then runs
# the orchestrator to loop TA × promotion × product cross product.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${SEO_DIR}/.env"
if [ -f "${ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

bash "${SCRIPT_DIR}/orchestrator.sh"
