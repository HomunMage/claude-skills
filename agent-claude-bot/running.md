# Running — Start, Monitor, Stop

## Start

```bash
bash .tmp/claude-bot/run.sh          # 1 worker, 50 cycles
bash .tmp/claude-bot/run.sh 50 2     # 2 workers, 50 cycles
```

## Monitor — REQUIRED, every 3 minutes

**After starting the bot, immediately arm a Monitor that polls every 180 s.**
Without it, you have no way to detect when the orchestrator self-exits, a
worker hangs, or the API goes 500. This is mandatory, not optional.

Use Claude Code's `Monitor` tool (NOT a sleep loop, NOT `/loop`) — it streams
one event per tick straight into the chat:

```
Monitor(
  command:
    'cd <project>; while true; do
       TS=$(date "+%H:%M:%S")
       ORCH=$(pgrep -f "orchestrator.sh" | head -1)
       WORKERS=$(tmux list-windows -t LatticeCast-bot 2>/dev/null \
         | grep -cE "^[0-9]+: w[0-9]+-")
       LAST=$(tail -1 .tmp/out/orchestrator.log 2>/dev/null \
         | sed "s/^[0-9:]* \[ORCH\] //" | head -c 100)
       STATS=$(curl -s "$LC_API/tables/$TABLE_ID/rows?limit=200" \
         -H "$LC_AUTH_HEADER" 2>/dev/null \
         | python3 -c "import sys,json
try: rows=json.load(sys.stdin)
except: print(\"API_ERROR\"); sys.exit()
sid=\"<status_col_id>\"; tyid=\"<type_col_id>\"; c={}
for r in rows:
    if r[\"row_data\"].get(tyid) in (\"task\",\"bug\"):
        c[r[\"row_data\"].get(sid,\"?\")] = c.get(r[\"row_data\"].get(sid,\"?\"),0)+1
print(\" \".join(f\"{k}={v}\" for k,v in sorted(c.items())) or \"none\")")
       H=ok
       [ -z "$ORCH" ] && H=ORCH_DEAD
       echo "$LAST" | grep -qE "TIMEOUT|FAILED|ERROR" && H=ALERT
       echo "$TS [$H] orch=${ORCH:-none} w=$WORKERS | $STATS | $LAST"
       sleep 180
     done',
  description: 'bot health check (3-min cadence)',
  persistent: true,
  timeout_ms: 3600000,
)
```

Each tick yields one line like:
`16:08:21 [ok] orch=2022352 w=1 | done=7 in_progress=1 | Still working: [10] (180s)`

Flag and act on:
- `ORCH_DEAD` — orchestrator exited; check log, restart if needed.
- `ALERT` — log contains TIMEOUT/FAILED/ERROR; investigate.
- `API_ERROR` for ≥2 ticks — backend is 500ing; check `docker compose logs backend`.
- Tickets stuck in `testing` longer than 30 min — worker hung; reap.

`TaskStop` the Monitor when the run is finished.

## Window inspection (live)

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
