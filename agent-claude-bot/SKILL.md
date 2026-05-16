---
name: agent-claude-bot
description: Start the autonomous multi-agent dev loop — orchestrator + workers in tmux solving tickets from LatticeCast PM
argument-hint: plan | running | status
version: 0.34.1
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

## Ticket Sizing — 900s Hard Cap

Every worker has a **900-second wall clock** before the orchestrator
gives up on it and kills the tmux window. This is non-negotiable —
don't raise it. If a ticket can't be completed in 15 minutes of
worker time, **the ticket is too big — split it before opening**.

Practical sizing rules when filing tickets:

- **One file changed.** If the implementation touches >1 file, the
  description is mixing concerns. Split.
- **One topic** (for tests this is enforced by `developing-e2e-test`'s
  one-topic-per-file rule).
- **<300 lines of new code.** Skim the description: if it sounds like
  "add column type X _and_ wire it through 4 views", that's 5 tickets,
  not 1.
- **Smoke test rerunable in <60s.** Tests that need long-running
  Docker setup or external services blow the budget on docker compose
  warm-up alone.

Signals you went too big:
- Orchestrator log shows `Still working: [N] (900s)` → `TIMEOUT after
  900s` → ticket should be split.
- Worker hits `debugging` 3+ times — usually means the ticket
  description doesn't constrain the surface area enough.

Recovery from a TIMEOUT: see "Recovery rule" below.

## Prerequisites

- **LatticeCast PM running** — `http://localhost:13491/api/v1/status` must respond
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
ISSUE_ROW_NUMBER="<row_id>"
TABLE_ID="<table_id>"
# From row_data, get the Parent column value (= story row_id)
# Then fetch that story row to get its type-<row_id> key (e.g. story-5)
# Story branch name: story/{story-key-lowercase}  e.g. story/story-5
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

### Step 3: Pick Ticket → update status → READ DOC FIRST
- Query LatticeCast PM for `todo` issues (type=task or type=bug)
- **Update PM status → `in_progress` FIRST**
- **READ THE DOC FIRST** via `GET /api/v1/tables/{table_id}/rows/{row_id}/doc`
  - The doc has ALL implementation detail — what to do, which files, decisions, acceptance criteria
  - Title is just a short summary — **doc is the real spec**
  - If a previous worker attempted this ticket, the doc has their work log + what's left
  - **Follow the doc instructions, not just the title**
- Append to doc: `- {timestamp} Picked up by W{id}`
- Work on ONLY that ticket

**IMPORTANT: API uses `row_id` (BIGINT, integer) in URL paths and JSON.
The v0.40 squash renamed the old `row_number` field to `row_id`; the
older UUID `row_id` shape is long gone.**

### Step 3.5: Check if Test Ticket
- Check the ticket's Tags column in `row_data`
- If tags contain `"test"` → this is a **test ticket**, go to Step 4T instead of Step 4
- If tags do NOT contain `"test"` → normal implementation, go to Step 4

### Step 4T: Test Ticket (title starts with `e2e_test_` or tags include `"test"`)
Instead of writing application code, write + run one e2e test.

1. Load `Skill(developing-e2e-test)` — follow its two-container
   architecture (test-e2e runs the script, browser owns Chromium).
2. Parse the test filename from the ticket title (the
   `e2e_test_<scope>_<topic>.py` token).
3. Bring both services up:
   `docker compose --profile test up -d browser test-e2e`
4. Write the test at `test-e2e/<filename>.py`, following the skill's
   "one topic per file" rule and connecting via
   `pw.chromium.connect(os.environ['BROWSER_WS'])`.
5. Run it:
   `docker compose exec -T test-e2e python3 /scripts/<filename>.py`
6. Exit 0 → append `PASS` + any screenshot paths to ticket doc, go to
   Step 5 (commit).
   Non-zero → append stderr to doc, set status to `debugging`, retry
   (max 3 attempts per Worker Rules).

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
- Update PM status → `testing` via `PUT /api/v1/tables/{table_id}/rows/{row_id}`
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

