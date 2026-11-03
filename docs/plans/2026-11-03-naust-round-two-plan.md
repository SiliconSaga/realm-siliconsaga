# Naust round two Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the dispatcher's realm trust check cost well under a second, make a bay watchable while it works, stop a bay re-fetching what the parent already has, fail a bay add before cloning when its realm pin cannot be met, and land the agreed renames.

**Architecture:** The trust fingerprint keeps its value and its semantics; it is computed with two `yq` processes instead of two per adapter, and then answered from a content-keyed cache that one `git hash-object` call validates. Bays get a log file under their own `.outputs/`, written by `ws bay` and by naust alike, with `ws bay log` to tail it. `ws bay add` seeds components and nested repositories from the parent's checkouts with `git clone --reference-if-able --dissociate`, so the network fetches only what the parent lacks. Everything else is a small edit with a test that failed first.

**Tech Stack:** bash 3.2-compatible scripts, yq v4, git 2.55, bats. Three repositories: yggdrasil (`scripts/`, `tests/`), the naust component (`components/naust`), the realm (`realms/realm-siliconsaga`).

**Spec:** `realms/realm-siliconsaga/docs/plans/2026-10-30-naust-bring-up-round-two-design.md`

## Global Constraints

- bash 3.2: no associative arrays, no `wait -n`, empty arrays expand as `${arr[@]+"${arr[@]}"}`.
- `type -P yq`, never `command -v yq` in `scripts/` (a workspace test enforces it).
- Never `cmd | head` under `set -o pipefail`.
- The trust fingerprint's value for unchanged inputs must not change: the golden values in Task 1 are the contract.
- Commits through `ws commit <target> <bodyfile>` with a `.commits/*.md` bodyfile (frontmatter `message:` and `add:`); file moves are a plain `mv` with both paths in `add:`, never `git mv`. Nothing is pushed in this plan.
- Test commands: yggdrasil `ws test yggdrasil tests/<suite>/<file>.bats`; naust `bash components/naust/tests/run.sh test tests/<file>.bats`; realm `bash realms/realm-siliconsaga/terasology/tests/run.sh`. Shellcheck: `bash scripts/ws-shellcheck.sh`.
- Prose in docs is never hard-wrapped; reference docs describe the current state only.
- Branches: Tasks 1 to 3 on yggdrasil `feat/realm-trust-fast` cut from `siliconsaga/main` (310c2fb8d); Tasks 5, 7, 8 on yggdrasil `feat/ws-bays-next`; Tasks 4, 6, 9a on naust `feat/phase1`; Task 9b on the realm's `feat/naust-terasology-next`. The parent's realm checkout returns to `main` before Task 10, because a bay's realm pin must be a pushed commit.

## Review Focus

1. An adapter file holding two YAML documents: refused with the file named, as today, never silently attributed to the wrong adapter (Task 1 pins it, Task 2 keeps it).
2. A command value with an embedded line break: every line is still scanned for referenced helpers against the same adapter's target directory (Task 1 golden, Task 2).
3. A helper file changed after the cache was written, or replaced by a symlink to identical content: the cache misses and the full computation runs its symlink refusal (Task 3).
4. A parent component with no declared repository URL, or a seed clone that fails: `ws bay add` falls back to the bay's own `ws clone` and still succeeds (Task 8).
5. `ws bay log` on a bay that has never been added or reset through the verb: a clear error, not an empty tail or a hang (Task 5).

---

### Task 1: Pin the trust fingerprint before touching its computation

**Files:**
- Create: `tests/ws-realm/fingerprint.bats`

**Interfaces:**
- Consumes: `ws_realm_trust_fingerprint <realm> [<captured_adapter_path> <captured_content>]` from `scripts/ws-realm.sh`, prints a 40-hex fingerprint.
- Produces: four golden tests every later task in this group must keep green.

- [ ] **Step 1: Cut the branch**

Run: `ws checkout yggdrasil main` then `ws checkout yggdrasil feat/realm-trust-fast -b`
Expected: on `feat/realm-trust-fast` at 310c2fb8d.

- [ ] **Step 2: Write the golden tests**

