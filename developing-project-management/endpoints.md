# API Endpoints Reference

**URL**: `http://localhost:13491`
**Auth**: Always login first via `POST /api/v1/login/password` to obtain a token. Auto-create-user is disabled — admins create users via `POST /api/v1/admin/users`.

```bash
TOKEN=$(curl -s -X POST http://localhost:13491/api/v1/login/password \
  -H "Content-Type: application/json" \
  -d '{"user_name":"<id>","password":""}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
# Then: -H "Authorization: Bearer $TOKEN"
```

## Endpoint Table

| Resource | Create | Read | Update | Delete |
|----------|--------|------|--------|--------|
| Login | `POST /api/v1/login/password` → access_token (UUID) | `GET /api/v1/login/me` | — | — |
| User (admin) | `POST /api/v1/admin/users` | `GET /api/v1/admin/users` | `PUT /api/v1/admin/users/{id}` | `DELETE /api/v1/admin/users/{id}` |
| Workspace | `POST /api/v1/workspaces` | `GET /api/v1/workspaces` | `PUT /api/v1/workspaces/{id}` | `DELETE /api/v1/workspaces/{id}` |
| Members | `POST /api/v1/workspaces/{id}/members` | `GET /api/v1/workspaces/{id}/members` | — | `DELETE /api/v1/workspaces/{id}/members/{uid}` |
| Table | `POST /api/v1/tables` | `GET /api/v1/tables` | `PUT /api/v1/tables/{id}` | `DELETE /api/v1/tables/{id}` |
| PM Template | `POST /api/v1/tables/template/pm` | — | — | — |
| Column | `POST /api/v1/tables/{id}/columns` | (in table.columns) | `PUT /api/v1/tables/{id}/columns/{cid}` | `DELETE /api/v1/tables/{id}/columns/{cid}` |
| Row | `POST /api/v1/tables/{id}/rows` | `GET /api/v1/tables/{id}/rows` | `PUT /api/v1/tables/{id}/rows/{row_number}` | `DELETE /api/v1/tables/{id}/rows/{row_number}` |
| Doc | `PUT .../rows/{row_number}/doc` | `GET .../rows/{row_number}/doc` | same as create | — |

## Key Conventions

- Column list comes from `table.columns` (JSONB array), not a separate endpoint
- Row data field is `row_data` (not `data`)
- Rows addressed by `row_number` (integer, per-table), NOT `row_id` (UUID — removed)
- Table PK is string `table_id` (lowercase, IS the table name)
- Composite row PK: `(workspace_id, table_id, row_number)`
- `workspace_id` is UUID

## Query Tickets

Find PM table matching repo name, list tickets sorted newest first:

```bash
REPO_NAME="$(basename $(git rev-parse --show-toplevel 2>/dev/null || pwd))"
curl -s http://localhost:13491/api/v1/tables -H "Authorization: Bearer $TOKEN" | \
python3 -c "
import sys, json, urllib.request
tables = json.load(sys.stdin)
repo = '${REPO_NAME}'
table = next((t for t in tables if t['name'].lower() == repo.lower()), None)
if not table:
    print(f'No PM table for \"{repo}\"'); exit()
tid = table['table_id']
cols = {c['name']: c['column_id'] for c in table.get('columns',[])}
print(f'Project: {table[\"name\"]}  URL: http://localhost:13491/tables/{tid}')
rows = json.loads(urllib.request.urlopen(urllib.request.Request(
    f'http://localhost:13491/api/v1/tables/{tid}/rows?offset=0&limit=20',
    headers={'Authorization': f'Bearer {TOKEN}'}
)).read())
rows.sort(key=lambda r: r.get('updated_at',''), reverse=True)
kid,tid2,sid,pid,tyid = cols.get('Key',''),cols.get('Title',''),cols.get('Status',''),cols.get('Priority',''),cols.get('Type','')
print(f'Tickets ({len(rows)}):')
for r in rows:
    d = r.get('row_data',{})
    print(f'  {d.get(kid,\"?\"):8s} [{d.get(sid,\"-\"):12s}] {d.get(pid,\"-\"):8s} {d.get(tyid,\"-\"):5s}  {d.get(tid2,\"(untitled)\")}')
"
```

## Update Ticket Status

Statuses: `todo`, `in_progress`, `testing`, `debugging`, `review`, `merged`

