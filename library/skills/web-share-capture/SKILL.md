---
name: web-share-capture
description: How to ship a "share this as an image" / "download this" feature on the web that actually works on iPhones — composing a share card off-screen instead of photographing the page, WebKit's five-second transient-activation rule for navigator.share(), telling a dismissed share sheet from a failed one, and the download-anchor rules Firefox and Safari enforce. Use when building or debugging image share/download/export buttons, DOM-to-image capture, or a share sheet that silently fails on iOS.
always_on: false
activation: "invoke when building or debugging a share-as-image, download or export button — anything touching navigator.share(), a DOM-to-image capture library, an <a download> anchor, or a share sheet that fails silently on iOS"
context_cost: medium
---

# Share and capture on the web

Hard-won platform facts for the feature everyone underestimates: a button
that turns part of the page into a picture and hands it to the OS share
sheet or the Downloads folder. Every rule below was paid for by a real bug.

## Compose a card; never photograph the live page

The exported picture should be a **different artefact from the page**,
composed from scratch at a fixed width — not the page clipped, cloned, or
re-rendered at another width. Cloning the live page node and un-hiding
marks inside the clone is the pattern this replaces, and it breaks on every
layout change.

**Stage the card off-screen with real layout:**

```css
.share-stage { position: fixed; top: 0; left: -20000px; z-index: -1; pointer-events: none; }
```

- **`position: fixed`, not `display: none`.** `display: none` has no layout,
  so the card cannot be measured, its images never decode and its fonts never
  settle. Fixed gives real layout and real paint at zero cost to the page.
- **`fixed`, not `absolute`.** A fixed element cannot extend the scrollable
  area, so a card parked at −20000px can never hand a phone a horizontal
  scrollbar.
- **`inert` + `aria-hidden`** — it is a rendering surface, not content.
- **Render it up-front** (server-render if possible) so artwork and marks
  decode long before anyone presses the button.

**Inside the card:**

- Fix the card's pixel width everywhere so the output is identical on all
  devices. Then **size everything by container, never by viewport
  breakpoints** — an `sm:` inside a fixed-width card asks a question about a
  box it cannot see, and the same picture comes out with 9px names from a
  phone and 11px names from a laptop.
- **Every image inside the card must load eagerly.** A lazy image parked
  off-screen never intersects the viewport, never loads, and photographs as
  a hole in the PNG. Keep the eager flag opt-in per instance; the page's own
  copies stay lazy.
- Clip lists to a deliberate preview count; a share card is a summary, not a
  dump.

## WebKit transient activation — the five-second rule

**WebKit gates `navigator.share()` on transient user activation** — a
timestamp stamped on the window when the finger lifts, good for about five
seconds, consumed by the call. It is a property of the *window*, not of the
call stack, so **an `await` does not carry it** — wall-clock time simply
runs out underneath a slow capture. There is no way to hold activation open
across an await (`whatwg/html#8529`, open since 2022).

The structure that works:

1. **Build the picture first.** `await capture()`, build the `File`.
2. **Check `navigator.userActivation.isActive`.** If still live — true for
   most fast captures — call `share()` immediately; nothing changes for the
   user.
