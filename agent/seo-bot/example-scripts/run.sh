#!/usr/bin/env bash
# seo-bot/run.sh — Entry point. Sources config + lc_api, then runs
# the orchestrator to loop TA × promotion × product cross product.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck disable=SC1091
source "${SEO_DIR}/config.sh"

bash "${SCRIPT_DIR}/orchestrator.sh"
