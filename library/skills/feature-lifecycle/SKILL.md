---
name: feature-lifecycle
description: The full cascade for adding, renaming, merging or removing a route or feature in a web app — every derived surface (the page tree, the nav registry, sitemap and hreflang, redirects, export/report sources, every locale catalog, legal and FAQ prose) plus the copy namespaces that must survive their deleted route, and why removing a third-party permission scope breaks login rather than a feature. Use when asked to remove a feature, rename or merge a page, move something into another page, or drop an OAuth scope.
always_on: false
activation: "invoke when a route or feature is being added, renamed, merged, removed, or when an OAuth scope is being dropped"
context_cost: medium
keywords: "remove a feature, delete a page, retire functionality, route removal cascade"

---

# Route and feature lifecycle

**Deleting the directory is the smallest part of the job.** A route is named by
a dozen surfaces that no compiler checks: the sitemap keeps advertising the URL,
the nav registry keeps linking it, every locale catalog keeps its copy, and the
FAQ keeps promising a user the feature exists. Skip the prose half and the app
ships N languages describing features it no longer has.

A type checker catches maybe three of these surfaces. Everything else fails
silently, in production, in a language you do not read.

## First, learn this repo's URL shape

Two facts decide every path you are about to write:

1. **Where pages live.** Many localized apps put *every* page under a single
   locale segment (`app/[locale]/<route>/page.tsx`) and leave only global files
   at the root of the route tree. Check before you create
   `app/<route>/page.tsx` — a page in the wrong half of the tree renders, and
   then behaves differently from every other page in the app.
2. **How paths are written internally.** Under an "as-needed" prefix strategy
   the source locale keeps bare URLs and a helper adds the prefix when a
   localized URL is needed. Then **every internal path is written unprefixed**
   — the sitemap, the nav registry, the redirect table, every `returnTo`. Write
   one prefixed path into that set and it will be prefixed twice, or bypass the
   locale negotiation entirely.

## The touchpoint list

Walk it top to bottom for a removal, a rename or a merge. Column three says who
complains if you skip it — "nobody" means it ships broken.

| # | Surface | What changes | Caught by |
|---|---|---|---|
| 1 | the page file + its co-located parts | the page itself | build |
| 2 | the page's metadata call (seo key + path argument) | both arguments | types, partly |
| 3 | the SEO/metadata catalog, **every locale** | the seo key's block | nobody |
| 4 | the feature's own copy namespace, **every locale** | the namespace file | nobody |
| 5 | the namespace registry the loader iterates | the namespace entry | nobody |
| 6 | the nav registry (header/footer link lists) | the nav entry | nobody |
| 7 | the nav label key, **every locale** | the label key | nobody |
| 8 | the sitemap source | the route entry | nobody |
| 9 | the redirect table | a new permanent redirect from the old URL | nobody |
| 10 | the export/report source catalogue | the source spec | types |
| 11 | the exhaustive maps keyed by that source id (builders, filenames, sheets) | one entry each | types |
| 12 | the export/report label catalog, **every locale** | labels keyed by column and by source id | nobody |
| 13 | legal pages and the FAQ | prose that asserts what the app does | nobody |
| 14 | the FAQ copy inside the marketing catalog, **every locale** | the same answers, translated | nobody |
| 15 | the backlog / roadmap ledger | the row claiming the feature | nobody |

Two traps in that table:

- **The metadata key is not the route segment.** Keys drift from URLs as pages
  get renamed — a camelCase key for a hyphenated path, a short key for a long
  legal URL. Read the page's own metadata call; do not infer.
- **A legacy copy constant is not the live metadata.** When a repo migrated to a
  catalog-driven metadata helper, the old hardcoded page-meta object often
  survives as documentation with nothing importing it. Grep for its importers
  before you "fix a title" there and watch nothing move.

Catalog mechanics beyond this cascade — the translate workflow's reach, the
bundler's catalog cache, missing-vs-extra semantics — belong to the
`i18n-catalogs` skill. This list is only what a route change makes true.

## Renaming: move the files, never delete-plus-create

```bash
git mv "app/[locale]/<old-route>" "app/[locale]/<new-route>"
for l in <every locale dir>; do
  git mv "messages/$l/<old-ns>.json" "messages/$l/<new-ns>.json"
done
```

`git mv`, never delete-plus-create: the page and its catalog carry the argument
for every decision in them, and `git log --follow` is the only way a future
session learns why. A recreated file starts at *"why is this here?"*.

Then follow the route with, in order: the namespace name in the registry, every
`useTranslations("<ns>")` / `getTranslations("<ns>")` call site, the nav entry's
href and key, the nav label key in **every** locale, the metadata key, every
`returnTo="/<route>"` (post-login return targets silently land the user
somewhere else when stale), the sitemap path, and a redirect from the old URL.

If a name is in flight across surfaces, one object exported under two names with
a comment saying when to drop the alias buys a beat — two objects that can drift
do not.

## Sitemap, hreflang and the no-redirect rule

