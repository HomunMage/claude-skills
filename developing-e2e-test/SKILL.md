---
name: developing-e2e-test
description: End-to-end tests for LatticeCast — Playwright drives the real browser, every step verifies DB state directly, optional per-step snapshot.
user-invocable: false
version: 0.6.0
---

# E2E Testing — Playwright + DB Verification

## Three pillars

| Pillar | Catches |
|---|---|
| **Playwright UI** | DOM / routing / hydration bugs |
| **Direct DB read** | BE silently dropped writes |
| **Step snapshots** (opt-in) | visual regressions |

## Layout

```
browser/
├── e2e_helper.py            # copy from example-scripts/
├── snapshot_decorator.py    # copy from example-scripts/
└── test_e2e_<feature>.py    # your tests
```

Bind-mounted to `/scripts/` in the `browser` container.

```bash
docker compose exec browser python3 /scripts/test_e2e_<feature>.py [--snapshot]
```

**Debugging a failure**: each test file is one scenario. Re-run that
single file with `--snapshot` — every decorated step writes a screenshot
to `.browser/<step_name>.png`, including the failing step (decorator
uses try/finally), so you see the full progression up to the break.

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
