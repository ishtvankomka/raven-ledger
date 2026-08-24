---
name: verify-change
description: How to prove a web change actually works before saying it is done — running the gate in an order that means something, knowing which dev server you are really talking to when a repo has many worktrees, the caches that make your edits invisible, the four specific ways a browser preview pane lies, settling colour and CSS arguments against the emitted bundle instead of the source, and measuring mobile fit as DOM math. Use before reporting a change done, when a screenshot or console error looks wrong, when verifying CSS/colours/mobile fit, or when the app seems to ignore your edits.
always_on: false
activation: "invoke before reporting a change done, or when the app appears to ignore your edits, a screenshot looks wrong, or a colour/mobile-fit claim needs proving"
context_cost: medium
---

# Proving a change works

**Most of a repo's gate can pass in a worktree that has no dependencies
installed at all.** Package-manager run scripts prepend every ancestor
`node_modules/.bin` to `PATH`, and Node's own resolution walks up the same way,
so the type checker, the script runner and even the dev server quietly resolve
out of the **main checkout** from inside a bare worktree. Usually only the
production build notices. Run the whole gate, in order, every time — a green
typecheck proves less here than it does anywhere else.

## The gate, in order

```bash
cd <this worktree>
ls node_modules >/dev/null 2>&1 || npm install
<typecheck>          # cheapest, names every error at once
<unit/pure checks>
<catalog / data-parity checks>
<build>              # the real gate; stops at the first error
```

Cheapest first is not a style preference: the cheap checks enumerate every
error in one pass, while the build stops at the first one and tells you nothing
about the other nine.

**Read `package.json` before reaching for a script.** Repos routinely have no
`lint` and no `test`; `npm test` then fails with *"Missing script"*, and that
failure tells you nothing about your change while looking exactly like a
failure that would.

Record a **baseline** for the tree you started from: wall-clock time and exit
status per command, and the exact failure count of any check that exits non-zero
on a clean tree. A gate with a known non-zero baseline is fine; a gate with an
*unwritten* baseline gets ignored by the next reader. Diff your run against the
baseline and report only the delta as yours.

Incremental type checkers write a build-info file (gitignored) that makes every
run after the first roughly a second — delete it when you want the cold number
back.

Two smaller facts that cost turns:

- A script that computes its own root from `__file__` runs from any cwd;
  package-manager scripts do not. Use `npm --prefix <abs-worktree-path> run …`,
  or chain with `&&` inside one call.
- Install-time warnings about packages whose install scripts are "not covered
  by allowScripts" are warnings, not failures — check whether the build and the
  runtime actually need them before approving anything.

## Which dev server you are actually talking to

When a repo runs many worktrees against a couple of fixed ports, find out what
already owns them and **which tree it serves**:

```bash
lsof -nP -iTCP:$PORT_A -iTCP:$PORT_B -sTCP:LISTEN
lsof -p <pid> -a -d cwd -Fn        # prints n<cwd> — the checkout it compiles
```

The second command is the whole section. A dev server on the port you expected
tells you nothing until you know its cwd. **A server started in a different
checkout serves that checkout's module graph. Your edits will never appear, no
matter how many times you reload or clear caches.** It presents as a cache bug,
you will spend turns deleting build caches, and it is not a cache bug — it is
the wrong process.

- If your port is taken by another session, **take a free one**.
- **Never kill a server you did not start** — another agent is mid-verification
  on it.
- **Wait several seconds after starting before the first request.** The first
  compile of a route is slow; an immediate curl reports a false failure and you
  go debugging a healthy server.

A build in a worktree with no dependencies installed fails with a "could not
find the framework package, resolved from …" error. Modern bundlers pin the
workspace root at the nearest lockfile and refuse to compile outside it —
deliberately, for a hermetic build. That error means *"install here"*, not
*"the config is broken"*; do not add a workspace-root override to chase it.

## Caches that make your edits invisible

Suspect in this order: **wrong server** (above) → the bundler's module cache →
nothing else. Build caches are per-checkout; they are never shared between
worktrees.

The specific trap: assets that enter the graph through a **template dynamic
import** are tracked as a *context*, not as individual files, so editing one of
them may not invalidate anything:

```ts
return (await import(`../messages/${locale}/${ns}.json`)).default;
```

Touch the modules that own the import; if stale content survives, drop the cache
and restart:

```bash
touch <the modules that own the dynamic import>
rm -rf <the bundler cache dir>     # the next compile is slow; that is expected
```

## When the browser pane lies

Four failure modes, all observed in real work:

| symptom | cause | what to do instead |
| --- | --- | --- |
| console shows an error you already fixed | pane console history **persists across navigations and HMR** | only believe an error that survives a **cold reload** |
| first screenshot is dim, text sits a few px low | an entrance animation is still running | wait, then re-screenshot |
| screenshot after scrolling renders **black** | pane compositor | resize the viewport tall, or read the text instead |
| nothing changes, screenshots identical | pane **suspends when hidden** — no rAF, no IntersectionObserver frames | DOM math via page scripting, or `curl` |

Retained console history is the expensive one. It is what makes an agent restart
the dev server and bolt debug hooks onto working code to chase a message emitted
three navigations ago. **An error is only real if it survives a cold reload.**

