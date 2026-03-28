---
name: developing-codebase-onboarding
description: Onboard a new codebase — explore, understand, and generate .tmp/llm*.md docs for quick reference. Use when joining a new project or needing to understand unfamiliar code.
allowed-tools: Read, Grep, Glob, Bash, Agent
---

# Codebase Onboarding

Explore a codebase and produce `.tmp/llm*.md` docs so future Claude sessions (and humans) can ramp up instantly.

## Process

### 1. Scan Project Root

Read overview first (if they exist).
ex:
- `README.md`, `CLAUDE.md`, `*.md` — project overview
- `package.json` / `pyproject.toml` / `Cargo.toml` — stack + deps
- `docker-compose.yml` — services architecture
- `.env.example` — config shape

### 2. Map Directory Structure

```bash
find . -type f -not -path './.git/*' -not -path './node_modules/*' -not -path './.tmp/*' | head -200
```

Identify layers: frontend, backend, API, DB, auth, infra, tests.

### 3. Trace Key Flows

For each major module, trace:
- **Entry point** — where does it start?
- **Data flow** — input → processing → output
- **Dependencies** — what does it import/call?
- **Config** — env vars, constants, feature flags

### 4. Write `.tmp/llm*.md` Docs

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

### 5. Doc Format

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