`setup()` is the fixture from `tests/ws-realm/trust.bats` lines 7 to 43 verbatim (realm `realm.test` with that `ecosystem.yaml`, `adapters/app.yaml`, `adapters/tool.yaml`, an empty `tools/`, `components/app`). Helper `fingerprint() { run bash -c 'source "$1"; ws_realm_trust_fingerprint realm.test' _ "$REALM_LIB"; }`.

```bash
@test "the two-adapter fixture fingerprints to its golden value" {
    fingerprint
    [ "$status" -eq 0 ]
    [ "$output" = "2038d91a26b048a9ccc713a67dc25e6c7ca6848b" ]
}

@test "a referenced helper and a provision.init helper join the fingerprint" {
    printf '#!/usr/bin/env bash\necho hi\n' > "$REALMS_DIR/realm.test/tools/helper.sh"
    mkdir -p "$COMPONENTS_DIR/helped"
    cat > "$REALMS_DIR/realm.test/adapters/helped.yaml" <<'YAML'
commands:
  test: bash ../../realms/realm.test/tools/helper.sh
provision:
  init: bash "../../realms/realm.test/tools/helper.sh" init
YAML
    fingerprint
    [ "$status" -eq 0 ]
    [ "$output" = "7215116d038159e36c4458ea7a1550393f1480c7" ]
}

@test "every line of a multi-line command is scanned for helpers" {
    rm "$REALMS_DIR/realm.test/adapters/tool.yaml"
    printf 'components:\n  app:\n    tier: supporting\n' > "$REALMS_DIR/realm.test/ecosystem.yaml"
    printf '#!/usr/bin/env bash\necho hi\n' > "$REALMS_DIR/realm.test/tools/helper.sh"
    cat > "$REALMS_DIR/realm.test/adapters/app.yaml" <<'YAML'
commands:
  test: "uv run pytest\n    bash ../../realms/realm.test/tools/helper.sh"
YAML
    fingerprint
    [ "$status" -eq 0 ]
    [ "$output" = "7a3964ad77a75dd59bbd65355df96b16a17e9a73" ]
}

@test "an adapter holding two YAML documents is refused by name" {
    printf 'commands:\n  test: go test ./...\n---\ncommands:\n  lint: go vet ./...\n' > "$REALMS_DIR/realm.test/adapters/two.yaml"
    fingerprint
    [ "$status" -ne 0 ]
    [[ "$output" == *"two.yaml"* ]]
}
```

- [ ] **Step 3: Run them**

Run: `ws test yggdrasil tests/ws-realm/fingerprint.bats`
Expected: 4 passed. These are characterization tests of the committed code; they pass first by design (ledger a ruling saying so).

- [ ] **Step 4: Commit**

Bodyfile `.commits/trust-fingerprint-pin.md`, message `test(realm): pin the trust fingerprint before its computation changes`, add the bats file.

---

### Task 2: Two yq processes per fingerprint

**Files:**
- Modify: `scripts/ws-realm.sh` `ws_realm_trust_fingerprint()` (lines 594 to 750)
- Test: `tests/ws-realm/fingerprint.bats`

**Interfaces:**
- Consumes: Task 1's goldens.
- Produces: `_ws_realm_adapter_canonicals <adapters_dir> <basename>...` printing one line per adapter `<basename><TAB><canonical JSON>`, refusing a file that yields more than one document; `_ws_realm_adapter_commands` reading the canonical JSON lines on stdin and printing `<doc index><US><command line>` where `<US>` is `$'\x1f'`, continuation lines of a multi-line command carrying no prefix.

- [ ] **Step 1: Write the failing test**

```bash
@test "fingerprinting runs two yq processes however many adapters there are" {
    local real_yq; real_yq="$(type -P yq)"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$BATS_TEST_TMPDIR/yq.log" "$real_yq" > "$BATS_TEST_TMPDIR/bin/yq"
    chmod +x "$BATS_TEST_TMPDIR/bin/yq"
    local i; for i in $(seq 1 15); do printf 'commands:\n  test: make test-%s\n' "$i" > "$REALMS_DIR/realm.test/adapters/a$i.yaml"; done
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" fingerprint
    [ "$status" -eq 0 ]
    [ "$(grep -c 'sort_keys' "$BATS_TEST_TMPDIR/yq.log")" -eq 1 ]
    [ "$(grep -c 'provision.init' "$BATS_TEST_TMPDIR/yq.log")" -eq 1 ]
}
```

