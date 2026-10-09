#!/usr/bin/env bats

REALM="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

# A fake engine checkout whose gradlew prints a marker after a moment and then
# lingers like a game would; the scripts must find the marker and stop it.
setup() {
    ENGINE="$BATS_TEST_TMPDIR/engine"
    export NAUST_JOB_DIR="$BATS_TEST_TMPDIR/job"
    mkdir -p "$ENGINE" "$NAUST_JOB_DIR" "$BATS_TEST_TMPDIR/bin"
    export NAUST_SCREENSHOT_CMD="touch"
    export NAUST_JPS_CMD="true"
    export NAUST_SETTLE_SECONDS=0 NAUST_HEADLESS_TIMEOUT=20 NAUST_SMOKE_TIMEOUT=20
    export MARKER_HEADLESS="12:00:00.000 [main] INFO  o.t.e.n.internal.NetworkSystemImpl - Server started"
    export MARKER_RENDER="12:00:00.000 [main] INFO  o.t.e.r.world.WorldRendererImpl - Initialising rendering class CoreRenderingModule from CoreRendering module."
    cat > "$ENGINE/gradlew" <<'EOF'
#!/usr/bin/env bash
echo "gradlew $*" >> "$GRADLEW_LOG"
echo $$ > "$GRADLEW_PID"
sleep 1
case "$1" in
  server) mkdir -p terasology-server/logs; echo "$MARKER_HEADLESS" ;;
  game)   mkdir -p logs/run; echo "menu"; [ -n "${NO_MARKER:-}" ] || echo "$MARKER_RENDER" ;;
esac
sleep 120
EOF
    chmod +x "$ENGINE/gradlew"
    export GRADLEW_LOG="$BATS_TEST_TMPDIR/gradlew.log"
    export GRADLEW_PID="$BATS_TEST_TMPDIR/gradlew.pid"
    cd "$ENGINE"
}

# The fake gradlew must be gone: the scripts promise to stop what they start.
gradlew_stopped() { ! kill -0 "$(cat "$GRADLEW_PID")" 2>/dev/null; }

@test "headless boots the server, sees Server started, stops it and keeps the logs" {
    run bash "$REALM/terasology/pr-headless.sh"
    [ "$status" -eq 0 ]
    grep -q 'Server started' "$NAUST_JOB_DIR/headless.log"
    grep -q '^gradlew server' "$GRADLEW_LOG"
    [ -d "$NAUST_JOB_DIR/headless-logs" ]
    gradlew_stopped
}

@test "headless fails on timeout and still stops the process" {
    export MARKER_HEADLESS="nothing useful"
    export NAUST_HEADLESS_TIMEOUT=4
    run bash "$REALM/terasology/pr-headless.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"timeout"* ]]
    gradlew_stopped
}

@test "smoke needs the seed save" {
    run bash "$REALM/terasology/pr-smoke.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no seed save"* ]]
    [ ! -s "$GRADLEW_LOG" ]
}

@test "smoke boots with the create-last-game flags, screenshots after the renderer line, stops" {
    mkdir -p saves/naust-seed; printf '{"title":"naust-seed"}\n' > saves/naust-seed/manifest.json
    run bash "$REALM/terasology/pr-smoke.sh"
    [ "$status" -eq 0 ]
    grep -q -- 'gradlew game --args=--create-last-game --no-splash --no-crash-report --no-save-games' "$GRADLEW_LOG"
    grep -q 'Initialising rendering class' "$NAUST_JOB_DIR/smoke.log"
    [ -f "$NAUST_JOB_DIR/screenshot.png" ]
    [ -d "$NAUST_JOB_DIR/game-logs/run" ]
    gradlew_stopped
}

@test "smoke fails when the renderer line never comes, keeping the log tail" {
    mkdir -p saves/naust-seed; printf '{"title":"naust-seed"}\n' > saves/naust-seed/manifest.json
    export NO_MARKER=1 NAUST_SMOKE_TIMEOUT=4
    run bash "$REALM/terasology/pr-smoke.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"timeout"* ]]
    [ ! -e "$NAUST_JOB_DIR/screenshot.png" ]
    grep -q 'menu' "$NAUST_JOB_DIR/smoke.log"
}
