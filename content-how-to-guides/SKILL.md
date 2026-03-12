---
name: content-how-to-guides
description: Create step-by-step tutorial guides with Playwright screenshots and Jekyll markdown output.
---

# How-to Guides

Create step-by-step tutorial guides with screenshots, using a Playwright browser container to capture each step.

## Infrastructure

### Docker Setup
```bash
# Start browser container
docker compose --profile browser up -d

# Execute browse script
docker compose --profile browser exec browser python browse.py <url> --steps steps.json

# Stop
docker compose --profile browser down
```

- [docker-compose.yml](docker-compose.yml) — browser service definition
- [browser/Dockerfile](browser/Dockerfile) — Playwright Python environment
- [browser/browse.py](browser/browse.py) — browse + screenshot automation

### Screenshot Conversion
Convert PNG screenshots to WebP for Jekyll embedding:
```bash
ffmpeg -i input.png input.webp
```

## Workflow

1. **Define steps** — create a `steps.json` describing the user journey:
   ```json
   [
     {"action": "screenshot", "name": "01-landing"},
     {"action": "click", "selector": "#signup-btn", "name": "02-click-signup"},
     {"action": "fill", "selector": "#email", "value": "user@example.com", "name": "03-fill-email"},
     {"action": "wait", "ms": 2000, "name": "04-loading"},
     {"action": "scroll", "y": 500, "name": "05-scrolled"}
   ]
   ```

2. **Run browse.py** — outputs `.png` files to `.browser/` volume mount

3. **Convert to WebP** — `ffmpeg -i .browser/01-landing.png 01-landing.webp`

4. **Write guide in Jekyll markdown** — use HTML img tags to embed:
   ```markdown
   ---
   title: "How to Do X"
   layout: "page/note/slides"
   ---

   ## Step 1: Open the landing page

   Navigate to the site.

   <img src="./01-landing.webp" width="500">

   ## Step 2: Click Sign Up

   Click the sign up button in the top right.

   <img src="./02-click-signup.webp" width="500">
   ```

## Steps JSON Actions

| Action | Required Fields | Description |
|--------|----------------|-------------|
| `screenshot` | `name` | Take screenshot only |
| `click` | `selector`, `name` | Click element, wait for load, screenshot |
| `fill` | `selector`, `value`, `name` | Fill input field, screenshot |
| `wait` | `name`, `ms` (optional, default 1000) | Wait then screenshot |
| `scroll` | `name`, `y` (optional, default 500) | Scroll down Y pixels, screenshot |

## Output Format

- Layout: `page/note/slides` — each `## h2` = one slide/step
- Images: always `<img src="./filename.webp" width="500">` (never markdown `![]()`)
- Keep each step focused: one action per slide, brief description above the screenshot
- Number steps sequentially in filenames: `01-`, `02-`, etc.
