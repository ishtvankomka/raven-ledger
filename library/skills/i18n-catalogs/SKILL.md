---
name: i18n-catalogs
description: Message-catalog mechanics for a multi-locale app — running the repo's own parity checker and reading its output, what missing vs extra keys actually mean, per-key vs per-file fallback, ICU argument and CLDR plural checks and their blind spots, the namespace-registry ↔ source-catalog invariants no checker sees, translation tooling that silently knows fewer locales than the app, semantic drift that passes every structural check, and the bundler cache that keeps serving old catalogs. Use when editing the source locale's catalogs, adding or deleting a namespace, adding a locale, translating copy, or when UI text shows up in the wrong language.
always_on: false
activation: "invoke when editing message catalogs, adding/removing a namespace or locale, translating copy, or when UI text renders in the wrong language"
context_cost: medium
---

# Message catalogs — many locales, one source of truth

**If a parity checker already exists in this repo, do not write another one.**

```bash
grep -rn "check-messages\|i18n-check\|check-translations" package.json scripts .github
```

The usual finding is that a real checker exists, is wired into no npm script, no
CI step and no hook, and that every past session therefore re-derived an ad-hoc
diff script — which is exactly why the drift below survived. Run the real one;
wire it up if you want it enforced. The `check-translations` command and the
`i18n-engineer` agent are the collection's generic tooling if the repo has
none; this skill is the mechanics both of them assume you know.

Catalog bugs are invisible to the build and to the type checker. Nothing
type-checks a JSON key path, and a missing key renders the source language
instead of throwing. A parity script is the only mechanical check there is —
and it still cannot see the last two sections of this file.

## Run the checker before anything else

Before editing, to know the baseline; after editing, to know what you changed.
Run it scoped to the locales you touched when you want a fast answer, and
unscoped when you want the baseline.

What a good checker verifies, and what each verdict means:

| Check | Verdict |
|---|---|
| Key present in a target locale but not in the source | ERROR — extra/dead key |
| Key present in the source but not in a target | MISS (ERROR under `--strict`) |
| Whole namespace file absent for a locale | MISS `whole file missing` |
| Locale file is not valid JSON | ERROR |
| ICU argument used by the source, dropped in translation | ERROR `drops args` |
| ICU argument invented by the translation | ERROR `invents args` |
| Plural message lacking the locale's CLDR categories | ERROR `plural lacks` |

**Required plural categories are per language, from CLDR**, not a global list:
Slavic languages typically need one/few/many/other; Arabic needs
zero/one/two/few/many/other, with zero and two reasonably forgiven when the
catalog uses `=0` / `=2` literals instead; most Western European languages need
one/other. Encode that table in the checker, not in reviewers' heads.

**Known blind spot worth stating in the source rather than "fixing":** ICU
argument comparison can only compare *typed* arguments (`{count, plural …}`)
once a message contains a plural or select, because branch output text reads as
an argument to a regex. Simple `{name}` arguments inside plural branches go
unchecked — eyeball those by hand.

## Reading the output: MISS vs ERROR vs --strict

```
MISS  <locale>/consent.json: whole file missing   ← fine at runtime, source language shows
ERROR <locale>/footer.json: extra key footer.old  ← dead key, delete it
OK    <locale>: complete
OK    <locale>: valid (3 fallbacks)
```

- **ERROR always exits 1.** Extra keys, bad JSON, dropped arguments, missing
  plural categories. Fix these before committing.
- **MISS exits 0 on purpose.** A missing key is a *designed* state — it falls
  back to the source language, so a half-translated locale is shipping
  software, not a broken build. Plain runs still report it, so a complete
  locale can prove it is complete.
- **`--strict` promotes MISS to ERROR.** Use it to gate "this locale is done".

**If you wire the checker into CI, wire the plain form.** `--strict` fails the
build over every known-incomplete locale, which is a policy decision disguised
as a lint rule. And whatever the tree's current strict exit status is, **record
it as the baseline** — a gate that exits 1 on a clean tree teaches the next
reader to ignore it unless the expected line count is written down somewhere.

## Fallback is per KEY, not per file

When the loader deep-merges each translation over the source catalog, any key a
locale lacks renders its source string. This is what makes MISS survivable — and
also what makes drift silent: nothing crashes, nothing logs, the sentence is
just in the wrong language.

Per-*file* fallback is the tempting simplification and it is worse: a file that
exists but lags renders raw key paths (`artists.stats.liked`) in the UI. Keep
the merge at key granularity.

The user-visible consequence of accepting MISS is worth deciding deliberately
per namespace. A half-translated marketing page is fine. A **consent or
permission dialog rendering in the wrong language is not** — comprehension is
the entire point of that dialog, so finish those namespaces first even when the
checker calls them optional.

## The translation tooling may know fewer locales than the app

A translate workflow or agent script usually hardcodes its own locale list, with
names and registers attached:

```js
const ALL = [ /* …a subset of the app's locales… */ ];
```

Passing a locale it does not know does not fall through to a generic
translator — the argument filter drops it and the workflow throws *"no known
locales in args"*. That missing array entry is the most common direct cause of
long-lived drift in exactly the same handful of locales.

To translate them: extend the list with the code, the language name and the
register, update any count advertised in the tool's own description, or drive a
translation agent directly with the same prompt contract.

