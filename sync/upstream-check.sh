#!/bin/bash
# Upstream check for template copies of the collection.
#
# A copy created via GitHub's "Use this template" has no link back to the original
# repo. The owner opts in by adding one:
#
#   git remote add upstream <original repo URL>
#
# From then on this script keeps an eye on it: a throttled read-only fetch in the
# background, and a one-line suggestion (via pull.sh at session start, or run
# directly) when upstream has commits this copy lacks. It never merges on its own,
# never pushes, and never blocks on the network — applying is a human decision:
#
#   upstream-check.sh            print the suggestion line, or nothing
#   upstream-check.sh --merge    apply: fetch + merge upstream into a clean main
#
# Tune with RAVEN_UPSTREAM_REMOTE (default: upstream) and RAVEN_UPSTREAM_HOURS
# (fetch throttle, default: 24). No upstream remote configured → silent exit 0,
# which is what keeps the original repo itself, and anyone uninterested, quiet.
set -u
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

UP_REMOTE="${RAVEN_UPSTREAM_REMOTE:-upstream}"
UP_HOURS="${RAVEN_UPSTREAM_HOURS:-24}"
UP_STAMP="$STATE_DIR/last-upstream-fetch"

cd "$RAVEN_ROOT" || exit 0
[ -d .git ] || exit 0
git config "remote.$UP_REMOTE.url" >/dev/null 2>&1 || exit 0

if [ "${1:-}" = "--merge" ]; then
  if ! on_sync_branch; then
    echo "upstream-check: collection is not on $BRANCH with a clean git state — switch first" >&2
    exit 1
  fi
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    echo "upstream-check: working tree has uncommitted changes — commit or stash first" >&2
    exit 1
  fi
  # Synchronous fetch is fine here: --merge is a deliberate foreground command,
  # not a hook. Only the hook path must never wait on the network.
  if ! git fetch "$UP_REMOTE" "$BRANCH"; then
    echo "upstream-check: fetch from $UP_REMOTE failed (offline?)" >&2
    exit 1
  fi
  date +%s > "$UP_STAMP"
  if git merge-base --is-ancestor "$UP_REMOTE/$BRANCH" HEAD 2>/dev/null; then
    echo "upstream-check: already up to date with $UP_REMOTE/$BRANCH"
    exit 0
  fi
  if git merge --no-edit "$UP_REMOTE/$BRANCH"; then
    log "upstream-check: merged $UP_REMOTE/$BRANCH into $BRANCH ($(git rev-parse --short HEAD))"
    echo "upstream-check: merged $UP_REMOTE/$BRANCH — review with 'git log -1 --stat', then run sync/validate-library.sh"
  else
    echo "upstream-check: merge stopped on conflicts — resolve and commit, or undo with 'git merge --abort'" >&2
    exit 1
  fi
  exit 0
fi

# Check mode. Fetch on the throttle, detached, so a dead network can't slow a
# session start; the comparison below runs against whatever an earlier fetch
# already brought in.
NOW=$(date +%s)
LAST=$(cat "$UP_STAMP" 2>/dev/null || echo 0)
case "$LAST" in (*[!0-9]*|'') LAST=0 ;; esac
if [ $((NOW - LAST)) -ge $((UP_HOURS * 3600)) ]; then
  nohup sh -c "cd '$RAVEN_ROOT' && git fetch -q '$UP_REMOTE' '$BRANCH' && date +%s > '$UP_STAMP'" >/dev/null 2>&1 &
fi

git rev-parse --verify -q "$UP_REMOTE/$BRANCH" >/dev/null 2>&1 || exit 0
git merge-base --is-ancestor "$UP_REMOTE/$BRANCH" HEAD 2>/dev/null && exit 0
if git merge-base "$UP_REMOTE/$BRANCH" HEAD >/dev/null 2>&1; then
  N="$(git rev-list --count "HEAD..$UP_REMOTE/$BRANCH" 2>/dev/null || echo '?')"
  echo "the template's original repo has $N new commit(s) — review: 'git -C $RAVEN_ROOT log --oneline HEAD..$UP_REMOTE/$BRANCH', apply: 'sync/upstream-check.sh --merge'."
else
  echo "the template's original repo has rewritten history (no common ancestor with this copy) — compare manually before taking anything."
fi
exit 0