3. **Otherwise ARM.** Keep `{key, dataUrl, file}` in a ref, flip an `armed`
   flag, and say so in the UI ("Image ready — tap again to open the share
   sheet"). The next tap calls `share()` with the File already in hand — and
   in that armed branch, **nothing may be awaited between entering the
   handler and calling `share()`**. Put a comment on that line saying so.

The armed picture is a bridge from one tap to the next, **not a cache**:

- Give it a TTL (~90s) — a multi-megabyte File resident in a ref is a real
  cost on a phone, and an armed picture of data the page has since changed
  is worse than no picture.
- Key it on everything that changes the picture (capture target + filename
  built from the active state), so flipping a filter between taps
  *invalidates* rather than sharing the wrong data.
- Discard it on theme change (watch `data-theme` with a MutationObserver) —
  the card is painted from theme tokens, so a flip would leave a daylight
  picture armed on a night page.

Warm your capture library on `onPointerDown`, not on click: the activation
clock starts when the finger *lifts*, so a `void import("your-capture-lib")`
on press is free.

## Telling a dismissed share from a failed one

**Never infer the outcome from the error name alone.**

| Symptom | What actually happened |
| --- | --- |
| `NotAllowedError` | Activation was dead. The picture is fine — arm and re-offer. |
| `AbortError`, message not matching /read\|file/ | The person closed the sheet. Not a fault; say nothing. |
| `AbortError`, message matching /read\|file/ | The payload read failed. This IS a problem. |

WebKit reports **both** a dismissed sheet and a failed one as `AbortError`,
separated only by the message text. Collapsing them makes a shrug and a
failed payload read indistinguishable — and both silent.

**Every non-share path saves the file and says which happened.** A generic
catch that shows one error toast discards a picture the phone just spent
seconds making. Reserve "couldn't create the image" for the only case it is
true; "the sheet didn't open, so it's saved to your files" covers the rest.
A dismissal after arming keeps the picture armed, so changing your mind is
instant and free.

## Downloads: the anchor rules

Two paths, one shared rule.

- **The PNG download**: put a `data:` URL directly on the anchor's `href`.
  The tempting alternative — blob + object URL + immediate revoke — races
  the revoke against the click and fails outside Chrome.
- **A file export** should be a **real `fetch`**, not a bare `<a download>`
  to the API: a fetch gives the button something to be busy *for* (spinner),
  and a failure surfaces as a message instead of the browser rendering the
  API's error page over the app. That path legitimately uses
  `URL.createObjectURL(blob)` — revoke it on the **next tick**
  (`setTimeout(…, 0)`), after the browser has taken the URL — and reads the
  filename off `Content-Disposition` rather than guessing.
- **The rule both obey: attach the anchor to the document before `click()`,
  remove it after.** Firefox ignores a click on an anchor that is not in the
  document — the classic "the button does nothing, only on Firefox" bug.
- The spinner must occupy exactly the box of the icon it replaces, so a
  round icon button never changes size when it starts working.

## iOS is all WebKit — including "Chrome"

**Chrome for iOS reports `CriOS`, not `Chrome`**, and runs WebKit. Any UA
gate written as `includes("Chrome")` sends every iOS browser down the Safari
path (or fails to) — so "only Safari does this" is false for every browser
on iOS. Do not reason about iOS share/capture bugs as if Chrome there were
Chromium.

DOM-to-image libraries carry Safari-specific workarounds (Safari can paint a
`foreignObject` before its embedded `data:` images have decoded, producing
blank or half-drawn output). These workarounds are often slow — e.g. a full
canvas redraw per embedded image on a timer. **Leave them on.** Disabling
one trades a diagnosed bug for an undiagnosed one; with the two-tap arm
structure above, correctness does not depend on the capture being fast. If
you revisit capture speed, do it on its own merits with a measured
before-and-after on a real iPhone.

## Toasts and panels near the trigger

Position a confirmation toast/panel from the trigger's **measured viewport
rect**, in the same render that sets its text — never a static
`absolute end-0 w-<n>` offset. On phones, toolbars wrap their controls onto
a left-aligned row, which puts an end-anchored panel at a negative inline
offset — off the world, unscrollable, and reading as "the share failed
silently".

And **do not reach for `position: fixed` to get viewport clamping for
free**: any ancestor with a container query or a retained transform becomes
the containing block for a fixed child, so half your callers get placed
against a box that is not the screen. Absolute inside the trigger, offset by
numbers derived from the trigger's own `getBoundingClientRect()`, is true
everywhere — and direction-agnostic by construction, since a physical left
offset needs no RTL branch.
