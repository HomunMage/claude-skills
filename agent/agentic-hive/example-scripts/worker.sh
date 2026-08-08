#!/bin/bash
# worker.sh — swappable LLM backend for bee.sh
#
# Exposes one function: work <prompt> <log_file>
#   - Runs the configured backend on <prompt>.
#   - Streams human-readable progress lines to stdout, which the caller
#     tees into <log_file> (so `tmux attach` shows live progress).
#   - Returns the backend's exit code — bee.sh's watchdog/ERR trap relies
#     on a non-zero return to flip the ticket to `debugging`.
#
# Backend selection: $LLM_BACKEND (default "claude"). To point the hive
# at a different CLI (codex, hermes, ...), add a case branch below with
# the same contract — nothing in queen.sh or bee.sh needs to change.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLM_BACKEND="${LLM_BACKEND:-claude}"

work() {
  local prompt="$1"
  local log_file="$2"

  case "$LLM_BACKEND" in
    claude)
      # stream-json + verbose = live event stream (thinking, tool_use,
      # tool_result, final result). format_claude_stream.py renders each
      # event as one line so `tmux attach` shows progress in real time
      # instead of waiting for the final blob.
      CLAUDECODE= claude -p \
        --dangerously-skip-permissions \
        --output-format=stream-json --verbose \
        "${prompt}" 2>&1 \
      | python3 -u "${SCRIPT_DIR}/format_claude_stream.py" \
      | tee -a "$log_file"
      return "${PIPESTATUS[0]}"
      ;;

    codex)
      # Stub: wire up `codex exec` (or equivalent) here. Keep the same
      # contract — write progress lines to stdout/$log_file, return the
      # backend's real exit code so the watchdog/ERR trap still work.
      echo "worker.sh: LLM_BACKEND=codex has no implementation yet — add one in ${BASH_SOURCE[0]}" \
        | tee -a "$log_file" >&2
      return 1
      ;;

    hermes)
      # Stub: same contract as above, for a Hermes-compatible CLI/API.
      echo "worker.sh: LLM_BACKEND=hermes has no implementation yet — add one in ${BASH_SOURCE[0]}" \
        | tee -a "$log_file" >&2
      return 1
      ;;

    *)
      echo "worker.sh: unknown LLM_BACKEND='${LLM_BACKEND}' (known: claude, codex, hermes)" >&2
      return 1
      ;;
  esac
}
