# Shared helpers for the raven-ledger sync mesh. Sourced, not executed.
# Compatible with macOS system bash 3.2 — no associative arrays, no mapfile.

SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAVEN_ROOT="$(cd "$SYNC_DIR/.." && pwd)"
STATE_DIR="${RAVEN_STATE_DIR:-$HOME/.cache/raven-ledger}"
LOG_FILE="$STATE_DIR/sync.log"
LOCK_DIR="$STATE_DIR/git.lock"
REMOTE="${RAVEN_REMOTE:-origin}"
BRANCH="${RAVEN_BRANCH:-main}"
FETCH_INTERVAL_HOURS="${RAVEN_PULL_HOURS:-6}"
# A sanity bound, not a policy: the baseline is what stops a big project being harvested,
# so this only guards against something absurd. The walk itself is cheap (see scan_tree).
SCAN_MAX_ITEMS="${RAVEN_SCAN_MAX:-2000}"
BASELINE_ACTIVE=""

# One-time migration from the pre-rename state dir. Baselines, session ledgers and the
# fetch throttle all live here; orphaning them would silently re-harvest every wired project
# on the next scan, because a missing baseline reads as "first contact".
if [ ! -d "$STATE_DIR" ] && [ -d "$HOME/.cache/claude-collection" ]; then
  mv "$HOME/.cache/claude-collection" "$STATE_DIR" 2>/dev/null || true
fi
mkdir -p "$STATE_DIR"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

