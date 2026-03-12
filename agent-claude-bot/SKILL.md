---
name: agent-claude-bot
description: Start the autonomous multi-agent dev loop — orchestrator + workers in tmux solving tickets from .tmp/llm.plan.status
argument-hint: plan | running | status
---

# claude-bot — Autonomous Dev Loop

Start a tmux-based orchestrator that runs N workers in parallel to solve project tickets autonomously.

## What This Does

1. Creates a tmux session named after the project folder
2. Runs an orchestrator (Haiku) that reads `.tmp/llm.plan.status` and assigns tickets to workers
3. Spawns N workers (Sonnet) in separate tmux windows
4. Each worker: git clean → implement ticket → `Skill(developing-programming)` → commit
5. Orchestrator monitors workers (kills if >900s), collects results, loops (50 cycles max)

## Prerequisites

The target project must have:
- `.tmp/llm.plan.status` — ticket list with `[ ]` / `[x]` checkboxes
- `README.md` — project overview

## Worker Workflow

### On Start — Read These First

1. `README.md` — project overview, architecture, tech stack
2. `.tmp/llm.plan.status` — ticket list and current status
3. `.tmp/llm.working.log` — abstract of recent completed work
4. `.tmp/llm.working.notes` — detailed working notes (if exists)
5. Any `.tmp/llm*md` files — design docs, API specs, references

### Step 1: Clean Slate
```bash
git status
# If there are uncommitted changes → git reset --hard HEAD
```

### Step 2: Pick ONE Ticket
- Read `.tmp/llm.plan.status`
- Find the first `[ ]` (unchecked) ticket
- Work on ONLY that ticket

### Step 3: Implement
- Make the smallest possible change to complete the ticket
- Stay in scope — don't refactor unrelated code

### Step 4: Test, Format, Lint, Commit
Use `Skill(developing-programming)` — follow developing.md workflow.

### Step 5: Update Status
1. Mark the ticket `[x]` in `.tmp/llm.plan.status`
2. Append a summary to `.tmp/llm.working.log`:
   ```
   [W{id}] <what was done> — <files changed>
   ```

## Worker Rules

- **ONE ticket per session.** Do not batch multiple tickets.
- **Never ask questions.** Make reasonable decisions and document them in the commit message.
- **Stay in your assigned scope.** Don't touch files outside your task boundary.
- **If stuck after 3 attempts:** `git stash`, write BLOCKED to the trigger file, stop.
- **All tests must pass** before committing.
- **Don't break existing tests.**
- **Commit messages:** `ticket: <verb> <what>` (e.g., `ticket: add user auth endpoint`)

## Usage

The planning phase designs custom runner scripts in the target project's `.tmp/claude-bot/`.

Start the bot:
```bash
bash .tmp/claude-bot/start.sh $ARGUMENTS
```

Monitor:
```bash
tmux attach -t <project-folder-name>
```

Stop:
```bash
bash .tmp/claude-bot/stop.sh $ARGUMENTS
```

## Planning Phase

Before running the bot, use the planning phase to discuss and design tickets with the user.
See [plan/plan.md](plan/plan.md) for the full planning workflow.
See [plan/examples/plan-session.md](plan/examples/plan-session.md) for an example session.

## Example Scripts

The [example-scripts/](example-scripts/) directory contains **reference implementations** — patterns to learn from, not scripts to copy. During planning, Claude designs custom scripts in `.tmp/claude-bot/` tailored to the project.

| Example | Pattern |
|---------|---------|
| [start.sh](example-scripts/start.sh) | tmux session setup |
| [stop.sh](example-scripts/stop.sh) | Cleanup trigger/lock files |
| [orchestrator.sh](example-scripts/orchestrator.sh) | Plan → spawn → monitor(900s) → collect loop |
| [worker.sh](example-scripts/worker.sh) | Clean → read context → work → `Skill(developing-programming)` → commit |
| [checkpoint.sh](example-scripts/checkpoint.sh) | Git commit with lock |
| [rollback.sh](example-scripts/rollback.sh) | Git reset --hard |

## Architecture

```
tmux session: "<project-folder-name>"
 ├── window 0: orchestrator.sh (Haiku — plans tasks, monitors workers)
 ├── window 1: worker.sh #1   (Sonnet — picks ticket, codes, tests, commits)
 ├── window 2: worker.sh #2   (Sonnet — picks ticket, codes, tests, commits)
 └── ...N workers
```

### Model Usage

| Role | Model | Why |
|------|-------|-----|
| Orchestrator (planner) | Haiku | Fast, cheap — only reads status and assigns tasks |
| Worker | Sonnet | Smart enough to code, test, and commit correctly |

### Orchestrator Cycle (50 rounds max)

```
1. Plan: read .tmp/llm.plan.status → call claude (haiku) to assign tasks
2. Spawn: launch N workers in tmux windows
3. Monitor: poll _trigger_{id} files → kill workers if >900s
4. Collect: read DONE/BLOCKED results
5. Sleep 5s → next cycle
```

### Worker Cycle (one ticket per round)


1. Clean: git status → reset --hard if dirty
2. Read: .tmp/llm.plan.status, .tmp/llm.working.log, README.md
3. Work: implement the assigned ticket
4. `Skill(developing-programming)`: test → format → lint → commit
5. Signal: write DONE to _trigger_{id}


## Coordination

| Mechanism | How | Why |
|-----------|-----|-----|
| **Git Lock** | `mkdir _git.lock` (atomic) | Only one worker commits at a time |
| **Trigger Files** | `_trigger_{id}` with DONE/BLOCKED | Workers signal completion to orchestrator |
| **Task Queue** | `_task_queue` file | Orchestrator writes planned tasks |
| **Timeout** | 900s (15 min) | Kill stuck workers, orchestrator continues |

## File Conventions

These files live in the **target project**:

| File | Required | Purpose |
|------|----------|---------|
| `README.md` | Yes | Project overview |
| `.tmp/llm.plan.status` | Yes | Ticket list with `[ ]`/`[x]` checkboxes |
| `.tmp/llm.working.log` | Auto-created | Abstract of completed work (append-only) |
| `.tmp/llm.working.notes` | Optional | Detailed working notes |
| `.tmp/llm*.md` | Optional | Design docs, references, specs |

### .tmp/llm.plan.status format

```markdown
## Phase 1: Core
- [x] Initialize project scaffold
- [ ] Add database models         ← worker picks this
- [ ] Create API endpoints
```

- Each ticket must be small enough to implement, test, and commit in <15 minutes
- Use `[ ]` for pending, `[x]` for done
- Workers mark `[x]` after committing

### .tmp/llm.working.log format (auto-generated by workers)

```
[W1] Initialized project scaffold — created package.json, tsconfig, src/ structure
[W2] Added database models — User, Post, Comment with Prisma schema
```

## Logs

```
<project_dir>/.tmp/out/
├── orchestrator.log
├── worker_1.log
├── worker_2.log
└── ...
```
