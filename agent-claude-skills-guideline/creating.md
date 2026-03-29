# Writing & Syntax Reference

## Philosophy

**精簡但深邃。AI秒懂。**

- Every line must carry weight. No filler. No redundancy.
- Write for AI — dense, structured, pattern-matchable.
- In English as possible.
- SKILL.md < 500 lines. Can't? Decompose.
- Detail → sub-files (lazy-loaded, zero context cost).

## Frontmatter

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

## Body Variables

`$ARGUMENTS` all · `$0 $1 $2` positional · `${CLAUDE_SKILL_DIR}` skill dir · `` `cmd` `` shell inject

## Scope

`.claude/skills/` project > `~/.claude/skills/` global
