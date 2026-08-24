#!/usr/bin/env bash
# Stop hook — the session ledger.
#
# Appends ONE compact line per assistant turn to
# <cwd>/.claude/handoff/sessions/<date>-<session>.md:
# the files that turn touched and a one-line gist of what was decided. That is the
# breadcrumb trail /handoff distills into a capsule, and the thing that survives when
# a session dies, is compacted, or is abandoned without anyone running /handoff.
#
# It is a WORKING file, not a handoff: raw, unreviewed, bounded, and gitignored
# (.claude/handoff/ is already in the library's ignore set).
#
# Never blocks a stop — always exits 0, prints nothing. Fails OPEN on every error.
#
# Budget: two python3 processes (~13ms startup each) — one for the hook payload, one
# reading the last 1MB of the transcript — plus an append. Measured ~85ms end to end
# on the largest transcript on this machine (9MB). The full-file turn count that
# context_occupancy does is deliberately NOT done here: Stop cannot inject context,
# so there is nothing for a pressure reading to do at this event.
#
# macOS bash 3.2 compatible. No network, no LLM.

set -u

SL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SL_US=$'\037'   # unit separator — the field delimiter between python and bash
# shellcheck source=./handoff-lib.sh
. "$SL_DIR/handoff-lib.sh" || exit 0

# Cap the ledger, counted in ENTRIES (not file lines, so the header never eats into
# the budget and a small cap cannot trigger a re-trim on every append). 400 entries
# is far more than any single session produces; the cap exists so an all-day session
# or a stuck loop cannot grow an unbounded file in the user's repo. On overflow the
# header is rewritten and the newest 300 entries kept.
SL_KEEP_SESSIONS="${RAVEN_KEEP_SESSIONS:-25}"
case "$SL_KEEP_SESSIONS" in ''|*[!0-9]*) SL_KEEP_SESSIONS=25 ;; esac
SL_MAX_ENTRIES="${RAVEN_LEDGER_MAX_LINES:-400}"
case "$SL_MAX_ENTRIES" in ''|*[!0-9]*) SL_MAX_ENTRIES=400 ;; esac
[ "$SL_MAX_ENTRIES" -lt 20 ] && SL_MAX_ENTRIES=20
SL_KEEP_ENTRIES=$(( SL_MAX_ENTRIES * 3 / 4 ))

sl_header() {
  cat <<'HDR'
# Session ledger — working breadcrumbs

One line per assistant turn, appended automatically by `sync/session-ledger.sh`
(Stop hook): the files that turn touched and a one-line gist of what was decided.

This is **not** a handoff capsule. It is raw, unreviewed, bounded, and gitignored.
`/handoff` reads it and distills the real capsule into
`HANDOFF-<slug>-<YYYY-MM-DD>.md` alongside this file. Safe to delete at any time —
it will start over on the next turn.

HDR
}

# ---------------------------------------------------------------------------
# Last-turn extraction.
#
# A "turn" is every main-chain assistant record since the last real user message.
# A user record carrying only tool_result blocks is the tool loop, not a new turn,
# so it does not close the window.
#
# Emits three \x1f-separated fields: <last-assistant-uuid> <paths> <gist>.
# The gist prefers a decision-shaped sentence (we chose / instead of / root cause
# / turns out ...) from anywhere in the turn's prose, and falls back to the first
# sentence of the turn's closing text. Nothing else from the transcript is copied.
# ---------------------------------------------------------------------------
SL_PY_DIGEST='
import sys, json, os, re

path = sys.argv[1]
cwd = sys.argv[2] if len(sys.argv) > 2 else ""
WINDOW = 1048576          # 1MB tail: comfortably more than one turn, still cheap

try:
    size = os.path.getsize(path)
    start = max(0, size - WINDOW)
    with open(path, "rb") as fh:
        fh.seek(start)
        blob = fh.read()
except OSError:
    sys.exit(0)
if start > 0:
    blob = blob.split(b"\n", 1)[-1]

