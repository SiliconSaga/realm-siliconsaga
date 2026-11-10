#!/usr/bin/env bats

REALM="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

# A fake engine checkout whose gradlew prints a marker after a moment and then
# lingers like a game would; the scripts must find the marker and stop it.
setup() {
    ENGINE="$BATS_TEST_TMPDIR/engine"
    export NAUST_JOB_DIR="$BATS_TEST_TMPDIR/job"
    mkdir -p "$ENGINE" "$NAUST_JOB_DIR" "$BATS_TEST_TMPDIR/bin"
    # A stand-in for the screenshot: writes the file and records what it was asked for.
    cat > "$BATS_TEST_TMPDIR/bin/shot" <<'EOF'
#!/usr/bin/env bash
echo "shot $*" >> "$SHOT_LOG"; touch "$1"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/shot"
    export NAUST_SCREENSHOT_CMD="$BATS_TEST_TMPDIR/bin/shot" SHOT_LOG="$BATS_TEST_TMPDIR/shot.log"
    export NAUST_JPS_CMD="true"
    export NAUST_SETTLE_SECONDS=0 NAUST_HEADLESS_TIMEOUT=20 NAUST_LAUNCH_TIMEOUT=20
    export MARKER_HEADLESS="12:00:00.000 [main] INFO  o.t.e.n.internal.NetworkSystemImpl - Started server on port 25777"
    export MARKER_RENDER="12:00:00.000 [main] INFO  o.t.e.r.world.WorldRendererImpl - Initialising rendering class CoreRenderingModule from CoreRendering module."
    cat > "$ENGINE/gradlew" <<'EOF'
#!/usr/bin/env bash
echo "gradlew $*" >> "$GRADLEW_LOG"
echo $$ > "$GRADLEW_PID"
sleep 1
case "$1" in
  # The engine resolves --homedir with toRealPath before it creates anything,
  # so a home directory that does not exist yet is a crash, not a mkdir.
  server) [ -d terasology-server ] || { echo "NoSuchFileException: terasology-server"; exit 1; }
          mkdir -p terasology-server/logs; echo "$MARKER_HEADLESS" ;;
  game)   mkdir -p logs/run; echo "menu"; [ -n "${NO_MARKER:-}" ] || echo "$MARKER_RENDER" ;;
esac
[ -z "${EXIT_AFTER_MARKER:-}" ] || exit 0      # a crash right after the marker
sleep 120
EOF
    chmod +x "$ENGINE/gradlew"
    export GRADLEW_LOG="$BATS_TEST_TMPDIR/gradlew.log"
    export GRADLEW_PID="$BATS_TEST_TMPDIR/gradlew.pid"
    cd "$ENGINE"
}

# The fake gradlew must be gone: the scripts promise to stop what they start.
gradlew_stopped() { ! kill -0 "$(cat "$GRADLEW_PID")" 2>/dev/null; }

@test "headless boots the server, sees it bind its port, stops it and keeps the logs" {
    run bash "$REALM/terasology/pr-headless.sh"
    [ "$status" -eq 0 ]
    grep -q 'Started server on port' "$NAUST_JOB_DIR/server.log"
    grep -q '^gradlew server' "$GRADLEW_LOG"
    [ -d "$NAUST_JOB_DIR/headless-logs" ]
    gradlew_stopped
}

# naust runs each step with its output appended to <step>.log in the job
# directory, so the server's own output must land in a file of its own: a
# script that truncated the step log for Gradle would clobber the step's
# lines, and grep refuses to read the file it is writing to.
@test "headless keeps the server's output apart from the step log it runs under" {
    bash "$REALM/terasology/pr-headless.sh" >> "$NAUST_JOB_DIR/headless.log" 2>&1
    grep -q 'Started server on port' "$NAUST_JOB_DIR/server.log"
    grep -q 'stopped cleanly' "$NAUST_JOB_DIR/headless.log"
    ! grep -q 'Started server on port' "$NAUST_JOB_DIR/headless.log"
}

@test "headless fails on timeout and still stops the process" {
    export MARKER_HEADLESS="nothing useful"
    export NAUST_HEADLESS_TIMEOUT=4
    run bash "$REALM/terasology/pr-headless.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"timeout"* ]]
    gradlew_stopped
}

