#!/bin/bash
# validate-library.sh — mechanical contract validator for library/.
#
# The library is a contract with a machine: the harness reads the frontmatter, not
# the prose. A key that is spelled wrong does not error — it is silently ignored,
# and the file keeps working in the demo while doing the opposite of what it says.
# This script is the only thing standing between "it parses" and "it means what we
# think it means". It checks what is mechanically checkable and stays quiet about
# what is not.
#
#   sync/validate-library.sh            full report
#   sync/validate-library.sh --quiet    violations only, nothing on success (CI)
#   sync/validate-library.sh --all      do not truncate the advisory lists
#   sync/validate-library.sh --root DIR validate another checkout
#
# Exit: 0 = contract holds (warnings allowed) · 1 = violations · 2 = cannot run.
#
# Runtime is ~160ms over 117 files, most of it one python3 interpreter start. That
# brushes the 150ms budget the hook scripts hold themselves to, and is fine here:
# this is NOT a hook. It runs on demand and in CI, never on a keystroke batch. One
# python3 process doing every check beats a dozen shell-outs that are each cheaper.
#
# macOS bash 3.2 compatible. No network, no git, no writes.

set -u

SCRIPT_NAME="$(basename "$0")"
SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAVEN_ROOT="$(cd "$SYNC_DIR/.." && pwd)"

usage() {
  cat <<USAGE
$SCRIPT_NAME — validate the curated library against its mechanical contract.

usage: $SCRIPT_NAME [--quiet] [--all] [--root <collection-dir>]

  -q, --quiet   print only violations; print nothing at all when the contract
                holds. Warnings are counted but not listed. For CI.
  -a, --all     list every advisory item instead of the worst few
      --root    validate the collection rooted at <collection-dir> instead of
                $RAVEN_ROOT
  -h, --help    this text

exit 0 = contract holds · 1 = violations found · 2 = could not run the checks
USAGE
}

QUIET=0
SHOW_ALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    -q|--quiet) QUIET=1 ;;
    -a|--all)   SHOW_ALL=1 ;;
    -h|--help)  usage; exit 0 ;;
    --root)
      shift
      [ $# -gt 0 ] || { printf '%s: --root needs a directory\n' "$SCRIPT_NAME" >&2; exit 2; }
      RAVEN_ROOT="$(cd "$1" 2>/dev/null && pwd)" || {
        printf '%s: --root: no such directory: %s\n' "$SCRIPT_NAME" "$1" >&2; exit 2; }
      ;;
    *)
      printf '%s: unknown argument: %s\n' "$SCRIPT_NAME" "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

LIB_ROOT="$RAVEN_ROOT/library"
[ -d "$LIB_ROOT" ] || {
  printf '%s: FATAL no library/ under %s\n' "$SCRIPT_NAME" "$RAVEN_ROOT" >&2
  exit 2
}

# Hard dependency, checked loudly. "Frontmatter parses as strict YAML" is only a
# real check if a real YAML parser makes it — a regex that approximates YAML would
# pass exactly the files this script exists to catch. Missing tool => exit 2
# (cannot run), never exit 0 (looks like a pass).
PY="${PYTHON:-python3}"
command -v "$PY" >/dev/null 2>&1 || {
  printf '%s: FATAL %s not found — cannot parse YAML, refusing to report a pass.\n' "$SCRIPT_NAME" "$PY" >&2
  exit 2
}
"$PY" -c 'import yaml' >/dev/null 2>&1 || {
  printf '%s: FATAL PyYAML not importable by %s — cannot parse YAML, refusing to report a pass.\n' "$SCRIPT_NAME" "$PY" >&2
  printf '%s: install it with: %s -m pip install --user pyyaml\n' "$SCRIPT_NAME" "$PY" >&2
  exit 2
}

# The optional private-name deny list. Absent is normal and is reported as a
# skipped check, never as a pass — see the NOTE the report prints.
PRIVATE_NAMES="$SYNC_DIR/private-names.txt"

