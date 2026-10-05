#!/bin/bash
# SessionStart hook — one short note that the Gemini worker exists, so the delegation triggers
# are known BEFORE the first bulk read. Wired into every project's settings.local.json, which is
# the one channel that reaches all of them: a project's CLAUDE.md and skill stubs are usually
# untracked, so a git worktree (where most sessions run) never receives them.
#
# Silent — zero tokens — unless the worker can actually run: script present, keys configured,
# project not opted out. Opt out per project with `touch .claude/no-worker` (gw.py refuses to
# send anything there as well, so the opt-out is enforced, not just advised).
#
# Like pull.sh it serves the collection only while it is on the sync branch: a topic-branch
# experiment must not reach the projects.
set -u
cat >/dev/null 2>&1 || true   # drain hook stdin

source "$(cd "$(dirname "$0")" && pwd)/lib.sh" 2>/dev/null || exit 0

GW="$RAVEN_ROOT/library/skills/gemini-worker/scripts/gw.py"
PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$GW" ] || exit 0
[ -e "$PROJ/.claude/no-worker" ] && exit 0
[ "$PROJ" = "$RAVEN_ROOT" ] && exit 0
cd "$RAVEN_ROOT" 2>/dev/null && on_sync_branch || exit 0

# Keys: environment first, then the key file. The values are never read into this shell.
if [ -z "${GEMINI_API_KEYS:-}${GEMINI_API_KEY:-}" ]; then
  grep -Eq '^(export[[:space:]]+)?GEMINI_API_KEYS?=.{8,}' \
    "${GW_ENV_FILE:-$HOME/.config/raven-ledger/gemini.env}" 2>/dev/null || exit 0
fi

printf '%s\n' "[raven-ledger] Gemini worker available (saves context). Before reading >200 lines of log/test/build output, a long doc/PDF, or long text only for facts, delegate it: python3 \"$GW\" \"QUESTION\" [FILE... | -]  ('-' pipes a command's output; only the answer returns). Not for edits needing exact text, exact counts, or secrets/client data; verify claims before acting. On exit 3-6 do not retry: use grep/head/tail locally, or ask the user. Rules: $RAVEN_ROOT/library/skills/gemini-worker/SKILL.md"
exit 0
