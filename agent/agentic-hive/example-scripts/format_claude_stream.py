#!/usr/bin/env python3
"""Pretty-print `claude -p --output-format=stream-json --verbose` output.

Reads one JSON event per line on stdin, emits a single human-readable
line per event so `tail -F` and `tmux attach` show real-time progress
instead of one opaque blob at the end of a slow LLM call.

Copy this into the project's `.tmp/agentic-hive/` next to bee.sh.
"""
import json
import sys


def _trunc(s: str, n: int) -> str:
    s = (s or "").replace("\n", " ⏎ ")
    return s if len(s) <= n else s[: n - 1] + "…"


def main() -> None:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            print(line, flush=True)
            continue

        t = e.get("type")
        if t == "assistant":
            for c in e.get("message", {}).get("content", []):
                ct = c.get("type")
                if ct == "thinking":
                    print("🧠 " + _trunc(c.get("thinking", ""), 240), flush=True)
                elif ct == "text":
                    print("💬 " + _trunc(c.get("text", ""), 240), flush=True)
                elif ct == "tool_use":
                    args = _trunc(json.dumps(c.get("input", {})), 200)
                    print(f"🔧 {c.get('name')} {args}", flush=True)
        elif t == "user":
            for c in e.get("message", {}).get("content", []):
                if c.get("type") == "tool_result":
                    body = c.get("content", "")
                    if isinstance(body, list):
                        body = " ".join(
                            b.get("text", "") if isinstance(b, dict) else str(b)
                            for b in body
                        )
                    print("✓  " + _trunc(str(body), 160), flush=True)
        elif t == "result":
            ms = e.get("duration_ms", "?")
            usd = e.get("total_cost_usd", "?")
            err = e.get("is_error")
            print(f"━ DONE ms={ms} usd={usd} error={err}", flush=True)


if __name__ == "__main__":
    main()
