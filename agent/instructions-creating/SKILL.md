---
name: agent/instructions-creating
description: Guide for creating portable AGENTS.md project instructions for coding agents. Use when setting up, writing, or organizing repository-level agent guidance.
version: 0.3.0
---

# Writing Philosophy

Same as skills — dense, structured, AI-readable. No filler.

# What is AGENTS.md?

Portable project-level instructions for coding agents. Think `.editorconfig` for agent behavior.

# File Locations & Loading

| Location | Scope | Loading |
|----------|-------|---------|
| `AGENTS.md` | Project root | Repository-wide |
| `src/AGENTS.md` | Subdirectory | Applies within `src/` |
| Runtime-specific global file | User defaults | Depends on the active agent runtime |

- **Project root** — main instructions, loaded every conversation
- **Subdirectory** — scoped rules, loaded only when the agent works in that directory
- **Global** — personal defaults across all projects

## Loading Order

Runtime defaults → project root → subdirectory (deeper instructions take priority on conflicts)

# Structure Template

```markdown
# Project Name

Brief one-liner about what this project does.

## On Start — Read These First

1. `README.md` — project overview, architecture, tech stack
2. Query LatticeCast PM for tickets — use `Skill(developing/project-management)` "Query Tickets"
3. Any `.tmp/llm*.md` files — design docs, API specs, references

## Temporary Files

- **All temp/scratch work MUST go in `./.tmp/`** (project-local), never `/tmp/`
- Create `.tmp/` if it doesn't exist before writing to it
- `.tmp/` should be in `.gitignore` — never commit `.tmp/**`

## Tech Stack

- Language, framework, key dependencies
- Build tool, package manager

## Commands

- `npm run dev` — start dev server
- `npm test` — run tests
- `npm run lint` — lint

## Architecture

Brief description of project structure:
- `src/lib/` — core logic
- `src/routes/` — pages/endpoints
- `src/components/` — UI components

## Conventions

- Naming: camelCase for files, PascalCase for components
- Imports: use `$lib/` alias
- Tests: colocated as `*.test.ts`

## Rules

- Never commit `.env` or secrets
- All PRs need tests
- Use conventional commits

## Workflows

- After code changes: use `Skill(developing/programming)` for test/format/lint/commit
- If project uses Svelte/SvelteKit: follow `Skill(developing/svelte)` architecture
- If project uses FastAPI: follow `Skill(developing/fastapi)` conventions
```

# What to Include

| Category | Examples |
|----------|---------|
| **Commands** | Build, test, lint, deploy — exact commands |
| **Architecture** | Directory structure, key patterns |
| **Conventions** | Naming, imports, file organization |
| **Rules** | Hard constraints the agent must follow |
| **Stack** | Language, framework, key deps |
| **Gotchas** | Non-obvious project quirks |

# What NOT to Include

- Generic best practices the agent already knows
- Lengthy explanations — keep it terse
- Duplicating README.md content
- Things derivable from `package.json`, `tsconfig.json`, etc.
- Temporary task-specific instructions (use skills or memory instead)

# Writing Rules

1. **Imperative voice** — "Use X", "Never Y", not "We typically use X"
2. **Specific > general** — `npm run test:unit` not "run the tests"
3. **One fact per line** — scannable, not paragraph prose
4. **Commands must be copy-pasteable** — exact, not approximate
5. **< 200 lines** for root AGENTS.md. Offload to subdirectory AGENTS.md files

# Subdirectory AGENTS.md Pattern

Split concerns by directory:

```
project/
├── AGENTS.md               # Global: stack, commands, architecture
├── src/
│   ├── AGENTS.md           # src-wide conventions
│   ├── lib/
│   │   └── AGENTS.md       # Logic layer rules
│   └── routes/
│       └── AGENTS.md       # Route/page conventions
└── tests/
    └── AGENTS.md           # Testing patterns
```

Each subdirectory file only contains rules relevant to that scope.

# Composing with Skills

AGENTS.md can reference skills by canonical name. Auto-detect the stack and apply:

| Stack | Skill |
|-------|-------|
| Any project | `Skill(developing/programming)` — test/format/lint/commit |
| Svelte/SvelteKit | `Skill(developing/svelte)` — pure TS logic + .svelte UI |
| FastAPI | `Skill(developing/fastapi)` — Python API conventions |

This keeps AGENTS.md lean — delegate detailed workflows to skills.

# Anti-patterns

- Walls of text — agents need scannable instructions
- Contradicting rules at different levels — deeper file wins but it's confusing
- Over-specifying — trust the agent's defaults, only override what's different
- Putting secrets or credentials in AGENTS.md (it's committed to git)
