#!/bin/bash
# Standalone secret gate: scans files (or a directory tree) with the same rules the
# capture pipeline uses. Exit 0 = clean, exit 1 = something secret-like found.
# Usage: secret-scan.sh <file-or-dir> [...]
set -u
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

FOUND=0
scan_one() {
  local abs
  abs="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"
  case "$abs" in "$SYNC_DIR"/*) return 0 ;; esac   # the mesh's own scripts scan clean
  if looks_secret "$1"; then
    echo "SECRET-LIKE: $1"
    FOUND=1
  fi
}

for target in "$@"; do
  if [ -d "$target" ]; then
    while IFS= read -r f; do scan_one "$f"; done \
      < <(find "$target" -type f -not -path '*/.git/*' -not -name '.DS_Store' 2>/dev/null)
  elif [ -f "$target" ]; then
    scan_one "$target"
  fi
done

[ "$FOUND" -eq 0 ] && echo "secret-scan: clean"
exit "$FOUND"
