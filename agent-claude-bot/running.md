# Running — Start, Monitor, Stop

## Start

```bash
bash .tmp/claude-bot/run.sh          # 1 worker, 50 cycles
bash .tmp/claude-bot/run.sh 50 2     # 2 workers, 50 cycles
```

## Monitor

```bash
tmux attach -t <project-folder-name>
```

Tmux windows: `0:orch  1:w1-task-182  2:w2-bug-45`

## Stop

```bash
bash .tmp/claude-bot/stop.sh
```

Or from inside tmux: `Ctrl-B` then `:kill-session`

## Recovery

On startup, orchestrator auto-recovers orphaned tickets:
- If `in_progress` tickets exist but no tmux worker window matches → reset to `todo`
- Worker's partial code stays in git working tree — next worker reads it and continues

## Logs

```
.tmp/out/
├── orchestrator.log
├── worker_1.log
└── worker_2.log
```

## Track Progress

Open LatticeCast PM board in browser:
```
http://localhost:13491/<workspace>/<table>
```

Switch to Sprint Board (Kanban) view to see ticket flow: `todo → in_progress → testing → done`
