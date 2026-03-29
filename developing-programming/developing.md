# Developing — Full Workflow

## PM Ticket Status Helper

Throughout the workflow, update the ticket status in LatticeCast. Use this helper:

```bash
# Usage: update_ticket_status <ticket_key> <new_status>
# Statuses: todo, in_progress, testing, debugging, review, done, merged
update_ticket_status() {
  local KEY="$1" NEW_STATUS="$2"
  curl -s http://localhost:5000/api/status 2>/dev/null | grep -q '"ok"' || return 0
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
row = next((r for r in rows if r['row_data'].get(key_id) == '${KEY}'), None)
if not row: exit()
new_data = {**row['row_data'], status_id: '${NEW_STATUS}'}
req = urllib.request.Request(
    f'http://localhost:5000/api/rows/{row[\"row_id\"]}',
    data=json.dumps({'row_data': new_data}).encode(),
    headers={'Authorization': 'Bearer claude', 'Content-Type': 'application/json'},
    method='PUT'
)
urllib.request.urlopen(req)
print(f'  PM: ${KEY} → ${NEW_STATUS}')
" 2>/dev/null || true
}
```

## Step 0: Pre-flight — Git & PM Status

Before writing any code, check current state:

### Git status
```bash
git fetch --all 2>/dev/null
git branch --show-current
git status --short
git log --oneline -5
git worktree list
```

### LatticeCast PM status (if running)
```bash
STATUS=$(curl -s http://localhost:5000/api/status 2>/dev/null)
if echo "$STATUS" | grep -q '"ok"'; then
  echo "PM: connected"
  REPO_NAME="$(basename $(git rev-parse --show-toplevel 2>/dev/null || pwd))"
  curl -s http://localhost:5000/api/tables \
    -H "Authorization: Bearer claude" 2>/dev/null | \
    python3 -c "
import sys, json, urllib.request

tables = json.load(sys.stdin)
repo = '${REPO_NAME}'
table = next((t for t in tables if t['name'].lower() == repo.lower()), None)
if not table:
    print(f'  No PM table found for \"{repo}\"')
    sys.exit(0)

tid = table['table_id']
print(f'  Project: {table[\"name\"]} ({tid[:8]}...)')
print(f'  URL: http://localhost:3000/claude/{tid}')

req = urllib.request.Request(
    f'http://localhost:5000/api/tables/{tid}/rows?offset=0&limit=20',
    headers={'Authorization': 'Bearer claude'}
)
rows = json.loads(urllib.request.urlopen(req).read())
rows.sort(key=lambda r: r.get('updated_at',''), reverse=True)

cols = {c['name']: c['column_id'] for c in table.get('columns', [])}
key_id = cols.get('Key','')
title_id = cols.get('Title','')
status_id = cols.get('Status','')
prio_id = cols.get('Priority','')
type_id = cols.get('Type','')

print(f'  Tickets ({len(rows)}):')
for r in rows:
    d = r.get('row_data', {})
    key = d.get(key_id, '?')
    title = d.get(title_id, '(untitled)')
    status = d.get(status_id, '-')
    prio = d.get(prio_id, '-')
    typ = d.get(type_id, '-')
    print(f'    {key:8s} [{status:12s}] {prio:8s} {typ:5s}  {title}')
" 2>/dev/null || true
else
  echo "PM: not running (skip)"
fi
```

Report the branch, uncommitted changes, and PM ticket status to the user before starting work.

## Step 1: Pick Ticket & Create Branch → status: `in_progress`

When starting a new ticket:

```bash
# Create branch from ticket key: feat/SA-3/oauth-login-flow
TICKET_KEY="<ticket_key>"  # e.g. SA-3
SLUG="feat/${TICKET_KEY}/$(echo '<short-description>' | tr ' ' '-')"
git checkout -b "$SLUG" main
```

Update PM status:
```bash
update_ticket_status "$TICKET_KEY" "in_progress"
```

## Step 2: Implement

Write the code. Stay in scope — one ticket only.

## Step 3: Test → status: `testing`

Update PM status before running tests:
```bash
update_ticket_status "$TICKET_KEY" "testing"
```

Auto-detect and run tests:
- `package.json` → `npm test`
- `Cargo.toml` → `cargo test`
- `pyproject.toml` or `setup.py` → `pytest`
- `go.mod` → `go test ./...`
- `Makefile` with test target → `make test`

If tests **fail** → status: `debugging`
```bash
update_ticket_status "$TICKET_KEY" "debugging"
# Fix the issue, then re-run tests
# When tests pass, continue to Step 4
```

All tests MUST pass before proceeding.

## Step 4: Format & Lint

Auto-detect and run formatters:
- JS/TS → `npx prettier --write .`
- Rust → `cargo fmt`
- Python → `ruff format .`
- Go → `gofmt -w .`

Auto-detect and run linters:
- JS/TS → `npx eslint --fix .`
- Rust → `cargo clippy -- -D warnings`
- Python → `ruff check --fix .`
- Go → `golangci-lint run`

## Step 5: Commit → status: `review`

```bash
git add -A
git reset HEAD .tmp/ 2>/dev/null || true
git commit -m "ticket: <short description>"

update_ticket_status "$TICKET_KEY" "review"
```

## Step 6: Merge → status: `merged`

Merge branch back to main (or dev):

```bash
git checkout main
git merge "$SLUG"
git branch -d "$SLUG"

update_ticket_status "$TICKET_KEY" "merged"
```

If using worktrees:
```bash
git worktree remove <worktree-path> 2>/dev/null || true
```

## Ticket Status Flow

```
todo → in_progress → testing → review → merged
                       ↓
                    debugging → testing (loop until pass)
```

| Status | Trigger |
|--------|---------|
| `todo` | Default on creation |
| `in_progress` | Branch created, coding started |
| `testing` | Running tests |
| `debugging` | Tests failed, fixing |
| `review` | Committed, ready for merge |
| `merged` | Branch merged to main/dev |

**Important:** Never commit `.tmp/` — it must be in `.gitignore` and excluded from staging.
