#!/usr/bin/env bash
# PreToolUse(Bash) guard. Reads hook JSON on stdin; exit 2 blocks the command and returns
# stderr to the agent. Fails OPEN (exit 0) on any parse error — a broken guard must not brick
# the session. Enforces GLOBAL_PREFERENCES hard-denies + a pre-commit secret scan mechanically.
# Patterns are anchored to avoid false-positives on routine dev commands.
set -euo pipefail

CMD="$(python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get("tool_input",{}).get("command",""))
except Exception:
    sys.exit(0)
' 2>/dev/null || true)"

[ -z "$CMD" ] && exit 0

block() { echo "BLOCKED by pre-bash-guard: $1" >&2; exit 2; }
has()   { echo "$CMD" | grep -Eq "$1"; }

# --- Hard-deny list (GLOBAL_PREFERENCES) — no prompt or CONFIRM overrides these ---

# Destructive rm ONLY on a bare protected path (root, root-glob, ~, $HOME) — not on subpaths.
# Matches rf/fr in any flag order; requires the target to BE the protected root, not contain it.
if has 'rm +-[a-zA-Z]*(rf|fr)[a-zA-Z]*'; then
  # Target must BE a protected root (optionally with a trailing / or /*), not a subpath under it.
  if has 'rm +-[a-zA-Z]+ +(/|~|\$HOME|\$\{HOME\})(/\*?|\*)?( |$|;)'; then
    block "destructive rm on a protected root path"
  fi
fi

# pipe-to-shell of remote content (curl|wget → any shell, tolerating flags/sudo)
if has '(curl|wget)\b.*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh)\b'; then
  block "pipe-to-shell of remote content"
fi
# process-substitution form: bash <(curl ...) / sh <(wget ...)
if has '(bash|sh|zsh)[[:space:]]+<\([[:space:]]*(curl|wget)\b'; then
  block "shell of process-substituted remote content"
fi

# git clean with a force flag in any position/order (-f, -fd, -fdx, -xfd, --force)
if has 'git +clean\b' && has '(--force|-[a-zA-Z]*f[a-zA-Z]*)'; then
  block "git clean --force is irrecoverable; stage or stash instead"
fi

# force-push to a protected branch — flag form OR leading-+ refspec form
if has 'git +push'; then
  if has '(--force([^-]|$)|--force-with-lease|-[a-zA-Z]*f([^a-z]|$))' \
     && has '\b(master|main|origin/(master|main)|HEAD:(master|main))\b'; then
    block "force-push to master/main is hard-denied — no CONFIRM overrides it"
  fi
  if has '\+(refs/heads/)?(master|main)\b'; then
    block "force-push (+refspec) to master/main is hard-denied"
  fi
fi

# --- Authorship: the commit is the operator's, not the tool's ------------------
# Prose asks; a hook enforces. Seat-billed platforms count distinct commit identities
# against the paid team, so a stray co-author trailer can fail a deploy that has nothing
# wrong with the code. Blocked here rather than merely discouraged because the trailer is
# habitual — it gets appended by muscle memory and nobody notices until a build breaks.
if has 'git +commit'; then
  if printf '%s' "$CMD" | LC_ALL=C grep -qiE 'co-authored-by:[^\n]*(claude|anthropic)'; then
    block "this commit carries a Co-Authored-By trailer naming the assistant. Commit as the repo's own git identity — drop the trailer. (Seat-billed CI counts commit identities; see GLOBAL_PREFERENCES 'Authorship'.)"
  fi
  if printf '%s' "$CMD" | LC_ALL=C grep -qiE -- '--author[= ][^ ]*(claude|anthropic)'; then
    block "this commit overrides --author with an assistant identity. Use the repo's configured git user instead."
  fi
fi
# Reconfiguring the repo's git identity to the assistant is the same problem, one step earlier.
if printf '%s' "$CMD" | LC_ALL=C grep -qiE 'git +config[^|;&]*user\.(name|email)[^|;&]*(claude|anthropic|noreply@anthropic)'; then
  block "refusing to set this repo's git identity to the assistant. Commits belong to the operator."
fi

# --- Pre-commit secret scan: block a commit that would capture a staged secret ---
if has 'git +commit'; then
  if command -v gitleaks >/dev/null 2>&1; then
    if ! gitleaks protect --staged --no-banner >/dev/null 2>&1; then
      block "gitleaks found a secret in the staged diff — unstage/rotate before committing"
    fi
  else
    # No gitleaks: fall back to the shared pattern list. It lives in ONE file so this
    # hook, the sync mesh and secret-scanner cannot drift apart — divergent copies are
    # how a gap survives unnoticed. Missing file = fail closed, not fail open.
    PATTERNS="$(dirname "$0")/../../guardrails/secret-patterns.txt"
    STAGED="$(git diff --cached -U0 2>/dev/null | grep '^+' || true)"
    if [ ! -f "$PATTERNS" ]; then
      [ -n "$STAGED" ] && block "secret-patterns.txt is missing from the vendored library — cannot scan the staged diff, so this commit is blocked. Restore .claude/library/guardrails/secret-patterns.txt or install gitleaks."
    elif printf '%s\n' "$STAGED" | LC_ALL=C grep -qiE -f <(grep -vE '^[[:space:]]*(#|$)' "$PATTERNS"); then
      block "staged diff contains a recognizable secret — unstage/rotate; move it to a git-ignored env file. (Install gitleaks for full-coverage scanning.)"
    fi
  fi
fi

exit 0