VL_LIB="$LIB_ROOT" VL_SYNC="$SYNC_DIR" VL_PRIVATE="$PRIVATE_NAMES" VL_QUIET="$QUIET" \
VL_ALL="$SHOW_ALL" "$PY" - <<'PYEOF'
import os
import re
import sys
import warnings as pywarnings

import yaml


def _crash(exc_type, exc, tb):
    """An internal error must never be mistaken for a verdict.

    Exit 1 means "violations found" and exit 0 means "the contract holds"; a
    traceback means neither, so it exits 2 like any other could-not-run.
    """
    import traceback
    traceback.print_exception(exc_type, exc, tb)
    sys.stderr.write(
        "validate-library: FATAL internal error — the checks did not complete, "
        "this is NOT a pass\n")
    sys.stderr.flush()
    os._exit(2)


sys.excepthook = _crash

LIB = os.environ["VL_LIB"]
SYNC = os.environ["VL_SYNC"]
PRIVATE_NAMES = os.environ["VL_PRIVATE"]
QUIET = os.environ["VL_QUIET"] == "1"
SHOW_ALL = os.environ["VL_ALL"] == "1"
ADVISORY_HEAD = 12   # advisory lists are truncated to the worst N unless --all

# Verified in the binary: skillListingMaxDescChars = 1536 is the hard per-skill cap.
DESC_HARD_CAP = 1536
DESC_WARN_AT = 300

# The tool names the harness actually recognises. An unrecognised name is not an
# error the harness reports — it is silently dropped from the grant, which is how
# `Agent` instead of `Task` ships a fan-out agent that cannot fan out.
KNOWN_TOOLS = {
    "Read", "Write", "Edit", "MultiEdit", "NotebookEdit", "Grep", "Glob", "Bash",
    "BashOutput", "KillShell", "Task", "TodoWrite", "WebFetch", "WebSearch",
    "SlashCommand", "Skill", "AskUserQuestion",
}

# Files with no module contract to keep. Everything else under library/ that is
# markdown must carry frontmatter with context_cost + activation.
#   README.md              — the manifest itself
#   GLOBAL_PREFERENCES.md  — the inherited contract, not a loadable module
#   settings.template.json — a settings baseline
#   HANDOFF_TEMPLATE.md    — its frontmatter IS the capsule schema
#   CURATION.md            — an append-only record; nothing ever loads it
# (this list mirrors library/README.md § "Context-budget strategy", rule 5 — which
# still names only the first four. Rule 5 needs CURATION.md added to it; until then
# this list is deliberately the wider of the two rather than failing a record file
# for lacking a loader budget it will never use.)
CONTRACT_EXEMPT = {
    "README.md",
    "CURATION.md",
    "GLOBAL_PREFERENCES.md",
    "settings.template.json",
    "handoff/HANDOFF_TEMPLATE.md",
    "guardrails/secret-patterns.txt",
}

VENDORED_PREFIX = "skills/design/"

errors = []      # (rel, line, message)
warns = []       # (rel, line, message)
notes = []       # free-form strings


def add(bucket, rel, line, msg):
    bucket.append((rel, line, msg))


class StrictLoader(yaml.SafeLoader):
    """SafeLoader that refuses duplicate mapping keys.

    Plain safe_load accepts `tools:` twice and silently keeps the last one, so a
    file can declare a narrow tool grant, be overridden three lines later, and
    still 'parse fine'. Strict YAML rejects that; so do we.
    """


def _no_duplicates(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.constructor.ConstructorError(
                None, None,
                "duplicate key %r in frontmatter mapping" % (key,),
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


StrictLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_duplicates
)


def walk_files(root):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d != ".git")
        for fn in sorted(filenames):
            if fn == ".DS_Store":
                continue
            out.append(os.path.relpath(os.path.join(dirpath, fn), root))
    return sorted(out)


def read_text(rel):
    try:
        with open(os.path.join(LIB, rel), encoding="utf-8") as fh:
            return fh.read()
    except UnicodeDecodeError:
        # Skipping an unreadable file would silently drop every check on it and still
        # report a pass — the exact shape of failure this script exists to prevent.
        add(errors, rel, 1, "not valid UTF-8 — cannot be checked, so it cannot be trusted")
        return None
    except OSError as exc:
        add(errors, rel, 1, "unreadable: %s" % exc)
        return None


