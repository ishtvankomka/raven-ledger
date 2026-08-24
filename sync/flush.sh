#!/bin/bash
# PUBLISH: commit staged incoming/ captures and push pending collection commits.
# This is the ONLY thing in the mesh that sends anything off this machine, and it is
# never called from a hook — /promote calls it after a human has reviewed, or you run
# it yourself deliberately.
# Usage: flush.sh [commit-message]   (a subject that names a project is a leak — don't)
set -u
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
collection_git_flush "${1:-sync: publish reviewed captures}"
