#!/bin/bash
# Manually scan one project and push every un-synced agent/command/skill into the
# collection right now (synchronous, prints a summary).
# Usage: push-project.sh [project-dir] [--include-existing]
#
# --include-existing ignores the first-contact baseline and stages the project's PRE-EXISTING
# agents/commands/skills too. Off by default: connecting the mesh to a repo you did not write
# should observe what happens next, not drain what is already there.
set -u
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

PROJ="$(cd "${1:-$PWD}" && pwd)" || exit 1
if [ ! -d "$PROJ/.claude" ]; then
  echo "push-project: $PROJ has no .claude/ directory" >&2
  exit 1
fi
if [ "$PROJ" = "$RAVEN_ROOT" ]; then
  echo "push-project: refusing to scan the collection itself" >&2
  exit 1
fi

MODE=""
for a in "$@"; do [ "$a" = "--include-existing" ] && MODE="--include-existing"; done
COUNT="$(scan_project "$PROJ" "$MODE")"
echo "push-project($(basename "$PROJ")): captured $COUNT new/changed item(s)"
# Subject stays generic: the pushed git log is as public as the files (see lib.sh's
# flush policy) — the project name is already in the local log via scan_project.
collection_git_flush "capture: manual push-project"
echo "push-project: done (see $LOG_FILE for details)"