records = []
for line in blob.splitlines():
    if not line.startswith(b"{"):
        continue
    try:
        records.append(json.loads(line.decode("utf-8", "replace")))
    except Exception:
        continue

DECISION = re.compile(
    r"\b(we (?:will|decided|chose|are going)|decided to|decision|chose|switched to|"
    r"instead of|going with|settled on|root cause|turns out|the fix is|will not|won’t|"
    r"wont|rejected|ruled out|confirmed that|the bug (?:is|was))\b", re.I)

def sentences(text):
    text = re.sub(r"```.*?```", " ", text, flags=re.S)      # drop fenced code
    text = re.sub(r"^\s*[#>*\-\d.]+\s*", " ", text)         # drop a leading md marker
    text = re.sub(r"\s+", " ", text).strip()
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+", text) if s.strip()]

def clip(text, limit=200):
    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit(" ", 1)[0]
    return (cut or text[:limit]).rstrip(",;:-") + "…"

paths, seen = [], set()
gist_fallback = ""
gist_decision = ""
uuid = ""

for rec in reversed(records):
    kind = rec.get("type")
    msg = rec.get("message") if isinstance(rec.get("message"), dict) else {}
    if kind == "user":
        content = msg.get("content")
        if isinstance(content, str):
            break                                   # a real prompt: turn boundary
        if isinstance(content, list) and not any(
                isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            break
        continue
    if kind != "assistant" or rec.get("isSidechain") is True:
        continue
    if not uuid:
        uuid = rec.get("uuid") or ""
    blocks = msg.get("content")
    if not isinstance(blocks, list):
        continue
    for b in reversed(blocks):
        if not isinstance(b, dict):
            continue
        if b.get("type") == "tool_use":
            inp = b.get("input") if isinstance(b.get("input"), dict) else {}
            for key in ("file_path", "notebook_path"):
                v = inp.get(key)
                if isinstance(v, str) and v and v not in seen:
                    seen.add(v)
                    paths.append(v)
        elif b.get("type") == "text":
            for s in sentences(b.get("text") or ""):
                if not gist_fallback:
                    gist_fallback = s
                if not gist_decision and DECISION.search(s):
                    gist_decision = s

paths.reverse()                                     # back to chronological order
prefix = (cwd.rstrip("/") + "/") if cwd else None
home = os.path.expanduser("~").rstrip("/") + "/"

def shorten(p):
    if prefix and p.startswith(prefix):
        return p[len(prefix):]                      # in-project: relative
    if p.startswith(home):
        return "~/" + p[len(home):]                 # elsewhere: at least drop $HOME
    return p

paths = [shorten(p) for p in paths]
extra = len(paths) - 6
if extra > 0:
    paths = paths[:6] + ["+%d more" % extra]
joined = ", ".join(paths)
if len(joined) > 240:                               # keep the line bounded regardless
    joined = joined[:240].rsplit(", ", 1)[0] + ", …"

gist = (gist_decision or gist_fallback or "").replace("**", "").lstrip("#*->| ")
gist = clip(gist.strip())
gist = "".join(ch if ch >= " " else " " for ch in gist).strip()
# \x1f (unit separator) rather than TAB: with IFS=tab bash collapses runs of
# whitespace, so an empty middle field would silently shift the others.
sys.stdout.write("\x1f".join([uuid, joined, gist]) + "\n")
'

sl_main() {
  local input session="" tp="" cwd="" active="" ledger dir digest
  local uuid="" paths="" gist="" line statefile last_uuid lines tmp stamp

  input="$(cat)"
  command -v python3 >/dev/null 2>&1 || {
    hl_log "session-ledger: python3 missing — cannot read the transcript, skipping"
    return 0
  }

  # One parse for the whole payload. stop_hook_active means this Stop is already a
  # continuation we caused — appending again would double-log the same turn.
  input="$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print("\x1f".join([
    d.get("session_id") or "",
    d.get("transcript_path") or "",
    d.get("cwd") or "",
    "1" if d.get("stop_hook_active") else ""]))' 2>/dev/null)" || return 0
  [ -n "$input" ] || return 0

  IFS="$SL_US" read -r session tp cwd active <<< "$input"

  [ -n "$active" ] && return 0
  [ -n "$tp" ] && [ -f "$tp" ] || return 0
  [ -n "$cwd" ] && [ -d "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$cwd" ] && [ -d "$cwd" ] || return 0

  digest="$(python3 -c "$SL_PY_DIGEST" "$tp" "$cwd" 2>/dev/null)" || return 0
  [ -n "$digest" ] || return 0
  IFS="$SL_US" read -r uuid paths gist <<< "$digest"

  # Nothing touched and nothing said — no breadcrumb worth leaving.
  [ -n "$paths" ] || [ -n "$gist" ] || return 0

  # Idempotence: the same last-assistant record must never be logged twice (a Stop
  # can fire more than once around a single turn).
  statefile="$HL_STATE_DIR/ledger-$(hl_sha "${session:-$cwd}")"
  if [ -n "$uuid" ] && [ -f "$statefile" ]; then
    last_uuid="$(cat "$statefile" 2>/dev/null || true)"
    [ "$last_uuid" = "$uuid" ] && return 0
  fi

  # Secret gate. The gist is model prose that may quote a value it just read; the
  # path list is names only. hl_scrub fails CLOSED — no pattern file, no gist.
  [ -n "$gist" ] && gist="$(hl_scrub "$gist")"

  # One file PER SESSION, not one rolling file. A single current.md meant the last
  # session's breadcrumbs were overwritten by the next one, so nothing accumulated and a
  # fresh chat had no way to know what the previous ones had done. Per-session files make
  # the archive that session-digest.sh reads at the start of every new session.
  dir="$(ledger_dir "$cwd")/sessions"
  mkdir -p "$dir" 2>/dev/null || return 0
  sid="$(printf '%s' "${session:-nosession}" | tr -c 'A-Za-z0-9' '-' | cut -c1-12)"
  ledger="$dir/$(date '+%Y-%m-%d')-$sid.md"
  if [ ! -f "$ledger" ]; then
    sl_header > "$ledger" 2>/dev/null || return 0
    # First turn of a session in this project — the one cheap moment to evict the
    # per-session state files that older sessions left behind. Never on the hot path.
    find "$HL_STATE_DIR" -maxdepth 1 \( -name 'ledger-*' -o -name 'handoff-advice-*' \) \
      -mtime +14 -delete 2>/dev/null || true
    # Bound the archive too. Session files are small, but "small forever" is still
    # forever; keep the most recent SL_KEEP_SESSIONS and drop the rest.
    ls -1t "$dir"/*.md 2>/dev/null | tail -n +"$((SL_KEEP_SESSIONS + 1))" \
      | while IFS= read -r old_file; do rm -f "$old_file" 2>/dev/null; done
  fi

  stamp="$(date '+%Y-%m-%d %H:%M')"
  if [ -n "$paths" ] && [ -n "$gist" ]; then
    line="- $stamp · $paths · $gist"
  elif [ -n "$paths" ]; then
    line="- $stamp · $paths"
  else
    line="- $stamp · $gist"
  fi
  printf '%s\n' "$line" >> "$ledger" 2>/dev/null || return 0
  [ -n "$uuid" ] && printf '%s\n' "$uuid" > "$statefile" 2>/dev/null

  # Bound the file. grep -c on a few-hundred-line file is free; the rewrite only
  # runs on overflow.
  lines="$(grep -c '^- ' "$ledger" 2>/dev/null || true)"
  case "$lines" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$lines" -gt "$SL_MAX_ENTRIES" ]; then
    tmp="$ledger.tmp.$$"
    {
      sl_header
      printf '<!-- older entries trimmed %s (cap: %s entries) -->\n\n' "$stamp" "$SL_MAX_ENTRIES"
      grep '^- ' "$ledger" 2>/dev/null | tail -n "$SL_KEEP_ENTRIES"
    } > "$tmp" 2>/dev/null && mv "$tmp" "$ledger" 2>/dev/null
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

sl_main
exit 0
