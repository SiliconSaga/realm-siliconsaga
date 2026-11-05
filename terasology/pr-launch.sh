#!/usr/bin/env bash
# The launch check: a windowed boot. The `game` task adds --homedir=. itself, so the checkout
# is the home directory; --create-last-game makes a fresh world from the seed
# save pr-seed.sh restored; --no-save-games keeps the run from writing one back.
# Readiness is the renderer's own log line, which a real run shows about six
# seconds after the world seed and before the first chunks tick; after a settle
# the primary display is captured and the game stopped.
#
# cwd: the engine checkout. Writes $NAUST_JOB_DIR/game.log (the game's own
# output), screenshot.png and game-logs/. This script's lines go to stdout and
# stderr, which naust appends to the step's launch.log: the game's file must be
# a different one, or Gradle's writes clobber the step log and grep refuses to
# read the file it is writing to.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=terasology/pr-lib.sh
. "$HERE/pr-lib.sh"
JOB="${NAUST_JOB_DIR:?pr-launch: NAUST_JOB_DIR is required}"
TIMEOUT="${NAUST_LAUNCH_TIMEOUT:-900}"
SETTLE="${NAUST_SETTLE_SECONDS:-45}"
LOG="$JOB/game.log"
SHOT="$JOB/screenshot.png"

if [ ! -f saves/naust-seed/manifest.json ]; then
  echo "launch: no seed save at saves/naust-seed/manifest.json (pr-seed.sh restore did not run); --create-last-game would fail with 'last game not found'" >&2
  exit 1
fi
rm -rf logs "$SHOT"
before="$(terasology_jvms --no-save-games | tr '\n' ' ')"
./gradlew game --args="--create-last-game --no-splash --no-crash-report --no-save-games" > "$LOG" 2>&1 &
pid=$!
# Whatever ends this script, the game it started does not outlive it.
trap 'stop_game "$pid" --no-save-games "$before"' EXIT
trap 'exit 130' INT     # a signal ends the boot at once and as a failure
trap 'exit 143' TERM
rc=0
if wait_for_marker "$LOG" "Initialising rendering class" "$TIMEOUT" "$pid"; then
  sleep "$SETTLE"
  if kill -0 "$pid" 2>/dev/null; then
    screenshot "$SHOT" || { echo "launch: screenshot failed" >&2; rc=1; }
  else
    echo "launch: the game exited during the ${SETTLE}s settle; last lines:" >&2
    tail -n 5 "$LOG" >&2 || true
    rc=1
  fi
else
  rc=1
  grep -F 'last game not found' "$LOG" >&2 || true
  echo "launch: last lines of $LOG:" >&2
  tail -n 5 "$LOG" >&2 || true
fi
stop_game "$pid" --no-save-games "$before"
if [ -d logs ]; then rm -rf "$JOB/game-logs"; cp -r logs "$JOB/game-logs"; fi
[ -f "$SHOT" ] || rc=1
[ "$rc" -eq 0 ] && echo "launch: renderer up, screenshot at $SHOT, game stopped"
exit "$rc"
