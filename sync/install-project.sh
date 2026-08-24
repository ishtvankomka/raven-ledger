#!/bin/bash
# Wire the sync mesh into one project: adds the capture (PostToolUse), pull
# (SessionStart), router (UserPromptSubmit), session-ledger (Stop) and
# session-digest (SessionStart) hooks to the project's .claude/settings.local.json.
# Idempotent — safe to re-run; never touches .claude/settings.json.
# settings.local.json is machine-local (auto-gitignored by Claude Code), which is
# exactly right for hooks that reference this machine's collection path.
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

SETTINGS="$PROJ/.claude/settings.local.json" SYNC_DIR="$SYNC_DIR" python3 - <<'PY'
import json, os, sys

path = os.environ["SETTINGS"]
sync = os.environ["SYNC_DIR"]
capture = os.path.join(sync, "capture.sh")
pull = os.path.join(sync, "pull.sh")

data = {}
if os.path.exists(path):
    with open(path) as f:
        raw = f.read().strip()
    if raw:
        try:
            data = json.loads(raw)
        except ValueError:
            sys.exit(f"install-project: {path} is not valid JSON — fix it first, nothing was changed")
if not isinstance(data, dict):
    sys.exit(f"install-project: {path} is not a JSON object — nothing was changed")

hooks = data.setdefault("hooks", {})
changed = []

# Drop hook entries whose script no longer exists. A dangling hook is not inert — the harness
# tries to run it every time the event fires, so a moved or renamed toolset leaves every
# session in this project firing a missing command. Only OUR scripts are pruned: an entry
# pointing somewhere else is the project's own business.
pruned = []
for event in list(hooks.keys()):
    kept = []
    for entry in hooks[event]:
        live = []
        for h in entry.get("hooks", []):
            cmd = h.get("command", "")
            first = cmd.split()[0] if cmd.split() else ""
            ours = first.endswith((
                "capture.sh", "pull.sh", "on-prompt.sh",
                "session-ledger.sh", "session-digest.sh", "handoff-lib.sh"))
            if ours and first and not os.path.exists(first):
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
prune_note = ("pruned %d dead hook(s): %s; " % (len(pruned), ", ".join(sorted(set(pruned))))) if pruned else ""

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

# The router and the session ledger are wired only once their scripts exist, so a
# half-built checkout never registers a hook pointing at a missing file — a hook that
# cannot run is a broken session, not a missing feature.
on_prompt = os.path.join(sync, "on-prompt.sh")
ledger = os.path.join(sync, "session-ledger.sh")
if os.path.exists(on_prompt):
    ensure("UserPromptSubmit", None, on_prompt)
if os.path.exists(ledger):
    ensure("Stop", None, ledger)
digest = os.path.join(sync, "session-digest.sh")
if os.path.exists(digest):
    ensure("SessionStart", None, digest)

if changed:
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"install-project: {prune_note}wired {', '.join(changed)} hook(s) into {path}")
elif pruned:
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print(f"install-project: {prune_note.rstrip('; ')} — {path}")
else:
    print(f"install-project: already wired — {path} unchanged")
PY
STATUS=$?
if [ $STATUS -ne 0 ]; then exit $STATUS; fi

# NOTHING is written into the project except .claude/settings.local.json, which Claude Code
# already treats as machine-local. Earlier versions appended an ignore rule to the project's
# .gitignore — a tracked file, so connecting the mesh produced a diff the owner had to
# explain. Session breadcrumbs now default to the collection's state dir instead
# (see ledger_dir in lib.sh); a repo you do not own stays untouched.

echo "install-project: next session start in $(basename "$PROJ") may ask to approve the new hooks — that is expected."
