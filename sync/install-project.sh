#!/bin/bash
# Wire the sync mesh into one project: adds the capture (PostToolUse), pull (SessionStart),
# router (UserPromptSubmit), session-ledger (Stop), session-digest and worker-note
# (SessionStart) hooks to the project's .claude/settings.local.json, plus the machine-local
# token tuning below. Idempotent — safe to re-run; never touches .claude/settings.json.
# settings.local.json is machine-local (auto-gitignored by Claude Code), which is
# exactly right for hooks that reference this machine's collection path.
#
# Git worktrees each carry their OWN copy of settings.local.json (made when the worktree was
# created), so wiring only the main checkout would leave every existing worktree on the old
# hooks — and most sessions run in worktrees. The same wiring is therefore applied to each
# worktree that already has a settings.local.json; none is created.
#
# Token tuning (env, machine-local, never overrides a value the shell, the project's
# settings.json or ~/.claude/settings.json already sets):
#   CLAUDE_CODE_AUTO_COMPACT_WINDOW  caps the context at N tokens (default 400000). Measured over
#       60 days of real sessions: calls made with a 200K+ prompt were ~42% of calls but ~70% of
#       weighted cost, because every call re-reads the whole context. Compacting near 355K cuts
#       ~23% of that cost. RAVEN_COMPACT_WINDOW=<n> changes it; =0 skips the tuning.
# Usage: install-project.sh <project-dir>
set -u
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

PROJ="$(cd "${1:?usage: install-project.sh <project-dir>}" && pwd)" || exit 1
if [ ! -d "$PROJ/.claude" ]; then
  echo "install-project: $PROJ has no .claude/ directory — is it a Claude Code project?" >&2
  exit 1
fi
if [ "$PROJ" = "$RAVEN_ROOT" ]; then
  echo "install-project: the collection itself needs no sync hooks" >&2
  exit 1
fi

