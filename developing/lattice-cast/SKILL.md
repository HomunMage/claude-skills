---
name: developing/lattice-cast
description: Thin bash curl wrapper around the LatticeCast HTTP API — one function per route, no domain knowledge, no caching, no magic. Use as the foundation for project-specific tool layers (PM, SEO, dev tracking, etc.). Caller composes lc_api.sh + their own config.sh + domain helpers.
version: 0.4.0
---

# developing/lattice-cast

`lc_api.sh` is a thin bash client over the LatticeCast HTTP API. One
function per route. **No domain knowledge, no caching, no magic.** Each
function is roughly `curl + sane defaults + JSON in/out`.

This skill is consumed by other skills (`developing/project-management`)
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

# ── columns ──────────────────────────────────────────────────────────
# v40: per-aspect GET /columns was removed. Columns are in the GET
# /tables/{tid} response's `columns` array, and every mutation returns
# the full TableSchema. PATCH replaces the old PUT for updates.
lc_column_create  TID JSON        → POST  /tables/{tid}/columns
lc_column_update  TID COL_ID JSON → PATCH /tables/{tid}/columns/{col_id}
lc_column_delete  TID COL_ID      → DELETE /tables/{tid}/columns/{col_id}

# ── rows (v40: row_id is the identifier, was row_number) ────────────
lc_row_list   TID [LIMIT] [FILTER_JSON]  → GET /tables/{tid}/rows[?…]
lc_row_create TID JSON                   → POST /tables/{tid}/rows
                                            JSON = '{"row_data": {...}}'
                                            echoes the new row's row_id (int)
lc_row_update TID ROW_ID JSON            → PUT    /tables/{tid}/rows/{row_id}
# (no single-row GET — use lc_row_list with filter_json instead)
lc_row_delete TID ROW_ID                 → DELETE /tables/{tid}/rows/{row_id}

# ── docs (keyed by row_id, same as rows) ────────────────────────────
lc_doc_read   TID ROW_ID          → GET /…/rows/{row_id}/doc      (text out)
lc_doc_write  TID ROW_ID [-f FILE]→ PUT /…/rows/{row_id}/doc      (text in)
                                    -f for files (avoids quoting hell);
                                    omit and pipe content via stdin.

# ── views (v40: view_id is the identifier, was view_name) ───────────
# Display name + view type now live INSIDE config JSONB; pass them in
# the body for create/update.
lc_view_list   TID                     → GET    /tables/{tid}/views
lc_view_get    TID VIEW_ID             → GET    /tables/{tid}/views/{view_id}
lc_view_create TID JSON                → POST   /tables/{tid}/views
                                          JSON = '{"name":"…","type":"kanban","config":{…}}'
lc_view_update TID VIEW_ID JSON        → PUT    /tables/{tid}/views/{view_id}
lc_view_delete TID VIEW_ID             → DELETE /tables/{tid}/views/{view_id}

# Schema patch — order / default_view / col_order all live in
# table_schemas.config; one endpoint, partial body, returns full schema.
lc_schema_patch TID JSON               → PATCH /tables/{tid}
                                          JSON = any subset of
                                          {view_order:[int…], default_view:int,
                                           col_order:[col_id…]}

# ── dashboard widget query ───────────────────────────────────────────
lc_block_query TID VIEW_ID BLOCK_ID [PARAMS_JSON]
                                  → POST /tables/{tid}/views/{view_id}/blocks/{id}/query
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
source "${SKILLS_DIR}/developing/lattice-cast/lc_api.sh"

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
- Column-id caching — fetch from `lc_table_get TID` (`.columns` array);
  cache it yourself if needed. Caching policy varies by consumer.
- Domain workflows (PM ticket flow, SEO content pipeline, dashboard
  layouts) — those live in `pm_tool.sh`, `seo_tool.sh`, etc., which
  source this file.