Entrance animations are the second: if a `rise`/`fade-in` utility wraps
essentially every route's page container, the first screenshot after any
navigation catches the page mid-entrance — dimmed and displaced. That is not a
layout bug and not a broken opacity token. Grep for the utility's call sites
once and you will stop re-diagnosing it.

While the pane is hidden, an IntersectionObserver-driven reveal simply never
fires. That is a suspended tab, not a broken observer — do not "fix" it.

## Settling colour and CSS arguments without a screenshot

Never argue a colour from a thumbnail, and never from the source stylesheet
alone: a CSS-first theme block is *source*, and modern CSS pipelines can drop
tokens on the way out (tree-shaking a variable whose name is only ever composed
at runtime). Verify against the bundle the browser actually got:

```bash
curl -sL "$BASE/" -o /tmp/page.html
grep -o '/_next/static/[^"]*\.css' /tmp/page.html | sort -u   # or the repo's asset path
curl -s "$BASE/<the-hashed-css-url>" | grep -o -- '--color-<token>: *[^;]*'
```

Several hits for one token is normal, not a duplicate-definition bug — a token
is redefined per theme, and often once more inside a scoped override.

Two things that silently waste a turn:

- **Grep with ` *` after the colon.** A dev server serves the chunk unminified
  (`--color-x: #abc`); a production build emits it minified
  (`--color-x:#abc`). A pattern that hard-codes one spelling finds nothing, and
  you conclude the token was tree-shaken when it is right there.
- **Pull the chunk URL out of the HTML.** Filenames are content-hashed and
  sometimes URL-encoded; they change on every meaningful edit and cannot be
  guessed.

The same procedure works against production — it is the only honest way to
answer "did the deploy actually ship my CSS".

## Mobile fit is DOM math, not eyes

Horizontal overflow is a number, per route:

```js
const d = document.documentElement;
({ scroll: d.scrollWidth, client: d.clientWidth, overflow: d.scrollWidth > d.clientWidth });
```

A 2px overflow is invisible in a screenshot and very visible on a phone.

**A window-resize tool can silently fail to apply** — you get the same wide
render back, measure it, and "fix" a bug you never reproduced. The reliable
viewport is a **same-origin iframe** sized inside the page that is *already*
loaded. Two calls, because top-level `await` is not dependable in page-scripting
tools:

```js
// call 1 — mount
const f = document.createElement('iframe');
f.id = 'fitprobe';
f.style.cssText = 'position:fixed;left:0;top:0;width:390px;height:844px;z-index:2147483647;border:0';
f.src = location.pathname + location.search;
document.body.appendChild(f);
'mounted';
```

```js
// call 2 — measure
const d = document.getElementById('fitprobe').contentDocument.documentElement;
({
  scroll: d.scrollWidth,
  client: d.clientWidth,
  offenders: [...d.querySelectorAll('*')]
    .filter(e => e.getBoundingClientRect().right > d.clientWidth + 0.5)
    .slice(0, 10)
    .map(e => e.tagName + '.' + (e.className || '')),
});
```

Measure at **two widths**: the common phone width your users have, and the
narrowest one you support. The narrow one is where overflow bugs actually live.
For the many-route batched form of this probe, see the `pre-ship-sweep` agent.

## A real browser vs the in-app pane

A full external browser is needed for **exactly one thing**: steps that require
a live, already-signed-in session belonging to the account holder. Layout, copy,
colours, console, network, overflow — all cheaper and more reliable in the
in-app pane plus `curl`.

Some production sites wedge an automation-driven browser; retrying makes it
worse. **Switch tools instead of retrying**: curl production, or drive the local
server in the in-app pane.

**Never type anyone else's credentials, and never ask for them.** For what a
credential-free login check can and cannot prove, see the
`oauth-login-verification` skill — in particular, reaching a provider's login
page does **not** prove the redirect URI is registered.

## Runtime and lockfile parity with the deploy platform

- A `engines.node` field usually **overrides the hosting project's runtime
  setting**, so `package.json` decides the deploy runtime and changing the
  dashboard alone proves nothing.
- **Never commit a lockfile produced with `--legacy-peer-deps` or `--force`.**
  CI runs a plain install. A lockfile written under relaxed resolution can
  describe a tree the platform will not reproduce — and it fails there and
  nowhere else. If you installed with flags:

  ```bash
  git checkout package-lock.json
  npm install                                  # no flags — the way CI does it
  git status --porcelain package-lock.json     # must be empty
  ```

  Any diff after a flagless install is a real dependency change and belongs in
  the commit deliberately.
- **Bash calls do not share shell state, and cwd resets between them.** Use
  absolute paths in every command; a `cd` in one call does not carry to the
  next.

## Before you say "done"

- [ ] Dependencies exist in *this* worktree.
- [ ] Every gate command ran, in order; any non-zero exit matches the recorded
      baseline exactly.
- [ ] Any dev-server evidence came from a server whose cwd you confirmed with
      `lsof -p <pid> -a -d cwd -Fn`.
- [ ] Any console error you are reporting survived a cold reload.
- [ ] Any colour or token claim was checked against the emitted CSS bundle, not
      the source and not a screenshot.
- [ ] Any mobile-fit claim is a `scrollWidth` vs `clientWidth` number at two
      widths, not an eyeball.
- [ ] You did not kill a server you did not start.
