---
name: developing-project-management
description: LatticeCast PM integration — ticket status updates, project setup, pre-flight checks. Internal lib used by developing-programming, agent-claude-bot, developing-onboarding.
user-invocable: false
allowed-tools: Bash, Read
version: 0.2.1
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
curl -s -X PUT "http://localhost:13491/api/tables/{table_id}/rows/{row_number}" \
  -H "Authorization: Bearer claude" \
  -H "Content-Type: application/json" \
  -d '{"row_data": {...existing_data, "<status_col_id>": "<NEW_STATUS>"}}'
```

See [endpoints.md](endpoints.md) "Update Ticket Status" for the full script that looks up by ticket key.

## Default Time Rule

When creating a ticket, if `Start Date` or `Due Date` is not explicitly specified, **default both to today's date** (e.g. `2026-04-03`). Never leave date fields empty.

## Create Ticket

```bash
TODAY=$(date -u +%Y-%m-%d)
curl -s -X POST "http://localhost:13491/api/tables/{table_id}/rows" \
  -H "Authorization: Bearer claude" \
  -H "Content-Type: application/json" \
  -d '{"row_data": {"<title_col_id>": "<title>", "<type_col_id>": "task", "<status_col_id>": "todo", "<priority_col_id>": "medium", "<start_date_col_id>": "'$TODAY'", "<due_date_col_id>": "'$TODAY'"}}'
```

## Ticket Docs (MinIO)

- `GET /api/tables/{table_id}/rows/{row_number}/doc` — read
- `PUT /api/tables/{table_id}/rows/{row_number}/doc` — save (text/plain body)

All notes go to the ticket's doc in LatticeCast.

## Story Branch Management

Story branches bridge issues and main. Issues branch off the story branch; when all issues are merged, the story merges into main.

### Create Story Branch from Main

```bash
STORY_KEY="<story-key-lowercase>"  # e.g. l-5
STORY_BRANCH="story/${STORY_KEY}"

git checkout main
git checkout -b "$STORY_BRANCH" 2>/dev/null || git checkout "$STORY_BRANCH"
```

### Merge Story into Main (when all issues merged)

After merging an issue into its story branch, check whether all sibling issues are done, then merge story into main:

```bash
TABLE_ID="<table_id>"
STORY_ROW_ID="<story_row_id>"
PARENT_COL_ID="<parent_col_id>"
STATUS_COL_ID="<status_col_id>"
STORY_BRANCH="story/<story-key-lowercase>"

ALL_ROWS=$(curl -s "http://localhost:13491/api/tables/${TABLE_ID}/rows?limit=200" \
  -H "Authorization: Bearer claude")

UNMERGED=$(echo "$ALL_ROWS" | python3 -c "
import json, sys
rows = json.load(sys.stdin)
unmerged = [r for r in rows
            if r["row_data"].get("${PARENT_COL_ID}") == "${STORY_ROW_ID}"
            and r["row_data"].get("${STATUS_COL_ID}") != "merged"]
print(len(unmerged))
")

if [ "$UNMERGED" = "0" ]; then
  git checkout main
  git merge "$STORY_BRANCH"
  git branch -d "$STORY_BRANCH"
  # Update story ticket → merged
  STORY_ROW_NUMBER=$(echo "$ALL_ROWS" | python3 -c "
import json, sys
rows = json.load(sys.stdin)
for r in rows:
    if r[\"row_id\"] == \"${STORY_ROW_ID}\":
        print(r[\"row_number\"])
        break
")
  STORY_DATA=$(echo "$ALL_ROWS" | python3 -c "
import json, sys
rows = json.load(sys.stdin)
for r in rows:
    if r[\"row_id\"] == \"${STORY_ROW_ID}\":
        d = r[\"row_data\"]
        d[\"${STATUS_COL_ID}\"] = \"merged\"
        print(json.dumps({\"row_data\": d}))
        break
")
  curl -s -X PUT "http://localhost:13491/api/tables/${TABLE_ID}/rows/${STORY_ROW_NUMBER}" \
    -H "Authorization: Bearer claude" \
    -H "Content-Type: application/json" \
    -d "$STORY_DATA" > /dev/null
  echo "Story merged into main."
else
  echo "Not all issues merged yet ($UNMERGED remaining). Story branch stays open."
fi
```

## Status Flow

```
todo → in_progress → testing → review → merged
                       ↓
                    debugging → testing (loop)

Auto-cascade: all children merged → parent auto-merged
```

After marking a ticket `merged`, run cascade check — see [endpoints.md](endpoints.md) "Auto-Cascade".
