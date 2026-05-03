# Prepare — Write Runner Scripts

After planning creates tickets in LatticeCast PM, prepare the runner scripts before starting workers.

**IMPORTANT: Do NOT `cp` from example-scripts/. Write each script file from scratch**, referencing `example-scripts/` as a pattern guide. Each project may need different context, skills, test commands, or worker pipeline steps.

## Step 1: Create directories

```bash
mkdir -p .tmp/claude-bot .tmp/out
```

## Step 2: Write each script

Read the example scripts in `.claude/skills/agent-claude-bot/example-scripts/` to understand the patterns, then **write customized versions** for this project:

### 2a. `run.sh` — project-specific wrapper
- Set `TABLE_ID` for this project's PM table
- Call `start.sh` with project dir, max cycles, num workers

### 2b. `start.sh` — tmux session setup
- Validate PM is running
- Kill existing session
- Start orchestrator in tmux window 0

### 2c. `stop.sh` — kill session
- Kill tmux session, clean up lock files

### 2d. `orchestrator.sh` — pure rule-based task dispatch (NO LLM)
- Cache column IDs at startup (`_col_cache.json`)
- Recover orphaned in_progress tickets
- Loop: query todo → spawn workers → poll PM until done → cleanup

### 2e. `worker.sh` — bash infra + LLM code
- Extract row_number from task description
- Set status to `in_progress` immediately (bash, not LLM)
- Build context from CLAUDE.md, README.md, skills, ticket doc
- Pipeline: implement → test → commit → done
- PM status updates via bash helpers (never LLM)

### 2f. `config.sh` — per-project values

```bash
export LC_API="http://localhost:13491/api/v1"
export LC_AUTH_HEADER="Authorization: Bearer claude"
export PM_USER="claude"
export TABLE_ID="pm"
export WORKSPACE_ID="<uuid>"
_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_DIR="$(cd "${_THIS_DIR}/../.." && pwd)"
export SKILLS_DIR="${PROJECT_DIR}/.claude/skills"
```

That's it. The helpers (`pm_*`, `lc_*`) are sourced from the skill,
not duplicated per project:

```bash
# at the top of orchestrator.sh / worker.sh:
source "${SCRIPT_DIR}/config.sh"
source "${SKILLS_DIR}/developing-project-management/pm_tool.sh"
# pm_tool.sh auto-sources lc_api.sh from developing-lattice-cast
```

## Customization points per project

When writing scripts, tailor these to the specific project:

| What | Customize |
|------|-----------|
| **Context files** | Which files to load (CLAUDE.md, README.md, .tmp/llm*.md) |
| **Skills loaded** | Which `Skill(developing-*)` to include in worker prompt |
| **Test commands** | FE: svelte-check, build. BE: pytest, ast.parse. Or project-specific |
| **Num workers** | 1 for simple tasks, 2-3 for parallel stories |
| **Worker prompt** | Task-specific rules, file restrictions, coding patterns |

## File layout after prepare

```
.tmp/claude-bot/
├── config.sh           ← per-project: LC_API, WORKSPACE_ID, TABLE_ID, …
├── run.sh              ← bash run.sh — sources config.sh, calls start.sh
├── start.sh            ← tmux session setup
├── stop.sh             ← kill session
├── orchestrator.sh     ← pure rule-based task dispatch
└── worker.sh           ← bash infra + LLM code
```

PM/LC helpers (`pm_*`, `lc_*`) live in the skill submodule, not in
`.tmp/claude-bot/`. Scripts source them from `${SKILLS_DIR}`.

## Checklist before running

- [ ] LatticeCast PM running (`curl localhost:13491/api/v1/status`)
- [ ] TABLE_ID set in `run.sh`
- [ ] All 6 scripts written and `chmod +x`
- [ ] `_col_cache.json` will be auto-created by orchestrator at startup
