#!/usr/bin/env bash
# PreCompact hook. PreCompact CANNOT inject context (additionalContext is ignored for this event),
# so this drops a breadcrumb file instead; the SessionStart hook reads it after compaction and
# injects the reminder then (SessionStart source=compact DOES honor additionalContext). Never
# blocks compaction. Fails OPEN.
set -euo pipefail
DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/handoff"
mkdir -p "$DIR" 2>/dev/null || exit 0
: > "$DIR/.compaction-pending" 2>/dev/null || true
exit 0
