#!/usr/bin/env bash
# seo-bot/run.sh — Entry point. Loops the cross product of
# TA × promotion × production and spawns a fresh claude -p worker for
# each missing combination.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck disable=SC1091
source "${SEO_DIR}/config.sh"

bash "${SCRIPT_DIR}/orchestrator.sh"