If siblings are **not all merged**, leave the story branch open.

### Step 8: Done
Worker sets PM status to `done`. Orchestrator polls PM to detect completion — no trigger files needed.

## Worker Rules

- **ONE ticket per session.** Do not batch multiple tickets.
- **Never ask questions.** Make reasonable decisions and document them in the commit message.
- **Stay in your assigned scope.** Don't touch files outside your task boundary.
- **If stuck after 3 attempts:** set PM status to `debugging`, stop.
- **All tests must pass** before committing.
- **Don't break existing tests.**
- **Commit messages:** `<type>-<row_id>: <verb> <what>` (e.g., `task-42: add user auth endpoint`, `bug-7: fix login redirect`)
- **Issue branches base off story branch, not main.**
- **Story branches base off main.**
- **CRITICAL: Continuously update the ticket doc.** Use `PUT /api/v1/tables/{table_id}/rows/{row_id}/doc` (row_id, NOT row_id). Append timestamped entries after EVERY action. Empty doc after work = FAILED.
- **CRITICAL: FE changes MUST have `.browser/` snapshot.** Run a Playwright check from `test-e2e` (`docker compose exec -T test-e2e python3 -c "..."` connecting via `BROWSER_WS`) — server-side `page.screenshot(path="/output/...")` lands at `.browser/...` on host. If the snapshot looks wrong, fix before committing.
- **API uses row_id (integer) in URL paths**, not row_id (UUID). Example: `PUT /api/v1/tables/{tid}/rows/42` not `PUT /api/v1/rows/{uuid}`.
- **NEVER POST new rows to update status.** Always use `PUT /api/v1/tables/{table_id}/rows/{row_id}` to update existing row_data. POST creates a NEW row with a new auto-generated Key — this causes duplicate rows (e.g. TO-* mirrors). Workers must ONLY update, never create.
- **If stuck:** diagnose why, append error + analysis to ticket doc, try different approach. If can't finish in time: commit partial work, log what's done and what's left in doc, set status to `review`, signal DONE. Next worker picks up from where you left off by reading the doc.

## Live worker progress (stream-json + formatter)

Workers call `claude -p --output-format=stream-json --verbose` and pipe
through `example-scripts/format_claude_stream.py`. Every event the LLM
emits — thinking blocks, tool calls, tool results, the final cost —
gets rendered as one short line. So when you `tmux attach -t <session>`
and switch into a worker window, you see the bot's progress in real
time instead of waiting for one giant blob at the end of a slow call.

`claude -p` alone streams the final text only. `--verbose` alone does
nothing for tool-less prompts. The pair `--output-format=stream-json
--verbose` (with `format_claude_stream.py` to format it) is the only
combination that exposes the full inner loop.

## 3 Phases

| Phase | Doc | What |
|-------|-----|------|
| **Plan** | [plan.md](plan.md) | Discuss design → create tickets in LatticeCast PM |
| **Prepare** | [prepare.md](prepare.md) | Write project's `.tmp/claude-bot/config.sh` + scripts that source the skill |
| **Run** | [running.md](running.md) | `bash run.sh`, `tmux attach`, `stop.sh`, recovery |

## Monitoring — main Claude opens a sibling `<project>-monitor` tmux

**The bot itself does not self-supervise.** Whenever you (the main Claude
session, not a worker) call `bash run.sh`, you ALSO spawn a sibling tmux
session that runs an independent monitoring loop. That loop polls every
~3 minutes and reports whether the bot is making progress.

Two equivalent ways to spawn the monitor — pick one based on how you
want results delivered:

### Option A — `ScheduleWakeup` from the main Claude session (simplest)

The main Claude session calls `ScheduleWakeup` with `delaySeconds=180`
and a self-replicating `prompt:` that re-checks `.tmp/out/orchestrator.log`,
the worker log, and PM status, then re-schedules itself. Uses no tmux —
the monitor lives entirely in the main session's wake cycle. Stops when
orchestrator says `ALL DONE!`.

