# Developing — Full Workflow

## PM Integration

All PM operations use `Skill(developing-project-management)`:
- **Query tickets** → "Query Tickets" section
- **Update status** → "Update Ticket Status" section
- **Status flow**: `todo → in_progress → testing → debugging → review → merged`

## Work Log Helper

Append a log entry to the ticket's MinIO doc at each phase. Replace `<TABLE_ID>` and `<ROW_ID>` with the values from your task context.

```bash
# Append a work log entry to the ticket doc
_log_step() {
  local TABLE_ID="<TABLE_ID>"
  local ROW_ID="<ROW_ID>"
  local MSG="$1"
  local CURRENT
  CURRENT=$(curl -s "http://localhost:13491/api/tables/${TABLE_ID}/rows/${ROW_ID}/doc" \
    -H "Authorization: Bearer claude")
  local ENTRY="- $(date -u +"%Y-%m-%dT%H:%M:%SZ") ${MSG}"
  if echo "$CURRENT" | grep -q "^## Work Log"; then
    local UPDATED="${CURRENT}"$'\n'"${ENTRY}"
  else
    local UPDATED="${CURRENT}"$'\n\n'"## Work Log"$'\n'"${ENTRY}"
  fi
  curl -s -X PUT "http://localhost:13491/api/tables/${TABLE_ID}/rows/${ROW_ID}/doc" \
    -H "Authorization: Bearer claude" \
    -H "Content-Type: text/plain" \
    --data-raw "$UPDATED" > /dev/null
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

### PM status
Use `Skill(developing-project-management)` — "Query Tickets" to show current tickets sorted newest first.

Report the branch, uncommitted changes, and ticket status to the user before starting work.

## Step 1: Pick Ticket & Create Branch → status: `in_progress`

```bash
TICKET_KEY="<ticket_key>"  # e.g. SA-3
SLUG="feat/${TICKET_KEY}/$(echo '<short-description>' | tr ' ' '-')"
git checkout -b "$SLUG" main
```

Update PM: `update_ticket <TICKET_KEY> in_progress`

Append to ticket doc:
```bash
_log_step "Started implementation on branch ${SLUG}"
```

## Step 2: Implement

Write the code. Stay in scope — one ticket only.

After completing implementation, append to ticket doc:
```bash
_log_step "Implementation complete"
```

## Step 2.5: If test ticket → run Playwright snapshot instead

If the ticket has tag `test`, skip normal implementation. Instead:
1. Write a Playwright test script in `browser/` (e.g. `browser/test_{feature}.py`)
2. Run via `docker compose exec browser python3 browser/test_{feature}.py`
3. Save screenshots to `.browser/`
4. Append screenshot paths + pass/fail to ticket doc
5. Skip to Step 5 (commit)

## Step 3: Test → status: `testing`

Update PM: `update_ticket <TICKET_KEY> testing`

Append to ticket doc:
```bash
_log_step "Running tests"
```

Auto-detect and run tests:
- `package.json` → `npm test`
- `Cargo.toml` → `cargo test`
- `pyproject.toml` or `setup.py` → `pytest`
- `go.mod` → `go test ./...`
- `Makefile` with test target → `make test`

If tests **fail** → `update_ticket <TICKET_KEY> debugging`, fix, re-test.

```bash
_log_step "Tests failed — debugging"
```

All tests MUST pass before proceeding.

```bash
_log_step "All tests passed"
```

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
```

Update PM: `update_ticket <TICKET_KEY> review`

Append to ticket doc:
```bash
COMMIT_SHA=$(git rev-parse --short HEAD)
_log_step "Committed ${COMMIT_SHA} — in review"
```

## Step 6: Merge → status: `merged`

```bash
git checkout main
git merge "$SLUG"
git branch -d "$SLUG"
```

Update PM: `update_ticket <TICKET_KEY> merged`

If using worktrees:
```bash
git worktree remove <worktree-path> 2>/dev/null || true
```

**Important:** Never commit `.tmp/` — it must be in `.gitignore` and excluded from staging.