# project_name_for <dir> — attribution name for a checkout: a worktree under
# <project>/.claude/worktrees/<wt> is attributed to <project>, not the worktree.
project_name_for() {
  case "$1" in
    */.claude/worktrees/*) basename "${1%%/.claude/worktrees/*}" ;;
    *) basename "$1" ;;
  esac
}

# project_key <dir> — a STABLE identity for a checkout. basename collides (every company
# has an "api" and a "web"), and a path changes when a repo moves, so prefer the git root
# commit: it is the same across clones, worktrees and renames. Falls back to a path hash.
project_key() {
  local d="$1" root=""
  root="$(cd "$d" 2>/dev/null && git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)"
  if [ -n "$root" ]; then printf '%s' "${root}" | cut -c1-16
  else printf '%s' "$d" | shasum -a 256 2>/dev/null | cut -c1-16 || printf '%s' "$d" | sha256sum | cut -c1-16
  fi
}

# ledger_dir <project-dir> — where session breadcrumbs live for this project.
# DEFAULT IS OUTSIDE THE REPO. Writing into someone's checkout means a diff they have to
# explain, and on a repo you do not own that is not acceptable for a tool that was only
# supposed to observe. The in-repo path is used ONLY when it already exists, i.e. when the
# full library was deliberately installed there.
ledger_dir() {
  local proj="$1"
  if [ -d "$proj/.claude/handoff" ]; then
    printf '%s' "$proj/.claude/handoff"
  else
    printf '%s' "$STATE_DIR/ledgers/$(project_key "$proj")"
  fi
}

# mkdir-based lock (macOS has no flock). The holder records its PID; a lock is
# stolen only when it is >10 min old AND its recorded holder is no longer alive
# (a slow-but-alive push keeps its lock). The steal is atomic via mv, so exactly
# one contender wins it.
# Usage: acquire_lock [max_seconds]  — returns 1 if it could not acquire in time.
acquire_lock() {
  local max="${1:-60}" waited=0 age pid
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0) ))
    if [ "$age" -gt 600 ]; then
      pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
      case "$pid" in (*[!0-9]*|'') pid="" ;; esac
      if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        if mv "$LOCK_DIR" "$LOCK_DIR.stale.$$" 2>/dev/null; then
          rm -rf "$LOCK_DIR.stale.$$"
          log "lock: stole stale lock (holder pid=${pid:-unknown} gone)"
        fi
      fi
    fi
    waited=$((waited + 1))
    [ "$waited" -ge "$max" ] && return 1
    sleep 1
  done
  echo "$$" > "$LOCK_DIR/pid" 2>/dev/null
  trap 'release_lock' EXIT
  return 0
}
release_lock() { rm -rf "$LOCK_DIR" 2>/dev/null; }

# A library stub only points at the vendored spec — never worth capturing back.
# Three generations of stub markers are recognized.
is_stub() {
  grep -q -e 'source_spec:[[:space:]]*\.claude/library/' \
          -e 'Master Agent Library — thin stub' \
          -e 'Follow your full specification at \.claude/library/' "$1" 2>/dev/null
}

# Secret gate. Order of preference:
#   1. a real scanner (gitleaks / trufflehog) when one is installed — a maintained
#      ruleset will always beat a hand-written regex, and this gate guards a push;
#   2. otherwise the shared pattern list in library/guardrails/secret-patterns.txt,
#      which is the SINGLE source these patterns live in (pre-bash-guard.sh and
#      secret-scanner.md read the same file — three divergent copies is how a gap
#      goes unnoticed).
# Filename classes are checked first and are cheap. .md is exempt from the filename
# rules so a document ABOUT secrets (secret-scanner.md) is not itself flagged.
SECRET_PATTERNS_FILE="${SECRET_PATTERNS_FILE:-$RAVEN_ROOT/library/guardrails/secret-patterns.txt}"

looks_secret() {
  local f="$1" pats
  case "$(basename "$f")" in
    *.md) ;;
    .env|.env.*|*.pem|*.key|*.p12|*.pfx|*.keystore|*.jks|credentials*|id_rsa*|id_ed25519*|id_ecdsa*) return 0 ;;
  esac
  if command -v gitleaks >/dev/null 2>&1; then
    gitleaks detect --no-banner --no-git --source "$f" >/dev/null 2>&1 || return 0
    return 1
  fi
  [ -f "$SECRET_PATTERNS_FILE" ] || {
    log "looks_secret: PATTERN FILE MISSING ($SECRET_PATTERNS_FILE) — failing closed"
    return 0
  }
  pats="$(grep -vE '^[[:space:]]*(#|$)' "$SECRET_PATTERNS_FILE")"
  LC_ALL=C grep -qiE -f <(printf '%s\n' "$pats") "$f" 2>/dev/null
}

# capture_file <abs-file> <project-dir> [name-override]
# Copies a project-authored agent/command/skill file into incoming/<project>/…
# name-override attributes a worktree checkout to its parent project.
# Returns 0 only when it actually staged something new.
capture_file() {
  local f="$1" proj="$2" name="${3:-}" cat rel dest curated sz real_dir proj_real verdict
  [ -f "$f" ] || return 1
  [ -L "$f" ] && { log "capture: SKIPPED symlink: $f"; return 1; }
  [ -n "$proj" ] || return 1
  # BSD and GNU stat disagree on flags; try both before giving up. A silent 0 here would
  # wave a 50MB file straight through the size cap.
  sz=$(stat -f %z "$f" 2>/dev/null || stat -c %s "$f" 2>/dev/null || echo 0)
  if [ "$sz" -gt 1048576 ]; then log "capture: SKIPPED >1MB file: $f"; return 1; fi
  case "$f" in
    "$proj"/.claude/library/*) return 1 ;;
    "$proj"/.claude/agents/*.md)   cat=agents;   rel="${f#"$proj"/.claude/agents/}" ;;
    "$proj"/.claude/commands/*.md) cat=commands; rel="${f#"$proj"/.claude/commands/}" ;;
    "$proj"/.claude/skills/*)      cat=skills;   rel="${f#"$proj"/.claude/skills/}" ;;
    *) return 1 ;;
  esac
  case "$rel" in *.DS_Store*) return 1 ;; esac
  # ALLOW-LIST, not deny-list. Only instruction files leave a project: markdown that
  # actually parses as an agent/command/skill. A skill's scripts, fixtures and
  # reference data stay home — that is where a customer list or a proprietary
  # dataset would live, and no credential regex would ever recognize it.
  # Non-markdown payloads are logged, never staged, so nothing is silently dropped.
  case "$rel" in
    *.md) ;;
    *) log "capture($(project_name_for "$proj")): NOT staged (non-markdown asset, stays in the project): $cat/$rel"; return 1 ;;
  esac
  if ! head -1 "$f" | grep -q '^---[[:space:]]*$'; then
    log "capture($(project_name_for "$proj")): NOT staged (no frontmatter — not an agent/command/skill): $cat/$rel"
    return 1
  fi
  # no path traversal, and the file must physically live inside the project
  case "/$rel/" in */../*) log "capture: SKIPPED traversal path: $f"; return 1 ;; esac
  proj_real="$(cd "$proj" 2>/dev/null && pwd -P)" || return 1
  real_dir="$(cd "$(dirname "$f")" 2>/dev/null && pwd -P)" || return 1
  case "$real_dir/" in "$proj_real"/*) ;; *) log "capture: SKIPPED outside project: $f"; return 1 ;; esac
  is_stub "$f" && return 1
  if looks_secret "$f"; then log "capture: SKIPPED secret-like file: $f"; return 1; fi
  [ -n "$name" ] || name="$(project_name_for "$proj")"
  # curation verdicts: items /promote already ruled on are never re-captured.
  # Entries are sha256 digests of "<project>/<category>/<path>" so the verdict list
  # is not a plaintext roster of projects and their internal tooling.
  if [ -f "$SYNC_DIR/ignore.list" ]; then
    verdict="$(printf '%s' "$name/$cat/$rel" | shasum -a 256 | cut -d' ' -f1)"
    grep -qxF "$verdict" "$SYNC_DIR/ignore.list" && return 1
  fi
  # Pre-existing tooling recorded at first contact is not "new work" — skip it unless the
  # operator explicitly asked for a full harvest.
  if [ -n "${BASELINE_ACTIVE:-}" ] && baseline_seen "$BASELINE_ACTIVE" "$cat/$rel" "$f"; then
    return 1
  fi
  dest="$RAVEN_ROOT/incoming/$name/$cat/$rel"
  curated="$RAVEN_ROOT/library/$cat/$rel"
  if [ -f "$dest" ] && cmp -s "$f" "$dest"; then return 1; fi
  if [ -f "$curated" ] && cmp -s "$f" "$curated"; then return 1; fi
  mkdir -p "$(dirname "$dest")"
  cp "$f" "$dest"
  log "capture($name): $cat/$rel"
  return 0
}

# scan_tree <root-dir> <attributed-name> — capture_file over one checkout's
# .claude/{agents,commands,skills}; echoes count.
scan_tree() {
  local root="$1" name="$2" count=0 f
  for f in "$root"/.claude/agents/*.md "$root"/.claude/commands/*.md; do
    [ -f "$f" ] || continue
    unchanged_since_baseline "$f" && continue
    capture_file "$f" "$root" "$name" && count=$((count + 1))
  done
  if [ -d "$root/.claude/skills" ]; then
    while IFS= read -r f; do
      unchanged_since_baseline "$f" && continue
      capture_file "$f" "$root" "$name" && count=$((count + 1))
    done < <(find "$root/.claude/skills" -type f -not -name '.DS_Store' 2>/dev/null)
  fi
  echo "$count"
}

# unchanged_since_baseline <file> — true when the file predates the baseline, so it cannot
# be new work. A stat is orders of magnitude cheaper than a sha256, and on a project with
# hundreds of tooling files that is the whole difference between a walk you can run every
# session and one you cannot.
unchanged_since_baseline() {
  [ -n "${BASELINE_ACTIVE:-}" ] || return 1
  [ -f "$BASELINE_ACTIVE" ] || return 1
  # Skip ONLY when the file is strictly OLDER than the baseline. mtime granularity is one
  # second here, so "not newer" would also swallow anything written in the same second the
  # baseline was — invisible forever. Erring the other way just costs a hash, and
  # baseline_seen then decides on content.
  [ "$BASELINE_ACTIVE" -nt "$1" ] && return 0
  return 1
}

# scan_project's first contact with a project is a BASELINE, not a harvest.
#
# Connecting the mesh to a repo that already has a large Claude Code setup used to stage
# every agent, command and skill it owned — on a real enterprise checkout that is hundreds
# of files, none of which you wrote. Pre-existing tooling belongs to that project. What is
# worth collecting is what appears AFTERWARDS, while you work.
#
# So the first scan records what already exists and stages nothing. Later scans stage only
# what is new or has changed since. To deliberately harvest the pre-existing set, run
# `push-project.sh --include-existing`.
baseline_file() { printf '%s' "$STATE_DIR/baseline-$(project_key "$1")"; }

# baseline_seen <baseline-file> <relpath> <file> — has this exact content been seen before?
baseline_seen() {
  [ -f "$1" ] || return 1
  grep -qxF "$(baseline_line "$2" "$3")" "$1" 2>/dev/null
}
baseline_line() {
  printf '%s  %s' "$(shasum -a 256 "$2" 2>/dev/null | cut -d" " -f1 || sha256sum "$2" 2>/dev/null | cut -d" " -f1)" "$1"
}

# scan_project <project-dir> — the main checkout plus every worktree under
# .claude/worktrees/ (worktree sessions have no sync hooks of their own; their
# creations are attributed to the parent project); echoes total count.
# scan_project <project-dir> [--include-existing]
scan_project() {
  local proj="$1" mode="${2:-}" name count wt bl total
  name="$(project_name_for "$proj")"
  bl="$(baseline_file "$proj")"

  # Refuse to auto-harvest an unusually large tooling set. A repo with hundreds of agents
  # has a curation policy of its own; silently draining it into a personal collection is
  # not a feature. The operator can still ask for it explicitly.
  total="$(project_tool_count "$proj")"
  if [ "$mode" != "--include-existing" ] && [ ! -f "$bl" ]; then
    write_baseline "$proj" "$bl"
    log "scan($name): first contact — baselined $total existing item(s), staged none. Run push-project.sh --include-existing to harvest them deliberately."
    echo 0
    return 0
  fi
  if [ "$total" -gt "$SCAN_MAX_ITEMS" ]; then
    log "scan($name): $total tooling files exceeds SCAN_MAX_ITEMS=$SCAN_MAX_ITEMS — skipping the catch-up walk (the live capture hook still sees individual writes)"
    echo 0
    return 0
  fi

  BASELINE_ACTIVE="$bl"
  [ "$mode" = "--include-existing" ] && BASELINE_ACTIVE=""
  count="$(scan_tree "$proj" "$name")"
  for wt in "$proj"/.claude/worktrees/*/; do
    [ -d "$wt" ] || continue
    count=$((count + $(scan_tree "${wt%/}" "$name") ))
  done
  BASELINE_ACTIVE=""
  echo "$count"
}

