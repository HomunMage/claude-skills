#!/bin/bash
# worker.sh — ticket-work interface used by bee.sh
#
# Keep orchestration code coupled to work(), not to a specific model CLI.
# llm.sh owns provider selection, invocation, streaming, and termination.

WORKER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${WORKER_SCRIPT_DIR}/llm.sh"

work() {
  llm_run "$@"
}

work_stop() {
  llm_stop "$@"
}
