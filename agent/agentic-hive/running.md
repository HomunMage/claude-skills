# Running — Start, Monitor, Stop

## Start

```bash
bash .tmp/agentic-hive/run.sh          # 1 bee, 50 cycles
bash .tmp/agentic-hive/run.sh 50 2     # 2 bees, 50 cycles
```

## Monitor — REQUIRED

Immediately after starting the hive, read [monitor.md](monitor.md) and arm a
supervising monitor. It must report into the supervising conversation, not
only a terminal log. Stop it when the hive finishes.

## Window inspection (live)

```bash
tmux attach -t <project-folder-name>
```

Tmux windows: `0:orch  1:w1-task-182  2:w2-bug-45`

## Stop

```bash
bash .tmp/agentic-hive/stop.sh
```

Or from inside tmux: `Ctrl-B` then `:kill-session`

## Recovery

On startup, queen auto-recovers orphaned tickets:
- If `in_progress` tickets exist but no tmux bee window matches → reset to `todo`
- Bee's partial code stays in git working tree — next bee reads it and continues

## Logs

```
.tmp/out/
├── queen.log
├── worker_1.log
└── worker_2.log
```

## Track Progress

Open LatticeCast PM board in browser:
```
http://localhost:13491/<workspace>/<table>
```

Switch to Sprint Board (Kanban) view to see ticket flow:
`todo → in_progress → testing → review → merged`.
