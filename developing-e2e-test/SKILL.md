---
name: developing-e2e-test
description: End-to-end tests for LatticeCast — Playwright drives the real browser, every step verifies DB state directly, optional per-step snapshot.
user-invocable: false
version: 0.9.0
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

## One topic per file

**Each test file covers exactly ONE topic.** A "topic" is one
user-visible behavior that fails or passes as a unit (e.g. *kanban
group_by persists across navigation*). When the file grows past one
topic, split it. Naming makes the scope explicit:

| Prefix | Scope | Examples |
|---|---|---|
| `e2e_test_<feature>.py` | High-level smoke / cross-cutting flow | `e2e_test_auth.py`, `e2e_test_seo_framework.py` |
| `e2e_test_views_<topic>.py` | Behavior that applies to **all** view types | `e2e_test_views_order.py` (drag-reorder tabs), `e2e_test_views_default.py` (last-clicked sticks), `e2e_test_views_rename.py` |
| `e2e_test_view_<type>_<topic>.py` | Behavior of **one** view type | `e2e_test_view_kanban_groupby.py`, `e2e_test_view_table_col_order.py`, `e2e_test_view_timeline_drag_resize.py` |
| `e2e_test_column_<topic>.py` | Column-level, propagates across views | `e2e_test_column_option_colors.py`, `e2e_test_column_rename.py` |

Cross-view tests (`e2e_test_views_*`) MUST exercise the topic on at
least two different view types to prove the persistence is not
view-type-specific. Per-view tests (`e2e_test_view_<type>_*`) MUST
also assert a *negative* case where switching to another view (or
another table and back) preserves the configured state.

Each file:
- One scenario, top-to-bottom imperative script.
- API verify + UI assert on every step (three pillars).
- < 300 lines. If you're past that, split or factor a helper.
- Idempotent setup using `bootstrap.py` or its own setup block.

## Layout

```
test-e2e/
├── Dockerfile               # FROM astral-sh/uv; deps from pyproject
├── pyproject.toml           # playwright + requests, NO browsers
├── bootstrap.py             # PG INSERT admin + BE create user, idempotent
├── e2e_helper.py            # E2E ctx: page + paired UI/API asserts
├── snapshot_decorator.py    # @snapshot opt-in per-step screenshot
└── e2e_test_<scope>_<topic>.py  # ONE topic per file (see table above)
```

Run:

```bash
# Bring both containers up:
docker compose --profile test up -d browser test-e2e

# Execute one test file (or all):
docker compose exec test-e2e python3 /scripts/e2e_test_<feature>.py [--snapshot]
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

## CRITICAL: Tests describe intended behavior — FIX SOURCE, never workaround in test

The test file encodes the **intended behavior** of the product. If a
test fails, **the source code is wrong, not the test.** Fix the FE/BE,
do NOT mutate the test to match buggy behavior.

This is non-negotiable. A test that's been twisted to make a buggy app
green is worse than no test — it lies about what the product does and
guarantees the bug ships.

### Banned "workaround" patterns

Every one of these is a red flag that you're papering over a real bug:

| Pattern | What it usually hides | What to do instead |
|---|---|---|
| `page.wait_for_timeout(N)` | slow / unobservable state change | `page.expect_response("**/api/...")`; or add a `data-status` attr in FE and `wait_for_selector('[data-status="ready"]')` |
| `time.sleep(N)` | same | same |
| `try: ... except: pass` (around an assert) | flaky FE / missing testid | fix the FE; never swallow |
| `if elem.is_visible(): ...` (conditional assert) | the test doesn't actually require it → DELETE it. Otherwise it's a real bug → fix FE | one or the other, never "maybe" |
| Changing a `[data-testid="X"]` selector to a text-/CSS-based one because the testid is missing | FE forgot the testid | **add the missing testid to the FE component** |
| Adding `wait_until="networkidle"` AND a follow-up `wait_for_timeout` | hydration race | wait for a real signal (testid, response) |
| `pytest.skip` / `# TODO` / `# brittle` / `# flaky` | unfixed bug being hidden | open a bug ticket and fix it; do not skip |

`@snapshot` decorator failures and the screenshot helper itself are
the **only** legitimate uses of `except: pass` — and only around the
screenshot call, never around an assert.

### When the test reveals a real bug

1. Run the test, see it fail.
2. Read the failure. If the source is wrong (missing testid, broken
   route, wrong response shape, slow PATCH with no observable signal),
   **edit the FE/BE source** to fix it.
3. Re-run the test. If it now passes against the fixed source, commit
   the FE/BE fix *and* the test together — that's one merged behavior.
4. If you genuinely can't fix the source in this ticket (e.g. cross-team
   change), **fail the test loudly**, append the failure to the ticket
   doc with the proposed source fix, and stop. Do **not** twist the
   test.

### Things you ARE allowed to touch

When working on an e2e test ticket, "scope" includes:
- `frontend/src/**` — add missing `data-testid`, fix wrong selectors,
  expose state in DOM, fix broken hydration.
- `backend/src/**` — fix wrong response shape, add missing endpoints,
  fix race conditions exposed by the test.
- `migration/V*.sql` (forward-only) — only if the source-of-truth
  schema is wrong; coordinate via skill `developing-db-sql`.

The ticket title is `e2e_test_*` but the *scope* is the whole behavior
the test exercises. Test files are read-only mirrors of intent.
