---
name: agent/swarm-cluster
description: Persistent cluster that delegates goal-scoped swarms to agentic hives; use for multi-initiative autonomous delivery and recovery
version: 0.6.6
---

# swarm-cluster

`cluster-main` is the CEO-facing chat: the user gives it a vision; it assigns
each independent goal to a swarm executive. A swarm owns execution through
one or more hives.

## Architecture

```
cluster-main (interactive agent cli — user chat target)
├── cluster-backup (interactive agent cli — recovery channel)
│
├── swarm-{SWARM1} (agent cli; plans and runs hives)
│     ├── hive1: queen + bees
│     └── hive2: queen + bees
│
└── swarm-{SWARM2} (parallel independent goal)
      └── hive3: queen + bees
```

Hierarchy: `cluster > swarm > hive ( epic > story > issue )`

多層次操作：老闆給 cluster 一個 vision；cluster 切分不同目標交給 swarm；
swarm 管理一個或多個 hive，讓 queen + bees 完成 hive 內的 epic、story、issue。


## cluster-main Rules

- You are the CEO and the user's chat interface: discuss, scope goals, assign
  swarms, verify, and report.
- NEVER do work yourself — no code, no git operations, no file changes in the project. ALL work goes through swarms.
- NEVER run a hive directly. Start a swarm in tmux; the swarm owns its hives.
- One swarm per independent goal. `SWARM` is a short kebab-case slug.
- Parallel swarms are OK only when they do not touch overlapping files.
- If something breaks: inspect `cluster-backup` through its pane; do not attach
  an interactive client to a cluster or swarm session.
- **Delegate:** Split a vision into independent goals before starting swarms. Do
  not pass an unscoped prompt to a swarm.
- **Verify:** When a swarm says `DONE`, verify the actual output before
  reporting completion.

## swarm Rules

- A swarm is the high-level executive for exactly one independent goal.
- It loads `Skill(agent/agentic-hive)`, owns planning, and manages one or more
  hives until the goal is verified.
- Use multiple hives only for independent work: no overlapping files, branches,
  or tickets. Dependency and branch rules remain in `Skill(agent/agentic-hive)`.
- A swarm reports goal status to `cluster-main`; it does not ask the user to
  coordinate hive work.

## tmux Rules

All cluster and swarm coordination happens in tmux. Start swarm sessions in
the project root; hive-owned story worktrees remain the responsibility of
`Skill(agent/agentic-hive)`.

- `cluster-main` starts a swarm and inspects its pane with `tmux capture-pane`.
- A swarm plans, starts, monitors, and stops every hive it owns.
- `cluster-main` must not kill a swarm tmux session. To stop work, request the
  swarm to stop all its hives; after they stop, the swarm ends its own session.


### Start a swarm

Set `AGENT_CLI` to the installed interactive agent command. The swarm owns one
goal and can start one or more agentic hives.

```bash
SWARM="google-oauth"
GOAL="Add Google OAuth login with PKCE to LatticeCast"
AGENT_CLI="claude"  # or another compatible interactive agent CLI
SWARM_PROMPT=$(cat <<EOF
SWARM: ${SWARM}
GOAL: ${GOAL}
Load Skill(agent/agentic-hive). Plan the swarm goal into one or more hives,
then each hive into epics, stories, and tasks. Prepare, run, and monitor every
hive. Report DONE only after the goal is verified.
EOF
)

tmux new-session -d -s "swarm-${SWARM}" -c "$PROJECT_DIR" \
  "$AGENT_CLI --append-system-prompt $(printf '%q' "$SWARM_PROMPT")"
```

### Inspect and stop

From `cluster-main`, read the swarm's pane directly. Do not use `tmux attach`:

```bash
tmux capture-pane -p -t "swarm-${SWARM}:0.0" -S -200
```

To stop work, request the swarm to stop every hive it owns first. The swarm
then ends its own tmux session. `cluster-main` may inspect but does not kill
the swarm tmux session.


## Skill Dependencies

```
agent/swarm-cluster (cluster)
      └── agentic-hive (queen + bees)
            └── developing/project-management (pm_tool.sh + lc_api.sh)
            └── developing/programming (test/format/lint)
```
