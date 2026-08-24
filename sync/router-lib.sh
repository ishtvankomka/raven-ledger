#!/usr/bin/env bash
# router-lib.sh — sourceable retrieval for the skill router. No network, no embeddings,
# no LLM: keyword overlap with IDF weighting over library/index.json.
#
#   . /path/to/sync/router-lib.sh
#   router_match "<query text>" [index.json] [max-results]
#
# Echoes at most <max-results> lines of "kind<TAB>name<TAB>description", best first, and
# echoes NOTHING when nothing clears the relevance floor — which is the common case and the
# correct answer. Exit status is 0 whether or not there were matches (a hook sourcing this
# must not die on "no match"); 1 only on a real fault (missing index, missing python3),
# with one diagnostic line on stderr.
#
# Budget: ~20-45ms, dominated by python3 startup (measured: 19ms for a conda python3, 48ms
# for /usr/bin/python3, plus ~3ms to parse a 110KB index). That is the whole per-turn cost
# and it is why scoring stays in one process with no imports beyond json/re/math.
#
# The tokenizer below MUST stay byte-identical to the one in sync/build-index.sh. The
# index records which version built it; a mismatch fails loudly instead of silently
# scoring against tokens that were produced by different rules.

ROUTER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Where the index lives when the caller does not say. $ROUTER_INDEX is read at CALL time, not
# here, so a hook can point one sourced copy of this file at a different index per invocation.
ROUTER_INDEX_FALLBACK="$ROUTER_LIB_DIR/../library/index.json"

# Tuning knobs — override per call via the environment. Scores are normalized so that one
# term unique to a single entry is worth ~0.8 and a term in a fifth of the library ~0.2,
# regardless of how big the library grows; absolute IDF floors would drift as it does.
#   MIN_SCORE   floor when two or more query terms corroborate each other
#   SINGLE      floor when the whole match rests on ONE term (must be genuinely rare)
#   REL_CUT     drop anything below this fraction of the top hit
ROUTER_MIN_SCORE="${ROUTER_MIN_SCORE:-1.30}"
ROUTER_SINGLE="${ROUTER_SINGLE:-1.50}"
ROUTER_REL_CUT="${ROUTER_REL_CUT:-0.45}"