def key_line(lines, key):
    """1-indexed line of a top-level frontmatter key, or 1 if not found."""
    pat = re.compile(r"^%s\s*:" % re.escape(key))
    for i, ln in enumerate(lines, start=1):
        if pat.match(ln):
            return i
    return 1


def classify(rel):
    """Return (kind, contract_required)."""
    if rel in CONTRACT_EXEMPT:
        return ("exempt", False)
    if rel.startswith(VENDORED_PREFIX):
        if rel.endswith("/MANIFEST.md") or rel.endswith("/ATTRIBUTION.md"):
            return ("design-doc", rel.endswith("/MANIFEST.md"))
        if rel.endswith("/SKILL.md"):
            return ("vendored-skill", False)
        return ("vendored-asset", False)
    if rel.startswith("agents/") and rel.endswith(".md"):
        return ("agent", True)
    if rel.startswith("guardrails/") and rel.endswith(".md"):
        # guardrails register as agents; they carry `tools:`, never `allowed-tools:`
        return ("agent", True)
    if rel.startswith("commands/") and rel.endswith(".md"):
        return ("command", True)
    if rel.startswith("stacks/") and rel.endswith(".md"):
        return ("stack", True)
    if rel.startswith("skills/") and rel.endswith("/SKILL.md"):
        return ("skill", True)
    if rel.startswith("skills/"):
        return ("skill-asset", False)
    if rel.startswith("hooks/scripts/"):
        return ("hook-script", False)
    if rel.endswith(".md"):
        # INSTALL_PROMPT.md, hooks/README.md, handoff/README.md — loadable docs
        return ("doc-module", True)
    return ("other", False)


def parse_frontmatter(rel, text):
    """Return (dict|None, lines). Records its own errors."""
    lines = text.split("\n")
    if not lines or lines[0].rstrip() != "---":
        return (None, lines)
    end = None
    for i in range(1, len(lines)):
        if lines[i].rstrip() == "---":
            end = i
            break
    if end is None:
        add(errors, rel, 1,
            "frontmatter opens with `---` but never closes — add a closing `---`")
        return (None, lines)
    block = "\n".join(lines[1:end])
    try:
        data = yaml.load(block, Loader=StrictLoader)
    except yaml.YAMLError as exc:
        mark = getattr(exc, "problem_mark", None)
        line = (mark.line + 2) if mark is not None else 1
        problem = getattr(exc, "problem", None) or str(exc).split("\n")[0]
        add(errors, rel, line,
            "frontmatter is not strict YAML: %s — fix the YAML (quote values "
            "containing `:` or `#`, use `>-` for multi-line prose)" % problem)
        return (None, lines)
    if data is None:
        add(errors, rel, 1, "frontmatter block is empty")
        return (None, lines)
    if not isinstance(data, dict):
        add(errors, rel, 1,
            "frontmatter must be a YAML mapping, got %s" % type(data).__name__)
        return (None, lines)
    return (data, lines)


def tool_list(value):
    if isinstance(value, list):
        return [str(v).strip() for v in value if str(v).strip()]
    return [p.strip() for p in str(value).split(",") if p.strip()]


# ---------------------------------------------------------------- the checks --

all_files = walk_files(LIB)
skill_desc = []        # (rel, name, chars) for the listing budget report
vendored_desc = []
modules_checked = 0
long_desc = []         # (chars, rel) for the grouped >300 report

