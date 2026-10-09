#!/usr/bin/env bats

REALM="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

@test "the Terasology profile carries every key naust reads, and none it stopped reading" {
    for k in .component .repo .persona .poll.debounce_minutes .poll.skip_drafts .bay.ready_ttl_days \
             .steps.compile_all .steps.headless .steps.smoke .hooks.after_add .hooks.after_reset .report.comment; do
        v="$(yq "$k" "$REALM/naust/terasology.yaml")"
        [ -n "$v" ] && [ "$v" != null ] || { echo "missing $k"; false; }
    done
    for k in .runtime_dirs .known_dirt .nested .upstream_remote .default_branch .init; do
        [ "$(yq "$k" "$REALM/naust/terasology.yaml")" = null ] || { echo "$k belongs in the adapter now"; false; }
    done
}

@test "the Terasology adapter says how to provision and reset the tree" {
    a="$REALM/adapters/terasology.yaml"
    [ "$(yq '.provision.init' "$a")" = "bash ./groovyw module init omega" ]
    [ "$(yq '.provision.runtime_dirs | length' "$a")" -eq 3 ]
    [ "$(yq '.provision.known_dirt | length' "$a")" -ge 1 ]
    [ "$(yq '.nested | length' "$a")" -ge 2 ]
}

@test "the profile's scripts exist beside this test" {
    for s in pr-headless.sh pr-smoke.sh pr-seed.sh pr-lib.sh screenshot.ps1 seed-manifest.template.json; do
        [ -f "$REALM/terasology/$s" ] || { echo "missing terasology/$s"; false; }
    done
    grep -q 'pr-headless.sh' "$REALM/naust/terasology.yaml"
    grep -q 'pr-smoke.sh' "$REALM/naust/terasology.yaml"
    grep -q 'pr-seed.sh' "$REALM/naust/terasology.yaml"
}

@test "the trust list names at least one maintainer and the nod phrase, and no label" {
    [ "$(yq '.terasology.maintainers | length' "$REALM/naust/trust.yaml")" -ge 1 ]
    [ "$(yq '.terasology.nod_phrase' "$REALM/naust/trust.yaml")" = "ok to test" ]
    [ "$(yq '.terasology.nod_label' "$REALM/naust/trust.yaml")" = null ]
}
