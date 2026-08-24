#!/usr/bin/env bash
# build-index.sh — compile library/{skills,agents,commands,stacks} into library/index.json,
# the lookup table the skill router matches queries against at runtime.
#
# Run this after ANY library change (it is a build step, not a hook — it is allowed to be
# slow; it is the only script here that reads every library file). Output is deterministic:
# entries and keywords are sorted, nothing is timestamped, so it diffs cleanly in git.
#
# Shell stays thin on purpose: frontmatter parsing, tokenization and JSON belong in python3.
# The TOKENIZER VERSION below is a contract with sync/router-lib.sh — if you change how
# tokens are produced, bump it in BOTH files or the router will refuse to use the index.
set -eu
set -o pipefail 2>/dev/null || true

SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAVEN_ROOT="$(cd "$SYNC_DIR/.." && pwd)"
LIB_DIR="${1:-$RAVEN_ROOT/library}"
OUT="${2:-$LIB_DIR/index.json}"

[ -d "$LIB_DIR" ] || { echo "build-index: no library dir at $LIB_DIR" >&2; exit 1; }

# Fail loudly rather than emit an empty index: a silently missing python3 would leave the
# router matching against nothing, which looks exactly like "no skill was relevant".
PY="$(command -v python3 2>/dev/null || true)"
[ -n "$PY" ] || { echo "build-index: python3 not found in PATH — cannot build index" >&2; exit 1; }

"$PY" - "$LIB_DIR" "$OUT" <<'PY'
import json, os, re, sys

LIB, OUT = sys.argv[1], sys.argv[2]
TOKENIZER = "v1"   # keep in sync with sync/router-lib.sh

# ---------------------------------------------------------------- frontmatter

BLOCK = re.compile(r'^([A-Za-z_][A-Za-z0-9_-]*):\s*([|>][-+]?)\s*$')
PLAIN = re.compile(r'^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$')


def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v


def frontmatter(path):
    """Minimal YAML-scalar reader: top-level `key: value` plus |/> block scalars.

    Deliberately not a YAML parser — library frontmatter is strict and flat, and pulling in
    PyYAML would make a build step depend on a package that may not be installed.
    Returns {} when the file does not open with a `---` fence.
    """
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            lines = fh.read().split("\n")
    except OSError as e:
        print("build-index: cannot read %s (%s)" % (path, e), file=sys.stderr)
        return {}
    if not lines or lines[0].strip() != "---":
        return {}
    out, i, n = {}, 1, len(lines)
    while i < n:
        line = lines[i]
        if line.strip() == "---":
            break
        m = BLOCK.match(line)
        if m:
            key, style = m.group(1), m.group(2)
            i += 1
            buf = []
            while i < n and lines[i].strip() != "---":
                if lines[i].strip() and not lines[i][:1].isspace():
                    break                      # dedented back to a new key
                buf.append(lines[i].strip())
                i += 1
            if style.startswith("|"):
                out[key] = "\n".join(buf).strip()
            else:                               # folded: blank line = paragraph break
                folded, para = [], []
                for b in buf:
                    if b:
                        para.append(b)
                    elif para:
                        folded.append(" ".join(para))
                        para = []
                if para:
                    folded.append(" ".join(para))
                out[key] = "\n".join(folded).strip()
            continue
        m = PLAIN.match(line)
        if m:
            out[m.group(1)] = unquote(m.group(2))
        i += 1
    return out


# ---------------------------------------------------------------- tokenizer v1
# MUST stay byte-identical to the copy in sync/router-lib.sh.

STOP = set("""
a an and are as at be been being but by can could do does doing done for from get gets had has
have having how i if in into is it its it's may might must no nor not of off on once only or
other our out over own per shall should so some such than that the their theirs them then there
these they this those through to too under until up upon very was we were what when whenever
where whether which while who whom why will with within without would you your yours
also always any because been before both during each either else ever every few here just least
less like made make making many more most much need needs new now often one two three
same see seen still take takes taken thing things time times use used uses using way ways
work worked working works
invoke invoked invokes trigger triggers triggered call calls called run runs running
skill skills agent agents command commands module modules stage step steps standalone
""".split())