for rel in all_files:
    kind, contract = classify(rel)
    if not rel.endswith(".md"):
        continue
    text = read_text(rel)
    if text is None:
        continue
    data, lines = parse_frontmatter(rel, text)

    if data is None:
        # parse_frontmatter already reported a precise YAML error when there was
        # one; only the "no frontmatter at all" case needs a message here.
        if contract and not lines[0].rstrip() == "---":
            add(errors, rel, 1,
                "%s has no frontmatter — every loadable module needs a `---` YAML "
                "block with at least name, description, context_cost, activation"
                % kind)
        continue

    if contract:
        modules_checked += 1

    name = data.get("name")
    desc = data.get("description")

    # --- the bug that has shipped twice -------------------------------------
    has_tools = "tools" in data
    has_allowed = "allowed-tools" in data
    if kind == "agent":
        if has_allowed:
            add(errors, rel, key_line(lines, "allowed-tools"),
                "AGENT declares `allowed-tools:` — agents are read via `tools:`. "
                "The harness ignores `allowed-tools:` here, so this agent's tool "
                "restriction is not in force. Rename the key to `tools:`.")
        if not has_tools:
            add(errors, rel, 1,
                "AGENT declares no `tools:` — an agent without a tool list "
                "inherits the full tool set. Add an explicit `tools:` line.")
    elif kind == "command":
        if has_tools:
            add(errors, rel, key_line(lines, "tools"),
                "COMMAND declares `tools:` — commands are read via "
                "`allowed-tools:`. A bare `tools:` key parses fine and is "
                "silently ignored, leaving the command with full tool access. "
                "Rename the key to `allowed-tools:`.")
        if not has_allowed:
            add(errors, rel, 1,
                "COMMAND declares no `allowed-tools:` — the command runs "
                "unrestricted. Add an explicit `allowed-tools:` line.")

    for key in ("tools", "allowed-tools"):
        if key not in data:
            continue
        for tool in tool_list(data[key]):
            base = tool.split("(")[0].strip()
            if base and base not in KNOWN_TOOLS:
                add(warns, rel, key_line(lines, key),
                    "unknown tool name %r in `%s:` — the harness drops names it "
                    "does not recognise (the subagent fan-out tool is `Task`)"
                    % (tool, key))

    # --- loader budget contract ---------------------------------------------
    if contract:
        cc = data.get("context_cost")
        if cc is None:
            add(errors, rel, 1,
                "missing `context_cost:` — a loader cannot budget this module. "
                "Add `context_cost: low|medium|high`.")
        elif cc not in ("low", "medium", "high"):
            add(errors, rel, key_line(lines, "context_cost"),
                "`context_cost: %r` is not in the enum {low, medium, high}" % (cc,))

        act = data.get("activation")
        if act is None:
            add(errors, rel, 1,
                "missing `activation:` — without a trigger condition this module "
                "either never loads or always loads. Add a one-line condition.")
        elif not str(act).strip():
            add(errors, rel, key_line(lines, "activation"),
                "`activation:` is empty — state the condition that loads this module")

        if not name or not str(name).strip():
            add(errors, rel, 1, "missing `name:`")
        if not desc or not str(desc).strip():
            add(errors, rel, 1,
                "missing `description:` — this is the text the model routes on")

    # --- description budget --------------------------------------------------
    if desc is not None:
        n = len(str(desc))
        if n > DESC_HARD_CAP:
            add(errors, rel, key_line(lines, "description"),
                "description is %d chars, over the verified hard cap of %d — it "
                "will be truncated. Cut it to the trigger conditions."
                % (n, DESC_HARD_CAP))
        elif n > DESC_WARN_AT and kind != "vendored-skill":
            long_desc.append((n, rel))
        if kind == "skill":
            skill_desc.append((rel, str(name or ""), n))
        elif kind == "vendored-skill":
            vendored_desc.append((rel, str(name or ""), n))

    # --- name/path agreement -------------------------------------------------
    if name is not None and str(name).strip():
        nm = str(name).strip()
        if kind == "skill":
            dirname = os.path.basename(os.path.dirname(rel))
            if nm != dirname:
                add(errors, rel, key_line(lines, "name"),
                    "SKILL name %r does not match its directory %r — the skill is "
                    "addressed by directory, so the two must agree. Rename one."
                    % (nm, dirname))
        elif kind == "vendored-skill":
            dirname = os.path.basename(os.path.dirname(rel))
            if nm != dirname:
                notes.append(
                    "%s: vendored skill self-names %r while its directory is %r. "
                    "Vendored files are unmodified upstream copies, so this is "
                    "not a violation — it must stay documented as an alias in "
                    "skills/design/MANIFEST.md, which it is."
                    % (rel, nm, dirname))
        elif kind in ("agent", "command", "stack"):
            stem = os.path.basename(rel)[:-3]
            if nm != stem:
                add(warns, rel, key_line(lines, "name"),
                    "`name: %s` does not match the filename stem %r — the manifest "
                    "and the routing table both address it by stem" % (nm, stem))

