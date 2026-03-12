# Planning Phase

This is Phase 1 of the two-phase workflow:
1. **Planning** (this) — Interactive with user: discuss, design, produce tickets
2. **`/claude-bot`** — Autonomous: execute the tickets in tmux

## Your Job

You are a **Tech Lead** having a planning session with the developer (user).
Your goal: produce a complete, ready-to-execute plan that `/claude-bot` workers can pick up autonomously.

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

## Step 3: Break Down into Tickets

Once aligned, create tickets following these rules:

### Ticket Rules
- Each ticket must be **completable in <15 minutes** by a Claude Sonnet worker
- Each ticket must be **independently testable** — tests must pass after each ticket
- Each ticket must be **independently committable** — clean git commit after each
- Tickets should **not conflict** — two workers shouldn't edit the same file
- Order matters — earlier tickets are picked first
- Group into phases — Phase 1 (scaffold), Phase 2 (core), Phase 3 (features), etc.

### Ticket Format
```markdown
## Phase 1: Setup
- [ ] Create project scaffold (package.json, tsconfig, src/ dirs)
- [ ] Add database schema (prisma/schema.prisma with User, Post models)
- [ ] Add base API router (src/routes/index.ts with health check)

## Phase 2: Core
- [ ] Implement User CRUD (src/routes/users.ts, src/services/user.ts)
- [ ] Implement Post CRUD (src/routes/posts.ts, src/services/post.ts)
- [ ] Add authentication middleware (src/middleware/auth.ts, JWT)
```

### Bad Tickets (too big)
- "Build the entire authentication system" — too many files, too many decisions
- "Refactor the codebase" — vague, unbounded

### Good Tickets (small, testable)
- "Add JWT verification middleware in src/middleware/auth.ts"
- "Add POST /users endpoint with email+password validation"

## Step 4: Produce Output Files

Once user approves the tickets, create these files in the project:

### `.tmp/llm.plan.status`
The ticket list (as shown above). This is the input for `/claude-bot`.

### `.tmp/llm.working.log`
Initialize empty (or with a planning entry):
```
[PLAN] Phase 1-3 planned: N tickets across M phases
```

### `.tmp/llm.working.notes` (optional)
If there were design decisions from the discussion, write them here:
- Architecture choices and why
- API contract decisions
- Data model decisions
- Things to watch out for

### `.tmp/claude-bot/*.sh` (runner scripts)
Design and write custom runner scripts tailored to THIS project's needs. Place them in `.tmp/claude-bot/`.

Reference [example-scripts/](../example-scripts/) for patterns and ideas, but **do not copy them blindly** — design scripts that fit the project.

Possible script designs:
- **Separate workers**: `worker1.sh` (backend), `worker2.sh` (frontend) — each with different scope, context, and constraints for parallel execution
- **Multi-role session**: `workers.sh` — multiple roles collaborating in one session (e.g., architect reviews while coder implements)
- **Sequential pipeline**: `pipeline.sh` — Phase 1 tickets first, then Phase 2, with dependency awareness
- **Single worker**: `worker.sh` — simple loop for small projects

Consider:
- How many workers can run in parallel without file conflicts?
- Do workers need different contexts or permissions?
- Should there be an orchestrator, or is a simple loop enough?
- What coordination mechanism fits? (git lock, trigger files, sequential)

```bash
# Example: user runs the scripts directly
bash .tmp/claude-bot/start.sh
```

## Step 5: Confirm

Show the user:
1. Total ticket count and phase breakdown
2. Estimated parallelism (how many workers can run at once)
3. Files that will be created/modified

Ask: **"Ready to start `/claude-bot`?"**

## Example Session

See [examples/plan-session.md](examples/plan-session.md) for a full example of a planning session.
