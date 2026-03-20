---
name: agent-claude-skills-creating
description: Guide for creating Claude Code skills (SKILL.md). Use when building, structuring, or debugging custom skills/slash commands.
---

# Writing Philosophy

**精簡但深邃。AI秒懂。**

- Every line must carry weight. No filler. No redundancy.
- Write for AI — dense, structured, pattern-matchable.
- Too long? Decompose into reusable components (`user-invocable: false` = internal lib).
- Detail → `reference.md` (lazy-loaded, zero context cost).
- SKILL.md < 500 lines. Can't? Decompose.
- In English as possible.

# Structure

```
.claude/skills/<name>/
├── SKILL.md          # YAML frontmatter + markdown body
├── reference.md      # Detail, lazy-loaded
└── scripts/          # Helpers
```

# Frontmatter

```yaml
---
name: skill-name
description: WHEN to trigger — Claude matches on this. Write like a search query.
argument-hint: [arg]                    # Autocomplete hint
allowed-tools: Read, Grep, Bash        # Auto-approved tools
# Visibility:
#   default                            → user ✓  auto-load ✓
#   disable-model-invocation: true     → user ✓  auto-load ✗  (side-effects!)
#   user-invocable: false              → user ✗  auto-load ✓  (internal lib)
# Isolation:
#   context: fork                      → subagent, fresh context
#   agent: Explore                     → subagent type (needs context: fork)
---
```

# Body Variables

`$ARGUMENTS` all · `$0 $1 $2` positional · `${CLAUDE_SKILL_DIR}` skill dir · `!cmd` shell inject

# Scope

`.claude/skills/` project > `~/.claude/skills/` global

# Decomposition Pattern

```
skills/agent/
├── my-skill/SKILL.md              # User-facing orchestrator
├── shared-lib-a/SKILL.md          # user-invocable: false — reusable
└── shared-lib-b/SKILL.md          # user-invocable: false — reusable
```

Compose via `Skill(shared-lib-a)` in CLAUDE.md or other skills.
