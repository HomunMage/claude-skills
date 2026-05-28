---
name: agent-assistant
description: Always-on AI assistant with mission delegation — assistant-main chats, mission-managers load Skill(agent-claude-bot) autonomously, assistant-main-backup handles recovery
argument-hint: start | stop | status
version: 0.1.0
---

# agent-assistant — Persistent AI Assistant

2 persistent tmux sessions + N mission-manager sessions. All `claude` CLI. Zero API keys.

## Architecture

```
assistant-main (interactive claude — your chat target)
├── assistant-main-backup (interactive claude — backup debug channel)
│
├── mission-{slug}-manager (claude, loads Skill(agent-claude-bot))
│     └── CBLC orchestrator + workers
│
└── mission-{slug2}-manager (parallel goals ok)
      └── CBLC orchestrator + workers
```

## Sessions

| Session | What | How |
|---------|------|-----|
| `assistant-main` | Chat target. Takes goals, spawns missions, reports. | Interactive `claude` |
| `assistant-main-backup` | Debug stuck missions, fix PM state, read logs. | Interactive `claude` |
| `mission-{slug}-manager` | Autonomous. Loads `Skill(agent-claude-bot)`, runs full plan→running flow. | Interactive `claude` |

## Start

```bash
PROJECT_DIR="$PWD"

# 1. assistant-main
tmux new-session -d -s assistant-main -c "$PROJECT_DIR" "claude"

# 2. assistant-main-backup
tmux new-session -d -s assistant-main-backup -c "$PROJECT_DIR" "claude"

# Attach
tmux attach -t assistant-main
```

Both sessions auto-load `CLAUDE.md` which loads `Skill(developing*)`. The assistant-main
session loads this skill (`Skill(agent-assistant)`) to know how to spawn missions.

## Spawn a Mission (from assistant-main)

When the user gives a goal, assistant-main creates a new tmux session:

```bash
MISSION="google-oauth"  # kebab-case slug
GOAL="Add Google OAuth login with PKCE to LatticeCast"

tmux new-session -d -s "mission-${MISSION}-manager" -c "$PROJECT_DIR" \
  "claude --append-system-prompt 'MISSION: ${MISSION}
GOAL: ${GOAL}
Load Skill(agent-claude-bot). Execute the full flow:
1. /agent-claude-bot plan — decompose goal into tickets
2. /agent-claude-bot prepare — write config if needed
3. /agent-claude-bot running — start CBLC workers
4. Monitor every 2 minutes using ScheduleWakeup(120s)
5. If stuck tasks: split them, restart CBLC
6. When GOAL fully achieved: report DONE and stop monitoring'"
```

Tell the user: "Mission `{slug}` started. Attach: `tmux attach -t mission-{slug}-manager`"

## Check Status

```bash
# List all sessions
tmux list-sessions 2>/dev/null | grep -E '^(assistant-|mission-)'

# Read mission logs
tail .tmp/out/orchestrator.log
tail .tmp/out/worker_*.log
```

Or just ask assistant-main: "how's the oauth mission?" — it reads the logs.

## Stop

```bash
# One mission
tmux kill-session -t "mission-{slug}-manager"

# Everything
tmux kill-session -t assistant-main 2>/dev/null
tmux kill-session -t assistant-main-backup 2>/dev/null
tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^mission-' | xargs -I{} tmux kill-session -t {}
```

## assistant-main Rules

- You are the user's chat interface. Discuss, plan, report.
- NEVER write application code yourself.
- NEVER run CBLC directly. Spawn a mission-manager for that.
- One mission per goal. Name: kebab-case, short.
- Parallel missions OK if they don't touch overlapping files.
- If something breaks: tell user to `tmux attach -t assistant-main-backup`.

## assistant-main-backup Rules

- You are the recovery channel. User comes here when things break.
- Read worker/mission/orchestrator logs in `.tmp/out/`
- Query LC PM directly via curl
- Fix stuck tickets (PUT status back to todo)
- Restart workers, resolve merge conflicts
- Full codebase access — read, edit, test

## mission-manager Rules

- You are autonomous. No user interaction needed.
- Load `Skill(agent-claude-bot)` — it has the full CBLC workflow.
- Flow:
  1. **Create PM table** — `POST /api/v1/tables/template/pm` to create a fresh PM table for this mission. Each mission gets its own table, its own TABLE_ID.
  2. **Plan** — decompose goal into epic/stories/tasks in the new table
  3. **Prepare** — write `.tmp/claude-bot/config.sh` with the new TABLE_ID
  4. **Running** — start CBLC workers
- After starting CBLC, monitor via `ScheduleWakeup(120s)`:
  - Read `.tmp/out/orchestrator.log` and `worker_*.log`
  - Query LC PM for ticket status
  - If all done but goal not met: create more tickets, restart CBLC
  - If tasks stuck debugging: split them, reset to todo
  - If GOAL verified complete: stop monitoring
- The 900s worker timeout and ticket sizing rules from `Skill(agent-claude-bot)` apply.

## Dependencies

```
agent-assistant (this skill)
  └── agent-claude-bot (CBLC: plan, prepare, orchestrator, workers)
        └── developing-project-management (pm_tool.sh)
              └── developing-lattice-cast (lc_api.sh)
        └── developing-programming (test/format/lint)
```
