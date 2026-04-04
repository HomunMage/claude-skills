---
name: developing-svelte
description: Svelte/SvelteKit development — enforce pure TS logic in src/lib/, .svelte files handle UI/UX only. Use when writing Svelte components or SvelteKit routes.
version: 0.2.0
---

# Svelte Architecture: Logic/UI Separation

**Pure TS in `src/lib/`. Svelte handles UI/UX only.**

## Core Rule

```
src/lib/           → Pure TypeScript (logic, state, types, utils)
src/routes/        → .svelte files (UI/UX, layout, routing)
src/lib/components/ → .svelte files (reusable UI components)
```

## src/lib/ — Pure TypeScript Layer

- **State** → `src/lib/stores/` — Svelte stores or runes as `.ts` files
- **Types** → `src/lib/types/` — interfaces, type guards, Zod schemas
- **Utils** → `src/lib/utils/` — pure functions, helpers, transformations
- **API** → `src/lib/api/` or `src/lib/server/` — data fetching, server logic
- **Constants** → `src/lib/constants/` — config, enums, magic values

Rules:
- No Svelte imports in `.ts` files (except `svelte/store` or `$state` runes)
- All business logic must be testable without Svelte runtime
- Export clean interfaces — components consume, never define logic

## .svelte Files — UI/UX Only

Allowed:
- Template markup, styling, transitions, animations
- Import and bind to stores/runes from `src/lib/`
- Event handling that delegates to imported logic
- Component composition and slot/snippet patterns
- `+page.ts` / `+page.server.ts` load functions (these are TS, not .svelte)

Forbidden:
- Business logic, data transformation, validation inside `<script>`
- Direct API calls — use `src/lib/api/` or `+page.server.ts`
- Complex computed values — extract to `src/lib/` as derived store or function

## Pattern: Component + Logic Pair

```
src/lib/stores/counter.ts    → export const count = writable(0)
                               export function increment() { count.update(n => n + 1) }

src/lib/components/Counter.svelte → <script>
                                      import { count, increment } from '$lib/stores/counter'
                                    </script>
                                    <button onclick={increment}>{$count}</button>
```

## Robot Awareness (Playwright-friendly)

All interactive/stateful elements MUST have `data-testid` for Playwright snapshot and automation.

```svelte
<!-- BAD: no way for Playwright to reliably target -->
<button onclick={submit}>Save</button>
<div>{status}</div>

<!-- GOOD: robot-friendly -->
<button data-testid="save-btn" onclick={submit}>Save</button>
<div data-testid="status-msg">{status}</div>
```

Rules:
- `data-testid` on every: button, link, input, form, modal, toast, dynamic text
- Naming: `{component}-{element}` — e.g. `login-email-input`, `cart-checkout-btn`
- Lists: `data-testid="item-{id}"` on each row for individual targeting
- States: reflect state in DOM — `aria-busy`, `aria-disabled`, `data-status` — so Playwright can `waitForSelector('[data-status="loaded"]')`

**Why:** Playwright snapshots and clicks rely on stable selectors. CSS classes change, text changes with i18n. `data-testid` is the contract between UI and automation.

## When Writing Code

1. **New feature?** Start with `.ts` in `src/lib/` — types first, then logic
2. **Need UI?** Create `.svelte` that imports from `src/lib/`
3. **Refactoring?** Extract any logic from `<script>` blocks into `src/lib/`
4. **Testing?** Logic tests = pure TS (vitest). UI tests = Playwright snapshot (see below)

## MUST: Verify with .browser Snapshot

**Every FE change MUST be verified with a Playwright screenshot before committing.** No exceptions. If you can't see it, it's not done.

```bash
# Start browser
docker compose --profile browser up -d browser

# Snapshot the page you changed
docker compose exec browser python3 -c "
from playwright.sync_api import sync_playwright
# ... intercept localhost:13491 → lattice-cast:13491 ...
# ... inject auth localStorage ...
page.goto('http://lattice-cast:13491/<your-page>')
page.wait_for_timeout(3000)
page.screenshot(path='/output/<feature_name>.png')
"

# View result
ls .browser/<feature_name>.png
```

**Why:** The typography bug (missing `@tailwindcss/typography`) shipped because nobody looked at the rendered output. A 3-second snapshot would have caught it instantly.

Rules:
- After **any** visual change (CSS, layout, component, view), take a snapshot
- Compare before/after if refactoring styling
- Include snapshot path in commit message or ticket doc
- If the snapshot looks wrong, fix before committing

## $lib Alias

Always use `$lib/` imports in .svelte and route files — never relative paths to src/lib/.
