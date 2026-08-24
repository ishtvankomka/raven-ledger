---
name: cms-page-sections-revalidation
type: stack-module
description: 'Self-hosted CMS pattern: a page/translation/section content model owned by the app itself, an authenticated editor API, and the cache-revalidation handshake that makes an edit visible on a statically rendered public site. Enforces the rule that content work touches four layers — schema, write API, editor UI, public render — and that shipping three of them is a broken half-feature.'
model: haiku
always_on: false
activation: "ACTIVATE ONLY IF public pages render from a content model stored in the app's own database and edited through an internal editor UI (no third-party headless CMS)"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## The four layers — always in lockstep

1. **Schema** — the content model and its migration.
2. **Write API** — authenticated endpoints the editor calls.
3. **Editor UI** — the internal screen authors actually use.
4. **Public render** — the page that reads the content, plus cache invalidation.

Classify the request against these before writing code: surfacing an existing field (layer 4 only),
making a hardcoded region editable (all four), adding a field to an existing section (all four),
restructuring data (all four + migration). If a request does not fit a known shape, ask for scope
rather than guessing — a change that lands in three layers reads as "done" and fails in production
when an author edits the field nothing renders.

## Content model (shape, not schema text)

- `Page` — one row per route, keyed by a unique `slug`.
- `PageTranslation` — per-locale `title` / meta / locale-specific copy, unique on `(pageId, locale)`,
  cascade-deleted with the page.
- `Section` — ordered, keyed blocks belonging to a page (`key` such as hero/features/cta, an explicit
  `order`, and a `content` JSON column holding the rich-text document).

Rules that survive any ORM:
- The section `key` is a stable identifier the renderer switches on — renaming one is a migration,
  not an edit.
- Ordering is an explicit column, never insertion order.
- Rich-text lives as structured JSON, never as raw HTML from the editor; sanitize/validate on write.
- Locale codes come from the app's locale registry, not free text.

## Write endpoint

- Guard every mutation with auth **and** an editor-role check; read endpoints for the public site stay
  separate and unauthenticated.
- Validate the rich-text payload against the expected document shape in the DTO before it reaches the
  database. Malformed JSON stored once breaks the renderer for everyone.
- Return the **updated row**, not the driver's `{ count }` — the editor needs the persisted value to
  reconcile its state.
- Bulk/structural writes are irreversible: gate them (see below).

## Revalidation handshake

After a successful write, the API tells the public site to drop its cached copy:

- POST to the public site's revalidation route, addressed by an env-configured site URL.
- Pass the shared secret in a **header**, never a query string — query strings land in access logs,
  proxies, and referrers. Compare it with a constant-time check and return 401 on mismatch.
- Send the smallest invalidation unit the framework supports (path or cache tag for that page), not a
  full-site purge.
- Do not block the author's save on the revalidation round-trip, but **do** log/surface its failure —
  a silently failed revalidation is indistinguishable from "the edit did not save" to the author, and
  is the single most common support report for this pattern.
- Verify by fetching the public URL after an edit; a green write response is not proof the page changed.

## Public render

- Read the page with its translations and ordered sections in one query; render sections by `key` in
  `order`.
- Unknown section keys render nothing (and log) rather than crashing the page.
- Empty content falls back to a declared default, never to a stale hardcoded string that authors
  cannot see or edit.

## Gates

Reversible — proceed: add a section, edit section content, upsert a translation, reorder sections.

CONFIRM before executing:
- Deleting a page or section (cascades translations and blocks) — state slug and how many rows.
- Structural migrations over existing content (splitting a JSON blob into columns, renaming a section
  key) — state how many rows are rewritten and whether the change is reversible.

## Troubleshooting

| Symptom | Check first |
|---|---|
| Edit saved, page unchanged | Revalidation POST result, then CDN/proxy TTL above the framework cache |
| Editor cannot load a page | Auth/role guard on the read-for-edit endpoint; slug mismatch |
| Renderer throws after an edit | Rich-text JSON shape — validate in the DTO, not in the component |
| Field editable but invisible on the site | Layer 4 was skipped: the renderer still reads a hardcoded value |
