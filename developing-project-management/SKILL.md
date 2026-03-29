---
name: developing-project-management
description: LatticeCast PM integration — ticket status updates, project setup, pre-flight checks. Internal lib used by developing-programming, agent-claude-bot, developing-onboarding.
user-invocable: false
allowed-tools: Bash, Read
---

# LatticeCast Project Management

Internal skill providing PM operations. Other skills compose via `Skill(developing-project-management)`.

## LatticeCast API

**URL**: `http://localhost:5000`
**Auth**: `Authorization: Bearer claude` (claude is the bot user)

## Ensure LatticeCast is Running

Before any PM operation, check connectivity:

```bash
curl -s http://localhost:5000/api/status 2>/dev/null | grep -q '"ok"'
```

If **not running**, tell the user:

> **LatticeCast PM is not running.** Please start it:
> ```bash
> cd <LatticeCast-repo> && docker compose up -d backend frontend
> ```
> If you don't have it yet:
> ```bash
> git clone https://github.com/LatticeMage/LatticeCast.git
> cd LatticeCast && docker compose up -d backend frontend
> ```
> Let me know when it's ready.

**Do NOT proceed with PM operations until LatticeCast is confirmed running. Do NOT fallback to file-based tracking.**

## Setup Project (used by developing-onboarding)

### 1. Create claude user
```bash
curl -s http://localhost:5000/api/login/me -H "Authorization: Bearer claude"
```

### 2. Ask user for team members
Ask: **"Which user IDs should have access? (e.g. homunmage@gmail.com)"**

### 3. Add members
```bash
# Ensure member user exists first
curl -s http://localhost:5000/api/login/me -H "Authorization: Bearer <user_id>"
# Add to claude's workspace
curl -s -X POST http://localhost:5000/api/workspaces/claude/members \
  -H "Authorization: Bearer claude" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "<user_id>", "role": "member"}'
```

### 4. Create PM table
```bash
PROJECT_NAME="$(basename $(git rev-parse --show-toplevel 2>/dev/null || pwd))"
curl -s -X POST http://localhost:5000/api/tables/template/pm \
  -H "Authorization: Bearer claude" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"${PROJECT_NAME}\", \"workspace_id\": \"claude\"}"
```

### 5. Report URL
```
Project board: http://localhost:3000/claude/<table_id>
Views: Table | Sprint Board (Kanban) | Roadmap (Timeline)
```

## Query Tickets (used by developing-programming pre-flight)

Find PM table matching repo name, list tickets sorted newest first:

```bash
REPO_NAME="$(basename $(git rev-parse --show-toplevel 2>/dev/null || pwd))"
curl -s http://localhost:5000/api/tables -H "Authorization: Bearer claude" | \
python3 -c "
import sys, json, urllib.request
tables = json.load(sys.stdin)
repo = '${REPO_NAME}'
table = next((t for t in tables if t['name'].lower() == repo.lower()), None)
if not table:
    print(f'No PM table for \"{repo}\"'); exit()
tid = table['table_id']
cols = {c['name']: c['column_id'] for c in table.get('columns',[])}
print(f'Project: {table[\"name\"]}  URL: http://localhost:3000/claude/{tid}')
rows = json.loads(urllib.request.urlopen(urllib.request.Request(
    f'http://localhost:5000/api/tables/{tid}/rows?offset=0&limit=20',
    headers={'Authorization': 'Bearer claude'}
)).read())
rows.sort(key=lambda r: r.get('updated_at',''), reverse=True)
kid,tid2,sid,pid,tyid = cols.get('Key',''),cols.get('Title',''),cols.get('Status',''),cols.get('Priority',''),cols.get('Type','')
print(f'Tickets ({len(rows)}):')
for r in rows:
    d = r.get('row_data',{})
    print(f'  {d.get(kid,\"?\"):8s} [{d.get(sid,\"-\"):12s}] {d.get(pid,\"-\"):8s} {d.get(tyid,\"-\"):5s}  {d.get(tid2,\"(untitled)\")}')
"
```

## Update Ticket Status (used by developing-programming workflow)

Statuses: `todo`, `in_progress`, `testing`, `debugging`, `review`, `merged`