Pros: no extra processes; reports inline in your conversation.
Cons: ties up the main session's wake budget.

### Option B — separate `<project>-monitor` tmux running `claude -p`

```bash
PROJECT="$(basename "$PROJECT_DIR")"  # same as the bot's session name
MONITOR_SESSION="${PROJECT}-monitor"
tmux kill-session -t "$MONITOR_SESSION" 2>/dev/null

tmux new-session -d -s "$MONITOR_SESSION" -c "$PROJECT_DIR" \
  "while true; do
     claude -p --dangerously-skip-permissions --model sonnet '
       Read tail of .tmp/out/orchestrator.log and worker_1.log.
       Query PM (table_id=$TABLE_ID) for any rn currently in_progress / testing.
       If a worker has 3+ Still working lines on the same step OR status==debugging, FLAG IT.
       Run git log --oneline -3 — if a TIMEOUTed ticket has a matching commit, mark its PM status done.
       Print one short paragraph: ticket, step, elapsed seconds.
       If orchestrator log ends with ALL DONE, print STOP_MONITOR and exit.
     '
     grep -q STOP_MONITOR <<<\"$(tail -1 .tmp/out/monitor.log)\" && break
     sleep 180
   done | tee -a .tmp/out/monitor.log"
```

Pros: independent of main session; persists across `/clear`.
Cons: extra tmux + a `claude -p` instance every 3 min.

### What the monitor checks

| Signal | What it means | Action |
|--------|---------------|--------|
| `3+ Still working` lines on the same step | LLM iterating on lint/test or stuck | flag, keep watching |
| Worker step `debugging` | tests failed | flag, escalate after 2 cycles |
| `TIMEOUT` in orchestrator log | 900s budget hit | check `git log` — if commit landed, mark PM `done` manually |
| `ALL DONE!` and queue empty | bot finished | print summary table, stop the monitor |

### Recovery rule (TIMEOUT after commit)

The orchestrator times out workers at 900s. If the worker had already
committed before the timeout, PM status will be stuck at `testing`/`review`
even though the work is in `main`. The monitor MUST verify with
`git log --oneline -5` and PUT the ticket to `done` so the next cycle
doesn't reprocess it.

### When NOT to spawn the monitor

- Single-ticket runs you're attaching to interactively.
- Dry-runs / debugging the bot scripts themselves.

## Key Dependencies

- `Skill(developing-lattice-cast)` — provides `lc_api.sh` (thin curl wrappers, generic).
- `Skill(developing-project-management)` — provides `pm_tool.sh` (PM domain
  helpers; auto-sources `lc_api.sh` from the sibling skill).
- `Skill(developing-programming)` — test/format/lint workflow.
- LatticeCast PM — ticket tracking, doc storage (MinIO).

## Composition pattern

Every project that uses the bot writes its own `.tmp/claude-bot/config.sh`
and the bot's local scripts source it + the skill's `pm_tool.sh`:

```bash
# .tmp/claude-bot/config.sh — per-project values only
export LC_API="http://localhost:13491/api/v1"
export LC_AUTH_HEADER="Authorization: Bearer claude"
export PM_USER="claude"
export TABLE_ID="pm"
export WORKSPACE_ID="<uuid>"
export PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export SKILLS_DIR="${PROJECT_DIR}/.claude/skills"

# orchestrator.sh / worker.sh
source "${SCRIPT_DIR}/config.sh"
source "${SKILLS_DIR}/developing-project-management/pm_tool.sh"
# pm_*, lc_* are now available
```

## Example Scripts

[example-scripts/](example-scripts/) — reference implementations:

| Script | Role |
|--------|------|
| orchestrator.sh | Pure rule-based: query PM → spawn → poll → cleanup |
| worker.sh | Bash infra + LLM code: `source pm_tool.sh` for PM ops |
| start.sh / stop.sh | tmux session lifecycle |
