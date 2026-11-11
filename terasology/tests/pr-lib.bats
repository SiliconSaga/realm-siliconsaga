#!/usr/bin/env bats

REALM="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
    # shellcheck source=../pr-lib.sh
    . "$REALM/terasology/pr-lib.sh"
}

# The listing is every Java process as "<pid> <command line>", the shape ps and
# the Windows process table both give. jps is not it: jps lists only the JVMs
# whose perf-data file it can see, which misses a game a human started from
# another session, so the check could not tell that game from its own.
@test "terasology_jvms finds the engine by its main class in a process listing and filters by argument" {
    cat > "$BATS_TEST_TMPDIR/procs" <<'EOF'
111 D:\Java\bin\java.exe -Xmx512m -cp gradle-daemon-main.jar org.gradle.launcher.daemon.bootstrap.GradleDaemon 9.6.1
222 D:\Java\bin\java.exe -cp engine.jar org.terasology.engine.Terasology --homedir=. --create-last-game --no-crash-report
333 D:\Java\bin\java.exe -cp engine.jar org.terasology.engine.Terasology --homedir=.
444 D:\Java\bin\java.exe -cp engine.jar org.terasology.engine.Terasology --headless --homedir=terasology-server
555 D:\Java\bin\java.exe -cp other.jar org.terasology.engine.TerasologyLauncher --no-crash-report
EOF
    export NAUST_JVM_LIST_CMD="cat $BATS_TEST_TMPDIR/procs"
    [ "$(terasology_jvms)" = $'222\n333\n444' ]
    [ "$(terasology_jvms --no-crash-report)" = "222" ]
    [ "$(terasology_jvms --headless)" = "444" ]
}

@test "terasology_jvms is empty, not an error, when the listing command fails" {
    export NAUST_JVM_LIST_CMD="false"
    run terasology_jvms
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