- [ ] **Step 2: Run it**

Run: `ws test yggdrasil tests/ws-realm/fingerprint.bats --filter "two yq"`
Expected: FAIL on the `sort_keys` count (17 today).

- [ ] **Step 3: Implement**

In `ws_realm_trust_fingerprint`, keep the per-file validation loop but collect basenames instead of calling `yq`. Then:

`_ws_realm_adapter_canonicals` runs, from inside `<adapters_dir>`, `yq -o=json -I=0 '{"f": filename, "c": sort_keys(..)}' "$@"`; each output line is `{"f":"<name>","c":<canonical>}` because basenames match `^[A-Za-z0-9][A-Za-z0-9._-]*\.yaml$` and need no JSON escaping. Strip the fixed prefix and the trailing `}` to recover `<canonical>`, which is byte-identical to the per-file `yq -o=json -I=0 'sort_keys(..)'` output (verified on the real realm). A name seen twice is an error: `ERROR: Cannot inspect adapter commands in <path> for referenced trust inputs.` (the message Task 1 pinned by file name). Skip the call when there are no adapters.

Substitute the captured content for the captured adapter's line, as today. Then `_ws_realm_adapter_commands` runs one `yq -N -p=json -r` over the canonical lines on stdin with `SEP=$'\x1f'` exported: `(((.commands // {} | to_entries | .[].value), .provision.init) | select(tag == "!!str")) | (document_index | tostring) + strenv(SEP) + .`. Parse each output line: `^([0-9]+)<SEP>(.*)$` sets the current document index; any other line is a continuation of the previous command at the same index. Run the existing candidate scan per line with that index's adapter and target directory. Records stay `adapters/<name><TAB><canonical>` and `referenced/<rel><TAB><hash>`, sorted and hashed as before.

- [ ] **Step 4: Run the suite**

Run: `ws test yggdrasil tests/ws-realm/fingerprint.bats` then `ws test yggdrasil tests/ws-realm/trust.bats` and `tests/ws-realm/nested-summary.bats`, `tests/ws-run/run.bats`, `tests/ws-bay/bay.bats`, `tests/ws-checkout/checkout.bats`.
Expected: all pass, the four goldens unchanged.

- [ ] **Step 5: Measure and commit**

Run: `time ws run naust bay list` on the idle machine (parent on this branch).
Expected: under 10 s (from 36 s); record the number in the ledger. Bodyfile `.commits/trust-fingerprint-batch.md`, message `perf(realm): canonicalize every adapter in one yq call when fingerprinting trust`.

---

### Task 3: A content-keyed fingerprint cache

**Files:**
- Modify: `scripts/ws-realm.sh` (new `_ws_trust_cache_file`, `_ws_trust_cache_lookup`, `_ws_trust_cache_store`; `ws_realm_trust_fingerprint` consults them)
- Test: `tests/ws-realm/fingerprint.bats`

**Interfaces:**
- Produces: cache file `${WS_TRUST_CACHE_DIR:-$ROOT_DIR/.tmp/ws/realm-trust}/<realm>.cache`; `WS_TRUST_CACHE=off` disables it. Format, one record per line: `fingerprint <sha>`; `sig <rel><TAB><link flag><TAB><blob hash>` for `ecosystem.yaml`, each `adapters/*.yaml` in sorted order, then each referenced helper; `canon <adapter basename><TAB><canonical JSON>`.

- [ ] **Step 1: Write the failing tests**