@test "a terminated boot stops the server at once and does not report success" {
    # TERM rather than INT: a background job in a non-interactive shell starts
    # with INT ignored, and a script cannot trap a signal it inherited ignored.
    export MARKER_HEADLESS="nothing useful"      # a boot still waiting when the signal comes
    bash "$REALM/terasology/pr-headless.sh" > "$BATS_TEST_TMPDIR/out" 2>&1 &
    script=$!
    for _ in $(seq 1 50); do [ -s "$GRADLEW_PID" ] && break; sleep 0.2; done   # the boot is up and its traps set
    [ -s "$GRADLEW_PID" ]
    kill -TERM "$script"
    status=0; wait "$script" || status=$?
    [ "$status" -eq 143 ]                        # not the timeout's 1 twenty seconds later
    [[ "$(cat "$BATS_TEST_TMPDIR/out")" != *"stopped cleanly"* ]]
    gradlew_stopped
}

@test "launch needs the seed save" {
    run bash "$REALM/terasology/pr-launch.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no seed save"* ]]
    [ ! -s "$GRADLEW_LOG" ]
}

@test "launch boots with the create-last-game flags, screenshots the game's window after the renderer line, stops" {
    mkdir -p saves/naust-seed; printf '{"title":"naust-seed"}\n' > saves/naust-seed/manifest.json
    run bash "$REALM/terasology/pr-launch.sh"
    [ "$status" -eq 0 ]
    grep -q -- 'gradlew game --args=--create-last-game --no-splash --no-crash-report$' "$GRADLEW_LOG"   # no --no-save-games: the engine cannot load a world under it
    grep -q 'Initialising rendering class' "$NAUST_JOB_DIR/game.log"
    [ -f "$NAUST_JOB_DIR/screenshot.png" ]
    # The window by its title, never "the primary display": on a machine with several, the game opens wherever the OS puts it.
    grep -q 'screenshot.png Terasology Alpha$' "$SHOT_LOG"
    [ -d "$NAUST_JOB_DIR/game-logs/run" ]
    gradlew_stopped
}

@test "screenshot.ps1 still captures a picture when no window carries the title (Windows only)" {
    case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ;; *) skip "Windows only" ;; esac
    unset NAUST_SCREENSHOT_CMD
    . "$REALM/terasology/pr-lib.sh"
    run screenshot "$BATS_TEST_TMPDIR/idle.png" "No Such Window Title"
    [ "$status" -eq 0 ]
    [ -s "$BATS_TEST_TMPDIR/idle.png" ]
}

@test "launch keeps the game's output apart from the step log it runs under" {
    mkdir -p saves/naust-seed; printf '{"title":"naust-seed"}\n' > saves/naust-seed/manifest.json
    bash "$REALM/terasology/pr-launch.sh" >> "$NAUST_JOB_DIR/launch.log" 2>&1
    grep -q 'Initialising rendering class' "$NAUST_JOB_DIR/game.log"
    grep -q 'renderer up' "$NAUST_JOB_DIR/launch.log"
    ! grep -q 'Initialising rendering class' "$NAUST_JOB_DIR/launch.log"
}

@test "launch fails when the game exits right after the renderer line" {
    mkdir -p saves/naust-seed; printf '{"title":"naust-seed"}\n' > saves/naust-seed/manifest.json
    export EXIT_AFTER_MARKER=1
    run bash "$REALM/terasology/pr-launch.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"exited"* ]]
    [ ! -e "$NAUST_JOB_DIR/screenshot.png" ]
}

@test "headless fails when the server exits right after binding its port" {
    export EXIT_AFTER_MARKER=1
    run bash "$REALM/terasology/pr-headless.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"exited"* ]]
}

@test "launch fails when the renderer line never comes, keeping the log tail" {
    mkdir -p saves/naust-seed; printf '{"title":"naust-seed"}\n' > saves/naust-seed/manifest.json
    export NO_MARKER=1 NAUST_LAUNCH_TIMEOUT=4
    run bash "$REALM/terasology/pr-launch.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"timeout"* ]]
    [[ "$output" == *"menu"* ]]                 # the game log's tail, so the step log says what the game last did
    [ ! -e "$NAUST_JOB_DIR/screenshot.png" ]
    grep -q 'menu' "$NAUST_JOB_DIR/game.log"
}