chmod +x "$SYNC_DIR"/*.sh 2>/dev/null

SETTINGS="$PROJ/.claude/settings.local.json" PROJ="$PROJ" SYNC_DIR="$SYNC_DIR" python3 - <<'PY'
import glob, json, os, sys

path = os.environ["SETTINGS"]
proj = os.environ["PROJ"]
sync = os.environ["SYNC_DIR"]
capture = os.path.join(sync, "capture.sh")
pull = os.path.join(sync, "pull.sh")
on_prompt = os.path.join(sync, "on-prompt.sh")
ledger = os.path.join(sync, "session-ledger.sh")
digest = os.path.join(sync, "session-digest.sh")
worker = os.path.join(sync, "worker-note.sh")
OURS = ("capture.sh", "pull.sh", "on-prompt.sh", "session-ledger.sh", "session-digest.sh",
        "handoff-lib.sh", "worker-note.sh")

TUNING = {}
window = os.environ.get("RAVEN_COMPACT_WINDOW", "400000")
if window not in ("", "0"):
    TUNING["CLAUDE_CODE_AUTO_COMPACT_WINDOW"] = window


def decided_elsewhere(key, settings_path):
    """True when the shell, the project's settings.json or the user's own settings already set it."""
    if os.environ.get(key):
        return True
    for p in (os.path.join(os.path.dirname(settings_path), "settings.json"),
              os.path.expanduser("~/.claude/settings.json")):
        try:
            with open(p) as f:
                if key in (json.load(f).get("env") or {}):
                    return True
        except (OSError, ValueError, AttributeError):
            pass
    return False


def wire(target, strict):
    """Wire one settings.local.json. Returns (hooks_added, pruned, tuned), or None if it was skipped.
    strict=True (the project itself): a malformed file aborts and nothing is changed.
    strict=False (a worktree's copy): a malformed file is left alone."""
    data = {}
    if os.path.exists(target):
        with open(target) as f:
            raw = f.read().strip()
        if raw:
            try:
                data = json.loads(raw)
            except ValueError:
                if strict:
                    sys.exit(f"install-project: {target} is not valid JSON — fix it first, nothing was changed")
                return None
    if not isinstance(data, dict):
        if strict:
            sys.exit(f"install-project: {target} is not a JSON object — nothing was changed")
        return None

    hooks = data.setdefault("hooks", {})
    changed, pruned, tuned = [], [], []

    # Drop hook entries whose script no longer exists. A dangling hook is not inert — the harness
    # tries to run it every time the event fires, so a moved or renamed toolset leaves every
    # session in this project firing a missing command. Only OUR scripts are pruned: an entry
    # pointing somewhere else is the project's own business.
    for event in list(hooks.keys()):
        kept = []
        for entry in hooks[event]:
            live = []
            for h in entry.get("hooks", []):
                cmd = h.get("command", "")
                first = cmd.split()[0] if cmd.split() else ""
                if first.endswith(OURS) and first and not os.path.exists(first):
                    pruned.append(os.path.basename(first))
                    continue
                live.append(h)
            if live:
                entry["hooks"] = live
                kept.append(entry)
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]

    def ensure(event, matcher, command):
        entries = hooks.setdefault(event, [])
        for entry in entries:
            for h in entry.get("hooks", []):
                if command in h.get("command", ""):
                    return  # already wired
        new = {"hooks": [{"type": "command", "command": command}]}
        if matcher:
            new["matcher"] = matcher
        entries.append(new)
        changed.append(event)

    ensure("PostToolUse", "Write|Edit|MultiEdit", capture)
    ensure("SessionStart", None, pull)
    # The router, ledger, digest and worker note are wired only once their scripts exist, so a
    # half-built checkout never registers a hook pointing at a missing file — a hook that
    # cannot run is a broken session, not a missing feature.
    for event, script in (("UserPromptSubmit", on_prompt), ("Stop", ledger),
                          ("SessionStart", digest), ("SessionStart", worker)):
        if os.path.exists(script):
            ensure(event, None, script)

    env = data.get("env") if isinstance(data.get("env"), dict) else {}
    for key, value in TUNING.items():
        if key not in env and not decided_elsewhere(key, target):
            data["env"] = dict(env, **{key: value})
            env = data["env"]
            tuned.append(f"{key}={value}")

    if changed or pruned or tuned:
        with open(target, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
    return changed, pruned, tuned


def describe(res):
    changed, pruned, tuned = res
    bits = []
    if changed:
        bits.append("wired " + ", ".join(changed) + " hook(s)")
    if pruned:
        bits.append("pruned %d dead hook(s): %s" % (len(pruned), ", ".join(sorted(set(pruned)))))
    if tuned:
        bits.append("tuned env " + ", ".join(tuned))
    return "; ".join(bits)


res = wire(path, True)
text = describe(res)
print(f"install-project: {text} into {path}" if text else f"install-project: already wired — {path} unchanged")

# Existing worktrees: only files that are already there, so no worktree gains settings it never had.
wts = sorted(glob.glob(os.path.join(proj, ".claude", "worktrees", "*", ".claude", "settings.local.json")))
touched = 0
for w in wts:
    r = wire(w, False)
    if r and (r[0] or r[1] or r[2]):
        touched += 1
if wts:
    print(f"install-project: {len(wts)} existing worktree(s) with local settings — {touched} updated")
PY
STATUS=$?
if [ $STATUS -ne 0 ]; then exit $STATUS; fi

# NOTHING is written into the project except .claude/settings.local.json files, which Claude Code
# already treats as machine-local. Earlier versions appended an ignore rule to the project's
# .gitignore — a tracked file, so connecting the mesh produced a diff the owner had to
# explain. Session breadcrumbs now default to the collection's state dir instead
# (see ledger_dir in lib.sh); a repo you do not own stays untouched.

echo "install-project: next session start in $(basename "$PROJ") may ask to approve the new hooks — that is expected."
