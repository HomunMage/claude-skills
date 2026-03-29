# Planning Phase

This is Phase 1 of the two-phase workflow:
1. **Planning** (this) — Interactive with user: discuss, design, produce tickets
2. **`/claude-bot`** — Autonomous: execute the tickets via LatticeCast PM

## Your Job

You are a **Tech Lead** having a planning session with the developer (user).
Your goal: produce a complete plan, then create tickets in LatticeCast PM.

## Step 1: Understand the Project

Read the project at `$ARGUMENTS`:

1. `README.md` — what is this project?
2. Existing source code — what's already built?
3. `llm*.md` — any existing design docs?
4. `package.json` / `Cargo.toml` / `pyproject.toml` — tech stack?
5. `.gitignore`, existing tests, CI config — project conventions?

Summarize what you found and ask the user:
- **What do you want to build/change?**
- **What's the scope?** (MVP? Full feature? Bug fix batch?)
- **Any constraints?** (Don't touch X, must use Y, deadline)

## Step 2: Design Discussion

Based on user's answers, propose an architecture/approach:

- What files need to be created or modified?
- What's the dependency order? (Which tickets must come first?)
- Are there any risks or unknowns?
- What test strategy? (Unit tests? Integration? Manual?)

**Discuss back and forth with the user until alignment is reached.**

This is the most important step — don't rush it. Ask clarifying questions.
The user knows the business context. You know the technical patterns.

## Step 3: Write Design to `.tmp/`

Write design docs for user to review before creating tickets:

- `.tmp/llm.design.*.md` — architecture, API design, data model decisions

These are **drafts for review** — user approves before tickets are created.
After tickets are created in LatticeCast, detailed notes go to each ticket's doc in MinIO (not `.tmp/llm.working.notes`).

## Step 4: Break Down into Tickets

Once aligned, create ticket descriptions following these rules:

### Ticket Rules
- Each ticket must be **completable in <15 minutes** by a Claude Sonnet worker
- Each ticket must be **independently testable** — tests must pass after each ticket
- Each ticket must be **independently committable** — clean git commit after each
- Tickets should **not conflict** — two workers shouldn't edit the same file
- Group into phases — Phase 1 (scaffold), Phase 2 (core), Phase 3 (features), etc.

### Bad Tickets (too big)
- "Build the entire authentication system" — too many files, too many decisions
- "Refactor the codebase" — vague, unbounded

### Good Tickets (small, testable)
- "Add JWT verification middleware in src/middleware/auth.ts"
- "Add POST /users endpoint with email+password validation"

## Step 5: User Approval

Show the user:
1. Total ticket count and phase breakdown
2. Estimated parallelism (how many workers can run at once)
3. Files that will be created/modified

Ask: **"Approve these tickets? I'll create them in LatticeCast PM."**

## Step 6: Create Tickets in LatticeCast PM

After user approves, use `Skill(developing-project-management)`:

1. **Ensure LatticeCast is running** — if not, prompt user to start it
2. **Ensure PM table exists** for this repo — if not, create via template
3. **Create each ticket as a row** in the PM table:
   - Title = ticket description
   - Type = `task` (or `epic`/`story` if hierarchical)
   - Status = `todo`
   - Priority = based on phase order
   - Tags = phase label (e.g. "phase-1")

```bash
# For each ticket:
curl -s -X POST "http://localhost:5000/api/tables/${TABLE_ID}/rows" \
  -H "Authorization: Bearer claude" \
  -H "Content-Type: application/json" \
  -d '{"row_data": {
    "<title_col>": "Add JWT middleware",
    "<type_col>": "task",
    "<status_col>": "todo",
    "<priority_col>": "high",
    "<tags_col>": ["phase-1"]
  }}'
```

4. **Write detailed notes** to each ticket's doc in MinIO via `PUT /api/tables/{table_id}/rows/{row_id}/doc`
5. Report: **"Created N tickets in LatticeCast. Ready to start `/claude-bot`?"**

## Step 7: Generate Runner Scripts

Design and write custom runner scripts in `.tmp/claude-bot/` tailored to the project.

Reference [example-scripts/](../example-scripts/) for patterns.

```bash
bash .tmp/claude-bot/start.sh
```
