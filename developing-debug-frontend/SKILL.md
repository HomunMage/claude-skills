---
name: developing-debug-frontend
description: Frontend debugging with Playwright in Docker — screenshot, click, inspect pages. Use when debugging frontend UI, testing web pages, or checking visual state.
allowed-tools: Read, Bash, Grep
---

# Frontend Debug — Playwright in Docker

Debug frontend UI via headless Playwright browser running in Docker. Screenshots output to `./.browser/`.

## Prerequisites

Add browser service to project's `docker-compose.yml` — see [examples/docker-compose.browser.yml](examples/docker-compose.browser.yml).

Copy `browse.py` into project's `./browser/` directory — see [examples/browse.py](examples/browse.py).

## Setup

```bash
# Start browser container
docker compose --profile browser up -d browser

# Verify it's running
docker compose ps browser
```

## Commands

All commands output JSON. Screenshots saved to `./.browser/` (mounted volume).

```bash
# Page status — title, URL, element counts, errors, text preview
docker compose exec browser python browse.py status [URL]

# Screenshot — full page capture
docker compose exec browser python browse.py screenshot [name]

# Click element — by text, data-testid, aria-label, or CSS selector
docker compose exec browser python browse.py click "Button Text"

# List menu items — opens menu, lists options
docker compose exec browser python browse.py menu

# List all visible buttons
docker compose exec browser python browse.py buttons
```

## Debug Workflow

1. **Check status** — `browse.py status` → see if page loads, check for errors
2. **Screenshot** — `browse.py screenshot before_fix` → capture current state
3. **Make code changes** — fix the issue
4. **Screenshot again** — `browse.py screenshot after_fix` → verify fix
5. **Read screenshots** — use `Read` tool on `.browser/*.png` to view

## Customizing BASE_URL

Edit `BASE_URL` in `browse.py` to match your dev server:

```python
BASE_URL = "http://host.docker.internal:5173"  # Vite dev server
BASE_URL = "http://host.docker.internal:3000"  # Next.js dev server
BASE_URL = "https://your-site.com"              # Production
```

For Docker-to-Docker networking, use the service name instead:
```python
BASE_URL = "http://app:5173"  # If app is on same Docker network
```

## Output Location

- Screenshots: `./.browser/*.png` (project-local, gitignored)
- All command output: JSON to stdout
- Read screenshots with `Read` tool — Claude can view images

## Examples

| File | Purpose |
|------|---------|
| [docker-compose.browser.yml](examples/docker-compose.browser.yml) | Browser service config — add to project's docker-compose |
| [Dockerfile](examples/Dockerfile) | Playwright container build |
| [browse.py](examples/browse.py) | Browser automation script — copy to `./browser/` |