```bash
# Usage: update_ticket <TICKET_KEY> <NEW_STATUS>
REPO_NAME="$(basename $(git rev-parse --show-toplevel 2>/dev/null || pwd))"
python3 -c "
import json, urllib.request
tables = json.loads(urllib.request.urlopen(urllib.request.Request(
    'http://localhost:5000/api/tables',
    headers={'Authorization': 'Bearer claude'}
)).read())
table = next((t for t in tables if t['name'].lower() == '${REPO_NAME}'.lower()), None)
if not table: exit()
tid = table['table_id']
cols = {c['name']: c['column_id'] for c in table.get('columns',[])}
status_id, key_id = cols.get('Status',''), cols.get('Key','')
if not status_id or not key_id: exit()
rows = json.loads(urllib.request.urlopen(urllib.request.Request(
    f'http://localhost:5000/api/tables/{tid}/rows?offset=0&limit=200',
    headers={'Authorization': 'Bearer claude'}
)).read())
row = next((r for r in rows if r['row_data'].get(key_id) == '<TICKET_KEY>'), None)
if not row: print('Ticket not found'); exit()
new_data = {**row['row_data'], status_id: '<NEW_STATUS>'}
req = urllib.request.Request(
    f'http://localhost:5000/api/rows/{row[\"row_id\"]}',
    data=json.dumps({'row_data': new_data}).encode(),
    headers={'Authorization': 'Bearer claude', 'Content-Type': 'application/json'},
    method='PUT'
)
urllib.request.urlopen(req)
print(f'<TICKET_KEY> → <NEW_STATUS>')
"
```

## Create Ticket (used by agent-claude-bot planning)

```bash
TABLE_ID="<table_id>"
curl -s -X POST "http://localhost:5000/api/tables/${TABLE_ID}/rows" \
  -H "Authorization: Bearer claude" \
  -H "Content-Type: application/json" \
  -d '{"row_data": {"<title_col_id>": "<title>", "<type_col_id>": "task", "<status_col_id>": "todo", "<priority_col_id>": "medium"}}'
```

## Auto-Cascade: Parent Status from Children

When a task/bug is marked `merged`, check if all siblings under the same parent are also `merged`. If yes, auto-update the parent (story) to `merged`. Same logic cascades: all stories merged → epic merged.

```bash
# After updating a ticket to merged, check parent cascade:
python3 -c "
import json, urllib.request

TABLE_ID = '<table_id>'
AUTH = {'Authorization': 'Bearer claude'}

# Fetch all rows
rows = json.loads(urllib.request.urlopen(urllib.request.Request(
    f'http://localhost:5000/api/tables/{TABLE_ID}/rows?offset=0&limit=200',
    headers=AUTH
)).read())

# Get column IDs from table
table = json.loads(urllib.request.urlopen(urllib.request.Request(
    f'http://localhost:5000/api/tables/{TABLE_ID}',
    headers=AUTH
)).read())
cols = {c['name']: c['column_id'] for c in table.get('columns',[])}
status_id = cols.get('Status','')
parent_id = cols.get('Parent','')
if not status_id or not parent_id: exit()

# Build parent → children map
by_id = {r['row_id']: r for r in rows}
children_of = {}
for r in rows:
    pid = r['row_data'].get(parent_id)
    if pid:
        children_of.setdefault(pid, []).append(r)

# Check each parent: if all children merged, mark parent merged
for pid, kids in children_of.items():
    if pid not in by_id: continue
    parent = by_id[pid]
    if parent['row_data'].get(status_id) == 'merged': continue
    if all(k['row_data'].get(status_id) == 'merged' for k in kids):
        new_data = {**parent['row_data'], status_id: 'merged'}
        req = urllib.request.Request(
            f'http://localhost:5000/api/rows/{pid}',
            data=json.dumps({'row_data': new_data}).encode(),
            headers={**AUTH, 'Content-Type': 'application/json'},
            method='PUT'
        )
        urllib.request.urlopen(req)
        key_id = cols.get('Key','')
        print(f'Auto-merged parent: {parent[\"row_data\"].get(key_id, pid)}')
"
```

Run this after every ticket status update to `merged`.

## Ticket Docs (MinIO)

Each ticket's detailed notes/spec live in MinIO, not in `.tmp/llm.working.notes`:

```
{user_id}/{workspace_id}/{table_id}/{row_id}.md
```

Access via:
- `GET /api/tables/{table_id}/rows/{row_id}/doc` — read doc
- `PUT /api/tables/{table_id}/rows/{row_id}/doc` — save doc

**Do NOT use `.tmp/llm.working.notes`** — all notes go to the ticket's doc in LatticeCast.

## Status Flow

```
todo → in_progress → testing → review → merged
                       ↓
                    debugging → testing (loop)

Auto-cascade: all children merged → parent auto-merged
  task merged ──┐
  task merged ──┤→ story auto-merged ──┐
  task merged ──┘                      ├→ epic auto-merged
  story auto-merged ───────────────────┘
```

| Status | Trigger |
|--------|---------|
| `todo` | Created |
| `in_progress` | Branch created |
| `testing` | Running tests |
| `debugging` | Tests failed |
| `review` | Committed |
| `merged` | Branch merged / all children merged |