# --- every skill directory has a SKILL.md ------------------------------------
skills_root = os.path.join(LIB, "skills")
if os.path.isdir(skills_root):
    for entry in sorted(os.listdir(skills_root)):
        path = os.path.join(skills_root, entry)
        if not os.path.isdir(path):
            continue
        subdirs = [entry] if entry != "design" else [
            os.path.join("design", d) for d in sorted(os.listdir(path))
            if os.path.isdir(os.path.join(path, d))
        ]
        for sd in subdirs:
            skill_md = os.path.join(skills_root, sd, "SKILL.md")
            if not os.path.isfile(skill_md):
                add(errors, "skills/%s/" % sd, 1,
                    "skill directory has no SKILL.md — a skill directory without "
                    "one is invisible to the harness. Add it or delete the directory.")

# --- private / client names --------------------------------------------------
# Honest scope: this is a deny-list check, not a detector. There is no reliable
# way to spot "a client name" in prose — a capitalised multi-word token that
# appears nowhere else is just as likely to be a product this library legitimately
# names (Paddle, RevenueCat, Sentry). So the check knows exactly what it is told
# and says so when it is told nothing.
private_terms = []
private_status = ""
if os.path.isfile(PRIVATE_NAMES):
    with open(PRIVATE_NAMES, encoding="utf-8") as fh:
        for raw in fh:
            term = raw.strip()
            if not term or term.startswith("#"):
                continue
            private_terms.append(term)
    private_status = "deny list: %s (%d term%s)" % (
        PRIVATE_NAMES, len(private_terms), "" if len(private_terms) == 1 else "s")
else:
    private_status = (
        "NOT CONFIGURED — no %s, so no project/client name was checked for. "
        "This check finds only what it is told to find. To arm it, create that "
        "file with one term per line (`#` comments allowed, `re:` prefix for a "
        "raw regex) and keep it out of git." % PRIVATE_NAMES)

if private_terms:
    compiled = []
    for term in private_terms:
        try:
            with pywarnings.catch_warnings():
                # A malformed `re:` entry must not leak an interpreter warning into
                # the report — it becomes a NOTE like any other bad input.
                pywarnings.simplefilter("error")
                if term.startswith("re:"):
                    compiled.append((term, re.compile(term[3:], re.IGNORECASE)))
                else:
                    compiled.append(
                        (term,
                         re.compile(
                             r"(?<![A-Za-z0-9])%s(?![A-Za-z0-9])" % re.escape(term),
                             re.IGNORECASE)))
        except (re.error, FutureWarning, DeprecationWarning) as exc:
            notes.append(
                "private-names.txt: term %r skipped — %s. `re:` entries are Python "
                "regex syntax (no POSIX [[:class:]])." % (term, exc))
    # Hits are collapsed per (file, term): a stack module that legitimately names a
    # vendor 15 times should produce one finding to judge, not 15 identical lines.
    for rel in all_files:
        text = read_text(rel)
        if text is None:
            continue
        seen = {}
        for lineno, line in enumerate(text.split("\n"), start=1):
            for term, rx in compiled:
                if rx.search(line):
                    if term not in seen:
                        seen[term] = [lineno, 0]
                    seen[term][1] += 1
        term_order = dict((term, i + 1) for i, (term, _rx) in enumerate(compiled))
        for term in sorted(seen):
            term_index = term_order.get(term, 0)
            first, count = seen[term]
            more = "" if count == 1 else " (+%d more line%s in this file)" % (
                count - 1, "" if count == 2 else "s")
            # The matched line is not echoed: this report gets pasted into issues
            # and logs, and re-printing the term is the leak the check prevents.
            # The term itself is NOT printed: this report gets pasted into issues and
            # chat logs, and echoing the protected name is precisely the leak the deny
            # list exists to prevent. The line number is enough to find it locally.
            add(errors, rel, first,
                "private-name deny list hit (entry #%d, %d chars)%s — the library holds "
                "no project-specific data. Generalize it, or move the file back to its "
                "home project." % (term_index, len(term), more))

