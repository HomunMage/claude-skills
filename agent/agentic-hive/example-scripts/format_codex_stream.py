#!/usr/bin/env python3
"""Render ``codex exec --json`` JSONL events as compact progress lines."""

from __future__ import annotations

import json
import sys
from typing import Any


def _text(value: Any) -> str:
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, list):
        return "\n".join(filter(None, (_text(part) for part in value))).strip()
    if isinstance(value, dict):
        for key in ("text", "content", "message", "output_text"):
            if key in value:
                return _text(value[key])
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return ""


def _single_line(value: Any, limit: int = 500) -> str:
    rendered = " ".join(_text(value).split())
    return rendered if len(rendered) <= limit else f"{rendered[: limit - 1]}…"


def format_event(event: dict[str, Any]) -> list[str]:
    event_type = str(event.get("type", "event")).replace("_", ".")
    item = event.get("item") if isinstance(event.get("item"), dict) else {}
    item_type = str(item.get("type", "")).replace("_", ".")

    if event_type == "thread.started":
        thread_id = event.get("thread_id") or event.get("threadId")
        return [f"[codex] thread {thread_id}"] if thread_id else ["[codex] thread started"]
    if event_type in {"turn.started", "task.started"}:
        return ["[codex] turn started"]
    if event_type in {"turn.completed", "task.complete", "task.completed"}:
        usage = event.get("usage")
        if isinstance(usage, dict):
            input_tokens = usage.get("input_tokens", usage.get("inputTokens", "?"))
            output_tokens = usage.get("output_tokens", usage.get("outputTokens", "?"))
            return [f"[codex] turn completed (tokens: {input_tokens} in, {output_tokens} out)"]
        return ["[codex] turn completed"]
    if event_type in {"turn.failed", "task.failed", "error"}:
        message = _single_line(event.get("error") or event.get("message") or event)
        return [f"[codex:error] {message}"]

    if event_type not in {"item.started", "item.updated", "item.completed"}:
        message = _single_line(event.get("message") or event.get("text") or event)
        return [f"[codex:{event_type}] {message}".rstrip()]

    if item_type in {"agent.message", "message"}:
        message = _single_line(item)
        return [f"[codex] {message}"] if message else []
    if item_type == "reasoning":
        reasoning = _single_line(item)
        return [f"[codex:thinking] {reasoning}"] if reasoning else []
    if item_type in {"command.execution", "command"}:
        command = _single_line(item.get("command"))
        status = item.get("status")
        exit_code = item.get("exit_code", item.get("exitCode"))
        if event_type == "item.started":
            return [f"[codex:command] {command}"]
        output = _single_line(item.get("aggregated_output") or item.get("output"))
        suffix = f"exit={exit_code}" if exit_code is not None else str(status or "completed")
        lines = [f"[codex:command:{suffix}] {command}"]
        if output:
            lines.append(f"[codex:output] {output}")
        return lines
    if item_type in {"file.change", "file.changes"}:
        changes = item.get("changes") or item.get("path") or item
        return [f"[codex:file] {_single_line(changes)}"]
    if item_type in {"mcp.tool.call", "tool.call"}:
        name = item.get("server") or item.get("name") or item.get("tool") or "tool"
        return [f"[codex:tool] {name}"]

    summary = _single_line(item)
    return [f"[codex:{item_type or 'item'}] {summary}".rstrip()]


def main() -> None:
    for raw_line in sys.stdin:
        line = raw_line.rstrip("\n")
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            print(line, flush=True)
            continue
        if not isinstance(event, dict):
            print(line, flush=True)
            continue
        for rendered in format_event(event):
            print(rendered, flush=True)


if __name__ == "__main__":
    main()