```bash
@test "a second fingerprint of an unchanged realm runs no yq at all" {
    export WS_TRUST_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
    fingerprint; [ "$status" -eq 0 ]; local first="$output"
    local real_yq; real_yq="$(type -P yq)"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$BATS_TEST_TMPDIR/yq.log" "$real_yq" > "$BATS_TEST_TMPDIR/bin/yq"
    chmod +x "$BATS_TEST_TMPDIR/bin/yq"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" fingerprint
    [ "$status" -eq 0 ]
    [ "$output" = "$first" ]
    [ ! -e "$BATS_TEST_TMPDIR/yq.log" ]
}

@test "a changed adapter or helper misses the cache" {
    export WS_TRUST_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
    printf '#!/usr/bin/env bash\necho hi\n' > "$REALMS_DIR/realm.test/tools/helper.sh"
    printf 'commands:\n  test: bash ../../realms/realm.test/tools/helper.sh\n' > "$REALMS_DIR/realm.test/adapters/app.yaml"
    fingerprint; local before="$output"
    printf '#!/usr/bin/env bash\necho changed\n' > "$REALMS_DIR/realm.test/tools/helper.sh"
    fingerprint; [ "$output" != "$before" ]; local helper_changed="$output"
    WS_TRUST_CACHE=off fingerprint; [ "$output" = "$helper_changed" ]
    printf 'commands:\n  test: make\n' > "$REALMS_DIR/realm.test/adapters/tool.yaml"
    fingerprint; [ "$output" != "$helper_changed" ]
}

@test "captured adapter content is fingerprinted as captured and never cached as the file" {
    export WS_TRUST_CACHE_DIR="$BATS_TEST_TMPDIR/cache"
    fingerprint; local file_fp="$output"
    run bash -c 'source "$1"; ws_realm_trust_fingerprint realm.test "$2" "{\"commands\":{\"test\":\"rm -rf /\"}}"' _ "$REALM_LIB" "$REALMS_DIR/realm.test/adapters/app.yaml"
    [ "$status" -eq 0 ]
    [ "$output" != "$file_fp" ]
    fingerprint
    [ "$output" = "$file_fp" ]
}
```

- [ ] **Step 2: Run them**

Run: `ws test yggdrasil tests/ws-realm/fingerprint.bats --filter cache`
Expected: the first fails on `yq.log` existing; the other two pass or fail incidentally, they are kept as guards.

- [ ] **Step 3: Implement**

`_ws_trust_cache_lookup <realm> <realm_dir> <captured_basename> <captured_content>`: read the cache file; collect the `sig` paths; refuse (miss) unless the current sorted `adapters/*.yaml` listing equals the adapter set in the sig; compute the link flag for each path and for its parent directory inside the realm with `[[ -L ]]` (no spawn); run one `git hash-object -- <paths>` from the realm directory (any failure is a miss); compare the rebuilt sig block to the stored one byte for byte; when a captured basename is given, its `canon` line must equal the captured content; on a hit print the stored fingerprint. `_ws_trust_cache_store` writes the file through a temp file and `mv` in the same directory, creating the directory with `mkdir -p`, and ignores write failures. `ws_realm_trust_fingerprint` consults the lookup after its argument and directory validations and before any `yq`, and stores after a full computation only when no captured content was given. The symlink refusals in the full computation stay as they are.

- [ ] **Step 4: Run the suites**

Run: the same set as Task 2 step 4, plus `ws test yggdrasil tests/hook/gdd-permission-hook.bats` is not needed. Also `bash scripts/ws-shellcheck.sh`.
Expected: all pass, shellcheck clean.

- [ ] **Step 5: Measure and commit**

Run: `time ws run naust bay list` twice.
Expected: the second under 3 s. Bodyfile `.commits/trust-fingerprint-cache.md`, message `perf(realm): answer an unchanged realm's trust fingerprint from a content-keyed cache`. Add a paragraph to `docs/gdd/adapters.md`'s trust section stating the cache's existence, location and `WS_TRUST_CACHE=off`.

---

### Task 4: A cloning bay is visible to naust

**Files:**
- Modify: `components/naust/bin/bay.sh` `cmd_add()` lines 121 to 124
- Test: `components/naust/tests/bay.bats`

- [ ] **Step 1: Write the failing test**

