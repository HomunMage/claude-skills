# Developing — Post-Code Workflow

After code changes are made, run this workflow before committing.

## Step 1: Auto-Detect & Run Tests

Detect project type and run tests:
- `package.json` → `npm test`
- `Cargo.toml` → `cargo test`
- `pyproject.toml` or `setup.py` → `pytest`
- `go.mod` → `go test ./...`
- `Makefile` with test target → `make test`

All tests MUST pass before proceeding.

## Step 2: Format

Auto-detect and run formatters:
- JS/TS → `npx prettier --write .`
- Rust → `cargo fmt`
- Python → `ruff format .`
- Go → `gofmt -w .`

## Step 3: Lint

Auto-detect and run linters:
- JS/TS → `npx eslint --fix .`
- Rust → `cargo clippy -- -D warnings`
- Python → `ruff check --fix .`
- Go → `golangci-lint run`

## Step 4: Branch (worktree) → Commit → Merge

**Never work directly on main.** Use a git worktree branch, then merge back.

```bash
# If already in a worktree branch (not main), just commit:
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
  git add -A
  git reset HEAD .tmp/ 2>/dev/null || true
  git commit -m "<short description>"
else
  # On main — create worktree branch first
  SLUG="feat/$(echo '<short-ticket-slug>' | tr ' ' '-')"
  git worktree add .tmp/wt-$$ -b "$SLUG" main
  # Copy changed files to worktree, commit there
  cd .tmp/wt-$$
  # ... make changes or cherry-pick ...
  git add -A
  git reset HEAD .tmp/ 2>/dev/null || true
  git commit -m "<short description>"
  # Merge back to main
  cd -
  git merge "$SLUG"
  git worktree remove .tmp/wt-$$
  git branch -d "$SLUG"
fi
```

### Merge back to main

After committing on a branch, merge back:
```bash
cd <project-root>
git checkout main
git merge <branch-name>
git worktree remove <worktree-path> 2>/dev/null || true
git branch -d <branch-name>
```

**Important:** Never commit `.tmp/` — it must be in `.gitignore` and excluded from staging.