```bash
REPO_NAME="$(basename $(git rev-parse --show-toplevel 2>/dev/null || pwd))"
python3 -c "
import json, urllib.request
tables = json.loads(urllib.request.urlopen(urllib.request.Request(
    'http://localhost:13491/api/v1/tables',
    headers={'Authorization': f'Bearer {TOKEN}'}
)).read())
table = next((t for t in tables if t['name'].lower() == '${REPO_NAME}'.lower()), None)
if not table: exit()
tid = table['table_id']
cols = {c['name']: c['column_id'] for c in table.get('columns',[])}
status_id, key_id = cols.get('Status',''), cols.get('Key','')
if not status_id or not key_id: exit()
rows = json.loads(urllib.request.urlopen(urllib.request.Request(
    f'http://localhost:13491/api/v1/tables/{tid}/rows?offset=0&limit=200',
    headers={'Authorization': f'Bearer {TOKEN}'}
)).read())
row = next((r for r in rows if r['row_number'] == <ROW_NUMBER>), None)
if not row: print('Ticket not found'); exit()
new_data = {**row['row_data'], status_id: '<NEW_STATUS>'}
req = urllib.request.Request(
    f'http://localhost:13491/api/v1/tables/{tid}/rows/{row[\"row_number\"]}',
    data=json.dumps({'row_data': new_data}).encode(),
    headers={'Authorization': f'Bearer {TOKEN}', 'Content-Type': 'application/json'},
    method='PUT'
)
urllib.request.urlopen(req)
print(f'<TICKET_KEY> → <NEW_STATUS>')
"
```

## Create Ticket

```bash
TABLE_ID="<table_id>"
curl -s -X POST "http://localhost:13491/api/v1/tables/${TABLE_ID}/rows" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"row_data": {"<title_col_id>": "<title>", "<type_col_id>": "task", "<status_col_id>": "todo", "<priority_col_id>": "medium"}}'
```

## Auto-Cascade: Parent Status from Children

When a task/bug is marked `merged`, check if all siblings under the same parent are also `merged`. If yes, auto-update the parent (story) to `merged`.

```bash
python3 -c "
import json, urllib.request

TABLE_ID = '<table_id>'
AUTH = {'Authorization': f'Bearer {TOKEN}'}

rows = json.loads(urllib.request.urlopen(urllib.request.Request(
    f'http://localhost:13491/api/v1/tables/{TABLE_ID}/rows?offset=0&limit=200',
    headers=AUTH
)).read())

table = json.loads(urllib.request.urlopen(urllib.request.Request(
    f'http://localhost:13491/api/v1/tables/{TABLE_ID}',
    headers=AUTH
)).read())
cols = {c['name']: c['column_id'] for c in table.get('columns',[])}
status_id = cols.get('Status','')
parent_id = cols.get('Parent','')
if not status_id or not parent_id: exit()

by_rn = {r['row_number']: r for r in rows}
children_of = {}
for r in rows:
    parent_rn = r['row_data'].get(parent_id)  # parent column stores parent row_number
    if parent_rn:
        children_of.setdefault(int(parent_rn), []).append(r)

for prn, kids in children_of.items():
    if prn not in by_rn: continue
    parent = by_rn[prn]
    if parent['row_data'].get(status_id) == 'merged': continue
    if all(k['row_data'].get(status_id) == 'merged' for k in kids):
        new_data = {**parent['row_data'], status_id: 'merged'}
        req = urllib.request.Request(
            f'http://localhost:13491/api/v1/tables/{TABLE_ID}/rows/{prn}',
            data=json.dumps({'row_data': new_data}).encode(),
            headers={**AUTH, 'Content-Type': 'application/json'},
            method='PUT'
        )
        urllib.request.urlopen(req)
        key_id = cols.get('Key','')
        print(f'Auto-merged parent: {parent[\"row_data\"].get(key_id, pid)}')
"
```

## Ticket Docs (MinIO)

Each ticket's detailed notes/spec live in MinIO at `{workspace_id}/{table_id}/{row_number}.md`:

```
{workspace_id}/{table_id}/{row_number}.md
```

Access via:
- `GET /api/v1/tables/{table_id}/rows/{row_number}/doc` — read doc
- `PUT /api/v1/tables/{table_id}/rows/{row_number}/doc` — save doc (text/plain body)