```bash
@test "add records the bay as provisioning before ws bay add starts cloning" {
    cat > "$NAUST_WORKSPACE/scripts/ws" <<'EOF'
#!/usr/bin/env bash
echo "ws $*" >> "$STUB_LOG"
case "$1 $2" in
  "bay add") echo "state-during-add=$(sed -n 's/^state=//p' "$NAUST_DIR/state/bays/$3.state" 2>/dev/null)" >> "$STUB_LOG"
             dir="$NAUST_WORKSPACE/bays/$3"; mkdir -p "$dir/scripts" "$dir/components/terasology" "$dir/realms/realm-test"; cp "$STUB_BIN/bayws-template" "$dir/scripts/ws" ;;
  "bay exec") shift 2; bay="$1"; shift; cd "$NAUST_WORKSPACE/bays/$bay" && exec bash scripts/ws "$@" ;;
esac
exit 0
EOF
    run_naust bay add bay-1 --profile terasology
    [ "$status" -eq 0 ]
    grep -q '^state-during-add=provisioning$' "$STUB_LOG"
}
```

- [ ] **Step 2: Run it** — Run: `bash components/naust/tests/run.sh test tests/bay.bats` Expected: FAIL, `state-during-add=` empty.
- [ ] **Step 3: Implement** — move the `printf 'state=provisioning\n…'` line above the `bash "$WS" bay add` call; on a failed `ws bay add`, set the state to `broken` and `die` (today a failure exits through `set -e` with no state at all).
- [ ] **Step 4: Run** — same command. Expected: all bay tests pass.
- [ ] **Step 5: Commit** — bodyfile `.commits/naust-bay-visible.md`, message `fix(bay): a bay is provisioning from the moment ws bay add starts`.

---

### Task 5: The bay log and `ws bay log`

**Files:**
- Modify: `scripts/ws-bay.sh` (help text, `cmd_add`, `cmd_reset`, new `bay_log_file`, `bay_say`, `bay_tee`, `cmd_log`, dispatcher case)
- Modify: `docs/gdd/features.md` (one sentence in the bays paragraph naming `ws bay log`)
- Test: `tests/ws-bay/bay.bats`

**Interfaces:**
- Produces: `bays/<name>/.outputs/bay.log`, lines `<UTC ISO-8601> <message>`; `ws bay log <name> [--follow] [--lines N]` (default 40 lines).

- [ ] **Step 1: Write the failing tests**

```bash
@test "add and reset write the bay's log and ws bay log tails it" {
    run_ws bay add bay-1 --with terasology
    [ "$status" -eq 0 ]
    grep -q 'bay add bay-1: cloning terasology' "$BAYS_DIR/bay-1/.outputs/bay.log"
    run_ws bay reset bay-1
    [ "$status" -eq 0 ]
    grep -q 'reset bay-1: clean in' "$BAYS_DIR/bay-1/.outputs/bay.log"
    run_ws bay log bay-1 --lines 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"reset bay-1: clean in"* ]]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
}

@test "log refuses a bay that has never been added or reset here" {
    make_bay bay-1
    run_ws bay log bay-1
    [ "$status" -ne 0 ]
    [[ "$output" == *"no log yet"* ]]
}
```

- [ ] **Step 2: Run** — Run: `ws test yggdrasil tests/ws-bay/bay.bats --filter log` Expected: FAIL, no `.outputs/bay.log`.
- [ ] **Step 3: Implement** — `bay_say <name> <message>` prints the message and appends `$(date -u +%Y-%m-%dT%H:%M:%SZ) <message>` to the log, creating `.outputs/`; every `echo "bay add $name: …"` and `echo "reset $name: …"` in `cmd_add` and `cmd_reset` becomes `bay_say`, including the failure lines. The realm approval, the clone and the provision init in `cmd_add` run as `… 2>&1 | bay_tee "$name"` where `bay_tee` is `tee -a "$(bay_log_file "$1")"`; `set -o pipefail` keeps their exit status. `cmd_log` validates the name with `bay_require`, errors `no log yet for bay <name>; nothing has been added or reset there` when the file is missing, else `tail -n "$lines" ${follow:+-f} "$file"`.
- [ ] **Step 4: Run** — the whole `tests/ws-bay/bay.bats` and `bash scripts/ws-shellcheck.sh`. Expected: all pass.
- [ ] **Step 5: Commit** — on `feat/ws-bays-next`; bodyfile `.commits/ws-bay-log.md`, message `feat(ws): bays keep a log under .outputs and ws bay log tails it`.

---

### Task 6: Naust writes to the bay log and lists activity

