#!/bin/bash
# UserPromptSubmit hook — the router, and nothing else.
#
# The skill listing is frozen at session start and cannot be refreshed, so the catalogue's
# tail is registered "name-only" (invocable, zero description cost) and this hook supplies
# the descriptions that actually matter for THIS message. A session that changes subject
# gets different tools on the very next turn.
#
# This hook deliberately does NOT comment on context usage. An earlier version measured the
# window and told the model to hand off; it was removed as nagging. Measurement still exists
# as `context_occupancy` in handoff-lib.sh for when you want to look — it just never speaks
# on its own.
#
# Injected context is visible for this turn only and does not survive compaction. That is fine:
# it is recomputed every turn. The cost is a few hundred tokens when something matches, and
# zero when nothing does — staying silent is the common, correct case.
#
# Input (verified empirically):
#   {"session_id","transcript_path","cwd","permission_mode","hook_event_name","prompt"}
# Output: nothing, or a hookSpecificOutput.additionalContext payload. Always exits 0.
set -u

SYNC_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT="$(cat)"
[ -n "$INPUT" ] || exit 0

eval "$(printf '%s' "$INPUT" | python3 -c '
import json, sys, shlex
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for k in ("prompt",):
    print("HOOK_%s=%s" % (k.upper(), shlex.quote(str(d.get(k) or ""))))
' 2>/dev/null)"

HOOK_PROMPT="${HOOK_PROMPT:-}"

BLOCKS=""

# --- 1. route -------------------------------------------------------------
INDEX="${RAVEN_INDEX:-$SYNC_DIR/../library/index.json}"
if [ -n "$HOOK_PROMPT" ] && [ -f "$INDEX" ] && [ -f "$SYNC_DIR/router-lib.sh" ]; then
  # shellcheck disable=SC1091
  . "$SYNC_DIR/router-lib.sh" 2>/dev/null || true
  if command -v router_match >/dev/null 2>&1 || type router_match >/dev/null 2>&1; then
    MATCHES="$(router_match "$HOOK_PROMPT" "$INDEX" "${RAVEN_ROUTER_MAX:-4}" 2>/dev/null || true)"
    if [ -n "$MATCHES" ]; then
      BLOCKS="Collection tools that match this request (invoke by name; they are registered but their descriptions are not loaded by default):
$(printf '%s\n' "$MATCHES" | awk -F'\t' 'NF>=3 {printf "- %s `%s` — %s\n", $1, $2, $3}')"
    fi
  fi
fi

[ -n "$BLOCKS" ] || exit 0

printf '%s' "$BLOCKS" | python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": sys.stdin.read(),
}}))
' 2>/dev/null
exit 0
