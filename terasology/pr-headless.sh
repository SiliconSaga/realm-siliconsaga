#!/usr/bin/env bash
# Headless pre-flight: boot the engine as a server (the facade's `server` task,
# --headless, home directory terasology-server/) and wait for the network layer
# to say "Server started", which means the engine initialised and a world
# loaded with no window involved. Headless setup builds its own manifest from
# the default module selection when no save exists, so no seed is needed.
#
# cwd: the engine checkout. Writes $NAUST_JOB_DIR/headless.log and headless-logs/.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=terasology/pr-lib.sh
. "$HERE/pr-lib.sh"
JOB="${NAUST_JOB_DIR:?pr-headless: NAUST_JOB_DIR is required}"
TIMEOUT="${NAUST_HEADLESS_TIMEOUT:-900}"
LOG="$JOB/headless.log"

rm -rf terasology-server
./gradlew server > "$LOG" 2>&1 &
pid=$!
rc=0
wait_for_marker "$LOG" "Server started" "$TIMEOUT" "$pid" || rc=1
stop_game "$pid"
if [ -d terasology-server/logs ]; then rm -rf "$JOB/headless-logs"; cp -r terasology-server/logs "$JOB/headless-logs"; fi
[ "$rc" -eq 0 ] && echo "headless: server started and stopped cleanly"
exit "$rc"
