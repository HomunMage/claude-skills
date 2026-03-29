---
name: developing-codebase-onboarding
description: Onboard a new codebase — explore, understand, and generate .tmp/llm*.md docs for quick reference. Use when joining a new project or needing to understand unfamiliar code.
allowed-tools: Read, Grep, Glob, Bash, Agent
---

# Codebase Onboarding

Explore a codebase and produce `.tmp/llm*.md` docs so future Claude sessions (and humans) can ramp up instantly.

## Process

### 1. Register Project in LatticeCast PM

Set up the project board **first** so tickets can be tracked during onboarding.

First, check if LatticeCast is running:
```bash
curl -s http://localhost:5000/api/status 2>/dev/null || echo "NOT_RUNNING"
```

If not running, ask the user: **"LatticeCast PM is not running. Please start it first: `cd <LatticeCast-repo> && docker compose up -d backend frontend`, then let me know when it's ready."**

Wait for the user to confirm before proceeding.

**LatticeCast API**: `http://localhost:5000`

#### 1a. Create "claude" user (idempotent)
```bash
curl -s http://localhost:5000/api/login/me -H "Authorization: Bearer claude"
```
This auto-creates user `claude` (if `auth_required=false`).
If `auth_required=true`, use admin API to create the user first.

#### 1b. Ask user for team member IDs
Ask: **"Which user IDs should have access to this project workspace? (e.g. homunmage@gmail.com, latticemage@gmail.com)"**

#### 1c. Add members to claude's workspace
```bash
# For each user_id provided:
curl -s -X POST http://localhost:5000/api/workspaces/claude/members \
  -H "Authorization: Bearer claude" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "<user_id>", "role": "member"}'
```
Ensure each member user exists first (call `/api/login/me` with their token, or admin API).

#### 1d. Create PM table from template
```bash
PROJECT_NAME="$(basename $(pwd))"
curl -s -X POST http://localhost:5000/api/tables/template/pm \
  -H "Authorization: Bearer claude" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"${PROJECT_NAME}\", \"workspace_id\": \"claude\"}"
```
This creates a table with: Key, Title, Type (epic/story/task/bug), Status, Priority, Assignee, Start/Due Date, Estimate, Tags, Description, Parent — plus default Kanban + Timeline views.

#### 1e. Report the URL
```
Project board: http://localhost:3000/claude/<table_id>
Views: Table (default) | Sprint Board (Kanban) | Roadmap (Timeline)
```

If LatticeCast is not reachable, skip this step and proceed to step 2.

### 2. Scan Project Root

Read overview first (if they exist).
ex:
- `README.md`, `CLAUDE.md`, `*.md` — project overview
- `package.json` / `pyproject.toml` / `Cargo.toml` — stack + deps
- `docker-compose.yml` — services architecture
- `.env.example` — config shape

### 3. Map Directory Structure

```bash
find . -type f -not -path './.git/*' -not -path './node_modules/*' -not -path './.tmp/*' | head -200
```

Identify layers: frontend, backend, API, DB, auth, infra, tests.

### 4. Trace Key Flows

For each major module, trace:
- **Entry point** — where does it start?
- **Data flow** — input → processing → output
- **Dependencies** — what does it import/call?
- **Config** — env vars, constants, feature flags

### 5. Write `.tmp/llm*.md` Docs

Create `.tmp/` if not exists. examples: (just possible, not must)

| File | Content |
|------|---------|
| `llm.arch.md` | Overall architecture, tech stack, directory map |
| `llm.arch.auth.md` | Auth flow, session handling, permissions |
| `llm.arch.db.md` | DB schema, ORM, migrations, key queries |
| `llm.arch.api.md` | API routes, request/response shapes, middleware |
| `llm.frontend.md` | UI structure, components, state management |
| `llm.backend.md` | Server logic, services, business rules |
| `llm.infra.md` | Deploy, CI/CD, Docker, env config |
| `llm.gotchas.md` | Non-obvious quirks, footguns, tech debt |

Only create files for domains that exist in the project. Skip what's not there.

### 6. Doc Format

Each `llm*.md` follows:

```markdown
# [Domain] — [Project Name]

## Overview
One paragraph: what this layer does and why.

## Key Files
- `path/to/file.ts` — what it does
- `path/to/other.ts` — what it does

## Architecture
How components connect. Use ascii diagram if complex:
```
A → B → C
    ↓
    D
```

## Patterns
- Pattern name — brief explanation
- Another pattern — brief explanation

## Gotchas
- Non-obvious thing 1
- Non-obvious thing 2
```

## Rules

- **All output goes to `./.tmp/`** — never `/tmp/`
- Keep each doc **under 100 lines** — dense, scannable
- **File paths must be current** — verify they exist before writing
- **No opinions** — document what IS, not what should be
- Skip boilerplate/obvious stuff — only document what's non-trivial
- If project is large, prioritize: auth > API > DB > frontend > infra
- **PM setup requires LatticeCast running** — skip step 1 if backend is not reachable
