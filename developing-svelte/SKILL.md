---
name: developing-svelte
description: Svelte/SvelteKit development — enforce pure TS logic in src/lib/, .svelte files handle UI/UX only, stores as SSOT, render via $derived. Use when writing Svelte components or SvelteKit routes.
version: 0.7.0
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

## Stores as SSOT — Derive, Don't Effect

**`*.store.ts` files are the single source of truth. All rendering MUST be `$derived` from stores. Minimize `$effect` usage.**

### The Principle

```
URL ($page.params) → one $effect fetches data → writes to stores
stores (SSOT)      → $derived chains compute render data
template           → binds to $derived values, never reads $page.params directly
```

### Rules

1. **Stores hold the truth.** `currentWorkspaceId`, `currentTableId`, `columns`, `rows`, `views` — these are SSOT. Components derive from them, never from URL params or local state.

2. **One `$effect` per page for data loading.** Read `$page.params`, fetch data, write results to stores. That's the only legitimate use of `$effect` for data flow.

3. **Everything else is `$derived`.** Column order, filtered rows, grouped rows, render items, active view — all derived from store values. No effects to "sync" derived state.

4. **Template binds to derived/store values.** Use `const tableId = $derived($currentTableId ?? '')` in the script, then `{tableId}` in the template. Never `{$page.params.table_id}` in props.

5. **Mutations go through stores, not effects.** When a user action changes state, call a function that updates the store directly. Don't chain effects to propagate changes.

6. **Guard effects by view type.** Functions like `persistViewConfig` and `applyViewConfig` must early-return for non-applicable view types (e.g. dashboard/kanban). Unguarded effects cause cascading store resets.

7. **Sequential fetch when dependent.** If fetch B needs a result from fetch A (e.g. workspace UUID from `resolveWorkspaceParam` before `fetchTable`), await sequentially. `Promise.all` causes race conditions (422 errors).

### Bad vs Good

```svelte
<!-- BAD: effect chain syncing derived state -->
<script>
  let filtered = $state([]);
  $effect(() => { filtered = rows.filter(r => r.status === status); });
  $effect(() => { sorted = filtered.sort(...); });
</script>

<!-- GOOD: derived chain, no effects -->
<script>
  const filtered = $derived(rows.filter(r => r.status === status));
  const sorted = $derived(filtered.sort(...));
</script>
```

```svelte
<!-- BAD: reading $page.params in template -->
<Component tableId={$page.params.table_id} />

<!-- GOOD: derived from store -->
<script>
  const tableId = $derived($currentTableId ?? '');
</script>
<Component {tableId} />
```

```svelte
<!-- BAD: Promise.all when B depends on A -->
const [table] = await Promise.all([
  fetchTable(id, $page.params.workspace_id),  // workspace might be a name!
  fetchWorkspaces()
]);

<!-- GOOD: sequential, resolve first -->
const wsList = await fetchWorkspaces();
const wsId = resolveWorkspaceParam(wsParam, wsList);
const table = await fetchTable(id, wsId ?? undefined);
```

### URL Rewriting

- Use `history.replaceState` for cosmetic URL changes (UUID → workspace name).
- **NEVER** use SvelteKit's `replaceState` from `$app/navigation` for cosmetic rewrites — it updates `$page` store, which re-triggers `$effect` loops and causes the app to get stuck.
- Keep URL rewrite effects in `+layout.svelte` only — don't duplicate in each page.

**Why:** Effects create implicit dependencies and cascade unpredictably. Derived chains are explicit, synchronous, and debuggable. Fewer effects = fewer bugs + better performance.

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

## MUST: Verify with .browser Snapshot — INSPECT IT, DON'T JUST SAVE IT

**Every FE change MUST be verified with a Playwright screenshot before committing.** No exceptions. If you can't see it, it's not done.

But "took a snapshot" is not the same as "verified the render is right." A
saved PNG that you never opened proves nothing. The rule is:

1. Take the snapshot.
2. **OPEN it (Read tool on the .png) and visually inspect it.**
3. Confirm the layout, content, and styling are correct.
4. If anything looks off — clipped numbers, blocks crammed together,
   missing labels, blank space, wrong colors — fix before committing.

```bash
# Start browser
docker compose --profile browser up -d browser

# Use Skill(developing-debug-frontend) for Playwright snapshot
# or write inline:
docker compose exec browser python3 -c "
from playwright.sync_api import sync_playwright
# ... set up page, inject auth ...
page.goto('<your-page-url>')
page.wait_for_timeout(3000)
page.screenshot(path='/output/<feature_name>.png', full_page=True)
"

# View result — Read tool on the PNG, look at it
ls .browser/<feature_name>.png
```

