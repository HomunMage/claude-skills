---
name: agent-claude-bot
description: Start the autonomous multi-agent dev loop — orchestrator + workers in tmux solving tickets from LatticeCast PM
argument-hint: plan | running | status
version: 0.18.0
---

# claude-bot — Autonomous Dev Loop

Start a tmux-based orchestrator that runs N workers in parallel to solve project tickets autonomously.

## Flow

```
1. User calls /claude-bot plan
2. Planning: discuss design → write .tmp/llm.design.*.md for review
3. User approves → create tickets in LatticeCast PM
5. User approve start workers
6. Workers: query PM → pick todo ticket → worktree branch → implement → update status → merge
```

## Prerequisites

- **LatticeCast PM running** — `http://localhost:13491/api/status` must respond
- See `Skill(developing-project-management)` for setup (git clone + docker compose up)
- `README.md` — project overview

## Branch Hierarchy

Tickets follow a strict 3-level hierarchy: **Epic → Story → Issue**

| Level | Branch base | Merges into |
|-------|-------------|-------------|
| Epic  | (no branch — grouping only) | — |
| Story | `main` | `main` (when all issues merged) |
| Issue | story branch | story branch |

```
main
└── story/{story-slug}          ← branched from main
    ├── issue/{issue-1-slug}    ← branched from story branch
    ├── issue/{issue-2-slug}    ← branched from story branch
    └── issue/{issue-N-slug}    ← branched from story branch
```

**Workers only implement issues.** Stories are never directly coded — they are merged into main automatically once all their issues are done.

## Worker Workflow

### On Start — Read These First

1. `README.md` — project overview, architecture, tech stack
2. **Query LatticeCast PM** — use `Skill(developing-project-management)` "Query Tickets" for current status
3. Any `.tmp/llm*.md` files — design docs, API specs, references
4. **Load `Skill(developing-programming)`** + **`Skill(developing-project-management)`**

### Step 1: Identify Parent Story Branch

Before creating a worktree, look up the issue's parent story in LatticeCast PM:

```bash
# Get the issue row to find parent story row_id
ISSUE_ROW_ID="<row_id>"
TABLE_ID="<table_id>"
# From row_data, get the Parent column value (= story row_id)
# Then fetch that story row to get its Key (e.g. L-5)
# Story branch name: story/{story-key-lowercase}  e.g. story/l-5
STORY_BRANCH="story/<story-key-lowercase>"
```

Ensure the story branch exists; create it from main if not:
```bash
git checkout main
git checkout -b "$STORY_BRANCH" 2>/dev/null || git checkout "$STORY_BRANCH"
```

### Step 2: Create Worktree Branch from Story Branch

```bash
STORY_BRANCH="story/<story-key-lowercase>"
TICKET_KEY="<issue-key>"  # e.g. L-13
SLUG="issue/${TICKET_KEY}/$(echo '<short-description>' | tr ' ' '-')"
git worktree add .tmp/worker_{id} -b "$SLUG" "$STORY_BRANCH"
cd .tmp/worker_{id}
```

Each worker operates in its own worktree — no conflicts.

### Step 3: Pick Ticket → IMMEDIATELY update to `in_progress`
- Query LatticeCast PM for `todo` issues (type=task or type=bug)
- **Update PM status → `in_progress` FIRST** via `PUT /api/tables/{table_id}/rows/{row_number}`
- **Append to doc** via `PUT /api/tables/{table_id}/rows/{row_number}/doc`: `- {timestamp} Picked up by W{id}`
- **Read the issue's doc** — the doc contains implementation instructions from planning
- Work on ONLY that ticket

**IMPORTANT: API uses `row_number` (integer) in URL, NOT `row_id` (UUID).**

### Step 3.5: Check if Test Ticket
- Check the ticket's Tags column in `row_data`
- If tags contain `"test"` → this is a **test ticket**, go to Step 4T instead of Step 4
- If tags do NOT contain `"test"` → normal implementation, go to Step 4

### Step 4T: Test Ticket (tags contain "test")
Instead of writing application code:
1. Start browser: `docker compose --profile browser up -d browser`
2. Write a Playwright test script in `browser/test_{feature}.py` if one doesn't exist
3. Run: `docker compose exec browser python3 browser/test_{feature}.py`
4. Screenshots saved to `.browser/`
5. Append screenshot paths + pass/fail to ticket doc
6. Go to Step 5 (commit the test script)

### Step 4: Implement — MUST update doc continuously
- Make the smallest possible change to complete the ticket
- **Append to doc** after each significant step:
  - `- {timestamp} Reading {file} to understand existing pattern`
  - `- {timestamp} Creating {file} with {description}`
  - `- {timestamp} Modifying {file}: {what changed}`
  - `- {timestamp} Decision: {why I chose X over Y}`
- Stay in scope — don't refactor unrelated code
- **After ANY FE visual change**, take a Playwright snapshot via `docker compose exec browser` and verify it looks correct

### Step 5: Test, Format, Lint, Commit
Use `Skill(developing-programming)` workflow:
- Update PM status → `testing` via `PUT /api/tables/{table_id}/rows/{row_number}`
- Run tests (if fail → `debugging`, append error to doc)
- Format + lint
- Commit → update PM status to `review`

### Step 6: Merge Issue into Story Branch & Cleanup

```bash
cd <project-root>
git checkout "$STORY_BRANCH"
git merge "$SLUG"                      # merge issue into story branch
git worktree remove .tmp/worker_{id}
git branch -d "$SLUG"
```

Update PM status → `merged`