- **A sitemap must never list a URL that redirects.** Asking a crawler to spend
  a fetch learning what the file could have told it is the whole cost.
- **A route that noindexes itself stays out.** A page behind a "coming soon"
  flag sets `robots: { index: false }` in its own metadata; the sitemap must not
  advertise it. When the flag comes off, both change together.
- **Every entry carries the full hreflang map**, except pages that are
  deliberately source-language only. Those opt out in **three places that must
  agree**: the sitemap flag, the page's own metadata overriding `alternates` to
  a bare canonical, and the middleware/proxy list that strips the framework's
  own `Link` response header. Two out of three is a crawler picking whichever it
  saw last.

A nav registry usually supports more states than "listed" and "absent" — an
optional `soon` flag renders the name without a link, and a route folded into
another page may have **no entry at all** while its URL still redirects.
Listed-but-unlinked and gone-but-redirected are different states; pick one
deliberately, and record which in a comment.

## Redirects are what a finished removal looks like

Every removed feature leaves a permanent (308) redirect behind, and the set of
them is the readable history of the product: a standalone page folded into a
section, a query-param page that became a real route, a feature that died with a
provider endpoint, an old SEO title that was never a URL.

Keep the redirect table's neighbours out of the diff. Build-config files
routinely mix redirects with cache/staleness settings that are load-bearing
against skeleton flashes; edit the array, not the file.

## Namespaces outlive their route

**Deleting a route does not license deleting its copy namespace.** Blocks
routinely move from a retired page onto a summary page, so the namespace has no
page directory and its copy is still rendering. Always grep before deleting a
catalog:

```bash
grep -rn 'Translations("<ns>")' app components lib
```

Which namespaces are in that state, and what still renders them, belongs in the
`i18n-catalogs` skill's table — along with the checker's file-level blind spot,
which is why deleting a namespace wrongly stays silent. When a namespace really
is dead, delete it in **every locale directory including the source locale**;
the checker only ever proves key-level hygiene.

The reverse residue is quieter: label keys for retired nav entries sit in the
nav catalog forever, read by nobody. Harmless, invisible, and exactly what
accumulates.

## Kill props as props

Remove the capability from the type, not only from the call sites. A prop left
in a signature is an invitation to put the removed thing back, and someone will
accept it. Write the absence down where the next reader will be tempted:

> There is no subtitle slot.

— because *"no component passes a subtitle right now"* is not the same statement
as *"this component has no subtitles"*. Same for a removed variant in a union, a
removed export-source id, a removed flag: delete the type member and let the
type checker list the wreckage.

## Scope removals break login, not a feature

An OAuth scope is not a feature flag. Providers commonly validate the requested
scope set **after** the user has signed in, so a single scope the production
client is not approved for answers the whole authorize request with
`error=invalid_scope` — **nobody gets in at all**. That is the failure mode:
credentials that had worked for years, refusing every login, because the request
had grown from six scopes to twelve.

Structure the constants so this is visible:

- the full set the code *would* ask for,
- the reduced set actually **proven against the production client**,
- the configurable set the login sends.

Scopes deliberately not requested need a comment saying so. Adding one back is
not a config change: it means bringing back a feature and updating the Terms,
the Privacy Policy and the FAQ, all of which now state as fact what the app can
and cannot touch.

Sessions issued before a scope was added do not carry it, so the affected call
answers 403 for those users. That is a "reconnect to grant the new permission"
outcome, never a logout.

### When a write capability goes away, the semantics change

Not just the button. A control becomes a **mark** — a hover-reveal was an
affordance promising something to press, and repeating it on something inert
invites a click, takes it, and does nothing. An indicator that used to be a
toggle needs three honest states — on, off, and *not yet known* — and the last
two usually must render identically, because a hollow icon that fills in a
moment later is a lie the user cannot correct.

Ask the same question for any removed write: what did this element mean when the
action existed, and what does it honestly mean now?

## Proving the removal is complete

```bash
# 1. No surface still names the route or namespace.
grep -rn "<route>" app components lib i18n messages <build-config> <proxy-or-middleware>

# 2. Exhaustive maps and dead props surface here.
<the repo's typecheck command>

# 3. Catalog parity across locales (strict mode to demand completeness).
<the repo's catalog checker>

# 4. Pure-function/unit checks for anything the feature computed.
<the repo's check command>

# 5. The real gate.
<the repo's build command>
```

Then, with a dev server up:

```bash
curl -sI "$BASE/<old-route>" | head -3            # expect 308 + Location
curl -s  "$BASE/sitemap.xml" | grep -c "<old-route>"   # expect 0
```

Grep hits that are *not* failures: a comment in the redirect table, the sitemap
or the nav registry explaining why the route is gone. Those are the record of
the decision — keep them, and add one wherever the absence looks like an
oversight.

## Things already deleted on purpose

Before building a module that feels conspicuously missing — a playback
transport, a demo-data module, a dashboard the nav hints at — check the redirect
table's comments and the scope constants. A previous session very likely removed
it deliberately, and the reason is usually one line away from where you are
about to type.
