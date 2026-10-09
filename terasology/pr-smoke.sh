#!/usr/bin/env bash
# Windowed smoke boot. The `game` task adds --homedir=. itself, so the checkout
# is the home directory; --create-last-game makes a fresh world from the seed
# save pr-seed.sh restored; --no-save-games keeps the run from writing one back.
# Readiness is the renderer's own log line, which a real run shows about six
# seconds after the world seed and before the first chunks tick; after a settle
# the primary display is captured and the game stopped.
#
# cwd: the engine checkout. Writes $NAUST_JOB_DIR/smoke.log, screenshot.png, game-logs/.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=terasology/pr-lib.sh
. "$HERE/pr-lib.sh"
JOB="${NAUST_JOB_DIR:?pr-smoke: NAUST_JOB_DIR is required}"
TIMEOUT="${NAUST_SMOKE_TIMEOUT:-900}"
SETTLE="${NAUST_SETTLE_SECONDS:-45}"
LOG="$JOB/smoke.log"
SHOT="$JOB/screenshot.png"

if [ ! -f saves/naust-seed/manifest.json ]; then
  echo "smoke: no seed save at saves/naust-seed/manifest.json (pr-seed.sh restore did not run); --create-last-game would fail with 'last game not found'" >&2
  exit 1
fi
rm -rf logs "$SHOT"
./gradlew game --args="--create-last-game --no-splash --no-crash-report --no-save-games" > "$LOG" 2>&1 &
pid=$!
rc=0
if wait_for_marker "$LOG" "Initialising rendering class" "$TIMEOUT" "$pid"; then
  sleep "$SETTLE"
  screenshot "$SHOT" || { echo "smoke: screenshot failed" >&2; rc=1; }
else
  rc=1
  grep -F 'last game not found' "$LOG" >&2 || true
fi
stop_game "$pid"
if [ -d logs ]; then rm -rf "$JOB/game-logs"; cp -r logs "$JOB/game-logs"; fi
[ -f "$SHOT" ] || rc=1
[ "$rc" -eq 0 ] && echo "smoke: renderer up, screenshot at $SHOT, game stopped"
exit "$rc"
