---
name: developing-project-management
description: LatticeCast PM integration — ticket status updates, project setup, pre-flight checks. Internal lib used by developing-programming, agent-claude-bot, developing-onboarding.
user-invocable: false
allowed-tools: Bash, Read
version: 0.4.0
---

# LatticeCast Project Management

Internal skill providing PM operations. Other skills compose via `Skill(developing-project-management)`.

**URL**: `http://localhost:13491`
**Auth**: `Authorization: Bearer <identifier>` — identifier can be UUID, display_id, or email (resolved in that order)

> **First-time setup?** See [setup.md](setup.md)
> **Full API reference?** See [endpoints.md](endpoints.md)

## ID Resolution (everywhere)

All identifiers (Bearer token, URL paths, member lookup) resolve in order:
1. **UUID** — `a712f960-8f9f-4b9d-8d12-3be3cd2d75d1`
2. **display_id** — `lattice`, `homun-lang-002` (case-insensitive)
3. **email** — `user@example.com` (case-insensitive)

```bash
# All equivalent:
curl -H "Authorization: Bearer a712f960-..."      # UUID
curl -H "Authorization: Bearer lattice"            # display_id
curl -H "Authorization: Bearer user@example.com"   # email
```

## Row Addressing

Rows use **row_number** (integer, auto-increment per table), NOT row_id (UUID).

```
PUT /api/tables/{table_id}/rows/{row_number}
GET /api/tables/{table_id}/rows/{row_number}/doc
```

Use `filter_json` to query by JSONB field without pagination issues:
```bash
curl "/api/tables/{id}/rows?filter_json={\"<status_col>\":\"todo\"}&limit=50"
```

## Ensure Running

```bash
curl -s http://localhost:13491/api/status 2>/dev/null | grep -q '"ok"'
```

If not running → tell user to `docker compose up -d`. **Do NOT fallback to file-based tracking.**

## Setup Project (used by developing-onboarding)

See [setup.md](setup.md). Summary:

1. `GET /api/login/me` -H "Bearer claude" (create bot user)
2. `POST /api/workspaces` (create workspace)
3. Ask user for team member IDs
4. `POST /api/workspaces/{id}/members` with `{"user_name": "<display_id>", "role": "member"}`
5. `POST /api/tables/template/pm` (create PM table)
6. Report board URL

## Add Member

Provide ONE of `user_id` (UUID), `user_name` (display_id), `user_email`:

```bash
curl -X POST "/api/workspaces/{workspace_id}/members" \
  -H "Authorization: Bearer claude" \
  -d '{"user_name": "lattice", "role": "member"}'
```

## Query Tickets

```bash
# All rows (default: newest first)
curl "/api/tables/{table_id}/rows?limit=100" -H "Authorization: Bearer claude"

# Filter by status (server-side JSONB containment)
curl "/api/tables/{table_id}/rows?filter_json={\"<status_col>\":\"todo\"}&limit=50"
```

## Update Ticket Status

**ALWAYS use PUT to update existing rows. NEVER use POST (POST creates a new row with auto-generated Key, causing duplicates).**

Statuses: `todo` → `in_progress` → `testing` → `review` → `merged` (also `debugging` loop)

```bash
# CORRECT: PUT updates existing row
curl -X PUT "/api/tables/{table_id}/rows/{row_number}" \
  -H "Authorization: Bearer claude" \
  -d '{"row_data": {...existing_data, "<status_col_id>": "in_progress"}}'

# WRONG: POST creates a NEW row — causes duplicate TO-* keys!
# curl -X POST "/api/tables/{table_id}/rows" ...  ← NEVER DO THIS FOR STATUS UPDATES
```

## Default Time Rule

When creating a ticket, if `Start Date` or `Due Date` not specified, **default both to today**. Never leave empty.

## Ticket Docs (MinIO)

```bash
GET  /api/tables/{table_id}/rows/{row_number}/doc   # read markdown
PUT  /api/tables/{table_id}/rows/{row_number}/doc   # save markdown (text/plain or multipart file)
```

### Recommended workflow: use `.tmp/issue/` as local scratch

```bash
# 1. Download doc to local file
mkdir -p .tmp/issue/{row_number}
curl -s "/api/tables/{table_id}/rows/{row_number}/doc" \
  -H "Authorization: Bearer claude" > .tmp/issue/{row_number}/doc.md

# 2. Edit locally (append, rewrite, whatever)
echo "- $(date -u +%Y-%m-%dT%H:%M:%SZ) Started by W1" >> .tmp/issue/{row_number}/doc.md

# 3. Upload back
curl -X PUT "/api/tables/{table_id}/rows/{row_number}/doc" \
  -H "Authorization: Bearer claude" \
  -F file=@.tmp/issue/{row_number}/doc.md
```

This avoids painful `--data-raw` escaping. Workers should use this pattern for all doc updates.

All notes go to ticket docs. Workers MUST update docs continuously.

## Status Flow

```
todo → in_progress → testing → review → merged
                       ↓
                    debugging → testing (loop)

Auto-cascade: all children merged → parent auto-merged
```