**Files:**
- Modify: `components/naust/bin/lib.sh` `log()`; `components/naust/bin/bay.sh` `bay_env()`, `cmd_add()`, `bay_run_in_comp()`, `cmd_list()`
- Modify: `components/naust/README.md` (the `bay list` sentence and a line on `ws bay log <bay> --follow`)
- Test: `components/naust/tests/bay.bats`

**Interfaces:**
- Consumes: the log file path from Task 5.
- Produces: `NAUST_BAY_LOG` exported by `bay_env`; `naust bay list` row `name<TAB>state<TAB>profile<TAB>job<TAB>age<TAB>activity`, activity being seconds since the bay log was last written or `-` with no log.

- [ ] **Step 1: Write the failing tests**

Change the existing list assertion to six columns: `bay-1$'\t'free$'\t'terasology$'\t'$'\t'0$'\t'-`. Add:

```bash
@test "add sends the warm-up and the hooks to the bay log and the list shows activity" {
    make_stub compile-all-stub 'echo warming-up'
    run_naust bay add bay-1 --profile terasology
    [ "$status" -eq 0 ]
    grep -q 'warming-up' "$NAUST_WORKSPACE/bays/bay-1/.outputs/bay.log"
    grep -q 'naust: compile_all:' "$NAUST_WORKSPACE/bays/bay-1/.outputs/bay.log"
    run_naust bay list
    [[ "${lines[0]}" =~ ^bay-1$'\t'free$'\t'terasology$'\t'$'\t'[0-9]+$'\t'[0-9]+$ ]]
}
```

- [ ] **Step 2: Run** — Expected: FAIL, no bay log.
- [ ] **Step 3: Implement** — `log()` also appends the line to `$NAUST_BAY_LOG` when that is set and its directory exists; `bay_env` sets `NAUST_BAY_LOG="$dir/.outputs/bay.log"` after `mkdir -p "$dir/.outputs"`; `bay_ws "$name" build "$comp"` in `cmd_add` and the command in `bay_run_in_comp` redirect `>> "$NAUST_BAY_LOG" 2>&1`, each preceded by a `log` line that says what runs and `follow with: ws bay log <name> --follow`; `cmd_list` appends the activity column from `file_mtime` of the log. The `ws bay add` and `ws bay reset` calls are not redirected: they tee themselves (Task 5).
- [ ] **Step 4: Run** — `bash components/naust/tests/run.sh test` (whole suite) and `bash components/naust/tests/run.sh lint`. Expected: all pass.
- [ ] **Step 5: Commit** — bodyfile `.commits/naust-bay-log.md`, message `feat(bay): the bay log carries naust's steps and the warm-up; bay list shows last activity`.

---

### Task 7: Refuse a bay add whose realm pin is not on the remote, before cloning

**Files:**
- Modify: `scripts/ws-bay.sh` `cmd_add()` between the realm resolution and `git clone`
- Test: `tests/ws-bay/bay.bats`

- [ ] **Step 1: Write the failing test**

```bash
@test "add refuses before cloning when the parent's realm commit is not on its remote" {
    printf 'local: edit\n' >> "$REALMS_DIR/community/ecosystem.yaml"
    git -C "$REALMS_DIR/community" -c user.email=t@example.invalid -c user.name=T commit -qam "unpushed"
    run_ws bay add bay-1 --with terasology
    [ "$status" -ne 0 ]
    [[ "$output" == *"push it first"* ]]
    [ ! -e "$BAYS_DIR/bay-1" ]
}
```

- [ ] **Step 2: Run** — Expected: FAIL, the add succeeds and the bay exists.
- [ ] **Step 3: Implement** — `pin="$(git -C "$REALMS_DIR/$realm" rev-parse HEAD)"`; the realm remote is the `src` already resolved on line 238; the check is `[[ -n "$(git -C "$REALMS_DIR/$realm" branch -r --contains "$pin" --list "$src/*")" ]]`, else `ERROR: this workspace's realm is at <7 chars>, which is not on the realm remote (<src>); push it first, since a bay runs only what has been reviewed and published.` and exit 1.
- [ ] **Step 4: Run** — `tests/ws-bay/bay.bats`. Expected: all pass (the fixtures push their realm, so existing adds are unaffected).
- [ ] **Step 5: Commit** — bodyfile `.commits/ws-bay-preflight.md`, message `fix(ws): bay add checks the realm pin before it clones anything`.

