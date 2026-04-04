---
name: agent-claude-skills-guideline
description: Guide for creating Claude Code skills (SKILL.md). Use when building, structuring, or debugging custom skills/slash commands.
version: 0.4.0
---

# Skills = Library Dependencies

A skill is a lib. Design it like one:

- **SKILL.md = public API** — always loaded, keep it thin
- **Sub-files = implementation** — lazy-loaded, zero cost until `Read`
- **`Skill(name)` = import** — compose skills like imports
- **`user-invocable: false` = private package** — internal lib, not user-facing

Don't dump everything into SKILL.md. Split by load frequency, not by topic.

## Real Examples

```
developing-programming/        # lib with 3 modules
├── SKILL.md                   # public API: workflow overview
├── developing.md              # impl: test/format/lint/commit steps
└── writelog.md                # impl: changelog/version logic

agent-claude-bot/              # lib with sub-packages
├── SKILL.md                   # public API: bot overview + rules
├── plan/                      # sub-package: planning phase
└── example-scripts/           # sub-package: reference scripts

developing-project-management/ # lib with lazy deps
├── SKILL.md                   # public API: daily ticket ops
├── setup.md                   # lazy dep: first-time project init
└── endpoints.md               # lazy dep: full API reference
```

## Rules

1. **MUST bump version on ANY edit.** Every SKILL.md frontmatter has `version:`. Patch (0.1.1) for fixes, minor (0.2.0) for features. **No exceptions.** If you edit a skill and don't bump version, you have violated the rules.
2. **Submodule commit.** `.claude/skills/` is a git submodule. After editing: `cd .claude/skills && git add && git commit`, then `cd .. && git add .claude/skills && git commit` in parent repo.
3. **SKILL.md < 500 lines.** Split or decompose.
4. **Split by load frequency.** Always → SKILL.md. Once → setup.md. On-demand → reference.md.
5. **Sub-files = zero context cost** until explicitly read.
6. **精簡但深邃。AI秒懂。** Every line carries weight. No filler.

See [creating.md](creating.md) for syntax/frontmatter reference.
