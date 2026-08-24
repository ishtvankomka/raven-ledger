---
name: clickable-inventory
description: >
  Enumerate EVERY place a user can click or navigate to on a web page/site — not just the public
  sitemap, but every real destination: links, buttons, form actions, dropdown/mega-menu items,
  tabs, accordions, modals/dialogs, search, language toggles, pagination, and gated/auth flows
  (login, register, account, cart, checkout, agent/admin). Use during website recon to build a
  complete destination map before cloning.
always_on: false
activation: "stage 1 of the replication pipeline — invoked by replica-scout per page; also invoke standalone whenever a task needs a complete map of every clickable/navigable destination on a site, including gated and interaction-only ones"
context_cost: low
---

# Clickable / navigable inventory

Goal: a complete list of everywhere a user can go. "Public pages only" is not enough — capture
every interactive destination, including ones behind auth or revealed by interaction.

## 1. Seed the crawl
- `curl -s <url>` each known page; also fetch `/sitemap.xml`, `/robots.txt`, `/sitemap_index.xml`.
- Start from the homepage and follow internal links breadth-first. Keep a visited set; stay on the
  target host (note external links separately).

## 2. Extract destinations from raw HTML (per page)
Parse for every trigger, not just `<a>`:
- `<a href>` (resolve protocol-relative `//`, relative, and query-string URLs).
- `<form action>` + method + every field/option (these are destinations + flows).
- `<button>`, `[role=button]`, `[onclick]`, `data-href`/`data-url`/`data-target` attributes.
- `<area>` image maps, `<link rel>` (canonical, alternate/hreflang, pagination rel=next/prev).
- Inline JS: `location.href=`, `window.open(`, `router.push(`, SPA route tables, and any
  site-specific menu/route query params (e.g. `mitem=`, `pmid=`) or JSON blobs of menu/route data.

## 3. Reveal interaction-only destinations (use the browser)
Open the page in a browser (browser MCP) and:
- `read_page` with `filter: "interactive"` to get the accessibility tree of clickable nodes.
- **Hover** every top-nav item to expand mega-menus; record each child link.
- Open the **mobile** layout (resize/emulate) and open the **hamburger** + any accordions.
- Click tabs, "show more", carousels, and **modals/dialogs** (cookie banner, login popup,
  newsletter, "request info", session/profile dialogs) — record where each leads.
- Footer + utility bar: search, sign-in, cart, account, language/locale, social.

## 4. Include gated / non-public flows (list even if you can't enter them)
Record these as destinations with `authRequired: true` and the trigger that reaches them:
login, register/enroll, forgot-password, my-account and its sub-tabs, cart, checkout, order
confirmation, wishlist, agent/back-office or admin entry points, document-sign / e-sign flows,
and any "members only" links. If you have test creds, walk them; otherwise capture the entry URL
and expected next step.

## 5. Output — `recon/clickable-map.json`
One record per destination:
```json
{
  "label": "<visible link text>",
  "url": "<path>?<site-specific-param>=<id>",
  "trigger": "link|button|form|modal|tab|menu-item|js-redirect",
  "sourcePage": "/",
  "revealedBy": "<the interaction that exposed it, e.g. hover on a nav item>",
  "authRequired": false,
  "kind": "page|action|external|asset|flow-step",
  "notes": "what it does / where it leads"
}
```
Also append each unique page route to `recon/INDEX.md`. De-duplicate by normalized URL. Flag any
destination that 404s or redirects (record the final URL).

**Done when:** every menu (incl. hover + mobile), every footer link, every form, every modal, and
every gated entry point is in the map — re-walk the homepage and one deep page to confirm nothing
new appears.
