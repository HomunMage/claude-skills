---
name: agent/agentic-hive
description: Start the autonomous multi-agent dev loop — a queen + bees in tmux solving tickets from LatticeCast PM
argument-hint: plan | running | status
version: 0.38.4
---

# agentic-hive — Autonomous Dev Loop

Start a tmux-based queen that runs N bees in parallel to solve project tickets autonomously.

## Flow

```
1. User calls /agentic-hive plan
2. Planning: discuss design → write .tmp/llm.design.*.md for review
3. User approves → create tickets in LatticeCast PM
5. User approve start bees
6. Bees: query PM → pick todo ticket → worktree branch → implement → update status → merge
```

## Ticket Sizing — 900s Hard Cap

Every bee has a **900-second wall clock** before the queen
gives up on it and kills the tmux window. This is non-negotiable —
don't raise it. If a ticket can't be completed in 15 minutes of
bee time, **the ticket is too big — split it before opening**.

Practical sizing rules when filing tickets:

- **One file changed.** If the implementation touches >1 file, the
  description is mixing concerns. Split.
- **One topic** (for tests this is enforced by `developing/e2e`'s
  one-topic-per-file rule).
- **<300 lines of new code.** Skim the description: if it sounds like
  "add column type X _and_ wire it through 4 views", that's 5 tickets,
  not 1.
- **Smoke test rerunable in <60s.** Tests that need long-running
  Docker setup or external services blow the budget on docker compose
  warm-up alone.

Signals you went too big:
- Queen log shows `Still working: [N] (900s)` → `TIMEOUT after
  900s` → ticket should be split.
- Bee hits `debugging` 3+ times — usually means the ticket
  description doesn't constrain the surface area enough.

Recovery from a TIMEOUT: see "Recovery rule" below.

## Prerequisites

- **LatticeCast PM running** — `http://localhost:13491/api/v1/status` must respond
- See `Skill(developing/project-management)` for setup (git clone + docker compose up)
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
└── story/{story-row-id}        ← base: main, or its parent story branch
    ├── task-{row-id} commit    ← serial ticket commit on the story branch
    ├── bug-{row-id} commit
    └── final integrated verification commit (if needed)
```

**One story has one persistent worktree and branch.** Bees process one ticket
at a time per story and commit directly to that story branch; they never make
issue branches. This keeps related controller/store/UI work on one integrated
code state. Merge the story into `main` only after all child tickets and the
story-level verification pass.

**Story dependency base rule:** if a story's PM `Parent` row is another
`story`, create it from `story/story-<parent-row-id>`. If its parent is an
`epic`, create it from `main`. Do not start a dependent story until its parent
story branch exists; if that parent is already merged and its branch was
cleaned up, create from `main` because it contains the same commits.

## Bee Workflow

### On Start — Read These First

1. `README.md` — project overview, architecture, tech stack
2. **Query LatticeCast PM** — use `Skill(developing/project-management)` "Query Tickets" for current status
3. Any `.tmp/llm*.md` files — design docs, API specs, references
4. **Load `Skill(developing/programming)`** + **`Skill(developing/project-management)`**

### Step 1: Identify Parent Story Branch

Before creating a worktree, look up the issue's parent story in LatticeCast PM:

```bash
# Get the issue row to find parent story row_id
ISSUE_ROW_ID="<row_id>"
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

### Step 2: Reuse the Persistent Story Worktree

```bash
STORY_BRANCH="story/story-<parent-row-id>"
STORY_WORKTREE=".tmp/story_<parent-row-id>"
git worktree add "$STORY_WORKTREE" "$STORY_BRANCH"  # only if it does not yet exist
cd "$STORY_WORKTREE"
```

All tickets for this story use this same worktree serially. Tickets from other
stories may use their own story worktrees in parallel.