**Why:** Typography bugs, broken grid layouts, and visual regressions
ship when nobody looks at the rendered output. A saved snapshot that's
never opened catches nothing. A 3-second look at the image catches the
class of bugs the type checker can never see.

Rules:
- After **any** visual change (CSS, layout, component, view), take AND
  inspect a snapshot.
- For grid/layout work, snapshot at realistic content volumes (5+ rows,
  4+ blocks). A single-block dashboard hides span/positioning bugs.
- Compare before/after if refactoring styling.
- Include snapshot path in commit message or ticket doc.
- If the snapshot looks wrong, fix before committing.

## Tailwind v4: Dynamic class names get purged

Tailwind 4 only emits CSS for class names it can statically see in the
source. Interpolated class names from runtime values are **NOT** generated
and silently fall through to default styling. This is the #1 cause of
"the layout looks broken but the code looks right" bugs.

```svelte
<!-- BAD: col-span-1, col-span-2, ... col-span-12 do NOT all exist -->
<div class="col-span-{item.w} row-span-{item.h}">

<!-- BAD: same problem with pad/text/bg/grid -->
<div class="p-{spacing}">
<div class="text-{size}">
<div class="grid-cols-{cols}">
```

Three fixes, in order of preference:

1. **Inline `style` for layout values that come from data** — most reliable.
   ```svelte
   <div style="grid-column: {item.x + 1} / span {item.w};
               grid-row:    {item.y + 1} / span {item.h};">
   ```

2. **Pre-defined Tailwind class lookup** when the value range is small and known.
   ```ts
   const SPAN: Record<number, string> = {
     1: 'col-span-1', 2: 'col-span-2', 3: 'col-span-3',
     4: 'col-span-4', 6: 'col-span-6', 12: 'col-span-12',
   };
   ```

3. **Tailwind safelist** in `tailwind.config` for the exact classes you
   need at runtime. Heaviest hammer; use only when (1) and (2) won't fit.

**Always pair this with a snapshot check.** If a layout-data-driven class
is purged, the page renders but quietly collapses — you'll only catch it
visually.

## Theme: Use `$lib/UI/theme.svelte.ts` — Single Source of Truth

**All dark/light mode styling MUST go through the theme manager.**

```
src/lib/UI/theme.svelte.ts  → isDark, theme.light, theme.dark tokens
```

Rules:
- **`theme.svelte.ts` exports `T`** — a reactive derived object that auto-switches between `theme.light` and `theme.dark` based on `isDark`. Components never derive it themselves.
- **Components just `import { T } from '$lib/UI/theme.svelte'`** and use `{T.cardBg}`, `{T.body}` etc. No ternaries, no isDark checks.
- **NEVER derive dark mode in components.** No `isDark.value ? ... : ...` ternaries for styling. No `const T = $derived(...)` in components. The theme manager handles it.
- **NEVER read `localStorage('theme')`, `prefers-color-scheme`, or create local dark flags.**
- **New tokens?** Add them to `ThemeTokens` interface and both `theme.light` / `theme.dark` objects in `theme.svelte.ts`.
- **Tag colors** use `TAG_COLORS` / `getTagColor()` from the same file.

```svelte
<!-- BAD: component derives dark mode -->
<script>
  import { isDark, theme } from '$lib/UI/theme.svelte';
  const T = $derived(isDark.value ? theme.dark : theme.light);
</script>
<div class="{isDark.value ? 'bg-gray-800' : 'bg-white'}">

<!-- GOOD: theme.ts exports T, component just uses it -->
<script>
  import { T } from '$lib/UI/theme.svelte';
</script>
<div class="{T.cardBg} {T.body}">
```

**Why:** Derivation in one place means Playwright can toggle dark mode by setting `settingsStore.darkMode` once — all components follow automatically. No scattered ternaries to miss.

## $lib Alias

Always use `$lib/` imports in .svelte and route files — never relative paths to src/lib/.

## Clean Lint — No Unused Vars

**Before commit**, `docker compose exec frontend npm run lint` MUST pass. No exceptions.

Common eslint violations to clean up:
- **`no-unused-vars`** — remove dead imports, dead props, dead destructure targets. Don't mask with `_` prefix unless the var is deliberately ignored from a destructure where you need later fields (e.g. `const [_first, ...rest] = arr`).
- **`svelte/no-at-html-tags`** — `{@html x}` is XSS-prone. Sanitize first (e.g. `DOMPurify.sanitize(marked(md))`) or avoid.
- **a11y warnings** (click without keyboard, missing role) — add `role`, `tabindex`, or use `<button>`.

**Never add `// eslint-disable`** to silence a real issue. Fix it. If a warning is genuinely a false positive, discuss before suppressing.