# project_tool_count <dir> — how many candidate files this project holds. Cheap: names only.
project_tool_count() {
  local proj="$1"
  { ls -1 "$proj"/.claude/agents/*.md "$proj"/.claude/commands/*.md 2>/dev/null
    find "$proj/.claude/skills" -name '*.md' 2>/dev/null; } | wc -l | tr -d ' '
}

# write_baseline <dir> <file> — record what exists now, so it is never mistaken for new.
write_baseline() {
  local proj="$1" out="$2" f rel
  mkdir -p "$(dirname "$out")" 2>/dev/null || return 1
  : > "$out"
  for f in "$proj"/.claude/agents/*.md "$proj"/.claude/commands/*.md; do
    [ -f "$f" ] || continue
    baseline_line "${f#"$proj"/.claude/}" "$f" >> "$out"; printf '\n' >> "$out"
  done
  if [ -d "$proj/.claude/skills" ]; then
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      baseline_line "${f#"$proj"/.claude/}" "$f" >> "$out"; printf '\n' >> "$out"
    done < <(find "$proj/.claude/skills" -name '*.md' 2>/dev/null)
  fi
  return 0
}

# on_sync_branch — true when the collection checkout is on $BRANCH with no git
# operation (rebase/merge/cherry-pick) in progress. The mesh NEVER touches the
# repo in any other state: a topic branch or WIP must not end up on main.
on_sync_branch() {
  [ "$(git symbolic-ref --short -q HEAD)" = "$BRANCH" ] || return 1
  local g; g="$(git rev-parse --git-dir 2>/dev/null)" || return 1
  [ -d "$g/rebase-merge" ] && return 1
  [ -d "$g/rebase-apply" ] && return 1
  [ -f "$g/MERGE_HEAD" ] && return 1
  [ -f "$g/CHERRY_PICK_HEAD" ] && return 1
  return 0
}

# collection_git_flush <commit-message>
# Commits staged incoming/ captures, then rebases onto the remote and pushes every
# pending local commit. Only ever operates on $BRANCH; never touches anything
# outside incoming/ in the commit; rebases only a fully clean tree (the user's
# uncommitted work is never autostashed or aborted). Offline-safe: on any network
# failure commits simply stay local for the next flush.
# The commit subject never names a project: the pushed git log is as public as the
# files, and a subject like "capture(<client>): session sync" publishes the roster
# that ignore.list is hashed to avoid. Attribution stays in the local state dir.
collection_git_flush() {
  local msg="${1:-sync: publish reviewed captures}"
  cd "$RAVEN_ROOT" || return 1
  [ -d .git ] || { log "flush: not a git repo yet"; return 1; }
  if ! on_sync_branch; then
    log "flush: not on $BRANCH (or git op in progress) — skipping"
    return 0
  fi
  acquire_lock 55 || { log "flush: lock busy, skipping"; return 1; }
  git add -A incoming/ 2>>"$LOG_FILE"
  if ! git diff --cached --quiet -- incoming/ 2>/dev/null; then
    # Last gate before anything leaves this machine. capture_file already scanned
    # each file, but the commit is what publishes it and a file can change in
    # between: re-scan what is actually staged. A hit unstages everything and
    # aborts the flush — never push first and apologize later.
    local sf tainted=""
    while IFS= read -r sf; do
      [ -n "$sf" ] && [ -f "$sf" ] || continue
      looks_secret "$sf" && tainted="$tainted $sf"
    done <<EOF
$(git diff --cached --name-only -- incoming/ 2>/dev/null)
EOF
    if [ -n "$tainted" ]; then
      git reset -q -- incoming/ 2>>"$LOG_FILE"
      log "flush: ABORTED — secret-like content staged:$tainted (left on disk, uncommitted — sanitize or delete it)"
      return 0
    fi
    git commit -q -m "$msg" -- incoming/ 2>>"$LOG_FILE" && log "flush: committed: $msg"
  fi
  git remote get-url "$REMOTE" >/dev/null 2>&1 || return 0
  if ! git fetch -q "$REMOTE" "$BRANCH" 2>>"$LOG_FILE"; then
    # remote reachable but branch absent (fresh repo)? then create it
    git ls-remote --exit-code "$REMOTE" "refs/heads/$BRANCH" >/dev/null 2>&1
    if [ $? -eq 2 ]; then
      git push -q "$REMOTE" "HEAD:refs/heads/$BRANCH" 2>>"$LOG_FILE" \
        && log "flush: created $REMOTE/$BRANCH" \
        || log "flush: initial push failed"
    else
      log "flush: fetch failed (offline?) — commits stay local"
    fi
    return 0
  fi
  date +%s > "$STATE_DIR/last-fetch"
  if ! git merge-base --is-ancestor "$REMOTE/$BRANCH" HEAD 2>/dev/null; then
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
      log "flush: behind $REMOTE/$BRANCH but tree dirty — deferring rebase/push"
      return 0
    fi
    if ! git rebase -q "$REMOTE/$BRANCH" >>"$LOG_FILE" 2>&1; then
      git rebase --abort >/dev/null 2>&1   # aborts only the rebase we just started
      log "flush: DIVERGED from $REMOTE/$BRANCH — resolve manually in $RAVEN_ROOT"
      return 0
    fi
  fi
  if [ -n "$(git log --oneline "$REMOTE/$BRANCH"..HEAD 2>/dev/null | head -1)" ]; then
    if git push -q "$REMOTE" "HEAD:$BRANCH" 2>>"$LOG_FILE"; then
      log "flush: pushed to $REMOTE/$BRANCH"
    else
      log "flush: push failed — commits stay local"
    fi
  fi
  return 0
}
