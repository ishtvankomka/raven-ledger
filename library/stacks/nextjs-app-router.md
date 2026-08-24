---
name: nextjs-app-router
type: stack-module
description: Guidance for Next.js App Router projects (v14+). App Router has breaking changes vs Pages Router—this module enforces modern patterns for routing, server/client boundaries, data fetching, and builds. Covers Tailwind v3/v4 compatibility, including v4 `@theme static` token tree-shaking. Always check nextjs.org docs/upgrade guides + `npx next info` for deprecations before implementing features.
model: haiku
always_on: false
activation: "ACTIVATE ONLY IF the repo uses Next.js App Router"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Key Differences from Pages Router

- **File-based routing**: `app/` directory, `layout.tsx`, `page.tsx`, `route.ts` (not `pages/`)
- **Server Components by default**: functions in `app/` are Server Components unless marked `'use client'`
- **Streaming & Suspense**: native support for `Suspense`, `loading.tsx`, error boundaries
- **Data fetching**: `fetch()` with caching semantics in Server Components; no `getServerSideProps`/`getStaticProps`
- **Dynamic routes**: `[param]`, `[...slug]`, `[[...optional]]` syntax unchanged but behavior differs

## Server vs Client Boundaries

- Default everything to Server Components (no `'use client'` needed)
- Add `'use client'` **only** for: interactivity (state, event handlers), hooks (useState, useEffect), browser APIs
- Avoid `'use client'` wrapper around multiple children—push it down to leaf components
- Pass data to Client Components as props, not via context (unless context is server-created, then wrap in `Suspense`)

## Data Fetching

- Use `fetch()` directly in Server Components; **caching default depends on the Next major — detect it from `package.json` first**:
  - **Next 14**: `fetch()` defaults to `cache: 'force-cache'`; omit options = static (build-time)
  - **Next 15+**: `fetch()` is uncached by default — opt in explicitly via `cache: 'force-cache'` or `next: { revalidate: N }`
- `revalidate: 0` = dynamic, `revalidate: 3600` = ISR with 1h TTL
- NO `getServerSideProps`, NO `getStaticProps`—those are Pages Router only
- Use Route Handlers (`app/api/route.ts`) for API endpoints; export `GET`, `POST`, etc.

## Common Pitfalls

- **Serialization**: Server Component props and RSC payloads must be JSON-serializable; no functions, Dates as strings
- **Hydration mismatch**: Client Components rendered on server must match client render exactly (check console for warnings)
- **Stale imports**: Restart dev server after dependency updates or Tailwind version changes
- **Deprecation drift**: Verify against nextjs.org docs/upgrade guides and `npx next info` before adopting or migrating APIs
- **Layout cascade**: Each `layout.tsx` wraps all children; avoid expensive logic at root `app/layout.tsx`

## Tailwind Configuration

- Detect the version: read `tailwindcss` semver from `package.json`, confirm in the global CSS — `@tailwind base/components/utilities` directives = **v3**; `@import "tailwindcss"` = **v4**
- **v3**: `tailwind.config.js` with `content: ['./app/**/*.{js,ts,jsx,tsx}']`
- **v4**: CSS-first config (`@theme` in globals); `tailwind.config.js` optional/legacy
- Match the detected version before writing styles; do not mix v3 and v4 syntax

### Tailwind v4: `@theme` vs `@theme static` (token tree-shaking)

- A plain `@theme` block only emits the CSS variables the scanner sees referenced **literally**
  in source. A name composed at runtime — `` var(`--color-depth-${step}`) ``, an array/record
  lookup producing a `--color-*` string, or `getPropertyValue()` on a computed name — is
  invisible to the scanner, so the token is **dropped from the stylesheet** and every `var()`
  reading it resolves to nothing.
- **Rule**: any token addressed by computation, and any ramp addressed by position
  (`depth-1`…`depth-5`), lives in **`@theme static`** — even if today's code happens to spell
  each name out. The next refactor that turns five literals into a loop is a silent regression
  otherwise.
- `color-mix()` amplifies the failure: a missing variable does not degrade the mix, it
  **invalidates the whole declaration**, so the element falls back to whatever it inherits —
  often black-on-black.
- The failure is **theme-asymmetric**: theme overrides written as ordinary CSS rules (e.g.
  `[data-theme="light"] { … }`) are never tree-shaken, so one theme ships intact while the
  other lost its defaults. A single-theme screenshot check passes a broken page — check both
  themes separately, every time.
- Audit for the whole class: `grep -rn 'var(--[^)]*\${' app/ components/ lib/` (also scan for
  computed `getPropertyValue()` names and template literals split across lines).
- **Prove against the emitted bundle, not the source** — the source always looks right; the bug
  is in what the compiler emitted. Build, then grep the emitted CSS for the token **name plus
  colon only** (`--color-depth-3:`): minified output drops the space after the colon, so a
  pattern containing `: #` matches only one of dev/prod output and reports a false absence.
  Count 0 = tree-shaken = the bug.

## Build & Performance

- Run `next build` to catch hydration issues, unused CSS, and ISR misconfiguration
- Use `next/image` for images—automatic optimization, responsive sizes
- Check `next.config.js` for experimental flags (e.g., `reactCompiler`, `dynamicIO`) that affect semantics
- Incremental Static Regeneration (ISR): set `revalidate` on pages, not in middleware

## Error Handling

- `error.tsx` boundaries catch errors in Server and Client Components within the segment
- `not-found.tsx` for 404s; return `notFound()` from Server Components
- Root `error.tsx` cannot catch root `layout.tsx` errors—use wrapper or global handler