### Step 3: Pick Ticket → update status → READ DOC FIRST
- Query LatticeCast PM for `todo` issues (type=task or type=bug)
- **Update PM status → `in_progress` FIRST**
- **READ THE DOC FIRST** via `GET /api/v1/tables/{table_id}/rows/{row_id}/doc`
  - The doc has ALL implementation detail — what to do, which files, decisions, acceptance criteria
  - Title is just a short summary — **doc is the real spec**
  - If a previous bee attempted this ticket, the doc has their work log + what's left
  - **Follow the doc instructions, not just the title**
- Append to doc: `- {timestamp} Picked up by W{id}`
- Work on ONLY that ticket

**IMPORTANT: API uses `row_id` (BIGINT, integer) in URL paths and JSON.
The v0.40 squash renamed the old `row_number` field to `row_id`; the
legacy UUID row identifier is long gone.**

### Step 3.5: Check if Test Ticket
- Check the ticket's Tags column in `row_data`
- If tags contain `"test"` → this is a **test ticket**, go to Step 4T instead of Step 4
- If tags do NOT contain `"test"` → normal implementation, go to Step 4

### Step 4T: Test Ticket (title starts with `e2e_test_` or tags include `"test"`)
Instead of writing application code, write + run one e2e test.

1. Load `Skill(developing/e2e)` — follow its two-container
   architecture (e2e runs the script, browser owns Chromium).
2. Parse the test filename from the ticket title (the
   `e2e_test_<scope>_<topic>.py` token).
3. Bring both services up:
   `docker compose --profile test up -d browser e2e`
4. Write the test at `e2e/<filename>.py`, following the skill's
   "one topic per file" rule and connecting via
   `pw.chromium.connect(os.environ['BROWSER_WS'])`.
5. Run it:
   `docker compose exec -T e2e python3 /scripts/<filename>.py`
6. Exit 0 → append `PASS` + any screenshot paths to ticket doc, go to
   Step 5 (commit).
   Non-zero → append stderr to doc, set status to `debugging`, retry
   (max 3 attempts per Bee Rules).

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
Use `Skill(developing/programming)` workflow:
- Update PM status → `testing` via `PUT /api/v1/tables/{table_id}/rows/{row_id}`
- Run tests (if fail → `debugging`, append error to doc)
- Format + lint
- Commit → update PM status to `review`

### Step 6: Leave the Ticket Commit on the Story Branch

The ticket commit is already on the persistent story branch. Do not create,
merge, or delete an issue branch/worktree. Update PM status → `merged`.

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

### Step 8: Complete
Bee leaves the PM status at `merged`. Queen polls PM to detect completion —
no trigger files are needed.

## Bee Rules

- **ONE ticket per session.** Do not batch multiple tickets.
- **Never ask questions.** Make reasonable decisions and document them in the commit message.
- **Stay in your assigned scope.** Don't touch files outside your task boundary.
- **If stuck after 3 attempts:** set PM status to `debugging`, stop.
- **All tests must pass** before committing.
- **Don't break existing tests.**
- **Commit messages:** `<type>-<row_id>: <verb> <what>` (e.g., `task-42: add user auth endpoint`, `bug-7: fix login redirect`)
- **Story branches base off main.**
- **Never create issue branches for tickets in a story.** Commit to the
  persistent story branch and process sibling tickets serially.
- **CRITICAL: Continuously update the ticket doc.** Use `PUT /api/v1/tables/{table_id}/rows/{row_id}/doc` (`row_id`, not the removed `row_number`). Append timestamped entries after EVERY action. Empty doc after work = FAILED.
- **CRITICAL: FE changes MUST have `.browser/` snapshot.** Run a Playwright check from `e2e` (`docker compose exec -T e2e python3 -c "..."` connecting via `BROWSER_WS`) — server-side `page.screenshot(path="/output/...")` lands at `.browser/...` on host. If the snapshot looks wrong, fix before committing.
- **API uses `row_id` (integer) in URL paths**, not the removed UUID row identifier. Example: `PUT /api/v1/tables/{tid}/rows/42`.
- **NEVER POST new rows to update status.** Always use `PUT /api/v1/tables/{table_id}/rows/{row_id}` to update existing row_data. POST creates a NEW row and therefore a duplicate derived ticket key such as `task-42`. Bees must ONLY update, never create.
- **If stuck:** diagnose why, append error + analysis to the ticket doc, try a different approach. If it still cannot finish, commit recoverable partial work, log what's done and what's left, set status to `debugging`, and stop. The next bee resumes by reading the doc.

