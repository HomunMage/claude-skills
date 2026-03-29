# Developing — Full Workflow

## PM Integration

All PM operations use `Skill(developing-project-management)`:
- **Query tickets** → "Query Tickets" section
- **Update status** → "Update Ticket Status" section
- **Status flow**: `todo → in_progress → testing → debugging → review → merged`

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

## Step 2: Implement

Write the code. Stay in scope — one ticket only.

## Step 3: Test → status: `testing`

Update PM: `update_ticket <TICKET_KEY> testing`

Auto-detect and run tests:
- `package.json` → `npm test`
- `Cargo.toml` → `cargo test`
- `pyproject.toml` or `setup.py` → `pytest`
- `go.mod` → `go test ./...`
- `Makefile` with test target → `make test`

If tests **fail** → `update_ticket <TICKET_KEY> debugging`, fix, re-test.

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
```

Update PM: `update_ticket <TICKET_KEY> review`

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
