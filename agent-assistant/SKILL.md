---
name: agent-assistant
description: Always-on AI assistant with theme delegation — assistant-main chats, theme-managers autonomously, assistant-main-backup handles recovery
argument-hint: start | stop | status
version: 0.3.0
---

# agent-assistant — Persistent AI Assistant

2 persistent tmux sessions + N theme-manager sessions. All `claude` CLI. Zero API keys.

## skill load rule

if this session is agent-assistant, load this skill high frequently make LLM keep in recent context, not too far.

## Architecture

```
assistant-main (interactive claude — your chat target)
├── assistant-main-backup (interactive claude — backup debug channel)
│
├── theme-{THEME}-manager (claude, loads Skill(agent-claude-bot))
│     └── CBLC orchestrator + workers
│
└── theme-{THEME2}-manager (parallel goals ok)
      └── CBLC orchestrator + workers
```

Hierarchy: `theme > initiative > epic > story > issue`

多層次操作 就像老闆(我)派提大方向vision給高管(agent-assistant)  高管才去跟主管(theme-manager )提各種季度目標(theme) 然後主管派員工(claude-bot)去做任務

## Sessions

| Session | What | How |
|---------|------|-----|
| `assistant-main` | Chat target. Takes themes, spawns theme-managers, reports. | Interactive `claude` |
| `assistant-main-backup` | Debug stuck themes, fix PM state, read logs. | Interactive `claude` |
| `theme-{THEME}-manager` | Autonomous. Initiatives several epics, loads `Skill(agent-claude-bot)`. | Interactive `claude` |

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
session loads this skill (`Skill(agent-assistant)`) to know how to spawn themes.

## Spawn a Theme (from assistant-main)

When the user gives a goal, assistant-main spawns a theme-manager that initiatives several epics:

```bash
THEME="google-oauth"  # kebab-case slug
GOAL="Add Google OAuth login with PKCE to LatticeCast"

tmux new-session -d -s "theme-${THEME}-manager" -c "$PROJECT_DIR" \
  "claude --append-system-prompt 'THEME: ${THEME}
GOAL: ${GOAL}
Load Skill(agent-claude-bot). Execute the full flow:
1. /agent-claude-bot plan — initiative the goal into several epics, each epic into stories/tasks
2. /agent-claude-bot prepare — write config if needed
3. /agent-claude-bot running — start CBLC workers
4. Monitor every 2 minutes using ScheduleWakeup(120s)
5. If stuck tasks: split them, restart CBLC
6. When GOAL fully achieved: report DONE and stop monitoring'"
```

Tell the user: "Theme `{THEME}` started. Attach: `tmux attach -t theme-{THEME}-manager`"

## Check Status

```bash
# List all sessions
tmux list-sessions 2>/dev/null | grep -E '^(assistant-|theme-)'

# Read theme logs
tail .tmp/out/orchestrator.log
tail .tmp/out/worker_*.log
```

Or just ask assistant-main: "how's the oauth theme?" — it reads the logs.

## Stop

```bash
# One theme
tmux kill-session -t "theme-{THEME}-manager"

# Everything
tmux kill-session -t assistant-main 2>/dev/null
tmux kill-session -t assistant-main-backup 2>/dev/null
tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^theme-' | xargs -I{} tmux kill-session -t {}
```

## assistant-main Rules

- You are the user's chat interface. Discuss, plan, report.
- NEVER write application code yourself.
- NEVER run CBLC directly. Spawn a theme-manager for that.
- One theme-manager per theme. Name: kebab-case, short.
- Parallel themes OK if they don't touch overlapping files.
- If something breaks: tell user to `tmux attach -t assistant-main-backup`.
- **Monitoring boundary:** Only monitor theme-manager health (alive / stuck / crashed) every 5 min. Do NOT drill into worker logs, worker progress, or CBLC internals — that is the theme-manager's job.

you prompot theme manager every 2 min monitor if CBLC bot right working.

## assistant-main-backup Rules

- You are the recovery channel. User comes here when things break.
- Read worker/theme/orchestrator logs in `.tmp/out/`
- Query LC PM directly via curl
- Fix stuck tickets (PUT status back to todo)
- Restart workers, resolve merge conflicts
- Full codebase access — read, edit, test

## theme-manager Rules

- You are autonomous. No user interaction needed.
- Load `Skill(agent-claude-bot)` — it has the full CBLC workflow.
- Flow:
  1. (Optional)**Create PM table** — `POST /api/v1/tables/template/pm` to create a fresh PM table for this theme if necessary. Each theme gets its own table, its own TABLE_ID.
  2. **Initiative** — decompose goal into several epics, each epic into stories/tasks in the new table
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