## Provider-neutral LLM workers (`worker.sh` + `llm.sh`)

Bees don't call an LLM CLI directly — `bee.sh`'s `step()` calls
`work()` from `example-scripts/worker.sh`. That thin ticket-work layer
delegates to `llm_run()` in `example-scripts/llm.sh`, which selects
`$LLM_PROVIDER` (`claude` by default, or `codex`) and streams progress
lines back into the step's log file. `$LLM_BACKEND` remains a backwards-
compatible alias. Adding another CLI provider changes `llm.sh` and its
formatter only — `queen.sh`, `bee.sh`, and `worker.sh` stay unchanged.

The abstraction is:

```text
bee.sh step() → worker.sh work() → llm.sh llm_run() → Claude or Codex CLI
```

The `claude` backend calls `claude -p --output-format=stream-json
--verbose` and pipes through `example-scripts/format_claude_stream.py`.
Every event the LLM emits — thinking blocks, tool calls, tool results,
the final cost — gets rendered as one short line. So when you `tmux
attach -t <session>` and switch into a bee window, you see the hive's
progress in real time instead of waiting for one giant blob at the end
of a slow call.

`claude -p` alone streams the final text only. `--verbose` alone does
nothing for tool-less prompts. The pair `--output-format=stream-json
--verbose` (with `format_claude_stream.py` to format it) is the only
combination that exposes the full inner loop. A non-Claude provider
needs its own equivalent formatter to preserve the same live view.

The `codex` provider sends the prompt on stdin to `codex exec --json
--ephemeral --dangerously-bypass-approvals-and-sandbox`, pins execution
to `$LLM_PROJECT_DIR`, and pipes JSONL through
`example-scripts/format_codex_stream.py`. Select it with:

```bash
export LLM_PROVIDER=codex
# export CODEX_MODEL=gpt-5.6-codex  # optional
```

Both adapters pass prompts over stdin, preserve the actual provider exit
code through the formatting pipeline, and support `LLM_DRY_RUN=1` for
command-construction checks without starting a model run.

### Watchdog: kill the provider if log goes silent

An LLM provider can hang silently after a few
minutes — usually after spawning an `Agent`/`Explore` sub-agent or a
long-running tool call. The subprocess stays alive but the event
pipe stops emitting events; without a guard the ticket burns the full
900s budget waiting.

The `example-scripts/bee.sh` `step()` function wraps `work()` with a
watchdog that samples the log file every 30s and calls the provider-neutral
`work_stop()`/`llm_stop()` interface if it hasn't grown for 120s. When it
fires, `work()` returns
non-zero → ERR trap flips the row to `debugging` → queen advances.
120s detection traded for 780s of otherwise-wasted budget.

## 3 Phases

| Phase | Doc | What |
|-------|-----|------|
| **Plan** | [plan.md](plan.md) | Discuss design → create tickets in LatticeCast PM |
| **Prepare** | [prepare.md](prepare.md) | Write project's `.tmp/agentic-hive/config.sh` + scripts that source the skill |
| **Run** | [running.md](running.md) | `bash run.sh`, `tmux attach`, `stop.sh`, recovery |

## Monitoring — the supervising agent opens a sibling monitor

**The hive itself does not self-supervise.** Whenever the supervising
agent (not a bee) calls `bash run.sh`, it ALSO starts an independent
monitoring loop. That loop polls every ~3 minutes and reports whether the
hive is making progress.

Two equivalent ways to spawn the monitor — pick one based on how you
want results delivered:

### Option A — use the host agent's scheduler (simplest)

