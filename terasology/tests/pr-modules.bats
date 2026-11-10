#!/usr/bin/env bats

REALM="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

# A fake engine checkout: the template build.gradle the harness copies into
# every module, and three module directories in the states a bay sees.
setup() {
    ENGINE="$BATS_TEST_TMPDIR/engine"
    mkdir -p "$ENGINE/templates" "$ENGINE/modules/Seeded" "$ENGINE/modules/Fetched" "$ENGINE/modules/NotAModule"
    printf 'template\n' > "$ENGINE/templates/build.gradle"
    printf 'name: Seeded\n' > "$ENGINE/modules/Seeded/module.txt"           # cloned from the parent: the ignored build.gradle did not come along
    printf 'name: Fetched\n' > "$ENGINE/modules/Fetched/module.txt"
    printf 'already here\n' > "$ENGINE/modules/Fetched/build.gradle"        # groovyw fetched it and copied the template itself
    printf 'junk\n' > "$ENGINE/modules/NotAModule/README.md"                # no module.txt: not a module, gets nothing
    cd "$ENGINE"
}

@test "ensure gives every module that lacks a build.gradle the template, and leaves the rest alone" {
    run bash "$REALM/terasology/pr-modules.sh" ensure
    [ "$status" -eq 0 ]
    [ "$(cat modules/Seeded/build.gradle)" = "template" ]
    [ "$(cat modules/Fetched/build.gradle)" = "already here" ]
    [ ! -e modules/NotAModule/build.gradle ]
    [[ "$output" == *"Seeded"* ]]
    [[ "$output" != *"Fetched"* ]]
}

@test "ensure says nothing when every module has its build file" {
    cp templates/build.gradle modules/Seeded/build.gradle
    run bash "$REALM/terasology/pr-modules.sh" ensure
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ensure fails when the engine has no template to copy" {
    rm templates/build.gradle
    run bash "$REALM/terasology/pr-modules.sh" ensure
    [ "$status" -ne 0 ]
    [[ "$output" == *"templates/build.gradle"* ]]
    [ ! -e modules/Seeded/build.gradle ]
}