---

### Task 8: Seed a bay from the parent's checkouts

**Files:**
- Modify: `scripts/git-remote.sh` (receives `remote_name_from_url` from `scripts/ws-clone.sh` lines 62 to 97, which drops its copy)
- Modify: `scripts/ws-bay.sh` (sources `git-auth.sh`; new `component_repo_url`, `seed_repo`, `seed_component`, `seed_nested`; `cmd_add` gains `--no-seed`; help text)
- Modify: `tests/ws-bay/test_helper.bash` (the stub ws's `clone` skips an existing `.git`; `init_parent` gives the parent a real `components/terasology` with a bare remote, a nested `modules/Cooking` with its own bare remote, and `components.terasology.repo` in `$ECOSYSTEM`)
- Modify: `docs/gdd/features.md` (one sentence: a bay seeds from the parent's checkouts; `--no-seed`)
- Test: `tests/ws-bay/bay.bats`

**Interfaces:**
- Produces: `component_repo_url <comp> <realm>` printing the repository URL from `ECOSYSTEM_LOCAL`, then the realm's `ecosystem.yaml`, then `ECOSYSTEM` (`.components.<comp>.repo`, else `defaults.gitOrg` + `/<comp>.git`), empty when none; `seed_repo <src> <url> <remote> <target> [<filter>]` running `git_auth_env_for_url "$url"` then `git_auth_run git clone --quiet ${filter:+--filter=$filter} --reference-if-able "$src" --dissociate --origin "$remote" -- "$url" "$target"`, removing `<target>` and returning 1 on failure; the filter is `blob:none` unless `WS_CLONE_FILTER` is set (empty means none), as `ws clone` does.

- [ ] **Step 1: Write the failing tests**

```bash
@test "add seeds the component and its nested repos from this workspace's checkouts" {
    run_ws bay add bay-1 --with terasology
    [ "$status" -eq 0 ]
    [[ "$output" == *"seeding terasology"* ]]
    git -C "$BAYS_DIR/bay-1/components/terasology" cat-file -e "$(git -C "$COMPONENTS_DIR/terasology" rev-parse HEAD)"
    [ "$(git -C "$BAYS_DIR/bay-1/components/terasology" remote get-url origin)" = "$REMOTES/terasology.git" ]
    [ ! -e "$BAYS_DIR/bay-1/components/terasology/c.txt" ]
    [ -d "$BAYS_DIR/bay-1/components/terasology/modules/Cooking/.git" ]
    [ "$(git -C "$BAYS_DIR/bay-1/components/terasology/modules/Cooking" remote get-url origin)" = "$REMOTES/Cooking.git" ]
    [ -f "$BAYS_DIR/bay-1/components/terasology/provisioned.marker" ]
}

@test "add --no-seed clones through the bay's own ws" {
    run_ws bay add bay-1 --with terasology --no-seed
    [ "$status" -eq 0 ]
    [ -f "$BAYS_DIR/bay-1/components/terasology/c.txt" ]
    [ ! -e "$BAYS_DIR/bay-1/components/terasology/modules" ]
}

@test "seeding falls back to the bay's clone when the parent component has no declared repository" {
    printf 'identity: {}\ncomponents: {}\n' > "$ECOSYSTEM"
    run_ws bay add bay-1 --with terasology
    [ "$status" -eq 0 ]
    [ -f "$BAYS_DIR/bay-1/components/terasology/c.txt" ]
}
```

- [ ] **Step 2: Run** — Expected: the first fails on `seeding`, the second on `modules` absent only if the helper already made it, the third passes incidentally.
- [ ] **Step 3: Implement** — in the `--with` loop: `[[ "$seed" == yes ]] && seed_component "$name" "$comp"` (which resolves the URL, derives the remote with `remote_name_from_url`, says `bay add <name>: seeding <comp> from this workspace`, and on any failure says it is cloning instead); then `bay_ws "$name" clone "$comp"` as today (it skips a directory with `.git`); then `[[ "$seed" == yes ]] && seed_nested "$name" "$comp"`, which reads the parent's trusted adapter `$REALMS_DIR/$realm/adapters/$comp.yaml` `.nested` globs through `bay_nested_glob_ok`, and for every parent match holding `.git` seeds it with the parent's `remote.origin.url` (else its first remote's URL, else skipped) as `origin`, no filter; then `provision.init` as today.
- [ ] **Step 4: Run** — `tests/ws-bay/bay.bats`, `tests/ws-clone/*.bats` if present (the moved function), `bash scripts/ws-shellcheck.sh`. Expected: all pass.
- [ ] **Step 5: Commit** — bodyfile `.commits/ws-bay-seed.md`, message `feat(ws): bay add seeds components and nested repos from this workspace's checkouts`.

---

### Task 9: Names and phrases

**Files (9a, naust `feat/phase1`):**
- Move: `components/naust/bin/run.sh` to `components/naust/bin/dock.sh`; `components/naust/tests/run.bats` to `components/naust/tests/dock.bats`
- Modify: `components/naust/bin/naust` (dispatcher list and usage), `bin/job.sh` (`step_launch`, labels `7 launch`), `bin/report.sh` (`launch.log`, the launch row, the human line `launch check failed: the game did not reach the renderer, or the screenshot is missing; read \`launch.log\`.`), `bin/gate.sh` and `bin/tick.sh` (fallback `haul it in`), comments in `lib.sh`, `poll.sh`, `queue.sh`, `README.md`, `AGENTS.md`, `tests/helpers/stub.bash` (`launch: "launch-stub"`, `nod_phrase: "haul it in"`), `tests/job.bats`, `tests/report.bats`, `tests/gate.bats`, `tests/lib.bats`

**Files (9b, realm `feat/naust-terasology-next`):**
- Move: `terasology/pr-smoke.sh` to `terasology/pr-launch.sh`
- Modify: `naust/terasology.yaml` (`launch:` key naming `pr-launch.sh`), `terasology/pr-launch.sh` (`launch.log`, `NAUST_LAUNCH_TIMEOUT`), `terasology/pr-lib.sh` and `pr-seed.sh` comments, `terasology/README.md` line 44, `terasology/tests/profile.bats`, `terasology/tests/pr-boot.bats`

- [ ] **Step 1 (9a): Rename in the tests first** — `dock.bats` calls `run_naust dock …`; `lib.bats` expects the usage to list `dock`; `job.bats`, `report.bats` and `stub.bash` use `launch`; `gate.bats` and `lib.bats` expect `haul it in`. Run `bash components/naust/tests/run.sh test`. Expected: FAIL across those files.
- [ ] **Step 2 (9a): Rename the code and docs** — as listed. Run the suite and lint. Expected: all pass.
- [ ] **Step 3 (9a): Commit** — bodyfile `.commits/naust-dock-launch.md` listing both old and new paths, message `refactor: naust dock, the launch check, and the realm's nod phrase`.
- [ ] **Step 4 (9b): Realm** — `ws checkout realm-siliconsaga feat/naust-terasology-next`; rename tests first (`profile.bats` expects `.steps.launch` and `pr-launch.sh`; `pr-boot.bats` runs `pr-launch.sh` and reads `launch.log`), run `bash realms/realm-siliconsaga/terasology/tests/run.sh`, expected FAIL; then the move and edits; run again, expected all pass; commit with bodyfile `.commits/realm-naust-launch.md`, message `refactor(naust): the launch check and pr-launch.sh`. Then `ws checkout realm-siliconsaga main` so the bay's realm pin stays a pushed commit.

---

### Task 10: Bring-up with the new round

- [ ] **Step 1:** On `feat/realm-trust-fast`: `time ws run naust bay list` twice; record both. Expected: second under 3 s.
- [ ] **Step 2:** `ws checkout yggdrasil feat/ws-bays-next`; `ws run naust bay add bay-2 --profile terasology` in the background; from another call, `ws run naust bay list` shows `bay-2 provisioning` at once and `ws bay log bay-2 --lines 5` shows progress. Record wall-clock against bay-1's 28 minutes.
- [ ] **Step 3:** Ledger the numbers; update the design doc's bring-up section with them; update the Thalamus arc `next:`.
