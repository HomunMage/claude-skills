---
name: agent/skill-rule
description: Rule for creating portable agent skills (SKILL.md). Use when building, structuring, or debugging reusable skills and commands for coding agents.
version: 0.7.1
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
developing/programming/        # lib with 3 modules
├── SKILL.md                   # public API: workflow overview
├── developing.md              # impl: test/format/lint/commit steps
└── writelog.md                # impl: changelog/version logic

agent/agentic-hive/            # lib with sub-packages
├── SKILL.md                   # public API: hive overview + rules
├── plan.md                    # sub-package: planning phase
└── example-scripts/           # sub-package: reference scripts

developing/project-management/ # lib with lazy deps
├── SKILL.md                   # public API: daily ticket ops
├── setup.md                   # lazy dep: first-time project init
└── endpoints.md               # lazy dep: full API reference
```

## Rule-based > LLM for infrastructure

When designing scripts that orchestrate LLM workers:

- **Rule-based (bash/python) for infrastructure** — PM status updates, git commit/merge, doc logging, ticket querying. Deterministic, no hallucination.
- **LLM only for creative work** — reading code, writing implementation, debugging errors.

### Wrap tools as bash helpers

```bash
# Good: bash helper, always correct
pm_set_status() {
  curl -s -X PUT ".../rows/${ROW_NUMBER}" -d '{"row_data": ...}'
}

# Bad: asking LLM to write curl
step "update-status" "Update PM status to in_progress via curl PUT..."
```

### Example: orchestrator = pure rule-based

`orchestrator.sh` — NO LLM at all. Pure bash+python:
- Query PM API for todo tickets
- Assign to workers
- Monitor timeouts
- Collect results

### Example: worker = bash infra + LLM code

`worker.sh` — bash handles git/PM, LLM writes code:
```
bash: pm_set_status "in_progress"     ← deterministic
bash: pm_append_doc "Started"         ← deterministic
LLM:  step "implement" "..."          ← creative (read + write code)
bash: pm_set_status "testing"         ← deterministic
LLM:  step "test" "..."              ← creative (run + fix tests)
bash: git add && git commit           ← deterministic
bash: pm_set_status "done"            ← deterministic
```

**Why:** LLM can't be trusted with `POST` vs `PUT`, correct curl flags, git merge order. It will hallucinate. Bash is deterministic.

## Rules

1. **MUST bump version on ANY edit.** Every SKILL.md frontmatter has `version:`. Patch (0.1.1) for fixes, minor (0.2.0) for features. **No exceptions.**
2. **Submodule commit.** `.agent-skills/` is a git submodule. After editing: `cd .agent-skills && git add && git commit`, then commit the updated `.agent-skills` gitlink in the parent repository.
3. **SKILL.md < 500 lines.** Split or decompose.
4. **Split by load frequency.** Always → SKILL.md. Once → setup.md. On-demand → reference.md.
5. **Sub-files = zero context cost** until explicitly read.
6. **Rule-based for infra, LLM for code.** Never ask LLM to do git, PM, or curl for status updates.
7. **Executable bash scripts use `.env`.** Every executable script shipped by a skill loads its script-local or project-local `.env`; commit a matching `.env.example`, and avoid `config.sh` one-offs. A sourced library may remain side-effect-free only when its caller loads `.env` first and its public contract says so.
8. **精簡但深邃。AI秒懂。** Every line carries weight. No filler.

See [creating.md](creating.md) for syntax/frontmatter reference.
