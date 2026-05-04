---
name: agent-seo-bot
description: Cross-product SEO article generator. Reads 3 CSVs (TA × promotion × product), loops the full Cartesian product, and spawns one fresh `claude -p` worker per article. Saves to LatticeCast articles table via table_helper.sh.
argument-hint: run | status
version: 0.1.0
---

# seo-bot — Cross-Product Article Generator

Spawns N×M×K fresh `claude -p` workers, one per (TA × promo × product)
combo. Each worker writes one article in isolation; the orchestrator
just loops + uploads via `table_helper.sh`.

## Architecture (same shape as `agent-claude-bot`)

```
Project root (e.g. seo-system/)
├── config.sh              # SEO_USER, SEO_API, SEO_WORKSPACE, …
├── table_helper.sh        # CRUD per row (provided by seo-system)
└── seo-bot/
    ├── run.sh             # entry point (sources config, calls orch)
    ├── orchestrator.sh    # pure shell — reads CSVs, loops product
    ├── worker.sh          # bash infra + `claude -p` for ONE article
    ├── a.csv              # source A (e.g. TA personas)
    ├── b.csv              # source B (e.g. promotions)
    └── c.csv              # source C (e.g. products)
```

## How it works

1. `bash seo-bot/run.sh` → sources `config.sh`, runs orchestrator
2. **Orchestrator (rule-based, no LLM):**
   - Parse `a.csv`, `b.csv`, `c.csv` (header row + `title,description`)
   - Build cross product (3 × 4 × 2 = 24 typically; generic for any size)
   - Query existing rows in `articles` table via `table_helper.sh articles list`
   - Skip combos already covered (idempotent — safe to rerun)
   - For each missing combo, exec `worker.sh` with the 3 (title, desc) pairs
   - Sleep 1s between workers (rate-limit per CLAUDE.md)
3. **Worker (bash + LLM):**
   - Compose a prompt embedding the three contexts
   - `timeout 120 claude -p --dangerously-skip-permissions "<prompt>"`
   - Worker writes ONE markdown file to `~/seo/.tmp/article-<title>.md`
   - Bash uploads via `table_helper.sh articles create -f <file>`
   - **No LLM in the upload path** — orchestrator+worker handle it
4. Orchestrator logs `ALL_DONE` when count reached, else exits non-zero

Each worker is a fresh process — **no shared context** between articles.

## CSV format

UTF-8, comma-delimited, first row is header. Two columns: `title,description`.

```csv
title,description
akai,26-year-old male office worker. WFH 3d/wk. Loves bouldering.
meiwen,22-year-old female grad student. Industrial design. Tight budget.
```

Title becomes the article-name component (used for the unique
`articles.Title` like `akai-spring-2026-ergopro-chair`). Description
is fed to the LLM as persona/context.

## Article-title contract

Worker uploads with `Title = "${a_title}-${b_title}-${c_title}"`.

This title is the dedupe key and the verifier's signal — it must be
unique across all combos. Don't change the format unless you also
update orchestrator's `contains` skip-check.

## Worker rules

- **One combo only.** Don't mention any other persona/promo/product.
- **≥400 chars** of substantive prose. The driver enforces this.
- **First line is `# <title>`.**
- **No filler / no echoing the prompt.**
- **Don't upload from inside the worker** — bash handles that. (LLM
  doesn't `curl` to PM. Same rule as `agent-claude-bot`.)

## Rate limit

`sleep 1` between workers in the orchestrator. From `seo-system/CLAUDE.md`:
> API rate limit: wait 1 second between each API call

## Idempotency

Re-running `run.sh` after partial completion picks up where it left
off — already-uploaded titles are skipped via `articles list`.

## Composition

Like `agent-claude-bot`, the bot's bash sources its parent project's
`config.sh` (for `SEO_USER`, `SEO_API`) and uses the project's
`table_helper.sh` (the thin LatticeCast wrapper). The bot itself
contains no LatticeCast-specific code.

## When to use this skill

- You have 3 source dimensions and want every cross-product article
  written without context leak between articles.
- You want deterministic, idempotent, rerunnable batch generation.
- You want cheap parallelism: each `claude -p` is independent.

For single-article writing: just use `claude` directly in the
seo-system project — pilot Claude reads `CLAUDE.md`, runs
`get_context.sh`, and writes ad-hoc.

## Reference scripts

[example-scripts/run.sh](example-scripts/run.sh)
[example-scripts/orchestrator.sh](example-scripts/orchestrator.sh)
[example-scripts/worker.sh](example-scripts/worker.sh)
[example-scripts/a.csv](example-scripts/a.csv) [b.csv](example-scripts/b.csv) [c.csv](example-scripts/c.csv)

Copy these into `<project>/seo-bot/`, replace CSVs with your real
sources, ensure `<project>/config.sh` and `<project>/table_helper.sh`
exist (seo-system layout), then `bash seo-bot/run.sh`.
