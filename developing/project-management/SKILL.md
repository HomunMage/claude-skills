---
name: developing/project-management
description: LatticeCast PM integration — ticket status updates, project setup, pre-flight checks. Internal library used by developing/programming, agent/agentic-hive, and developing/onboarding.
user-invocable: false
allowed-tools: Bash, Read
version: 0.10.0
---

# LatticeCast Project Management

> **v0.8.0**: Refactored as a thin layer over `developing/lattice-cast` (`lc_api.sh`).
> The PM-specific helpers (`pm_login`, `pm_cache_cols`, `pm_set_status`,
> `pm_create_ticket`, `pm_get_todo_tasks`, `pm_*_doc`) live in `pm_tool.sh`
> and source `lc_api.sh` from the sibling skill. Compose at the consumer:
>
> ```bash
> source <project>/config.sh        # exports LC_API, PM_USER, TABLE_ID, …
> source <skills>/developing/project-management/pm_tool.sh   # auto-sources lc_api.sh
> pm_login; pm_get_todo_tasks
> ```


Internal skill providing PM operations. Other skills compose via `Skill(developing/project-management)`.

**URL**: `http://localhost:13491`

> **First-time setup?** See [setup.md](setup.md)
> **Full API reference?** See [endpoints.md](endpoints.md)

## Login First — Always

Every PM session starts with `POST /api/v1/login/password` to obtain a token. The bare `Bearer <user_name>` shortcut is no longer reliable (auto-create-user is disabled since v0.21 to avoid multi-worker races, and the v0.23 role rebalance routes login through the `app` role).

```bash
# 1. Login → get access_token (UUID)
TOKEN=$(curl -s -X POST http://localhost:13491/api/v1/login/password \
  -H "Content-Type: application/json" \
  -d '{"user_name":"lattice","password":""}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# 2. Use the token for everything else
curl -s "http://localhost:13491/api/v1/tables/foo/rows" \
  -H "Authorization: Bearer $TOKEN"
```

In `AUTH_REQUIRED=false` (dev), the password is ignored — any value works. The user must already exist in `auth.users` + `gdpr.user_info` (v40 merged the old `public.user_info` + `auth.gdpr` into one row). New users are created by an admin via `POST /api/v1/admin/users` (see [setup.md](setup.md)).

## ID Resolution

After login, the token IS the `user_id` (UUID). Other identifier fields (URL paths, member lookup) resolve in this order:
1. **UUID** — `a712f960-8f9f-4b9d-8d12-3be3cd2d75d1`
2. **user_name** — `lattice`, `homun-lang-002` (case-insensitive, regex `^[a-z0-9][a-z0-9_-]{2,31}$`)
3. **email** — `user@example.com` (case-insensitive)

## Row Addressing

Rows use **`row_id`** (BIGINT, auto-increment per table). This was
renamed from `row_number` in v0.40 — the field, JSON key, and URL
segment are all `row_id` now.

```
GET /api/v1/tables/{table_id}/rows/{row_id}
PUT /api/v1/tables/{table_id}/rows/{row_id}
GET /api/v1/tables/{table_id}/rows/{row_id}/doc
PUT /api/v1/tables/{table_id}/rows/{row_id}/doc
```

Use `filter_json` to query by JSONB field without pagination issues:
```bash
curl "/api/v1/tables/{id}/rows?filter_json={\"<status_col>\":\"todo\"}&limit=50" \
  -H "Authorization: Bearer $TOKEN"
```

## Ensure Running

```bash
curl -s http://localhost:13491/api/v1/status 2>/dev/null | grep -q '"ok"'
```

If not running → tell user to `docker compose up -d`. **Do NOT fallback to file-based tracking.**

## Setup Project (used by developing/onboarding)

See [setup.md](setup.md). Summary:

1. Login as admin → get `$ADMIN_TOKEN`
2. `POST /api/v1/admin/users` — create bot user `claude` (admin must do this; auto-create is disabled)
3. Login as `claude` → get `$TOKEN`
4. `POST /api/v1/workspaces` (creates workspace with UUID `workspace_id`)
5. Ask user for team member identifiers
6. `POST /api/v1/workspaces/{ws_uuid}/members` with `{"user_name": "<id>", "role": "member"}`
7. `POST /api/v1/tables/template/pm`
8. Report board URL

## Add Member

Provide ONE of `user_id` (UUID), `user_name`, `user_email`:

```bash
curl -X POST "http://localhost:13491/api/v1/workspaces/{workspace_uuid}/members" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"user_name": "lattice", "role": "member"}'
```

## Query Tickets

```bash
# All rows (default: newest first)
curl "http://localhost:13491/api/v1/tables/{table_id}/rows?workspace_id={ws_uuid}&limit=100" \
  -H "Authorization: Bearer $TOKEN"

# Filter by status (server-side JSONB containment)
curl "http://localhost:13491/api/v1/tables/{table_id}/rows?workspace_id={ws_uuid}&filter_json={\"<status_col>\":\"todo\"}&limit=50" \
  -H "Authorization: Bearer $TOKEN"
```

## Update Ticket Status

**ALWAYS use PUT to update existing rows. NEVER use POST (POST creates a new row, causing duplicates).**

Statuses: `todo` → `in_progress` → `testing` → `review` → `merged` (also `debugging` loop)

```bash
# CORRECT: PUT updates existing row
curl -X PUT "http://localhost:13491/api/v1/tables/{table_id}/rows/{row_id}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"row_data": {...existing_data, "<status_col_id>": "in_progress"}}'

# WRONG: POST creates a NEW row → duplicate keys!
# curl -X POST "/api/v1/tables/{table_id}/rows" ...  ← NEVER for status updates
```

## Default Time Rule

When creating a ticket, if `Start Date` or `Due Date` not specified, **default both to today (UTC)**. Never leave empty.

## Ticket Docs (MinIO)

```bash
GET  /api/v1/tables/{table_id}/rows/{row_id}/doc   # read markdown
PUT  /api/v1/tables/{table_id}/rows/{row_id}/doc   # save markdown (text/plain or multipart)
```

### Recommended workflow: use `.tmp/issue/` as local scratch

```bash
# 1. Download doc to local file
mkdir -p .tmp/issue/{row_id}
curl -s "http://localhost:13491/api/v1/tables/{table_id}/rows/{row_id}/doc" \
  -H "Authorization: Bearer $TOKEN" > .tmp/issue/{row_id}/doc.md

# 2. Edit locally (append, rewrite, whatever)
echo "- $(date -u +%Y-%m-%dT%H:%M:%SZ) Started by W1" >> .tmp/issue/{row_id}/doc.md

# 3. Upload back
curl -X PUT "http://localhost:13491/api/v1/tables/{table_id}/rows/{row_id}/doc" \
  -H "Authorization: Bearer $TOKEN" \
  -F file=@.tmp/issue/{row_id}/doc.md
```

Avoids painful `--data-raw` escaping. Workers should use this pattern for all doc updates.

All notes go to ticket docs. Workers MUST update docs continuously.

## Status Flow

```
todo → in_progress → testing → review → merged
                       ↓
                    debugging → testing (loop)

Auto-cascade: all children merged → parent auto-merged
```