If the host agent supports scheduled wakeups, schedule a check every 180
seconds that reads `.tmp/out/queen.log`, the bee logs, and PM status, then
re-schedules itself. Stop when queen says `ALL DONE!`.

Pros: no extra processes; reports inline in your conversation.
Cons: ties up the main session's wake budget.

### Option B — separate `<project>-monitor` tmux using `llm.sh`

Write a small project-local `monitor.sh` that sources the same config and
provider adapter as the bees. Its core loop is provider-neutral:

```bash
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/llm.sh"

MONITOR_LOG="${PROJECT_DIR}/.tmp/out/monitor.log"
MONITOR_PROMPT="Read the queen and worker logs and PM status. Report ticket,
step, and elapsed time. If the queue is finished, print STOP_MONITOR."

while true; do
  llm_run "$MONITOR_PROMPT" "$MONITOR_LOG"
  grep -q STOP_MONITOR "$MONITOR_LOG" && break
  sleep 180
done
```

Pros: independent of main session; persists across `/clear`.
Cons: extra tmux + an LLM provider call every 3 min.

### What the monitor checks

| Signal | What it means | Action |
|--------|---------------|--------|
| `3+ Still working` lines on the same step | LLM iterating on lint/test or stuck | flag, keep watching |
| Bee step `debugging` | tests failed | flag, escalate after 2 cycles |
| `TIMEOUT` in queen log | 900s budget hit | check `git log` — if the merge landed, mark PM `merged` manually |
| `ALL DONE!` and queue empty | hive finished | print summary table, stop the monitor |

### Recovery rule (TIMEOUT after commit)

The queen times out bees at 900s. If the bee had already
committed before the timeout, PM status will be stuck at `testing`/`review`
even though the work is in `main`. The monitor MUST verify with
`git log --oneline -5` and PUT the ticket to `merged` so the next cycle
doesn't reprocess it.

### When NOT to spawn the monitor

- Single-ticket runs you're attaching to interactively.
- Dry-runs / debugging the hive scripts themselves.

## Key Dependencies

- `Skill(developing/lattice-cast)` — provides `lc_api.sh` (thin curl wrappers, generic).
- `Skill(developing/project-management)` — provides `pm_tool.sh` (PM domain
  helpers; auto-sources `lc_api.sh` from the sibling skill).
- `Skill(developing/programming)` — test/format/lint workflow.
- LatticeCast PM — ticket tracking, doc storage (MinIO).

## Composition pattern

Every project that uses the hive writes its own `.tmp/agentic-hive/config.sh`
and the hive's local scripts source it + the skill's `pm_tool.sh`:

```bash
# .tmp/agentic-hive/config.sh — per-project values only
export LC_API="http://localhost:13491/api/v1"
export LC_AUTH_HEADER="Authorization: Bearer lattice"
export PM_USER="lattice"
export TABLE_ID="pm"
export WORKSPACE_ID="<uuid>"
export PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export SKILLS_DIR="${PROJECT_DIR}/.agent-skills"
export LLM_PROVIDER="${LLM_PROVIDER:-${LLM_BACKEND:-claude}}" # or codex
export LLM_PROJECT_DIR="${PROJECT_DIR}"

# queen.sh / bee.sh
source "${SCRIPT_DIR}/config.sh"
source "${SKILLS_DIR}/developing/project-management/pm_tool.sh"
# pm_*, lc_* are now available
```

## Example Scripts

[example-scripts/](example-scripts/) — reference implementations:

| Script | Role |
|--------|------|
| queen.sh | Pure rule-based: query PM → spawn → poll → cleanup |
| bee.sh | Bash infra + LLM code: `source pm_tool.sh` for PM ops |
| worker.sh | Stable ticket-work interface: `work()` and `work_stop()` |
| llm.sh | Provider abstraction: validates, runs, and stops Claude or Codex |
| format_claude_stream.py | Formats Claude stream-json as live log lines |
| format_codex_stream.py | Formats `codex exec --json` JSONL as live log lines |
| start.sh / stop.sh | tmux session lifecycle |