KEEP_SHORT = set(["go", "ui", "ux", "db", "js", "ts", "qa", "ci", "cd", "ai", "id", "os", "e2e"])
SPLIT = re.compile(r'[^a-z0-9._+#/-]+')
TRIM = "._-/+#"


def _emit(tok, out):
    tok = tok.strip(TRIM)
    if not tok or tok.isdigit():
        return
    if len(tok) < 2:
        return
    if len(tok) == 2 and tok not in KEEP_SHORT:
        return
    if tok in STOP:
        return
    out.append(tok)


def tokenize(text):
    """Lowercase -> split -> keep technical compounds whole AND split into parts.

    'next.js' yields next.js/next/js; 'app-router' yields app-router/app/router; 'i18n' and
    'oauth' survive intact. Stopwords and bare numbers are dropped.
    """
    out = []
    for raw in SPLIT.split((text or "").lower()):
        if not raw:
            continue
        _emit(raw, out)
        if any(c in raw for c in "._-/"):
            for part in re.split(r'[._\-/]+', raw):
                _emit(part, out)
    return out


# ---------------------------------------------------------------- walk

def rel(p):
    return os.path.relpath(p, LIB)


def collect():
    found = []
    sk = os.path.join(LIB, "skills")
    if os.path.isdir(sk):
        for root, dirs, files in os.walk(sk):
            dirs.sort()
            if "SKILL.md" in files:
                found.append(("skill", os.path.join(root, "SKILL.md")))
    for kind, sub in (("agent", "agents"), ("command", "commands"), ("stack", "stacks"), ("guardrail", "guardrails")):
        d = os.path.join(LIB, sub)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.endswith(".md") and f != "README.md":
                found.append((kind, os.path.join(d, f)))
    return found


entries, skipped = [], 0
for kind, path in collect():
    fm = frontmatter(path)
    if not fm:
        print("build-index: SKIPPED (no frontmatter): %s" % rel(path), file=sys.stderr)
        skipped += 1
        continue
    name = fm.get("name", "").strip()
    if not name:
        # fall back to the directory (skills) or file stem so the entry stays addressable
        base = os.path.dirname(path) if os.path.basename(path) == "SKILL.md" else path
        name = os.path.splitext(os.path.basename(base))[0]
        print("build-index: no name: in %s — using %r" % (rel(path), name), file=sys.stderr)
    desc = " ".join((fm.get("description") or "").split())
    act = " ".join((fm.get("activation") or "").split())
    if not desc:
        print("build-index: WARNING no description: %s" % rel(path), file=sys.stderr)
    kws = sorted(set(tokenize(name) + tokenize(desc) + tokenize(act)))
    # Curated retrieval vocabulary. `keywords:` in frontmatter is a router-only field —
    # Claude Code ignores unknown keys, so it costs nothing in the skill listing, and it
    # lets an item be findable by the words a person actually types without bloating the
    # description that competes for the listing budget. Weighted higher than incidental
    # prose at match time, because it is deliberate rather than accidental.
    raw_kw = fm.get("keywords")
    if isinstance(raw_kw, str):
        raw_kw = [k for k in re.split(r"[,;]+", raw_kw)]
    boost = sorted(set(t for k in (raw_kw or []) for t in tokenize(str(k))))
    entries.append({
        "kind": kind,
        "name": name,
        "path": rel(path),
        "description": desc,
        "keywords": kws,
        "boost": boost,
    })

if not entries:
    # An empty walk means a wrong path or a broken parse, never a real library. Writing the
    # empty result would silently disable the router with a green exit code — the worst
    # possible failure for something that guards discoverability.
    sys.exit("build-index: refusing to write an empty index (found no parseable modules under %s)" % LIB)

entries.sort(key=lambda e: (e["kind"], e["name"], e["path"]))
doc = {"version": 1, "tokenizer": TOKENIZER, "entries": entries}

tmp = OUT + ".tmp.%d" % os.getpid()
os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, ensure_ascii=False, indent=1, sort_keys=False)
    fh.write("\n")
os.replace(tmp, OUT)

vocab = set()
for e in entries:
    vocab.update(e["keywords"])
print("build-index: %d entries, %d distinct keywords -> %s%s"
      % (len(entries), len(vocab), OUT,
         (" (%d skipped)" % skipped) if skipped else ""), file=sys.stderr)
PY
