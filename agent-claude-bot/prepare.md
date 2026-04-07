# Prepare — Write Runner Scripts

After planning creates tickets in LatticeCast PM, prepare the runner scripts before starting workers.

## Step 1: Create `.tmp/claude-bot/` directory

```bash
mkdir -p .tmp/claude-bot .tmp/out
```

## Step 2: Copy scripts from skills examples

```bash
cp .claude/skills/agent-claude-bot/example-scripts/start.sh .tmp/claude-bot/
cp .claude/skills/agent-claude-bot/example-scripts/stop.sh .tmp/claude-bot/
cp .claude/skills/agent-claude-bot/example-scripts/orchestrator.sh .tmp/claude-bot/
cp .claude/skills/agent-claude-bot/example-scripts/worker.sh .tmp/claude-bot/
chmod +x .tmp/claude-bot/*.sh
```

## Step 3: Copy pm_tools.sh from PM skill

```bash
cp .claude/skills/developing-project-management/pm_tools.sh .tmp/claude-bot/
```

Worker and orchestrator `source` this file for all PM operations (status, doc, create ticket).

## Step 4: Create `run.sh` wrapper

Set `TABLE_ID` for this project's PM table:

```bash
cat > .tmp/claude-bot/run.sh << 'EOF'
#!/bin/bash
SD="$(cd "$(dirname "$0")" && pwd)"; PD="$(cd "$SD/../.." && pwd)"
export TABLE_ID="<paste_table_id_here>"
exec bash "$SD/start.sh" "$PD" "${1:-50}" "${2:-1}"
EOF
chmod +x .tmp/claude-bot/run.sh
```

## File layout after prepare

```
.tmp/claude-bot/
├── run.sh              ← project-specific wrapper (TABLE_ID)
├── start.sh            ← tmux session setup
├── stop.sh             ← kill session
├── orchestrator.sh     ← pure rule-based task dispatch
├── worker.sh           ← bash infra + LLM code
└── pm_tools.sh         ← shared PM helpers (from developing-project-management)
```

## Checklist before running

- [ ] LatticeCast PM running (`curl localhost:13491/api/status`)
- [ ] TABLE_ID set in `run.sh`
- [ ] `pm_tools.sh` copied
- [ ] `_col_cache.json` will be auto-created by orchestrator at startup
