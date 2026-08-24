#!/bin/bash
# SessionStart hook installed in projects that use the collection.
# Never blocks on the network:
#   1. applies any previously-fetched collection updates (fast-forward, local op)
#   2. re-syncs the project's vendored .claude/library/ from library/ (ACTIVE.md preserved)
#   3. opportunistically captures un-synced project agents/commands/skills → incoming/
#   4. kicks a throttled background fetch/commit/push for next time
#   5. on template copies: nudges when the original repo has new commits
# Prints a one-line context note only when something actually changed.
set -u
cat >/dev/null 2>&1 || true   # drain hook stdin

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -d "$PROJ/.claude" ] || exit 0
[ "$PROJ" = "$RAVEN_ROOT" ] && exit 0
cd "$RAVEN_ROOT" || exit 0
[ -d .git ] || exit 0

NOTES=""

# The mesh only ever reads/advances the collection on $BRANCH with no git
# operation in progress — a topic-branch experiment must not reach the projects.
SAFE_BRANCH=0
if on_sync_branch; then SAFE_BRANCH=1; else log "pull: collection not on $BRANCH — apply/re-sync skipped"; fi

# 1. Apply fetched updates: fast-forward only, only with a clean tree, short lock wait.
if [ "$SAFE_BRANCH" = 1 ] && acquire_lock 3; then
  if git rev-parse --verify -q "$REMOTE/$BRANCH" >/dev/null 2>&1; then
    if ! git merge-base --is-ancestor "$REMOTE/$BRANCH" HEAD 2>/dev/null; then
      if git merge-base --is-ancestor HEAD "$REMOTE/$BRANCH" 2>/dev/null; then
        if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
          if git merge -q --ff-only "$REMOTE/$BRANCH" >>"$LOG_FILE" 2>&1; then
            NOTES="collection updated to $(git rev-parse --short HEAD). "
            log "pull: fast-forwarded to $(git rev-parse --short HEAD)"
          fi
        else
          log "pull: remote update pending but working tree dirty — skipped ff"
        fi
      else
        NOTES="collection has DIVERGED from $REMOTE/$BRANCH — resolve manually in $RAVEN_ROOT. "
      fi
    fi
  fi
  release_lock; trap - EXIT
fi

# 2. Re-sync the vendored library copy when it drifts from library/.
# Never inside a worktree checkout — that would dirty the feature branch's diff;
# the main checkout's own session start keeps the library fresh.
IS_WORKTREE=0
case "$PROJ" in */.claude/worktrees/*) IS_WORKTREE=1 ;; esac
LIB="$PROJ/.claude/library"
RESYNCED=0
if [ "$SAFE_BRANCH" = 1 ] && [ "$IS_WORKTREE" = 0 ] && [ -d "$LIB" ]; then
  if ! diff -rq -x ACTIVE.md -x .DS_Store "$RAVEN_ROOT/library" "$LIB" >/dev/null 2>&1; then
    if rsync -a --delete --exclude 'ACTIVE.md' --exclude '.DS_Store' \
         "$RAVEN_ROOT/library/" "$LIB/" 2>>"$LOG_FILE"; then
      chmod +x "$LIB/hooks/scripts/"*.sh 2>/dev/null
      RESYNCED=1
      NOTES="${NOTES}vendored .claude/library/ re-synced from the collection. "
      log "pull($(project_name_for "$PROJ")): library re-synced"
    fi
  fi
fi

# 3. Catch-up capture — IN THE BACKGROUND, never on the critical path.
#    Walking a large project's .claude tree took 15s on a real enterprise checkout, and
#    session start is the worst possible place to spend that: the user is waiting. The live
#    PostToolUse hook already sees individual writes, so this walk only catches manual edits
#    and is never urgent. First contact with a project baselines instead of harvesting.
# bash, not sh: lib.sh uses BASH_SOURCE and process substitution, so `sh -c` sources it
# into a shell that cannot run it — and because this is detached and silenced, that failed
# invisibly. The first version of this line did exactly that: no baseline was ever written
# and the catch-up walk never ran once.
nohup bash -c ". '$RAVEN_ROOT/sync/lib.sh' && scan_project '$PROJ' >/dev/null" >/dev/null 2>&1 &

PENDING="$(find "$RAVEN_ROOT/incoming" -name '*.md' -not -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$PENDING" -gt 0 ] 2>/dev/null; then
  NOTES="${NOTES}$PENDING item(s) staged in the collection awaiting review — run /promote in $(basename "$RAVEN_ROOT") to curate and publish them. "
fi

# 4. Fetch (read-only) on the throttle, so the next session start has updates ready
#    to fast-forward. Never pushes.
NOW=$(date +%s)
LAST_FETCH=$(cat "$STATE_DIR/last-fetch" 2>/dev/null || echo 0)
case "$LAST_FETCH" in (*[!0-9]*|'') LAST_FETCH=0 ;; esac
if [ $((NOW - LAST_FETCH)) -ge $((FETCH_INTERVAL_HOURS * 3600)) ]; then
  nohup sh -c "cd '$RAVEN_ROOT' && git fetch -q '$REMOTE' '$BRANCH' && date +%s > '$STATE_DIR/last-fetch'" >/dev/null 2>&1 &
fi

# 5. Template copies: same idea as step 4, but against the original repo — a
#    throttled read-only fetch of the 'upstream' remote (if the owner added one)
#    plus a one-line suggestion when it is ahead. Never merges; that stays a
#    human step (upstream-check.sh --merge).
U_NOTE="$(bash "$SYNC_DIR/upstream-check.sh" 2>>"$LOG_FILE")"
[ -n "$U_NOTE" ] && NOTES="${NOTES}${U_NOTE} "

# 6. After a library update, surface agents that exist in the library but have no
#    local stub (registering them is a deliberate step — see INSTALL_PROMPT.md).
if [ "$RESYNCED" = 1 ] && [ -d "$PROJ/.claude/agents" ]; then
  MISSING=""
  for a in "$RAVEN_ROOT/library/agents/"*.md; do
    [ -f "$a" ] || continue
    n="$(basename "$a")"
    [ -f "$PROJ/.claude/agents/$n" ] || MISSING="$MISSING ${n%.md}"
  done
  if [ -n "$MISSING" ]; then
    NOTES="${NOTES}Library agents with no local stub (register via the INSTALL_PROMPT upgrade if wanted, some may be deliberately skipped — check .claude/library/ACTIVE.md):$MISSING. "
  fi
fi

if [ -n "$NOTES" ]; then
  printf '[raven-ledger] %s\n' "$NOTES"
fi
exit 0
