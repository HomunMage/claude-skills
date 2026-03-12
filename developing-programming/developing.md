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

## Step 4: Commit

```bash
# Stage everything EXCEPT .tmp/
git add -A
git reset HEAD .tmp/ 2>/dev/null || true

git commit -m "<short description of what was done>"
```

**Important:** Never commit `.tmp/` — it must be in `.gitignore` and excluded from staging. The `.tmp/` directory is for scratch work, build artifacts, and intermediate outputs only.