# --- manifest agreement ------------------------------------------------------
# library/README.md is authoritative: "a file not listed here does not exist".
# Two directions, checked at different strictness, both honestly labelled:
#   (a) every relative link in the manifest resolves — exact, no false positives;
#   (b) every file under library/ is mentioned somewhere in it — a substring /
#       word-boundary match on path, basename or stem. Loose by construction: a
#       generic stem (LICENSE) can match a sentence that is about something else.
#       It catches the case that matters (a file added and never listed).
manifest_rel = "README.md"
manifest_text = read_text(manifest_rel) or ""
if not manifest_text:
    add(errors, manifest_rel, 1, "manifest is missing or empty — library/README.md "
                                 "is authoritative and cannot be absent")

design_docs = ""
for extra in ("skills/design/ATTRIBUTION.md", "skills/design/MANIFEST.md"):
    if os.path.isfile(os.path.join(LIB, extra)):
        design_docs += read_text(extra) or ""

link_rx = re.compile(r"\]\(([^)\s]+)")


def check_links(doc_rel, doc_text):
    base = os.path.dirname(os.path.join(LIB, doc_rel))
    for m in link_rx.finditer(doc_text):
        target = m.group(1)
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        target = target.split("#")[0]
        if not target:
            continue
        resolved = os.path.normpath(os.path.join(base, target))
        if not os.path.exists(resolved):
            line = doc_text[:m.start()].count("\n") + 1
            add(errors, doc_rel, line,
                "links to %r which does not exist — fix the link or add the file"
                % target)


check_links(manifest_rel, manifest_text)
for extra in ("skills/design/ATTRIBUTION.md", "skills/design/MANIFEST.md"):
    if os.path.isfile(os.path.join(LIB, extra)):
        check_links(extra, read_text(extra) or "")


# Stems too common to be evidence of anything. A file whose ONLY match is one of
# these matched a sentence, not an inventory entry — reported as a soft finding
# rather than silently passed. (This is the honest limit of a substring check.)
GENERIC_STEMS = {
    "index", "readme", "license", "notes", "manifest", "template", "config",
    "settings", "main", "data", "schema", "types", "utils", "common",
}

loose_matches = []


def mentioned(candidate, haystack):
    """Return 'exact', 'stem' or None."""
    if candidate in haystack:
        return "exact"
    stem = os.path.splitext(os.path.basename(candidate))[0]
    if not stem:
        return None
    if re.search(r"(?<![\w/-])%s(?![\w-])" % re.escape(stem), haystack):
        return "stem"
    return None


for rel in all_files:
    if rel == manifest_rel:
        continue
    haystack = manifest_text
    if rel.startswith(VENDORED_PREFIX):
        # the vendored subtree delegates its inventory to ATTRIBUTION.md + MANIFEST.md
        haystack = manifest_text + design_docs
    candidates = [rel, os.path.basename(rel)]
    if os.path.basename(rel) == "SKILL.md":
        candidates.append(os.path.basename(os.path.dirname(rel)))
    hits = [(c, mentioned(c, haystack)) for c in candidates]
    hits = [(c, h) for c, h in hits if h]
    if not hits:
        add(errors, rel, 1,
            "not listed in library/README.md — the manifest is authoritative, so "
            "an unlisted file does not exist. Add it to the file index (and the "
            "routing table if it is invocable), or delete it.")
    elif all(h == "stem" for _, h in hits) and \
            os.path.splitext(os.path.basename(rel))[0].lower() in GENERIC_STEMS:
        loose_matches.append(rel)

