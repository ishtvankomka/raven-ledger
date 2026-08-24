#!/usr/bin/env bash
# Handoff pressure library for the raven-ledger.
#
# One job:
#   context_occupancy <transcript>          — how full is the context, right now
#
# NOTE: this library no longer proposes anything. It used to inject "you are at N% —
# run /handoff" on a UserPromptSubmit hook; that was removed as unwanted nagging.
# What is left is a measurement you can call yourself, plus the helpers the session
# ledger uses. Nothing here runs automatically.

set -u

HL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HL_ROOT="$(cd "$HL_DIR/.." && pwd)"
HL_TAB=$'\t'   # literal tabs in source are too easy to lose to an editor; name it once
HL_STATE_DIR="${RAVEN_STATE_DIR:-$HOME/.cache/raven-ledger}"
HL_LOG_FILE="$HL_STATE_DIR/sync.log"
HL_SECRET_PATTERNS="${SECRET_PATTERNS_FILE:-$HL_ROOT/library/guardrails/secret-patterns.txt}"

mkdir -p "$HL_STATE_DIR" 2>/dev/null || true

hl_log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$HL_LOG_FILE" 2>/dev/null || true; }

# hl_sha <string> — short stable key. Never returns empty: if neither hasher is
# present it says so in the log and degrades to a sanitized tail of the input,
# because a silently-empty key would collide every session into one state file.
hl_sha() {
  local s="${1:-}"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$s" | shasum -a 256 | cut -d' ' -f1 | cut -c1-16
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$s" | sha256sum | cut -d' ' -f1 | cut -c1-16
  else
    hl_log "hl_sha: no shasum/sha256sum — using a sanitized-path key instead"
    printf '%s' "$s" | tr -c 'A-Za-z0-9' '-' | tail -c 24
  fi
}

# ---------------------------------------------------------------------------
# context_occupancy <transcript_path>  ->  "<tokens>\t<turns>"
#
# tokens = input_tokens + cache_read_input_tokens + cache_creation_input_tokens
#          of the LAST main-chain assistant record. That sum is exactly what the
#          model was asked to attend to on that request, i.e. current occupancy.
#          It drops on its own after a compaction, which is what we want.
# turns  = main-chain assistant records in the transcript. One logical turn can
#          span several records (tool loop), so this is a monotonic activity
#          counter, not a count of user exchanges — it is used for throttling.
#
# Speed: the token read seeks to the LAST 256KB and only widens if that window
# held no usable record (a single record can exceed it). The turn count is the
# one full-file pass, a substring test per line with no JSON parsing. Both run in
# ONE python3 process, so a per-prompt hook pays one interpreter startup (~13ms),
# not two. Measured 30ms total on a 9MB / 2870-line transcript; the whole
# UserPromptSubmit hook lands at ~85ms there, and that 9MB file is the largest on
# this machine — a typical transcript is well under it.
# Echoes nothing and returns non-zero on a missing or unparseable transcript.
# ---------------------------------------------------------------------------
HL_PY_OCCUPANCY='
import sys, json, os, re

path = sys.argv[1]
try:
    size = os.path.getsize(path)
except OSError:
    sys.exit(1)
if size <= 0:
    sys.exit(1)

def newest_usage(blob):
    best = 0
    for line in blob.splitlines():
        if not line.startswith(b"{"):
            continue
        try:
            rec = json.loads(line.decode("utf-8", "replace"))
        except Exception:
            continue
        if rec.get("type") != "assistant" or rec.get("isSidechain") is True:
            continue
        msg = rec.get("message")
        usage = msg.get("usage") if isinstance(msg, dict) else None
        if not isinstance(usage, dict):
            continue
        total = 0
        for key in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"):
            try:
                total += int(usage.get(key) or 0)
            except (TypeError, ValueError):
                pass
        if total > 0:
            best = total          # later records overwrite: last one wins
    return best

tokens = 0
for window in (262144, 4194304, 67108864):
    start = max(0, size - window)
    try:
        with open(path, "rb") as fh:
            fh.seek(start)
            blob = fh.read()
    except OSError:
        sys.exit(1)
    if start > 0:
        blob = blob.split(b"\n", 1)[-1]   # drop the partial first line
    tokens = newest_usage(blob)
    if tokens or start == 0:
        break
if not tokens:
    sys.exit(1)

# Turn count: the one full-file pass. The fast path is a plain substring test,
# which is what the writer actually emits (no space after the colon). If that
# finds nothing while the tail scan clearly did find assistant records, the
# format is not what we assumed — redo with a whitespace-tolerant regex rather
# than report a confident zero.
def count_turns(tolerant):
    n = 0
    if tolerant:
        is_a = re.compile(rb"\"type\"\s*:\s*\"assistant\"").search
        is_s = re.compile(rb"\"isSidechain\"\s*:\s*true").search
        with open(path, "rb") as fh:
            for line in fh:
                if is_a(line) and not is_s(line):
                    n += 1
    else:
        with open(path, "rb") as fh:
            for line in fh:
                if b"\"type\":\"assistant\"" in line and b"\"isSidechain\":true" not in line:
                    n += 1
    return n

try:
    turns = count_turns(False) or count_turns(True)
except OSError:
    turns = 0

sys.stdout.write("%d\t%d\n" % (tokens, turns))
'

context_occupancy() {
  local tp="${1:-}" out tokens turns
  [ -n "$tp" ] || return 1
  [ -f "$tp" ] || return 1
  if ! command -v python3 >/dev/null 2>&1; then
    hl_log "context_occupancy: python3 not found — cannot read the transcript, skipping"
    return 1
  fi
  out="$(python3 -c "$HL_PY_OCCUPANCY" "$tp" 2>/dev/null)" || return 1
  tokens="${out%%"$HL_TAB"*}"
  turns="${out##*"$HL_TAB"}"
  case "$tokens" in ''|*[!0-9]*) return 1 ;; esac
  case "$turns"  in ''|*[!0-9]*) turns=0 ;; esac
  printf '%s\t%s\n' "$tokens" "$turns"
  return 0
}

# ---------------------------------------------------------------------------

hl_scrub() {
  local text="${1:-}" pats
  [ -n "$text" ] || return 0
  if [ ! -f "$HL_SECRET_PATTERNS" ]; then
    hl_log "hl_scrub: pattern file missing ($HL_SECRET_PATTERNS) — withholding gist"
    printf '%s' '[gist withheld — secret pattern file missing]'
    return 0
  fi
  pats="$(grep -vE '^[[:space:]]*(#|$)' "$HL_SECRET_PATTERNS" 2>/dev/null || true)"
  if [ -z "$pats" ]; then
    hl_log "hl_scrub: pattern file empty ($HL_SECRET_PATTERNS) — withholding gist"
    printf '%s' '[gist withheld — secret pattern file empty]'
    return 0
  fi
  if printf '%s\n' "$text" | LC_ALL=C grep -qiE -f <(printf '%s\n' "$pats") 2>/dev/null; then
    printf '%s' '[redacted — matched a secret pattern]'
    return 0
  fi
  printf '%s' "$text"
}
