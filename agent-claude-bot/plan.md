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
After tickets are created in LatticeCast, detailed notes go to each ticket's doc in MinIO.

## Step 4: Break Down into Tickets

Once aligned, create ticket descriptions following these rules:

### Default Time Rule
When creating tickets, if the user does not specify Start Date or Due Date, **default both to today's date**. Never leave date fields empty.

### Mandatory Hierarchy: 1 Epic → N Stories → N Issues

Every plan **MUST** follow this exact three-level hierarchy. No exceptions.

```
Epic (1 per plan)
└── Story 1 (feature area / phase)
│   ├── Issue 1.1 (concrete implementation task)
│   ├── Issue 1.2
│   └── Issue 1.N
└── Story 2
    ├── Issue 2.1
    └── Issue 2.N
```

**Epic** — the single top-level goal of this plan. Set `type=epic`.  
**Story** — a feature area, phase, or user-facing capability. Set `type=story`, `Parent=<epic_row_id>`.  
**Issue/Task** — a single implementation unit. Set `type=task` or `type=bug`, `Parent=<story_row_id>`.

Rules:
- **Exactly 1 epic** per plan — never 0, never 2+
- **Every story** must have `Parent` pointing to the epic
- **Every issue** must have `Parent` pointing to a story (never directly to the epic)
- Stories are **never** directly implementable — they are groupings only
- Issues are the only tickets assigned to workers

### Title vs Doc Rule
- **Title is SHORT** — one line summary, max 80 chars. Example: `Add OAuth middleware`
- **Doc has ALL the detail** — implementation instructions, files to change, decisions, acceptance criteria
- Title is what you see in table view. Doc is what the worker reads before coding.
- **Every ticket MUST have a non-empty doc.** Empty doc = planning failure.

### Ticket Size Rules
- Each issue must be **completable in <15 minutes** by a Claude Sonnet worker
- Each issue must be **independently testable** — tests must pass after each issue
- Each issue must be **independently committable** — clean git commit after each
- Issues should **not conflict** — two workers shouldn't edit the same file
- Group stories into phases — Story 1 (scaffold), Story 2 (core), Story 3 (features), etc.

### Bad Tickets (too big or wrong level)
- "Build the entire authentication system" — too many files, too many decisions
- "Refactor the codebase" — vague, unbounded
- Creating tasks directly under the epic (skipping stories) — violates hierarchy

### Good Hierarchy Example
```
Epic: Add OAuth2 Login
├── Story: Backend Auth Endpoints  (Parent=epic)
│   ├── Task: Add /auth/google route in router/auth.py  (Parent=story)
│   ├── Task: Add JWT token generation in auth service  (Parent=story)
│   └── Task: Test: snapshot Backend Auth Endpoints      (Parent=story, tags=[test])
└── Story: Frontend Login UI  (Parent=epic)
    ├── Task: Add LoginButton component in src/lib/  (Parent=story)
    ├── Task: Handle OAuth callback in +page.svelte   (Parent=story)
    └── Task: Test: snapshot Frontend Login UI           (Parent=story, tags=[test])
```

### Auto-create Test Ticket per Story
After creating all issues for a story, **always** add one more issue:
- Title: `Test: snapshot {story_title}`
- Type: `task`
- Tags: `["test"]`
- Parent: the story's row_id

This test ticket uses `.browser/` Playwright to snapshot-verify the story's features render correctly. Workers pick it up last (after all implementation issues are merged).

## Step 5: User Approval

Show the user:
1. Total ticket count and phase breakdown
2. Estimated parallelism (how many workers can run at once)
3. Files that will be created/modified

Ask: **"Approve these tickets? I'll create them in LatticeCast PM."**

## Step 6: Create Tickets in LatticeCast PM

After user approves, use `Skill(developing-project-management)`:

1. Use "Ensure LatticeCast is Running" — if not, prompt user
2. Use "Setup Project" if PM table doesn't exist — create via template
3. Create the **epic first**, note its `row_id`
4. Create each **story** with `Parent=<epic_row_id>`, note each story's `row_id`
5. Create each **issue** with `Parent=<story_row_id>` — never parent directly to epic
6. **Write design content to ticket docs in MinIO** via `PUT /api/v1/tables/{table_id}/rows/{row_id}/doc`:

   **Epic doc** — full design overview, architecture decisions, scope:
   ```markdown
   # {Key}: {Title}
   
   ## Overview
   <paste the design discussion summary here>
   
   ## Architecture
   <architecture decisions, diagrams>
   
   ## Scope
   <what's in/out of scope>
   
   ## Stories
   - [{story_key}] {story_title}
   ```

   **Story doc** — story-level spec, acceptance criteria, files to change:
   ```markdown
   # {Key}: {Title}
   
   ## Parent
   [{epic_key}] {epic_title}
   
   ## Spec
   <what this story delivers>
   
   ## Files to Change
   - path/to/file.ts — what changes
   
   ## Issues
   - [{issue_key}] {issue_title}
   
   ## Acceptance Criteria
   - [ ] Criteria 1
   - [ ] Criteria 2
   ```

   **Issue doc** — implementation instructions, specific steps:
   ```markdown
   # {Key}: {Title}
   
   ## Parent
   [{story_key}] {story_title}
   
   ## What to Do
   <specific implementation instructions>
   
   ## Files
   - path/to/file.ts — exact changes needed
   
   ## Work Log
   (workers will append here as they work)
   ```

   **CRITICAL**: Every ticket MUST have non-empty doc content after planning. Empty docs = planning failure.

7. **Delete design docs** `.tmp/llm*.md` — content now lives in ticket docs
8. Report: **"Created N tickets in LatticeCast. Ready to start `/claude-bot`?"**

## Step 7: Generate Runner Scripts

Design and write custom runner scripts in `.tmp/claude-bot/` tailored to the project.

Reference [example-scripts/](../example-scripts/) for patterns.

```bash
bash .tmp/claude-bot/start.sh
```
