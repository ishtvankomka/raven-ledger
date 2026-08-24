#!/usr/bin/env bash
# Stop hook — dev-server hygiene (GLOBAL_PREFERENCES standing rule). If a known dev port is still
# listening when the agent tries to end its turn, bounce the stop back once with instructions.
# Loop-protected: if this hook already fired this turn (stop_hook_active), allow the stop.
# Fails OPEN. Requires lsof; if absent, no-op.
set -euo pipefail

ACTIVE="$(python3 -c '
import json,sys
try:
    print("1" if json.load(sys.stdin).get("stop_hook_active") else "")
except Exception:
    sys.exit(0)
' 2>/dev/null || true)"

[ -n "$ACTIVE" ] && exit 0
command -v lsof >/dev/null 2>&1 || exit 0

PORTS="3000 3001 4000 5173 5174 8000 8080 8081 19000 19006"
RUNNING=""
for p in $PORTS; do
  if lsof -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then RUNNING="$RUNNING $p"; fi
done

if [ -n "$RUNNING" ]; then
  # exit 2 on Stop asks the agent to continue rather than stop; message goes to the agent.
  echo "Dev server still listening on port(s):$RUNNING. Per GLOBAL_PREFERENCES, stop it (kill the process / lsof -ti:<port> | xargs kill) and verify the port is free before ending — unless the user asked to keep it running, in which case say so and stop." >&2
  exit 2
fi
exit 0
