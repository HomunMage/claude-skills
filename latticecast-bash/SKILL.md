---
name: latticecast-bash
description: Thin bash curl wrapper around the LatticeCast HTTP API — one function per route, no domain knowledge, no caching, no magic. Use as the foundation for project-specific tool layers (PM, SEO, dev tracking, etc.). Caller composes lc_api.sh + their own config.sh + domain helpers.
version: 0.1.0
---

# latticecast-bash

`lc_api.sh` is a thin bash client over the LatticeCast HTTP API. One
function per route. **No domain knowledge, no caching, no magic.** Each
function is roughly `curl + sane defaults + JSON in/out`.

This skill is consumed by other skills (`developing-project-management`)
and downstream projects (e.g. seo-system) which build their own
domain-specific tool layers on top.

## Composition rule

```
your_tool.sh = lc_api.sh + your_project/config.sh + your domain fns
```

Sourcing `lc_api.sh` only **defines functions** — it has no side effects
and reads no config implicitly. The caller is expected to set the
documented env vars before any `lc_*` call.

## Env contract (set by caller before sourcing)

| Var | Required | Purpose |
|---|---|---|
| `LC_API` | yes | Base URL, e.g. `http://localhost:13491/api/v1` |
| `LC_AUTH_HEADER` | yes | Full header value, e.g. `Authorization: Bearer claude` |
| `LC_PROJECT_DIR` | no | Where consumer wants caches; `lc_api.sh` doesn't write any |
| `LC_THROTTLE_MS` | no | Sleep between calls (default 0). |

## Routes (one function each)

```
# ── health + auth ─────────────────────────────────────────────────────
lc_status                         → GET  /status

lc_login_password USER_NAME PASS  → POST /login/password
                                    echoes access_token on success.
                                    Caller is responsible for caching.

# ── workspaces ────────────────────────────────────────────────────────
lc_workspace_list                 → GET  /workspaces
lc_workspace_create NAME          → POST /workspaces
lc_workspace_member_add WS USER ROLE  → POST /workspaces/{ws}/members

# ── tables ────────────────────────────────────────────────────────────
lc_table_list  [WS_ID]            → GET  /tables[?workspace_id=WS_ID]
lc_table_get   TID                → GET  /tables/{tid}
lc_table_create TID WS_ID         → POST /tables {table_id, workspace_id}
lc_table_delete TID               → DELETE /tables/{tid}

# ── columns (backed by __schema__ row server-side) ───────────────────
lc_columns_list   TID             → GET  /tables/{tid}/columns
lc_column_create  TID JSON        → POST /tables/{tid}/columns
lc_column_update  TID COL_ID JSON → PUT  /tables/{tid}/columns/{col_id}
lc_column_delete  TID COL_ID      → DELETE /tables/{tid}/columns/{col_id}

# ── rows ──────────────────────────────────────────────────────────────
lc_row_list   TID [LIMIT] [FILTER_JSON]  → GET /tables/{tid}/rows[?…]
lc_row_create TID JSON                   → POST /tables/{tid}/rows
                                            JSON = '{"row_data": {...}}'
                                            echoes the new row's row_number
lc_row_update TID RN JSON                → PUT  /tables/{tid}/rows/{rn}
lc_row_delete TID RN                     → DELETE /tables/{tid}/rows/{rn}

# ── docs ──────────────────────────────────────────────────────────────
lc_doc_read   TID RN              → GET /…/rows/{rn}/doc          (text out)
lc_doc_write  TID RN [-f FILE]    → PUT /…/rows/{rn}/doc          (text in)
                                    -f for files (avoids quoting hell);
                                    omit and pipe content via stdin.

# ── views ─────────────────────────────────────────────────────────────
lc_view_list      TID                  → GET /tables/{tid}/views
lc_view_create    TID JSON             → POST /tables/{tid}/views
lc_view_update    TID NAME JSON        → PUT  /tables/{tid}/views/{name}
lc_view_delete    TID NAME             → DELETE /tables/{tid}/views/{name}
lc_view_order_get TID                  → GET /tables/{tid}/view-order
lc_view_order_put TID JSON_ARRAY       → PUT /tables/{tid}/view-order
                                          body: {"order": [...]}

# ── dashboard widget query ───────────────────────────────────────────
lc_block_query TID VIEW_NAME BLOCK_ID [PARAMS_JSON]
                                  → POST /tables/{tid}/views/{name}/blocks/{id}/query
```

## Behavior

- All functions: `curl -sf` (silent + fail on 4xx/5xx), exit non-zero
  on any HTTP error and write the error body to stderr.
- Bodies are passed in via `--data` from a temp file, never
  shell-substituted into a string. Avoids JSON-in-bash injection bugs.
- All POST/PUT bodies are JSON unless noted (doc endpoints take text).
- Functions never read or write to stdin/stdout other than what the
  description says. No interactive prompts.
- `LC_THROTTLE_MS` is checked once before each call (cheap).

## Example use

```bash
# In a consumer's tool layer (e.g. pm_tool.sh):
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"               # exports LC_API, LC_AUTH_HEADER, …
source "${SKILLS_DIR}/latticecast-bash/lc_api.sh"

# now lc_* functions are available
lc_status
TID="pm"
lc_doc_read "$TID" 1
echo "todo task count:"
lc_row_list "$TID" 200 '{"<status_col_id>":"todo"}' \
  | python3 -c "import json,sys; print(len(json.load(sys.stdin)))"
```

## Out of scope

- Token management — `lc_login_password` returns the token; persistence
  is the consumer's concern.
- Column-id caching — fetch via `lc_columns_list`; cache it yourself if
  needed. Caching policy varies by consumer.
- Domain workflows (PM ticket flow, SEO content pipeline, dashboard
  layouts) — those live in `pm_tool.sh`, `seo_tool.sh`, etc., which
  source this file.