router_match() {
  local query="${1:-}" index="${2:-}" max="${3:-5}" py
  [ -n "$index" ] || index="${ROUTER_INDEX:-$ROUTER_INDEX_FALLBACK}"
  [ -n "$query" ] || return 0
  if [ ! -f "$index" ]; then
    echo "router_match: no index at $index (run sync/build-index.sh)" >&2
    return 1
  fi
  py="$(command -v python3 2>/dev/null || true)"
  if [ -z "$py" ]; then
    echo "router_match: python3 not found in PATH — router disabled" >&2
    return 1
  fi
  # Query goes through the environment, not argv: a user prompt is not something to leave
  # sitting in the process table for every other process on the box to read.
  ROUTER_QUERY="$query" \
  ROUTER_MIN_SCORE="$ROUTER_MIN_SCORE" \
  ROUTER_SINGLE="$ROUTER_SINGLE" \
  ROUTER_REL_CUT="$ROUTER_REL_CUT" \
  "$py" - "$index" "$max" <<'PY'
import json, math, os, re, sys

TOKENIZER = "v1"   # keep in sync with sync/build-index.sh

index_path, max_results = sys.argv[1], sys.argv[2]
try:
    max_results = max(1, int(max_results))
except ValueError:
    max_results = 5

try:
    with open(index_path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
except (OSError, ValueError) as e:
    print("router_match: unreadable index %s (%s)" % (index_path, e), file=sys.stderr)
    sys.exit(1)

if doc.get("tokenizer") != TOKENIZER:
    print("router_match: index tokenizer %r != router %r — rebuild with sync/build-index.sh"
          % (doc.get("tokenizer"), TOKENIZER), file=sys.stderr)
    sys.exit(1)

entries = doc.get("entries") or []
if not entries:
    sys.exit(0)

MIN_SCORE = float(os.environ.get("ROUTER_MIN_SCORE", "1.30"))
SINGLE = float(os.environ.get("ROUTER_SINGLE", "1.50"))
REL_CUT = float(os.environ.get("ROUTER_REL_CUT", "0.45"))

NAME_BOOST = 2.0      # a term that is part of the entry's own name counts more
CURATED_BOOST = 3.0   # a term the author listed in `keywords:` — deliberate intent, not prose
PREFIX_W = 0.55       # partial credit for deploy~deployment, bundle~bundler
NAME_HIT = 1.5        # the query literally said the entry's name
LEN_B = 0.30          # BM25-style length normalization; a 300-word description should not
                      # out-match a tight one just by covering more of the dictionary

# ---------------------------------------------------------------- tokenizer v1
# MUST stay byte-identical to the copy in sync/build-index.sh.

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
    out = []
    for raw in SPLIT.split((text or "").lower()):
        if not raw:
            continue
        _emit(raw, out)
        if any(c in raw for c in "._-/"):
            for part in re.split(r'[._\-/]+', raw):
                _emit(part, out)
    return out

# ---------------------------------------------------------------- stemming
# Crude and deliberate: plural collapse only. Anything cleverer (-ing/-ed/-ion) starts
# folding words that mean different things, and this has to be explainable when it misfires.


def stem(t):
    if len(t) > 4 and t.endswith("ies"):
        return t[:-3] + "y"
    if len(t) > 3 and t.endswith("s") and not t.endswith(("ss", "us", "is", "os")):
        return t[:-1]
    return t


# ---------------------------------------------------------------- index model

N = len(entries)
df = {}
docs = []
for e in entries:
    name_stems = set(stem(t) for t in tokenize(e.get("name", "")))
    # Curated `keywords:` outrank both the name and incidental prose: they are the words
    # the author decided a person would actually type for this item. Without them a term
    # that appears in five descriptions (say "translations") can never carry a match on
    # its own, because it is common in the index even though it is precise in intent.
    curated = set(stem(t) for t in (e.get("boost") or []))
    weights = {}
    for kw in list(e.get("keywords") or []) + list(e.get("boost") or []):
        s = stem(kw)
        if s in curated:
            w = CURATED_BOOST
        elif s in name_stems:
            w = NAME_BOOST
        else:
            w = 1.0
        if w > weights.get(s, 0.0):
            weights[s] = w
    for s in weights:
        df[s] = df.get(s, 0) + 1
    docs.append(weights)

# Normalize IDF into 0..1 against the rarest term the library could hold, so the floors
# below mean the same thing whether there are 86 entries or 400.
IDF_MAX = math.log((N + 1.0) / 0.5)
idf = dict((s, math.log((N + 1.0) / (d + 0.5)) / IDF_MAX) for s, d in df.items())

avg_len = float(sum(len(w) for w in docs)) / max(1, len(docs))
lnorm = [1.0 / (1.0 - LEN_B + LEN_B * (len(w) / avg_len)) if w else 0.0 for w in docs]

# Bucket the vocabulary by first letter so prefix matching does not scan the whole
# vocabulary per query token. Prefix relations always share a first letter — exact, not lossy.
# Compound tokens are excluded: build-index already emits their parts, and letting a generic
# word like "check" prefix-match the rare compound "check-locale-codes" would hand it that
# compound's rarity AND the name boost, which put four unrelated check-* commands into the
# results for "check that the google login works".
SEP = "._-/"
by_first = {}
for s in idf:
    if not any(c in s for c in SEP):
        by_first.setdefault(s[0], []).append(s)

query_raw = os.environ.get("ROUTER_QUERY", "")
q_stems = []
seen = set()
for t in tokenize(query_raw):
    s = stem(t)
    if s not in seen:
        seen.add(s)
        q_stems.append(s)
if not q_stems:
    sys.exit(0)

# For each query stem, the index stems it can match and at what discount.
cands = {}
for qs in q_stems:
    m = {qs: 1.0} if qs in idf else {}
    if len(qs) >= 5 and not any(c in qs for c in SEP):
        for s in by_first.get(qs[0], ()):
            if s == qs:
                continue
            if len(s) >= 5 and (s.startswith(qs) or qs.startswith(s)):
                if PREFIX_W > m.get(s, 0.0):
                    m[s] = PREFIX_W
    if m:
        cands[qs] = m

q_low = " " + " ".join(query_raw.lower().split()) + " "

results = []
for e, weights, ln in zip(entries, docs, lnorm):
    score, matched = 0.0, 0
    for qs, opts in cands.items():
        best = 0.0
        for s, disc in opts.items():
            w = weights.get(s)
            if w:
                v = idf[s] * w * disc
                if v > best:
                    best = v
        if best > 0.0:
            score += best
            matched += 1
    score *= ln
    name = (e.get("name") or "").lower()
    named = len(name) >= 5 and (name in q_low or name.replace("-", " ") in q_low)
    if named:
        score += NAME_HIT
    # A match resting on ONE term must be a term that is genuinely rare in the library;
    # two corroborating terms are allowed to be individually weaker. Anything below both
    # bars is noise, and noise is what makes a per-turn injection not worth paying for.
    if not named and score < (SINGLE if matched < 2 else MIN_SCORE):
        continue
    results.append((score, e, named))

if not results:
    sys.exit(0)

results.sort(key=lambda r: (-r[0], r[1]["kind"], r[1]["name"]))
top = results[0][0]
out = []
for score, e, named in results[:max_results]:
    if score < top * REL_CUT:
        break
    desc = " ".join((e.get("description") or "").split())
    out.append("%s\t%s\t%s" % (e.get("kind", "?"), e.get("name", "?"), desc))
if out:
    sys.stdout.write("\n".join(out) + "\n")
PY
  # python exits 0 for both "matches" and "no matches" (a no-match is a valid answer, not a
  # failure) and 1 only on a fault, so its status is already the function's contract.
}