### Step 7: Check if All Story Issues Done → Merge Story into Main

After marking the issue merged, check sibling issues in PM:

```bash
# Query all rows in table, filter by Parent = <story_row_id>
# If ALL sibling issues have status=merged:
git checkout main
git merge "$STORY_BRANCH"
git branch -d "$STORY_BRANCH"
# Update story PM status → merged
```

If siblings are **not all merged**, leave the story branch open and signal DONE.

### Step 8: Signal Done
Write DONE to trigger file for orchestrator.

## Worker Rules

- **ONE ticket per session.** Do not batch multiple tickets.
- **Never ask questions.** Make reasonable decisions and document them in the commit message.
- **Stay in your assigned scope.** Don't touch files outside your task boundary.
- **If stuck after 3 attempts:** write BLOCKED to the trigger file, stop.
- **All tests must pass** before committing.
- **Don't break existing tests.**
- **Commit messages:** `ticket-<row_number>: <verb> <what>` (e.g., `ticket-42: add user auth endpoint`)
- **Issue branches base off story branch, not main.**
- **Story branches base off main.**
- **CRITICAL: Continuously update the ticket doc.** Use `PUT /api/tables/{table_id}/rows/{row_number}/doc` (row_number, NOT row_id). Append timestamped entries after EVERY action. Empty doc after work = FAILED.
- **CRITICAL: FE changes MUST have `.browser/` snapshot.** Run `docker compose exec browser python3 -c "..."` with Playwright to screenshot. If the snapshot looks wrong, fix before committing.
- **API uses row_number (integer) in URL paths**, not row_id (UUID). Example: `PUT /api/tables/{tid}/rows/42` not `PUT /api/rows/{uuid}`.
- **If stuck:** diagnose why, append error + analysis to ticket doc, try different approach. If can't finish in time: commit partial work, log what's done and what's left in doc, set status to `review`, signal DONE. Next worker picks up from where you left off by reading the doc.

## Usage

Start the bot:
```bash
bash .tmp/claude-bot/start.sh
```

Monitor:
```bash
tmux attach -t <project-folder-name>
```

Stop:
```bash
bash .tmp/claude-bot/stop.sh
```

## Planning Phase

Before running the bot, use the planning phase to discuss and design tickets with the user.
See [plan/plan.md](plan/plan.md) for the full planning workflow.

## Example Scripts

The [example-scripts/](example-scripts/) directory contains **reference implementations**.

| Example | Pattern |
|---------|---------|
| [start.sh](example-scripts/start.sh) | tmux session setup |
| [stop.sh](example-scripts/stop.sh) | Cleanup trigger/lock files |
| [orchestrator.sh](example-scripts/orchestrator.sh) | Plan → spawn → monitor(900s) → collect loop |
| [worker.sh](example-scripts/worker.sh) | Worktree → implement → `Skill(developing-programming)` → merge |
| [checkpoint.sh](example-scripts/checkpoint.sh) | Git commit with lock |

## Architecture

```
tmux session: "<project-folder-name>"
 ├── window 0: orchestrator.sh (pure bash+python — queries PM, assigns tasks. NO LLM.)
 ├── window 1: worker.sh #1   (Sonnet — picks ticket, codes, tests, commits)
 ├── window 2: worker.sh #2   (Sonnet — picks ticket, codes, tests, commits)
 └── ...N workers
```

### Orchestrator Cycle (50 rounds max)

**CRITICAL: Orchestrator uses pure bash+python for ticket querying. NEVER use haiku/LLM to query PM — it hallucinates ALL_DONE.**

```
1. Query: curl PM API + python filter (status=todo, type=task/bug) — NO LLM
2. Spawn: launch N workers in tmux windows
3. Monitor: poll _trigger_{id} files → kill workers if >900s
4. Collect: read DONE/BLOCKED results
5. Sleep 5s → next cycle
```

### Worker Cycle (one ticket per round)

```
1. Lookup: find parent story branch from issue's Parent field in PM
2. Branch: git worktree add .tmp/worker_{id} -b issue/{slug} story/{story-slug}
3. Query: LatticeCast PM for assigned todo issue
4. Work: implement the ticket, update PM status throughout
5. Skill(developing-programming): test → format → lint → commit
6. Merge: merge issue branch into story branch, remove worktree, PM → merged
7. Check: if all sibling issues merged → merge story into main, PM story → merged
8. Signal: write DONE to _trigger_{id}
```

## Coordination

| Mechanism | How | Why |
|-----------|-----|-----|
| **Git Worktree** | `git worktree add .tmp/worker_{id}` | Isolated branch per worker |
| **Git Lock** | `mkdir _git.lock` (atomic) | Only one worker merges at a time |
| **Trigger Files** | `_trigger_{id}` with DONE/BLOCKED | Workers signal completion |
| **LatticeCast PM** | HTTP API for ticket status | Single source of truth for tickets |
| **Timeout** | 900s (15 min) | Kill stuck workers |

## File Conventions

| File | Purpose |
|------|---------|
| `README.md` | Project overview |
| `.tmp/llm*.md` | Design docs, references (planning phase output) |
| `.tmp/claude-bot/*.sh` | Runner scripts |
| `.tmp/out/*.log` | Worker/orchestrator logs |

**Note:** `.tmp/llm.plan.status` is NOT used. All ticket tracking is in LatticeCast PM. After planning creates tickets in PM, delete `.tmp/llm.plan.status` if it exists.

## Logs

```
<project_dir>/.tmp/out/
├── orchestrator.log
├── worker_1.log
├── worker_2.log
└── ...
```
