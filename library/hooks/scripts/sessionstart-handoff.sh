#!/usr/bin/env bash
# SessionStart hook. When a session starts from a compaction (breadcrumb left by precompact-handoff),
# inject the handoff reminder via additionalContext — the real, supported injection channel for
# SessionStart. Clears the breadcrumb so it fires once. No-op on normal startups. Fails OPEN.
set -euo pipefail
MARK="${CLAUDE_PROJECT_DIR:-.}/.claude/handoff/.compaction-pending"
[ -f "$MARK" ] || exit 0
rm -f "$MARK" 2>/dev/null || true
cat <<'MSG'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Context was just compacted. Before continuing, reconstruct working state from a handoff capsule rather than the lossy auto-summary: check .claude/handoff/ for the latest HANDOFF-*.md, or write one per .claude/library/handoff/HANDOFF_TEMPLATE.md (open tasks, current DoD pass/fail, next step, known blockers) if none exists."}}
MSG
exit 0
