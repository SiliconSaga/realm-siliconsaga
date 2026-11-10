#!/usr/bin/env bash
# Headless pre-flight: boot the engine as a server (the facade's `server` task,
# --headless, home directory terasology-server/) and wait for the network layer
# to say "Started server on port", which means the engine initialised and a
# world loaded with no window involved. NetworkSystemImpl logs that line
# unconditionally once it binds; its "Server started" comes only when the
# asynchronous bind has already finished at that instant, which it mostly has
# not, so a boot that worked would wait out the timeout on it. Headless setup
# builds its own manifest from the default module selection when no save
# exists, so no seed is needed.
#
# cwd: the engine checkout. Writes $NAUST_JOB_DIR/server.log (the server's own
# output) and headless-logs/. This script's lines go to stdout and stderr, which
# naust appends to the step's headless.log, so the server's file is a different one.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=terasology/pr-lib.sh
. "$HERE/pr-lib.sh"
JOB="${NAUST_JOB_DIR:?pr-headless: NAUST_JOB_DIR is required}"
TIMEOUT="${NAUST_HEADLESS_TIMEOUT:-900}"
LOG="$JOB/server.log"

# The engine resolves --homedir with toRealPath before it writes anything
# there, so the directory must exist, and the reset has just removed it.
rm -rf terasology-server
mkdir -p terasology-server
before="$(terasology_jvms --headless | tr '\n' ' ')"
./gradlew server > "$LOG" 2>&1 &
pid=$!
# Whatever ends this script, the server it started does not outlive it; a
# signal ends it at once and as a failure, never as the success line below.
trap 'stop_game "$pid" --headless "$before"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
rc=0
wait_for_marker "$LOG" "Started server on port" "$TIMEOUT" "$pid" || rc=1
stop_game "$pid" --headless "$before"
if [ -d terasology-server/logs ]; then rm -rf "$JOB/headless-logs"; cp -r terasology-server/logs "$JOB/headless-logs"; fi
[ "$rc" -eq 0 ] && echo "headless: server started and stopped cleanly"
exit "$rc"
