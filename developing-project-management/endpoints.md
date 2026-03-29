# API Endpoints Reference

**URL**: `http://localhost:13491`
**Auth**: `Authorization: Bearer <user_id>`

## Endpoint Table

| Resource | Create | Read | Update | Delete |
|----------|--------|------|--------|--------|
| User | `GET /api/login/me` (auto-create) | same | — | — |
| Workspace | `POST /api/workspaces` | `GET /api/workspaces` | `PUT /api/workspaces/{id}` | `DELETE /api/workspaces/{id}` |
| Members | `POST /api/workspaces/{id}/members` | `GET /api/workspaces/{id}/members` | — | `DELETE /api/workspaces/{id}/members/{uid}` |
| Table | `POST /api/tables` | `GET /api/tables` | `PUT /api/tables/{id}` | `DELETE /api/tables/{id}` |
| PM Template | `POST /api/tables/template/pm` | — | — | — |
| Column | `POST /api/tables/{id}/columns` | (in table.columns) | `PUT /api/tables/{id}/columns/{cid}` | `DELETE /api/tables/{id}/columns/{cid}` |
| Row | `POST /api/tables/{id}/rows` | `GET /api/tables/{id}/rows` | `PUT /api/rows/{rid}` | `DELETE /api/rows/{rid}` |
| Doc | `PUT .../rows/{rid}/doc` | `GET .../rows/{rid}/doc` | same as create | — |

## Key Conventions

- Column list comes from `table.columns` (JSONB array), not a separate endpoint
- Row data field is `row_data` (not `data`)
- Row PK is `row_id` (not `id`)
- Workspace ID format: `{user_id}/{workspace_name}` (e.g. `claude/MyProject`)

## Query Tickets

Find PM table matching repo name, list tickets sorted newest first:

```bash
REPO_NAME="$(basename $(git rev-parse --show-toplevel 2>/dev/null || pwd))"
curl -s http://localhost:13491/api/tables -H "Authorization: Bearer claude" | \
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
    f'http://localhost:13491/api/tables/{tid}/rows?offset=0&limit=20',
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

## Update Ticket Status

Statuses: `todo`, `in_progress`, `testing`, `debugging`, `review`, `merged`

```bash
REPO_NAME="$(basename $(git rev-parse --show-toplevel 2>/dev/null || pwd))"
python3 -c "
import json, urllib.request
tables = json.loads(urllib.request.urlopen(urllib.request.Request(
    'http://localhost:13491/api/tables',
    headers={'Authorization': 'Bearer claude'}
)).read())
table = next((t for t in tables if t['name'].lower() == '${REPO_NAME}'.lower()), None)
if not table: exit()
tid = table['table_id']
cols = {c['name']: c['column_id'] for c in table.get('columns',[])}
status_id, key_id = cols.get('Status',''), cols.get('Key','')
if not status_id or not key_id: exit()
rows = json.loads(urllib.request.urlopen(urllib.request.Request(
    f'http://localhost:13491/api/tables/{tid}/rows?offset=0&limit=200',
    headers={'Authorization': 'Bearer claude'}
)).read())
row = next((r for r in rows if r['row_data'].get(key_id) == '<TICKET_KEY>'), None)
if not row: print('Ticket not found'); exit()
new_data = {**row['row_data'], status_id: '<NEW_STATUS>'}
req = urllib.request.Request(
    f'http://localhost:13491/api/rows/{row[\"row_id\"]}',
    data=json.dumps({'row_data': new_data}).encode(),
    headers={'Authorization': 'Bearer claude', 'Content-Type': 'application/json'},
    method='PUT'
)
urllib.request.urlopen(req)
print(f'<TICKET_KEY> → <NEW_STATUS>')
"
```

## Create Ticket

```bash
TABLE_ID="<table_id>"
curl -s -X POST "http://localhost:13491/api/tables/${TABLE_ID}/rows" \
  -H "Authorization: Bearer claude" \
  -H "Content-Type: application/json" \
  -d '{"row_data": {"<title_col_id>": "<title>", "<type_col_id>": "task", "<status_col_id>": "todo", "<priority_col_id>": "medium"}}'
```

## Auto-Cascade: Parent Status from Children

When a task/bug is marked `merged`, check if all siblings under the same parent are also `merged`. If yes, auto-update the parent (story) to `merged`.

```bash
python3 -c "
import json, urllib.request

TABLE_ID = '<table_id>'
AUTH = {'Authorization': 'Bearer claude'}

rows = json.loads(urllib.request.urlopen(urllib.request.Request(
    f'http://localhost:13491/api/tables/{TABLE_ID}/rows?offset=0&limit=200',
    headers=AUTH
)).read())

table = json.loads(urllib.request.urlopen(urllib.request.Request(
    f'http://localhost:13491/api/tables/{TABLE_ID}',
    headers=AUTH
)).read())
cols = {c['name']: c['column_id'] for c in table.get('columns',[])}
status_id = cols.get('Status','')
parent_id = cols.get('Parent','')
if not status_id or not parent_id: exit()

by_id = {r['row_id']: r for r in rows}
children_of = {}
for r in rows:
    pid = r['row_data'].get(parent_id)
    if pid:
        children_of.setdefault(pid, []).append(r)

for pid, kids in children_of.items():
    if pid not in by_id: continue
    parent = by_id[pid]
    if parent['row_data'].get(status_id) == 'merged': continue
    if all(k['row_data'].get(status_id) == 'merged' for k in kids):
        new_data = {**parent['row_data'], status_id: 'merged'}
        req = urllib.request.Request(
            f'http://localhost:13491/api/rows/{pid}',
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

Each ticket's detailed notes/spec live in MinIO:

```
{user_id}/{workspace_id}/{table_id}/{row_id}.md
```

Access via:
- `GET /api/tables/{table_id}/rows/{row_id}/doc` — read doc
- `PUT /api/tables/{table_id}/rows/{row_id}/doc` — save doc (text/plain body)
