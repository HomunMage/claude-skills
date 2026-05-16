---
name: developing-e2e-test
description: End-to-end tests for LatticeCast — Playwright drives the real browser, every step verifies DB state directly, optional per-step snapshot.
user-invocable: false
version: 0.7.0
---

# E2E Testing — Playwright + BE/DB Verification

## Three pillars

| Pillar | Catches |
|---|---|
| **Playwright UI** | DOM / routing / hydration bugs |
| **BE API read (or direct DB)** | BE silently dropped writes |
| **Step snapshots** (opt-in) | visual regressions |

## Two-container architecture

```
┌─────────────────────────────┐     ws://browser:4444     ┌─────────────────────┐
│ test-e2e                    │ ────────────────────────▶ │ browser             │
│ uv image                    │   (Playwright client/srv) │ playwright/python   │
│ playwright + requests       │                           │ run-server :4444    │
│ runs your test scripts      │                           │ Chromium + browsers │
└─────────────────────────────┘                           └─────────────────────┘
            │                                                       │
            │ requests → BE API (DB content via /api/v1/...)         │
            ▼                                                       │
       lattice-cast (nginx)                                          │
                                                                     │
                                       page.screenshot(path=…) writes
                                       on the SERVER side, into /output
                                       (mounted as ./.browser/)
```

- **test-e2e** runs the test scripts. uv image, no Chromium, just the
  Playwright Python lib + requests. Connects to the browser container
  by setting `BROWSER_WS=ws://browser:4444` and calling
  `pw.chromium.connect(BROWSER_WS)`.
- **browser** owns Chromium. Boots `playwright run-server --port 4444`
  and idles. Only mounts `./.browser:/output` so server-side screenshots
  land on the host.
- Tests live in `./test-e2e/`, bind-mounted at `/scripts` in test-e2e.

## Layout

```
test-e2e/
├── Dockerfile               # FROM astral-sh/uv; deps from pyproject
├── pyproject.toml           # playwright + requests, NO browsers
├── bootstrap.py             # PG INSERT admin + BE create user, idempotent
├── e2e_helper.py            # E2E ctx: page + paired UI/API asserts
├── snapshot_decorator.py    # @snapshot opt-in per-step screenshot
└── test_e2e_<feature>.py    # your tests
```

Run:

```bash
# Bring both containers up:
docker compose --profile test up -d browser test-e2e

# Execute one test file (or all):
docker compose exec test-e2e python3 /scripts/test_e2e_<feature>.py [--snapshot]
```

**Connecting to the remote browser** — every test starts with:

```python
import os
from playwright.sync_api import sync_playwright

with sync_playwright() as pw:
    browser = pw.chromium.connect(os.environ["BROWSER_WS"])
    page = browser.new_page(viewport={"width": 1400, "height": 900})
    page.goto(f"{os.environ['BASE_URL']}/login")
    # … UI action + API verify + UI assert per the three pillars
    browser.close()
```

**Debugging a failure**: each test file is one scenario. Re-run that
single file with `--snapshot` — every decorated step writes a screenshot
to `.browser/<step_name>.png` (Playwright server writes them through
the WS, lands on host via the browser container's `/output` mount),
including the failing step (decorator uses try/finally), so you see
the full progression up to the break.

## Reference code

- [example-scripts/e2e_helper.py](example-scripts/e2e_helper.py) — `E2E` context: `page`, `db`, paired DB / UI asserts.
- [example-scripts/snapshot_decorator.py](example-scripts/snapshot_decorator.py) — `@snapshot` opt-in screenshot per step.

## Sub-files (lazy)

- [setup.md](setup.md) — bootstrap test users (PG + BE) before Playwright.
- [flow_template.md](flow_template.md) — canonical test sequence.

## Rules

1. Every UI mutation → DB check. UI "saved" ≠ DB has it.
2. Every DB mutation → UI check. DB row ≠ UI rendered it.
3. No `sleep()`. Use Playwright `wait_for_*`.
4. No conditional skipping. Failures must be loud.
5. Idempotent setup. Re-runs produce same result.
6. `@snapshot` opt-in. Default off (CI stays fast).
