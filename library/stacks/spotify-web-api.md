---
name: spotify-web-api
type: stack-module
description: Current constraints of the Spotify Web API — PKCE-only auth (Implicit Grant sunset Nov 2025), the April 2025 redirect-URI rules (127.0.0.1 not localhost, exact match), the November 2024 restricted-endpoint list, the invalid_scope login-refusal trap, and how to handle a 403 correctly. Prevents re-researching facts that pre-2025 tutorials and StackOverflow answers get wrong.
model: haiku
always_on: false
activation: "ACTIVATE ONLY IF the repo integrates the Spotify Web API"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

# Spotify Web API — current constraints

Verified against Spotify's docs and developer blog. Trust this module over
memory or over tutorials written before 2025 — nearly all of them describe
flows that no longer work.

## Auth: PKCE only

- The **Implicit Grant flow (`response_type=token`) was sunset on 27 November
  2025.** It is gone, not merely discouraged. Anything using
  `response_type=token` or reading an access token from
  `window.location.hash` is dead code.
- Use **Authorization Code with PKCE** (client- or server-side both work).
- **Never add a client secret to a public client.** PKCE exists precisely so
  public clients don't need one; the token endpoint accepts `client_id` alone.
- Access tokens live 1 hour. Centralize refresh in one place (middleware/
  proxy); pages must not implement their own.
- Refresh-token lifetime is a per-app dashboard setting (e.g. 180 days) —
  match your session cookie's maxAge to it.

## Redirect URI rules (enforced since April 2025)

- HTTPS required, **except** loopback addresses.
- **`localhost` is rejected.** Use the IP literal: `http://127.0.0.1:PORT`.
- Must match a registered URI **exactly**, including the trailing slash.
- Framework trap: some frameworks normalize the request origin to
  `localhost` even on a 127.0.0.1 request (e.g. Next.js `nextUrl.origin`).
  Derive the origin from the Host header, or pin the redirect URI via env.
- Unregistered-origin deployments (e.g. `*.vercel.app` previews) cannot
  complete login. Verify auth locally on 127.0.0.1 or in production, never
  on a preview URL.
- Spotify validates `redirect_uri` only *after* authentication — "the login
  page loaded" proves the parameter's presence and shape, **not** its
  registration. Read the `redirect_uri` inside the authorize URL and compare
  to the registered value yourself.

## Restricted endpoints — the 27 November 2024 change

These return **403** for any app that did not already hold *extended quota
mode* on that date. There is no replacement and no way to apply:

- `/audio-features`, `/audio-analysis` (also marked Deprecated)
- `/recommendations`
- `/artists/{id}/related-artists`
- `/browse/featured-playlists`, `/browse/categories/{id}/playlists`
- 30-second `preview_url` in multi-get responses
- algorithmic & Spotify-owned editorial playlists

Announcement: https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api

Two operational consequences:

- **Spotify is inconsistent about HOW it refuses** — observed empirically:
  `/audio-features` returns 403, `/recommendations` returns 404. Treat both
  status codes as "restricted" — but only for URLs on the restricted list,
  so a 404 elsewhere keeps its normal meaning.
- **Grandfathered (quota-extended) production apps keep access.** If a
  project has one grandfathered app and one development-mode app, restricted
  features work in production and 403 locally — never delete a feature on
  the basis of a local 403/404.

## Development Mode tightening (announced 6 Feb 2026)

Premium account required, one Client ID per developer, max 5 authorised
users; enforced for existing integrations from 9 March 2026. Quota-extended
production apps are unaffected.
https://developer.spotify.com/blog/2026-02-06-update-on-developer-access-and-platform-security

## Scopes: the invalid_scope login-refusal trap

Spotify validates the requested scope set against the app's **approved**
set, *after* the listener has signed in. **One scope outside the approval
refuses the WHOLE login with `error=invalid_scope`** — an unapproved scope
does not disable one feature, it locks every user out of the product.

- Keep the scope list minimal and centralized in one constants file; adding
  a scope is a product decision (it likely changes what your Terms, Privacy
  Policy, and FAQ state as fact), not a config tweak.
- Removing a write scope changes UI semantics: a control that can no longer
  write must become an honest indicator (or disappear), not an inert button.
- Sessions issued before a scope was added do not carry it — the affected
  call answers 403 for those users. That is a "reconnect to grant the new
  permission" outcome, never a logout.

## Handling a 403 correctly

A 403 from a restricted endpoint is **a permanent property of the endpoint**
for non-quota apps, not a bad session. It must never trigger a logout or a
retry. Pattern:

1. Map matching 403/404s (restricted list only) to a typed
   `RestrictedEndpointError` in the API client.
2. Fold it into the page loader's result type (`{ ok: false, kind:
   "restricted" }`).
3. Render a per-feature "unavailable" state — and degrade per-section, so
   unrestricted sections of the same page survive.

## Before claiming an endpoint is broken

Check in this order — most failures are auth, not the endpoint:

1. Is it on the restricted list above? → permanent for non-quota apps.
2. Which client ID is loaded? → a dev-mode app 403s on restricted endpoints
   by design.
3. Is the token expired? → the refresh layer's job; check the session first.
4. Only then hit the docs. Do not re-derive the facts in this module.
