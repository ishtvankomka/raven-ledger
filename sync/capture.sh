#!/bin/bash
# PostToolUse hook (Write|Edit) installed in projects that use the collection.
# When Claude (or an agent) writes a file under .claude/agents|commands|skills,
# the file is captured into the collection's incoming/<project>/ area — and stays
# local. Publication is a separate human step (flush.sh via /promote).
# Fast path: exits in ~0ms for every edit that doesn't touch .claude/.

INPUT="$(cat)"
case "$INPUT" in
  *'.claude/agents/'* | *'.claude/commands/'* | *'.claude/skills/'*) ;;
  *) exit 0 ;;
esac

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

FILE_PATH="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get("tool_input") or {}
print(ti.get("file_path") or ti.get("notebook_path") or "")' 2>/dev/null)"
[ -n "$FILE_PATH" ] || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("cwd") or "")
except Exception:
    pass' 2>/dev/null)"
fi
[ -d "$PROJECT_DIR" ] || exit 0
[ "$PROJECT_DIR" = "$RAVEN_ROOT" ] && exit 0

# Capture only. NOTHING is committed or pushed here — publication is a human step
# (`/promote`). A hook that pushed on every write meant files left the machine before
# anyone had read them, and no later review could unpublish them.
capture_file "$FILE_PATH" "$PROJECT_DIR"
exit 0
