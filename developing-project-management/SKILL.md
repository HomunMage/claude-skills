---
name: developing-project-management
description: LatticeCast PM integration — ticket status updates, project setup, pre-flight checks. Internal lib used by developing-programming, agent-claude-bot, developing-onboarding.
user-invocable: false
allowed-tools: Bash, Read
---

# LatticeCast Project Management

Internal skill providing PM operations. Other skills compose via `Skill(developing-project-management)`.

**URL**: `http://localhost:13491`
**Auth**: `Authorization: Bearer <user_id>` (dev mode: Bearer value = user_id, auto-created)

> **First-time setup?** See [setup.md](setup.md) — auth explanation, workspace creation, member management.
> **Full API reference?** See [endpoints.md](endpoints.md) — all CRUD endpoints, query/update scripts, cascade logic.

## Ensure Running

```bash
curl -s http://localhost:13491/api/status 2>/dev/null | grep -q '"ok"'
```

If not running → tell user to `docker compose up -d backend frontend`. **Do NOT fallback to file-based tracking.**

## Setup Project (used by developing-onboarding)

See [setup.md](setup.md) for full sequence. Summary:

1. `GET /api/login/me` -H "Bearer claude" (create bot user)
2. `POST /api/workspaces` (create workspace)
3. Ask user for team member IDs
4. `GET /api/login/me` + `POST /api/workspaces/{id}/members` (add members)
5. `POST /api/tables/template/pm` (create PM table)
6. Report board URL

## Query Tickets (used by developing-programming pre-flight)

See [endpoints.md](endpoints.md) "Query Tickets" for full script. Quick version:

```bash
curl -s http://localhost:13491/api/tables -H "Authorization: Bearer claude"
# Find table matching repo name, then:
curl -s "http://localhost:13491/api/tables/{table_id}/rows?limit=20" -H "Authorization: Bearer claude"
```

## Update Ticket Status

Statuses: `todo` → `in_progress` → `testing` → `review` → `merged` (also `debugging` → `testing` loop)

```bash
curl -s -X PUT "http://localhost:13491/api/rows/{row_id}" \
  -H "Authorization: Bearer claude" \
  -H "Content-Type: application/json" \
  -d '{"row_data": {...existing_data, "<status_col_id>": "<NEW_STATUS>"}}'
```

See [endpoints.md](endpoints.md) "Update Ticket Status" for the full script that looks up by ticket key.

## Create Ticket

```bash
curl -s -X POST "http://localhost:13491/api/tables/{table_id}/rows" \
  -H "Authorization: Bearer claude" \
  -H "Content-Type: application/json" \
  -d '{"row_data": {"<title_col_id>": "<title>", "<type_col_id>": "task", "<status_col_id>": "todo", "<priority_col_id>": "medium"}}'
```

## Ticket Docs (MinIO)

- `GET /api/tables/{table_id}/rows/{row_id}/doc` — read
- `PUT /api/tables/{table_id}/rows/{row_id}/doc` — save (text/plain body)

All notes go to the ticket's doc in LatticeCast.

## Status Flow

```
todo → in_progress → testing → review → merged
                       ↓
                    debugging → testing (loop)

Auto-cascade: all children merged → parent auto-merged
```

After marking a ticket `merged`, run cascade check — see [endpoints.md](endpoints.md) "Auto-Cascade".
