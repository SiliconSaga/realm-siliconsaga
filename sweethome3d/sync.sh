#!/usr/bin/env bash
# Pull new upstream revisions from SVN into the mirror's `upstream` branch.
# Manual for now:  bash sync.sh
# Later: the same script is invoked by a scheduled GitHub Action (which adds the
# .git/svn metadata-rehydration wrapper for ephemeral runners — core logic unchanged).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

if [ ! -d "$COMPONENT_DIR/.git" ]; then
  echo "error: no clone at $COMPONENT_DIR — run clone.sh first." >&2
  exit 1
fi

echo ">> git svn fetch"
"$GIT_BIN" -C "$COMPONENT_DIR" svn fetch --ignore-paths="$IGNORE_PATHS"

echo ">> fast-forwarding '$UPSTREAM_BRANCH' to SVN trunk"
"$GIT_BIN" -C "$COMPONENT_DIR" checkout -q "$UPSTREAM_BRANCH"
"$GIT_BIN" -C "$COMPONENT_DIR" merge --ff-only remotes/origin/trunk

echo ">> '$UPSTREAM_BRANCH' now at:"
"$GIT_BIN" -C "$COMPONENT_DIR" log -1 --format='   %h  %an  %ad  %s'

# Not yet automated (manual phase):
#   - push '$UPSTREAM_BRANCH' to the GitHub mirror
#   - open / update a PR  upstream -> main  (resolve the one build.xml hook conflict if any)
