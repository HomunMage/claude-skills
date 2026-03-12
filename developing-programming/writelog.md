# Write Log — Version & Changelog

When the user specifies a version (e.g., "v1.5", "bump to v2.0"), perform these steps:

## Step 1: Write CHANGELOG.md

Append or update `CHANGELOG.md` at the project root:

```markdown
## vX.Y — YYYY-MM-DD
- Short bullet of what changed
- Another change
```

Rules:
- Use **vMajor.Minor** format only (e.g., `v1.0`, `v1.1`, `v2.0`) — no patch level
- Versions may jump (e.g., `v1.1` → `v1.5` or `v1.1` → `v3.0`)
- Each entry: version, date, and bullet list of what changed
- Keep entries concise — not every detail, just the highlights
- Newest version goes at the top

## Step 2: Update Package Version

Auto-detect and update version in the appropriate file(s):

| File | Field | Example |
|------|-------|---------|
| `package.json` | `"version": "X.Y.0"` | `"version": "1.5.0"` |
| `pyproject.toml` | `version = "X.Y.0"` | `version = "1.5.0"` |
| `setup.py` | `version="X.Y.0"` | `version="1.5.0"` |
| `Cargo.toml` | `version = "X.Y.0"` | `version = "1.5.0"` |
| `setup.cfg` | `version = X.Y.0` | `version = 1.5.0` |

- If multiple version files exist, update all of them
- Use `X.Y.0` format in package files (append `.0` patch for compatibility)
- If no version file is found, only update CHANGELOG.md

## Step 3: Commit

```bash
git add CHANGELOG.md
# Also stage any updated version files
git add package.json pyproject.toml Cargo.toml setup.py setup.cfg 2>/dev/null || true

git commit -m "v<version>"
```