# ------------------------------------------------------------------ report ---

def fmt(bucket, label):
    out = []
    for rel, line, msg in sorted(bucket):
        out.append("%s  library/%s:%d\n      %s" % (label, rel, line, msg))
    return out


lines_out = []
if not QUIET:
    lines_out.append("=== library contract validation ===")
    lines_out.append("root: %s" % LIB)

body = fmt(errors, "FAIL")
if not QUIET:
    body.extend(fmt(warns, "WARN"))
    if body:
        lines_out.append("")
lines_out.extend(body)

if not QUIET:
    if long_desc:
        ranked = sorted(long_desc, reverse=True)
        shown = ranked if SHOW_ALL else ranked[:ADVISORY_HEAD]
        lines_out.append("")
        lines_out.append(
            "ADVISORY  %d of %d descriptions run over %d chars (median %d). "
            "Routing text is read on every listing — trim toward the trigger "
            "condition. Not a violation; the hard cap is %d."
            % (len(long_desc), modules_checked, DESC_WARN_AT,
               ranked[len(ranked) // 2][0], DESC_HARD_CAP))
        for n, rel in shown:
            lines_out.append("        %5d  library/%s" % (n, rel))
        if len(ranked) > len(shown):
            lines_out.append("        … and %d more (--all to list every one)"
                             % (len(ranked) - len(shown)))
    if loose_matches:
        lines_out.append("")
        lines_out.append(
            "ADVISORY  %d file%s matched the manifest only by a generic stem — the "
            "coverage check is a substring match and cannot tell an inventory entry "
            "from a passing mention. Confirm each is really listed:"
            % (len(loose_matches), "" if len(loose_matches) == 1 else "s"))
        for rel in loose_matches:
            lines_out.append("        library/%s" % rel)
    if notes:
        lines_out.append("")
        for n in notes:
            lines_out.append("NOTE  %s" % n)

    # description budget — what actually competes for the skill listing
    total = sum(n for _, _, n in skill_desc)
    vtotal = sum(n for _, _, n in vendored_desc)
    lines_out.append("")
    lines_out.append("--- skill listing budget ---")
    if skill_desc:
        lines_out.append(
            "curated skills: %d · descriptions total %s chars · mean %d · max %d (%s)"
            % (len(skill_desc), "{:,}".format(total), total // len(skill_desc),
               max(n for _, _, n in skill_desc),
               max(skill_desc, key=lambda r: r[2])[0]))
    if vendored_desc:
        lines_out.append(
            "vendored skills: %d · descriptions total %s chars (unmodified upstream — "
            "not trimmable here)" % (len(vendored_desc), "{:,}".format(vtotal)))
    lines_out.append(
        "combined %s chars. Per-skill hard cap %d. The listing is what these compete "
        "for: a skill set to a hidden mode (name-only / user-invocable-only / off) "
        "costs zero listing budget." % ("{:,}".format(total + vtotal), DESC_HARD_CAP))
    lines_out.append("")
    lines_out.append("--- private-name check ---")
    lines_out.append(private_status)
    lines_out.append("")
    lines_out.append(
        "checked %d files · %d modules under the frontmatter contract · "
        "%d violation%s · %d warning%s · %d long-description advisor%s"
        % (len(all_files), modules_checked,
           len(errors), "" if len(errors) == 1 else "s",
           len(warns), "" if len(warns) == 1 else "s",
           len(long_desc), "y" if len(long_desc) == 1 else "ies"))

if errors:
    if QUIET:
        lines_out.append("FAILED: %d violation%s, %d warning%s in %s"
                         % (len(errors), "" if len(errors) == 1 else "s",
                            len(warns), "" if len(warns) == 1 else "s", LIB))
    else:
        lines_out.append("RESULT: FAIL")
elif not QUIET:
    lines_out.append("RESULT: OK — the contract holds")

if lines_out and (errors or not QUIET):
    sys.stdout.write("\n".join(lines_out) + "\n")

sys.exit(1 if errors else 0)
PYEOF