**Second trap in the same kind of file:** a hardcoded absolute `ROOT` path
pointing at the *main checkout*. Run the workflow from a worktree and its agents
write catalogs into the other tree — a mess that has to be recovered by hand.
Check `ROOT` before invoking anything that writes.

A **glossary** (coined product terms, per-language register, formatting rules)
is binding: when it and a translator's instinct disagree, change the glossary
first, then the catalogs. Keep formatting rules in it too — never hand-format
dates or numbers, and note per-language digit conventions.

## Two registry invariants the checker does not cover

The namespace list the loader iterates and the files in the source catalog
directory must be the same set. Neither half is derived from the other, so they
drift apart silently in two directions:

1. **Namespace listed, no source file.** The loader catches the failed dynamic
   import and returns `{}`. The source language then has no strings at all for
   that namespace and the UI renders raw key paths. A checker that globs the
   source directory never even looks — it cannot see a namespace that has no
   source file.
2. **Source file present, namespace not listed.** The loader only iterates the
   registry, so the file never loads at runtime — but the checker still demands
   every locale translate it. Every translator does real work on copy that can
   never render.

Check by hand after adding or deleting a namespace:

```bash
node -e '
const fs=require("fs");
const ns=fs.readFileSync("<registry-file>","utf8")
  .match(/NAMESPACES = \[([\s\S]*?)\] as const/)[1]
  .match(/"([^"]+)"/g).map(s=>s.slice(1,-1));
const f=fs.readdirSync("<source-catalog-dir>").filter(x=>x.endsWith(".json"))
  .map(x=>x.replace(/\.json$/,""));
console.log("listed but no source file:", ns.filter(n=>!f.includes(n)));
console.log("source file but not listed:", f.filter(x=>!ns.includes(x)));'
```

Related blind spot: a target-locale file with **no source counterpart at all**
is never inspected, because the checker iterates source files and only reaches
for the matching target. A stray `<locale>/ghost.json` sits there forever.

Adding a namespace = create the source file, add the name to the registry, then
translate. **One file per namespace per locale** exists so parallel translation
agents never touch the same file — keep it that way.

## Namespaces outlive their route

A namespace whose page directory is gone is not necessarily dead: retired pages
routinely have their blocks moved onto a summary page, and the copy is still
rendering from components. Keep a table of those in the repo, and grep before
deleting:

```bash
grep -rn 'useTranslations("<ns>")\|getTranslations("<ns>")' app components lib
```

Conversely, a feature's copy may live inside a *neighbour's* namespace (FAQ
answers inside the marketing catalog, for instance). Namespace names track
ownership of copy, not the route table.

## Semantic drift a checker can never see

**A valid key subset proves nothing about truth.** This is the failure mode that
actually reaches users, and no parity script will ever catch it.

The canonical case: every locale passes structurally while

- an FAQ answer in five languages promises **three write permissions** on the
  day the app dropped to one — a faithful translation of source copy from before
  the feature was removed;
- another answers *"do you store my data"* with the exact sentence the Privacy
  Policy exists to correct.

So: **when source copy changes meaning — permissions, retention, pricing, what a
feature does — retranslate the affected keys explicitly.** Do not assume an
untouched translation is still correct just because its key still exists. After
a product change, read the claim in **every** locale, not just the source:

```bash
python3 -c "
import json, glob
for f in sorted(glob.glob('messages/*/<namespace>.json')):
    print(f.split('/')[1], json.load(open(f))['<section>']['<key>'][:70])
"
```

That prints one line per locale — read them. Any locale claiming a capability
the app no longer has is a bug that ships as a lie about permissions, and it
ranks above every missing key in the same run.

## Deliberately untranslated surfaces

Legal text is commonly source-language-only by decision ("it stays English until
counsel says otherwise"). When it is, the exclusion must be stated in **three
places that agree**:

- the namespace registry (no entry, plus the comment saying why),
- the sitemap (an `englishOnly`-style flag, so no hreflang language map),
- the middleware/proxy (a path list that deletes the i18n library's `Link`
  response header).

The third exists because the framework can emit an hreflang map in a **response
header** that a page's own metadata cannot reach; a crawler receiving a bare
canonical from one channel and N editions from another believes the wrong one
about half the time. Never add these pages to a parity expectation, and never
machine-translate legal text.

Other permanent source-language strings usually include third-party proper
nouns, provider-supplied metadata, and attribution labels a locale may only
change to the provider's own published equivalent. List them in the glossary so
"equals the source string" stops being reported as untranslated.

## After editing catalogs: the cache ritual

Bundlers do not reliably invalidate catalog JSON when it enters the module graph
through a **template dynamic import**:

```ts
return (await import(`../messages/${locale}/${ns}.json`)).default;
```

The dependency edge the bundler tracks is that *context*, not your individual
file, so the dev server happily keeps serving the previous strings — and you
will "verify" a translation that is not what is on disk.

```bash
touch <the modules that own the dynamic import>   # nudges the context
# still stale?
rm -rf <the bundler cache dir>                    # then restart the dev server
```

Do this **before** trusting any browser verification of copy. If a string looks
untranslated, rule out the cache before concluding the catalog is wrong — and
rule it out before concluding the catalog is right.

Full verification pass after a catalog change:

```bash
<the repo's catalog checker>          # structural parity + ICU + plurals
<the repo's typecheck command>        # will NOT catch catalog bugs; run anyway
touch <the dynamic-import owners>
# then load a couple of localized routes and read the actual words
```
