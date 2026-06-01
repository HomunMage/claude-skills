# Spawn a Theme (from assistant-main)

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

## Stop

```bash
# One theme
tmux kill-session -t "theme-{THEME}-manager"

# Everything
tmux kill-session -t assistant-main 2>/dev/null
tmux kill-session -t assistant-main-backup 2>/dev/null
tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^theme-' | xargs -I{} tmux kill-session -t {}
```

## Start Sessions

```bash
PROJECT_DIR="$PWD"

# 1. assistant-main
tmux new-session -d -s assistant-main -c "$PROJECT_DIR" "claude"

# 2. assistant-main-backup
tmux new-session -d -s assistant-main-backup -c "$PROJECT_DIR" "claude"

# Attach
tmux attach -t assistant-main
```

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

## assistant-main-backup Rules

- You are the recovery channel. User comes here when things break.
- Read worker/theme/orchestrator logs in `.tmp/out/`
- Query LC PM directly via curl
- Fix stuck tickets (PUT status back to todo)
- Restart workers, resolve merge conflicts
- Full codebase access — read, edit, test


## Dependencies

```
agent-assistant (this skill)
  └── agent-claude-bot (CBLC: plan, prepare, orchestrator, workers)
        └── developing-project-management (pm_tool.sh)
              └── developing-lattice-cast (lc_api.sh)
        └── developing-programming (test/format/lint)
```
