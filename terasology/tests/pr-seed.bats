#!/usr/bin/env bats

REALM="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SEED="$REALM/terasology/pr-seed.sh"

setup() {
    ENGINE="$BATS_TEST_TMPDIR/engine"
    export NAUST_BAY_DIR="$BATS_TEST_TMPDIR/bay"
    mkdir -p "$ENGINE/engine/src/main/resources/org/terasology/engine"
    printf '{ "id": "engine", "version": "5.4.0-SNAPSHOT" }\n' > "$ENGINE/engine/src/main/resources/org/terasology/engine/module.txt"
    for m in CoreSampleGameplay CoreAssets CoreAdvancedAssets CoreRendering CoreWorlds Health Inventory BiomesAPI; do
        mkdir -p "$ENGINE/modules/$m"
        printf '{\n    "id": "%s",\n    "version": "%s"\n}\n' "$m" "1.2.3-SNAPSHOT" > "$ENGINE/modules/$m/module.txt"
    done
    cd "$ENGINE"
}

@test "generate fills every version from the checkout" {
    run bash "$SEED" generate
    [ "$status" -eq 0 ]
    out="$NAUST_BAY_DIR/.tmp/naust/seed/manifest.json"
    [ -f "$out" ]
    ! grep -q '@' "$out"
    grep -q '"name": "engine", "version": "5.4.0-SNAPSHOT"' "$out"
    grep -q '"name": "CoreSampleGameplay", "version": "1.2.3-SNAPSHOT"' "$out"
    grep -q '"title": "naust-seed"' "$out"
}

@test "generate names a module whose descriptor is missing" {
    rm -r "$ENGINE/modules/Health"
    run bash "$SEED" generate
    [ "$status" -ne 0 ]
    [[ "$output" == *"Health"* ]]
}

@test "restore copies the generated manifest into saves/naust-seed" {
    bash "$SEED" generate
    run bash "$SEED" restore
    [ "$status" -eq 0 ]
    [ -f "$ENGINE/saves/naust-seed/manifest.json" ]
    cmp -s "$ENGINE/saves/naust-seed/manifest.json" "$NAUST_BAY_DIR/.tmp/naust/seed/manifest.json"
}

@test "restore without a generated seed fails and says to generate" {
    run bash "$SEED" restore
    [ "$status" -ne 0 ]
    [[ "$output" == *"generate"* ]]
}
