---
name: locale-routing-hreflang
type: stack-module
description: 'Build-time rules for serving a multi-locale public site: one locale registry as the source of truth, a mapping layer between internal locale identifiers and the BCP-47 tags emitted in markup, hreflang/canonical/x-default generation, why cookie- or geo-based redirects hide content from crawlers, and the all-locales-complete gate before release. Complements qa-auditor, which audits the running site rather than wiring it.'
model: haiku
always_on: false
activation: "ACTIVATE ONLY IF the app serves more than one locale to the public web (crawlable locale routes, hreflang tags, or locale-aware redirects)"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## One registry, everything derived

The locale set is declared **once** (a config module or union type) with, per locale: internal code,
BCP-47 tag, display name, text direction, and whether it is publicly routable. Routes, the language
switcher, hreflang links, the sitemap, and the parity checker all read that registry.

Two hand-kept lists is the defining bug of this area: a locale ships in the switcher but has no route,
or has a route no hreflang tag points at. If you find a second list, collapse it into the registry
before doing anything else.

## Internal code vs emitted tag — keep them separate

A codebase may legitimately use an internal identifier that is **not** the standard tag (a legacy
choice, a directory name, a DB enum, or a code the type system already enforces). That is survivable
internally and expensive to change — but it must never reach the browser or a crawler.

- Emit through **one** mapping function: internal code → BCP-47. Everything externally visible goes
  through it — `<html lang>`, `hreflang`, `Content-Language`, sitemap entries, social/OG locale, and
  any structured data.
- Never interpolate the raw internal code into markup, and never hand-write a tag at a call site.
- Deprecated ISO aliases are invalid as emitted tags even where runtimes still accept them
  (`iw`→`he`, `in`→`id`, `ji`→`yi`); region forms use a hyphen (`en-US`, never `en_US`).
- Adding a locale means adding **both** columns to the registry. A missing mapping must fail the
  build, not fall through to the internal code.

## URL strategy

| Strategy | Crawlable | Notes |
|---|---|---|
| Path segment (`/<locale>/…`) | Yes | Default choice; one dynamic segment serves all locales |
| Subdomain / ccTLD | Yes | Heavier ops; justified for per-market entities |
| Cookie or header only, one URL | **No** | Each locale has no address — crawlers index one language |

Pick one and make it total: every publicly routable locale in the registry has a real, linkable URL.

## hreflang, canonical, x-default

- Generate the full link set from the registry — never hand-maintain per page. Hand-kept hreflang
  goes stale on the first locale added and is a top source of silent international-SEO loss.
- Reciprocity: if A links B, B links A. Every page's set includes a **self-referencing** entry.
- Add `x-default` for the fallback/selector URL.
- Canonical points at the page's **own** locale URL, never at the primary locale's — a
  cross-locale canonical asks the crawler to drop the translation.
- Absolute URLs only.

## Cookie and geo redirects

- A stored locale preference may **refine** the experience; it must never be the only way to reach a
  language, and it must never change what is served at a crawlable URL.
- Auto-redirecting by IP/`Accept-Language` on entry hides every other locale from crawlers and traps
  users who deliberately asked for another language. If the product insists, redirect only from the
  locale-neutral root, keep every locale URL directly reachable, use a temporary status, and add
  `Vary: Accept-Language, Cookie` so caches do not serve one language to everyone.
- Whatever the resolution order (URL > cookie > header > default), `<html lang>` must state the
  language actually rendered. A mismatch between cookie, URL, and `lang` is the standard symptom
  when users report "the site keeps loading the wrong language" — check that triangle first.

## Release gate

- No partial locale rollouts: a routable locale ships complete or is marked non-routable in the
  registry until it is.
- Before release run the parity check for **every** locale (`/check-translations` per locale, or the
  project's own script) plus `/check-locale-codes`. Coverage reports are read-only — they gate the
  merge, they do not edit content.
- Verify the emitted HTML, not the source: fetch a page per locale without JavaScript and confirm
  `<html lang>`, the hreflang set, and the canonical are what the registry predicts.

## Handoffs

- Live-site international-SEO audit (reciprocity, crawler visibility, indexation) → `qa-auditor`.
- Dictionary storage, key lockstep, per-surface ownership → the i18n dictionary stack module.
- Content extraction/translation → `i18n-engineer`.
