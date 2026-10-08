# Naust — PR bays, Phase 1: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A scheduled script on Dionysus notices a maintainer's Terasology PR, runs it through a warm bay (checkout, build, every-module compile, scoped tests against PR and base, headless boot, windowed boot with a screenshot, clean-tree check) and leaves a report in the bay, on Discord and on the PR, with nobody at a keyboard.

**Architecture:** Three repositories, three CRs, in order. yggdrasil gains `ws checkout <target> --pr <N>`. A new SiliconSaga component `naust` holds the bay machinery as bash scripts: a tick that polls, gates, queues and runs one job; bays that are sibling yggdrasil workspaces reset between jobs; a report renderer; a Discord webhook notifier. This realm holds the Terasology profile, the trust list, and the Terasology-specific boot scripts the profile points at.

**Tech Stack:** bash (Git Bash on Windows, `set -euo pipefail`), `yq` v4 for YAML, `gh` with `--jq` for every JSON read (no host `jq`), `git`, `curl`, bats-core (workspace-vendored) with PATH stubs for tests, PowerShell only inside `screenshot.ps1`.

**Spec:** [`2026-10-08-naust-pr-bays-design.md`](2026-10-08-naust-pr-bays-design.md) — the plan argues from it; read both.

## Global Constraints

- Every script starts `#!/usr/bin/env bash` and `set -euo pipefail`; no `make`, no Python, no `jq` on the host. JSON from `gh` is shaped with `gh … --jq`; YAML with `yq` (present already, `ws hoard lint` needs it).
- Inside a bay, every build, test, checkout, review and status call goes through that bay's own `scripts/ws` (`bash "$WS" …`); naust never runs Gradle itself. Profile commands may, and they run with the component directory as cwd.
- Secrets come from `<naust root>/.env`, read literally (never sourced): `GDD_GITHUB_TOKEN` (machine account, exported to subprocesses as `GH_TOKEN`), `NAUST_DISCORD_WEBHOOK`. Personal tokens never reach a bay.
- A nod counts only from a login in `maintainers`; the actor of a `labeled` event or the author of a comment is checked, never the label's presence alone.
- PR comments go through `ws review <comp> comment`, which prepends the GDD banner; the text is in the `oss-wide` register: what was observed, what decision it needs, no characterisation of the contribution.
- Prose in docs, READMEs and commit bodies is one line per paragraph and per bullet; never hard-wrapped.
- Commits go through `ws commit <target> <bodyfile>` with a bodyfile under `.commits/`; the bodyfile's `add:` list is the staging list. Commit subjects use conventional prefixes.
- Bay reset keeps Gradle outputs (`build/`, `.gradle/`) so compiles stay incremental: `git clean -fd` plus explicit removal of the profile's `runtime_dirs`. `--deep` is `git clean -fdx`.
- Tests never touch the network: `gh`, `curl`, `git clone` and Gradle are PATH stubs; real `git` is used only on temp repositories.

## Review Focus

1. **A PR force-pushed between poll and fetch.** The job must record the SHA it actually fetched, not the one polled, and the next tick must queue the newer head. Pinned in Task 6 (replace on newer head) and Task 8 (`job.yaml` holds `git rev-parse HEAD` after checkout).
2. **A label applied by someone outside `maintainers`.** The gate ignores it and names the actor in its reason, so a self-labelled PR never runs. Pinned in Task 5.
3. **One nested module whose fetch fails during reset.** The bay goes `broken`, the job does not run, and the tick logs which repository failed. Pinned in Task 4.
4. **A game that never logs the renderer line.** The smoke step times out, stops the JVM, exits non-zero and leaves the log tail in the job directory; the report shows the step as failed, not skipped. Pinned in Task 14.
5. **A tick that fires while the previous tick's job is still running.** The second tick exits 0 with a "busy" line and runs nothing; a lock older than `lock_stale_hours` is treated as abandoned. Pinned in Task 7.

---

## File structure

**yggdrasil** (Task 1)
- Modify: `scripts/ws` — `ws_checkout()` gains `--pr <N> [--remote <name>]`; header comment line 32 and help text.
- Modify: `tests/ws-checkout/test_helper.bash` — `setup_pr_fixture`, `publish_pr_head`.
- Modify: `tests/ws-checkout/checkout.bats` — six `--pr` cases.
- Modify: `docs/gdd/features.md:23`, `CHANGELOG.md` Unreleased → Added.

**naust** (Tasks 2–11), new repository `SiliconSaga/naust`, checked out at `components/naust`
- `bin/naust` — dispatcher: `naust tick|bay|run|job|report|notify`.
- `bin/lib.sh` — logging, config (`cfg`, `prof`, `trust`), `.env` reading, lock, key=value state files.
- `bin/notify.sh` — Discord webhook: `say <text> [--file <path>]`.
- `bin/bay.sh` — `add`, `reset`, `list`, `release`, `claim`, `set`.
- `bin/gate.sh` — trust decision for one PR.
- `bin/poll.sh` — one profile's open PRs → candidate lines, with seen-state and debounce.
- `bin/queue.sh` — `put`, `next`, `drop`, `list`.
- `bin/tick.sh` — the scheduled entry point; also `naust run`.
- `bin/job.sh` — the nine steps.
- `bin/report.sh` — `report.md` and `comment.md` from a job directory.
- `tests/run.sh`, `tests/helpers/stub.bash`, one `tests/<script>.bats` per script.
- `README.md`, `AGENTS.md`, `naust.example.yaml`, `.env.example`, `.gitignore`.

**realm-siliconsaga** (Tasks 12–14)
- `naust/terasology.yaml` — the profile. `naust/trust.yaml` — maintainers and nod rules.
- `terasology/pr-lib.sh` — `wait_for_marker`, `stop_game`, `screenshot`.
- `terasology/pr-seed.sh` — `generate` and `restore` the seed manifest; `terasology/seed-manifest.template.json`.
- `terasology/pr-headless.sh`, `terasology/pr-smoke.sh`, `terasology/screenshot.ps1`.
- `terasology/tests/run.sh`, `terasology/tests/*.bats`.
- `adapters/naust.yaml`, `ecosystem.yaml` entry, `terasology/README.md` section.

**Dionysus** (Task 15) — operator runbook, no code.

---

### Task 1: `ws checkout <target> --pr <N>` (yggdrasil)

**Files:**
- Modify: `scripts/ws:460-540` (`ws_checkout`), `scripts/ws:32` (header comment)
- Modify: `tests/ws-checkout/test_helper.bash`
- Modify: `tests/ws-checkout/checkout.bats`
- Modify: `docs/gdd/features.md:23`, `CHANGELOG.md`

**Interfaces:**
- Produces: `ws checkout <target> --pr <N> [--remote <name>]`. Fetches `refs/pull/<N>/head` from the one remote that has it (or `--remote`), resets local branch `pr/<N>` to it and switches there. Prints `pr/<N> → <short sha> (pull request #<N> on <remote>)`. Exit 1 when no remote or several remotes have the PR, when `--pr` is combined with a branch or `-b`, or when `<N>` is not a positive integer. Nested targets (`terasology/modules/Health`) work unchanged.

- [ ] **Step 1: Branch**

Run from the yggdrasil root:

```bash
ws checkout yggdrasil feat/ws-checkout-pr -b
```

- [ ] **Step 2: Add the PR fixture to the test helper**

Append to `tests/ws-checkout/test_helper.bash`:

```bash
# A component whose "remote" is a local bare repository carrying a pull-request
# head ref, the shape GitHub exposes as refs/pull/<n>/head. The work branch that
# made the commit is deleted again, so the only way to reach PR_SHA is the ref.
setup_pr_fixture() {
    setup_component_repo
    PR_REMOTE="$BATS_TEST_TMPDIR/remote.git"
    git init -q --bare "$PR_REMOTE"
    git -C "$COMPONENTS_DIR/terasology" remote add origin "$PR_REMOTE"
    git -C "$COMPONENTS_DIR/terasology" push -q origin main
    publish_pr_head "$COMPONENTS_DIR/terasology" 7 "first change"
}

# Add a commit on top of main and publish it only as refs/pull/<n>/head on the
# repo's origin. Sets PR_SHA. Calling it again for the same number moves the PR.
publish_pr_head() {
    local repo="$1" number="$2" text="$3"
    git -C "$repo" switch -q -c pr-work
    printf '%s\n' "$text" >> "$repo/pr.txt"
    git -C "$repo" add pr.txt
    git -C "$repo" commit -qm "$text"
    PR_SHA="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" push -q -f origin "HEAD:refs/pull/$number/head"
    git -C "$repo" switch -q main
    git -C "$repo" branch -q -D pr-work
}

# The nested shape with a PR on the module's own origin.
setup_nested_pr_fixture() {
    setup_nested_component
    local mod="$COMPONENTS_DIR/terasology/modules/Cooking"
    MOD_REMOTE="$BATS_TEST_TMPDIR/cooking.git"
    git init -q --bare "$MOD_REMOTE"
    git -C "$mod" remote add origin "$MOD_REMOTE"
    git -C "$mod" push -q origin main
    publish_pr_head "$mod" 3 "module change"
}
```

- [ ] **Step 3: Write the failing tests**

Append to `tests/ws-checkout/checkout.bats`:

```bash
@test "--pr fetches a pull request head into pr/<n> and switches to it" {
    setup_pr_fixture

    run_ws checkout terasology --pr 7

    [ "$status" -eq 0 ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology")" = "pr/7" ]
    [ "$(git -C "$COMPONENTS_DIR/terasology" rev-parse HEAD)" = "$PR_SHA" ]
    [[ "$output" == *"pull request #7 on origin"* ]]
}

@test "--pr run again follows a moved pull request" {
    setup_pr_fixture
    run_ws checkout terasology --pr 7
    [ "$status" -eq 0 ]
    publish_pr_head "$COMPONENTS_DIR/terasology" 7 "second change"

    run_ws checkout terasology --pr 7

    [ "$status" -eq 0 ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology")" = "pr/7" ]
    [ "$(git -C "$COMPONENTS_DIR/terasology" rev-parse HEAD)" = "$PR_SHA" ]
}

@test "--pr works on a nested module repo" {
    setup_nested_pr_fixture

    run_ws checkout terasology/modules/Cooking --pr 3

    [ "$status" -eq 0 ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology/modules/Cooking")" = "pr/3" ]
    [ "$(git -C "$COMPONENTS_DIR/terasology/modules/Cooking" rev-parse HEAD)" = "$PR_SHA" ]
    [ "$(current_branch "$COMPONENTS_DIR/terasology")" = "main" ]
}

@test "--pr fails when no remote carries the pull request" {
    setup_pr_fixture

    run_ws checkout terasology --pr 99

    [ "$status" -ne 0 ]
    [[ "$output" == *"No remote"*"#99"* ]]
}

@test "--pr refuses a branch argument and -b" {
    setup_pr_fixture

    run_ws checkout terasology main --pr 7
    [ "$status" -ne 0 ]
    [[ "$output" == *"--pr takes no branch"* ]]

    run_ws checkout terasology --pr 7 -b
    [ "$status" -ne 0 ]
    [[ "$output" == *"--pr takes no branch"* ]]
}

@test "--pr rejects a non-numeric number" {
    setup_pr_fixture

    run_ws checkout terasology --pr seven

    [ "$status" -ne 0 ]
    [[ "$output" == *"positive integer"* ]]
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `ws test yggdrasil tests/ws-checkout/checkout.bats`
Expected: the six new tests fail with `Unknown option '--pr'`; the existing eight pass.

- [ ] **Step 5: Implement `--pr` in `ws_checkout`**

In `scripts/ws`, replace the body of `ws_checkout()` from `local create="" target="" branch=""` to the end of the function with:

```bash
    local create="" target="" branch="" pr="" remote=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--create) create="yes"; shift ;;
            --pr)
                [[ $# -ge 2 ]] || { echo "ERROR: --pr needs a pull request number." >&2; exit 1; }
                pr="$2"; shift 2 ;;
            --pr=*) pr="${1#--pr=}"; shift ;;
            --remote)
                [[ $# -ge 2 ]] || { echo "ERROR: --remote needs a remote name." >&2; exit 1; }
                remote="$2"; shift 2 ;;
            --remote=*) remote="${1#--remote=}"; shift ;;
            --)
                echo "ERROR: 'ws checkout' switches branches only; it does not restore paths." >&2
                echo "  Restoring a path discards working-tree changes. Do that with git, deliberately." >&2
                exit 1 ;;
            -*)
                echo "ERROR: Unknown option '$1'" >&2
                exit 1 ;;
            *)
                if [[ -z "$target" ]]; then
                    target="$1"
                elif [[ -z "$branch" ]]; then
                    branch="$1"
                else
                    echo "ERROR: Unexpected argument '$1'." >&2
                    echo "  Usage: ws checkout <target> <branch> [-b|--create]" >&2
                    exit 1
                fi
                shift ;;
        esac
    done

    if [[ -n "$pr" ]]; then
        if [[ -n "$branch" || -n "$create" ]]; then
            echo "ERROR: --pr takes no branch and no -b; the branch is always pr/<n>." >&2
            exit 1
        fi
        if [[ ! "$pr" =~ ^[1-9][0-9]*$ ]]; then
            echo "ERROR: --pr needs a positive integer, got '$pr'." >&2
            exit 1
        fi
        if [[ -n "$remote" && ! "$remote" =~ ^[A-Za-z0-9._/-]+$ ]]; then
            echo "ERROR: Invalid remote name '$remote'." >&2
            exit 1
        fi
        [[ -n "$target" ]] || { echo "ERROR: ws checkout --pr requires a target." >&2; exit 1; }
        ws_resolve_target "$target"
        cd "$COMPONENT_DIR"
        ws_checkout_pr "$pr" "$remote"
        return
    fi

    if [[ -z "$target" || -z "$branch" ]]; then
        echo "ERROR: ws checkout requires a target and a branch." >&2
        echo "  Usage: ws checkout <target> <branch> [-b|--create]" >&2
        exit 1
    fi

    # The name reaches git as an argument, never a shell word, so this is not
    # about injection - it rejects the shapes that make a branch ambiguous with
    # a path, which is where a typo turns into a surprising checkout.
    if [[ "$branch" == *".."* || "$branch" == /* || "$branch" == */ ]]; then
        echo "ERROR: Invalid branch name '$branch'." >&2
        exit 1
    fi

    ws_resolve_target "$target"
    cd "$COMPONENT_DIR"

    # git switch, not git checkout: it has no path-restoring mode at all, so the
    # refusal above cannot be worked around by a name that looks like a file.
    if [[ -n "$create" ]]; then
        git switch -c "$branch"
    else
        git switch "$branch"
    fi
}

# Fetch a pull request's head into the local branch pr/<n> and switch to it.
#
# The PR lives on exactly one remote, and the repo usually has two (the fork
# and the source), so without --remote every remote is asked whether it has
# refs/pull/<n>/head: one yes is the answer, none or several is an error. The
# ref is fetched into FETCH_HEAD rather than straight into the branch, because
# git refuses to fetch into a branch that is checked out — which pr/<n> is, the
# second time. `switch -C` then moves the branch to the fetched head whether or
# not it is current: pr/<n> mirrors the PR, and local commits on it are not
# something this verb preserves.
ws_checkout_pr() {
    local pr="$1" remote="$2" ref="refs/pull/$1/head" r
    local -a found=()
    if [[ -z "$remote" ]]; then
        for r in $(git remote); do
            if git ls-remote --exit-code "$r" "$ref" >/dev/null 2>&1; then
                found+=("$r")
            fi
        done
        case ${#found[@]} in
            0)
                echo "ERROR: No remote of this repo has pull request #$pr (looked for $ref on: $(git remote | tr '\n' ' '))." >&2
                exit 1 ;;
            1) remote="${found[0]}" ;;
            *)
                echo "ERROR: Pull request #$pr exists on several remotes: ${found[*]}." >&2
                echo "  Use --remote <name> to pick one." >&2
                exit 1 ;;
        esac
    fi
    if ! git fetch --quiet "$remote" "$ref"; then
        echo "ERROR: Could not fetch pull request #$pr from remote '$remote'." >&2
        exit 1
    fi
    git switch -C "pr/$pr" FETCH_HEAD >/dev/null
    echo "pr/$pr → $(git rev-parse --short HEAD) (pull request #$pr on $remote)"
}
```

Then update the help text inside `ws_checkout` (the `HELP` heredoc) to:

```text
Usage: ws checkout <target> <branch> [-b|--create]
       ws checkout <target> --pr <n> [--remote <name>]

Switch a component, realm, hoard or nested repo to a branch, or to the head of
a pull request.

Branches only. This deliberately cannot restore paths the way `git checkout --
<path>` does, because that silently discards working-tree changes; do that by
hand, on purpose, when you mean it.

The target accepts the same names as every other repo-touching verb, so nested
repos work here too: `ws checkout terasology/modules/Cooking fix/x -b` branches
the module in place, inside the tree where it actually builds.

--pr <n> fetches refs/pull/<n>/head (GitHub) from the one remote that has it
and resets the local branch pr/<n> to it, so running it again follows a PR
that moved. Local commits on pr/<n> are not kept; branch off it if you need
them. --remote picks the remote when more than one has the PR.

Options:
  -b, --create        Create the branch and switch to it
  --pr <n>            Check out pull request <n> as branch pr/<n>
  --remote <name>     With --pr: the remote to fetch the PR from

Examples:
  ws checkout yggdrasil main                        # the workspace root
  ws checkout terasology fix/assets -b              # a component
  ws checkout terasology/modules/Cooking fix/x -b   # a nested module repo
  ws checkout terasology --pr 5400                  # a PR, as branch pr/5400
  ws checkout terasology/modules/Health --pr 12     # a PR on a nested module
```

And change the header comment at `scripts/ws:32` to:

```text
#   checkout <target> <branch> [-b|--create] | --pr <n>  Switch/create a branch, or check out a PR head (branches only, never paths)
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `ws test yggdrasil tests/ws-checkout/checkout.bats`
Expected: 14 tests, all pass.

Run: `ws test yggdrasil tests/ws-target-resolution/`
Expected: unchanged, all pass (the resolver is untouched).

- [ ] **Step 7: Lint**

Run: `ws lint yggdrasil`
Expected: clean. If shellcheck flags the `for r in $(git remote)` word-split, it is intended (remote names carry no spaces); keep the loop and add `# shellcheck disable=SC2046` above it only if the lint actually fails.

- [ ] **Step 8: Docs and changelog**

Replace `docs/gdd/features.md` line 23 with:

```markdown
- `ws checkout <component> <branch> [-b]` / `ws checkout <component> --pr <n>` — Switch or create a branch, or check out a pull request's head as branch `pr/<n>`, refetched each time so it follows a PR that moved. Branches only; it has no path mode, so it cannot discard working-tree changes.
```

Add under `## [Unreleased]` → `### Added` in `CHANGELOG.md`, as the first bullet:

```markdown
- **`ws checkout <target> --pr <n>`** — check out a pull request's head as the local branch `pr/<n>`, nested targets included. The PR is looked up on every remote (`refs/pull/<n>/head`) so a fork-plus-source checkout needs no `--remote` unless both have it; running it again resets `pr/<n>` to the PR's new head. The first piece of naust, the PR-bay runner, and useful on its own for reviewing a PR in place.
```

- [ ] **Step 9: Commit**

Write `.commits/ws-checkout-pr.md`:

```markdown
---
message: "feat(ws): checkout --pr <n> fetches a pull request head into pr/<n>"
add:
  - scripts/ws
  - tests/ws-checkout/test_helper.bash
  - tests/ws-checkout/checkout.bats
  - docs/gdd/features.md
  - CHANGELOG.md
---

Reviewing a PR in place meant hand-typing the refs/pull refspec, and a bay runner cannot. The verb asks every remote for refs/pull/<n>/head so a fork-plus-source checkout needs no flag, fetches into FETCH_HEAD because git refuses to fetch into the checked-out branch pr/<n> on the second run, and resets the branch with switch -C so it always mirrors the PR.

GitHub refs only for now; GitLab's refs/merge-requests/<n>/head is a one-line follow-up when a GitLab component needs it.
```

Run: `ws commit yggdrasil .commits/ws-checkout-pr.md`

Then `ws push yggdrasil` and `ws cr yggdrasil "ws checkout --pr <n>" .crs/ws-checkout-pr.md` with a change bodyfile from `templates/change.md` (summary: the verb, the remote probing, the reset semantics; test plan: the six bats cases). Review-bot rounds follow the usual `ws review` flow.

### Task 2: naust skeleton — dispatcher, `lib.sh`, test harness

**Files:**
- Create: `components/naust/bin/naust`, `components/naust/bin/lib.sh`
- Create: `components/naust/tests/run.sh`, `components/naust/tests/helpers/stub.bash`, `components/naust/tests/lib.bats`
- Create: `components/naust/naust.example.yaml`, `components/naust/.env.example`, `components/naust/.gitignore`

**Interfaces:**
- Produces, in `lib.sh` (sourced by every other script): `log <msg>`, `die <msg>` (exit 1), `now` (epoch, overridable by `NAUST_NOW` for tests), `require_tool <name>`, `load_config` (sets `WORKSPACE REALM BAYS_ROOT STATE_DIR GRADLE_HOME REALM_DIR PROFILE_DIR` and creates `STATE_DIR/{queue,seen,jobs}` and `BAYS_ROOT`), `cfg <yq-path> [default]`, `prof <profile> <yq-path> [default]`, `trust <profile> <yq-path>`, `env_value <KEY>`, `kv_get <file> <key>`, `kv_set <file> <key> <value>`, `with_lock` (returns 1 when another tick holds the lock), `json_escape <text>`.
- Produces: `bin/naust <command> [args]` dispatching to `bin/<command>.sh` for `tick bay run job report notify`; `naust --help`.
- Config file `naust.yaml` keys: `workspace`, `realm`, `bays_root`, `state_dir`, `gradle_home`, `profiles` (list), `yggdrasil_repo`, `realm_repo`, `lock_stale_hours`.

- [ ] **Step 1: Create the repository and declare it locally**

The owner creates the empty repository `SiliconSaga/naust` on GitHub (private or public, their call; MIT like gdd-sandbox). Then:

```bash
git init -q -b main components/naust
git -C components/naust remote add SiliconSaga https://github.com/SiliconSaga/naust.git
```

Add to the workspace's `ecosystem.local.yaml` until Task 12 declares it in the realm:

```yaml
components:
  naust:
    repo: https://github.com/SiliconSaga/naust.git
    tier: supporting
```

Create `components/naust/.gitignore`:

```gitignore
/naust.yaml
/.env
/state/
/bays/
/gradle-home/
```

- [ ] **Step 2: Test harness**

Create `components/naust/tests/run.sh` (the gdd-sandbox runner, minus the image path):

```bash
#!/usr/bin/env bash
# Component self-test. Uses the workspace-vendored bats; shellcheck via the
# koalaman container unless a host shellcheck exists.
set -euo pipefail
cd "$(dirname "$0")/.."
WS_ROOT="$(cd ../.. && pwd)"
BATS="$(command -v bats || true)"
BATS="${BATS:-$WS_ROOT/tests/vendor/bats-core/bin/bats}"

shellcheck_run() {
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$@"
  else
    ws docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable "$@"
  fi
}

case "${1:-test}" in
  test)
    sel="${2:-}"
    if [ -z "$sel" ]; then
      exec bash "$BATS" tests/
    elif [ -f "$sel" ]; then
      exec bash "$BATS" "$sel"
    fi
    if [ "$(bash "$BATS" --count --filter "$sel" tests/)" -eq 0 ]; then
      echo "no test name matches '$sel' (a bats --filter regex over tests/)" >&2
      exit 1
    fi
    exec bash "$BATS" --filter "$sel" tests/
    ;;
  lint) shellcheck_run bin/naust bin/*.sh tests/*.sh ;;
  *) echo "usage: tests/run.sh {test [selector]|lint}" >&2; exit 2 ;;
esac
```

Create `components/naust/tests/helpers/stub.bash`:

```bash
# Fake executables on PATH so bats can assert how scripts call gh/git/curl/ws.
# Each stub appends its argv to "$STUB_LOG" and runs the provided body.
make_stub() {
  local name="$1"; shift
  local body="${*:-true}"
  mkdir -p "$STUB_BIN"
  cat > "$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
echo "$name \$*" >> "$STUB_LOG"
$body
EOF
  chmod +x "$STUB_BIN/$name"
}

stub_setup() {
  export STUB_BIN="$BATS_TEST_TMPDIR/bin"
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  : > "$STUB_LOG"
  mkdir -p "$STUB_BIN"
  PATH="$STUB_BIN:$PATH"
}

# A naust home with a config, a workspace holding a realm with one profile and
# a trust list, and empty state. Every bats file starts here.
naust_setup() {
  stub_setup
  export NAUST_HOME="$BATS_TEST_TMPDIR/naust"
  export NAUST_CONFIG="$NAUST_HOME/naust.yaml"
  export NAUST_ENV_FILE="$NAUST_HOME/.env"
  export NAUST_LOG="$BATS_TEST_TMPDIR/naust.log"
  export NAUST_NOW=1760000000
  WORKSPACE="$BATS_TEST_TMPDIR/ws"
  mkdir -p "$NAUST_HOME" "$WORKSPACE/realms/realm-test/naust"
  cat > "$NAUST_CONFIG" <<YAML
workspace: $WORKSPACE
realm: realm-test
bays_root: $NAUST_HOME/bays
state_dir: $NAUST_HOME/state
gradle_home: $NAUST_HOME/gradle-home
profiles: [terasology]
lock_stale_hours: 6
YAML
  cat > "$WORKSPACE/realms/realm-test/naust/terasology.yaml" <<'YAML'
component: terasology
repo: MovingBlocks/Terasology
upstream_remote: MovingBlocks
default_branch: develop
nested:
  - "modules/*"
nested_default_branch: develop
persona: Gooey
poll:
  debounce_minutes: 10
  skip_drafts: true
bay:
  ready_ttl_days: 7
runtime_dirs: [logs, saves, terasology-server, .outputs]
known_dirt:
  - "src/test/resources/logback-test.xml"
steps:
  compile_all: "compile-all-stub"
  headless: "headless-stub"
  smoke: "smoke-stub"
hooks:
  after_add: "after-add-stub"
  after_reset: "after-reset-stub"
report:
  comment: on
YAML
  cat > "$WORKSPACE/realms/realm-test/naust/trust.yaml" <<'YAML'
terasology:
  maintainers: [Cervator, jdrueckert]
  trusted: [SiliconSaga/Terasology, trustedbot]
  nod_label: ok-to-test
  nod_phrase: "ok to test"
YAML
  NAUST="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/bin/naust"
}

run_naust() { run bash "$NAUST" "$@"; }
```

- [ ] **Step 3: Write the failing tests for `lib.sh`**

Create `components/naust/tests/lib.bats`:

```bash
#!/usr/bin/env bats
load helpers/stub

setup() { naust_setup; }

@test "naust --help lists the commands" {
    run_naust --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"tick"*"bay"*"run"* ]]
}

@test "load_config reads naust.yaml and creates the state directories" {
    run bash -c "source '$(dirname "$NAUST")/lib.sh'; load_config; echo \"\$STATE_DIR|\$PROFILE_DIR\""
    [ "$status" -eq 0 ]
    [[ "$output" == "$NAUST_HOME/state|$BATS_TEST_TMPDIR/ws/realms/realm-test/naust" ]]
    [ -d "$NAUST_HOME/state/queue" ]
    [ -d "$NAUST_HOME/state/seen" ]
    [ -d "$NAUST_HOME/state/jobs" ]
}

@test "load_config fails without a workspace" {
    printf 'realm: x\n' > "$NAUST_CONFIG"
    run bash -c "source '$(dirname "$NAUST")/lib.sh'; load_config"
    [ "$status" -ne 0 ]
    grep -q "workspace is required" "$NAUST_LOG"
}

@test "prof and trust read the realm files with defaults" {
    run bash -c "source '$(dirname "$NAUST")/lib.sh'; load_config; prof terasology .repo; prof terasology .missing fallback; trust terasology .nod_label"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "MovingBlocks/Terasology" ]
    [ "${lines[1]}" = "fallback" ]
    [ "${lines[2]}" = "ok-to-test" ]
}

@test "env_value reads .env literally and never evaluates it" {
    printf 'export NAUST_DISCORD_WEBHOOK="https://example.invalid/$(touch %s/boom)"\n' "$BATS_TEST_TMPDIR" > "$NAUST_ENV_FILE"
    run bash -c "source '$(dirname "$NAUST")/lib.sh'; env_value NAUST_DISCORD_WEBHOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == 'https://example.invalid/$(touch '* ]]
    [ ! -e "$BATS_TEST_TMPDIR/boom" ]
}

@test "kv_set and kv_get round-trip and overwrite" {
    f="$BATS_TEST_TMPDIR/kv"
    run bash -c "source '$(dirname "$NAUST")/lib.sh'; kv_set '$f' state free; kv_set '$f' job none; kv_set '$f' state busy; kv_get '$f' state; kv_get '$f' job; kv_get '$f' absent"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "busy" ]
    [ "${lines[1]}" = "none" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "with_lock is exclusive and a stale lock is reclaimed" {
    run bash -c "source '$(dirname "$NAUST")/lib.sh'; load_config; with_lock && echo first; mkdir -p '$NAUST_HOME/state'; "
    [ "$status" -eq 0 ]
    [[ "$output" == *"first"* ]]
    # A lock left by a dead tick
    mkdir -p "$NAUST_HOME/state/lock"
    printf '%s\n' 1 > "$NAUST_HOME/state/lock/pid"
    run bash -c "source '$(dirname "$NAUST")/lib.sh'; load_config; if with_lock; then echo got; else echo busy; fi"
    [[ "$output" == *"busy"* ]]
    # Older than lock_stale_hours: reclaimed
    touch -d '@1759970000' "$NAUST_HOME/state/lock"
    run bash -c "source '$(dirname "$NAUST")/lib.sh'; load_config; if with_lock; then echo got; else echo busy; fi"
    [[ "$output" == *"got"* ]]
}

@test "json_escape handles quotes, backslashes and newlines" {
    run bash -c "source '$(dirname "$NAUST")/lib.sh'; json_escape \$'a \"b\" \\\\ c\nd'"
    [ "$status" -eq 0 ]
    [ "$output" = 'a \"b\" \\ c\nd' ]
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `bash components/naust/tests/run.sh test tests/lib.bats`
Expected: every test fails (no `bin/naust`, no `lib.sh`).

- [ ] **Step 5: Implement `bin/lib.sh`**

```bash
#!/usr/bin/env bash
# Shared helpers for naust: logging, config, state files, the tick lock.
# Sourced, never executed. Every script that sources it calls load_config.

NAUST_HOME="${NAUST_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
NAUST_CONFIG="${NAUST_CONFIG:-$NAUST_HOME/naust.yaml}"
NAUST_ENV_FILE="${NAUST_ENV_FILE:-$NAUST_HOME/.env}"

# Log lines go to stderr, or to NAUST_LOG when set (the tests set it, so a
# script's stdout stays an exact contract and the log is grepped on its own).
log() {
  local line; line="$(printf '%s naust: %s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*")"
  if [ -n "${NAUST_LOG:-}" ]; then printf '%s\n' "$line" >> "$NAUST_LOG"; else printf '%s\n' "$line" >&2; fi
}
die() { log "ERROR: $*"; [ -n "${NAUST_LOG:-}" ] && printf 'naust: ERROR: %s\n' "$*" >&2; exit 1; }
# Overridable so tests get a fixed clock.
now() { printf '%s\n' "${NAUST_NOW:-$(date +%s)}"; }
require_tool() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not on PATH"; }

# One scalar from a YAML file, with a default when absent or null.
_yq_scalar() { # <file> <path> [default]
  local v
  v="$(yq "$2 // \"\"" "$1" 2>/dev/null)" || v=""
  if [ -z "$v" ] || [ "$v" = "null" ]; then printf '%s\n' "${3:-}"; else printf '%s\n' "$v"; fi
}
# A YAML list, one item per line (empty when absent).
_yq_list() { # <file> <path>
  yq "($2 // [])[]" "$1" 2>/dev/null || true
}

cfg() { _yq_scalar "$NAUST_CONFIG" "$1" "${2:-}"; }
cfg_list() { _yq_list "$NAUST_CONFIG" "$1"; }
prof() { _yq_scalar "$PROFILE_DIR/$1.yaml" "$2" "${3:-}"; }
prof_list() { _yq_list "$PROFILE_DIR/$1.yaml" "$2"; }
trust() { _yq_scalar "$PROFILE_DIR/trust.yaml" ".$1$2" "${3:-}"; }
trust_list() { _yq_list "$PROFILE_DIR/trust.yaml" ".$1$2"; }

load_config() {
  [ -f "$NAUST_CONFIG" ] || die "no config at $NAUST_CONFIG (copy naust.example.yaml to naust.yaml)"
  require_tool yq; require_tool git
  WORKSPACE="$(cfg .workspace)"; [ -n "$WORKSPACE" ] || die "naust.yaml: workspace is required"
  REALM="$(cfg .realm)"; [ -n "$REALM" ] || die "naust.yaml: realm is required"
  BAYS_ROOT="$(cfg .bays_root "$NAUST_HOME/bays")"
  STATE_DIR="$(cfg .state_dir "$NAUST_HOME/state")"
  GRADLE_HOME="$(cfg .gradle_home "$NAUST_HOME/gradle-home")"
  LOCK_STALE_HOURS="$(cfg .lock_stale_hours 6)"
  REALM_DIR="$WORKSPACE/realms/$REALM"
  PROFILE_DIR="$REALM_DIR/naust"
  [ -d "$PROFILE_DIR" ] || die "no profiles at $PROFILE_DIR"
  mkdir -p "$STATE_DIR/queue" "$STATE_DIR/seen" "$STATE_DIR/jobs" "$BAYS_ROOT"
  export WORKSPACE REALM BAYS_ROOT STATE_DIR GRADLE_HOME REALM_DIR PROFILE_DIR LOCK_STALE_HOURS
}

# Read one value out of the operator's .env, literally: the optional `export `
# prefix is stripped, surrounding quotes are removed, nothing is evaluated.
env_value() {
  local key="$1" line
  [ -f "$NAUST_ENV_FILE" ] || return 0
  line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$NAUST_ENV_FILE" | tail -n1)" || true
  [ -n "$line" ] || return 0
  line="${line#*=}"
  line="${line%\"}"; line="${line#\"}"
  line="${line%\'}"; line="${line#\'}"
  printf '%s\n' "$line"
}

# key=value state files. Keys are [A-Za-z0-9_], values are single lines.
kv_get() { # <file> <key>
  [ -f "$1" ] || return 0
  sed -n "s/^$2=//p" "$1" | tail -n1
}
kv_set() { # <file> <key> <value>
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp)"
  { [ -f "$file" ] && grep -v "^$key=" "$file" || true; printf '%s=%s\n' "$key" "$value"; } > "$tmp"
  mv "$tmp" "$file"
}

# The tick lock: a directory, because mkdir is atomic everywhere. Holds the pid
# of the tick that took it. A lock older than LOCK_STALE_HOURS belongs to a tick
# that died without cleaning up and is reclaimed; a job never runs that long.
with_lock() {
  local lock="$STATE_DIR/lock" age
  if ! mkdir "$lock" 2>/dev/null; then
    age=$(( $(now) - $(stat -c %Y "$lock" 2>/dev/null || echo 0) ))
    if [ "$age" -gt $(( LOCK_STALE_HOURS * 3600 )) ]; then
      log "reclaiming a lock $age s old (pid $(cat "$lock/pid" 2>/dev/null || echo '?'))"
      rm -rf "$lock"
      mkdir "$lock" 2>/dev/null || return 1
    else
      return 1
    fi
  fi
  printf '%s\n' "$$" > "$lock/pid"
  trap 'rm -rf "$STATE_DIR/lock"' EXIT
  return 0
}

# Escape a string for use inside a JSON string literal. Enough for the Discord
# payload and the comment body: backslash, quote, newline, tab, carriage return.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}
```

- [ ] **Step 6: Implement `bin/naust`**

```bash
#!/usr/bin/env bash
# naust — the boathouse. Keeps bays (sibling yggdrasil workspaces) and runs
# pull requests through them. `naust tick` is what the scheduler calls.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Usage: naust <command> [args]

  tick                         poll, gate, queue, run one job, exit (the scheduled entry point)
  bay add <name> --profile <p> provision a bay
  bay reset <name> [--deep]    reset a bay to base; --deep also drops Gradle outputs
  bay list                     every bay with its state
  bay release <name>           hand a ready or held bay back to the pool
  run <profile> <n> [--with <target>#<n>]... [--bay <name>]
                               queue a PR by hand, ahead of polled ones
  report render <jobdir>       re-render a job's report.md and comment.md
  notify say <text> [--file <path>]
                               post to the Discord webhook

Config: naust.yaml beside this directory's parent (see naust.example.yaml);
secrets in .env (GDD_GITHUB_TOKEN, NAUST_DISCORD_WEBHOOK).
USAGE
}

cmd="${1:-}"
case "$cmd" in
  ""|-h|--help|help) usage; exit 0 ;;
  tick|bay|run|job|report|notify)
    shift
    exec bash "$HERE/$cmd.sh" "$@" ;;
  *) echo "naust: unknown command '$cmd'" >&2; usage >&2; exit 2 ;;
esac
```

Until the other scripts exist, `naust tick` fails with "No such file"; that is fine for this task's tests.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bash components/naust/tests/run.sh test tests/lib.bats`
Expected: 8 tests pass.

- [ ] **Step 8: Example config and env**

Create `components/naust/naust.example.yaml`:

```yaml
# Copy to naust.yaml beside bin/. Machine-local; never committed.
workspace: D:/Dev/GitWS/yggdrasil        # the dev workspace whose realm holds naust/ profiles
realm: realm-siliconsaga
bays_root: D:/Dev/GitWS/naust/bays
state_dir: D:/Dev/GitWS/naust/state
gradle_home: D:/Dev/GitWS/naust/gradle-home
profiles: [terasology]
yggdrasil_repo: https://github.com/SiliconSaga/yggdrasil.git
realm_repo: https://github.com/SiliconSaga/realm-siliconsaga.git
lock_stale_hours: 6
```

Create `components/naust/.env.example`:

```bash
# Copy to .env. Read literally by naust (never sourced). Secrets only.
GDD_GITHUB_TOKEN=github_pat_...   # the machine account; pull-requests: write on the watched repo
NAUST_DISCORD_WEBHOOK=https://discord.com/api/webhooks/...
```

- [ ] **Step 9: Commit**

Write `.commits/naust-skeleton.md` (paths relative to `components/naust`):

```markdown
---
message: "feat: naust skeleton — dispatcher, shared library, bats harness"
add:
  - bin/naust
  - bin/lib.sh
  - tests/run.sh
  - tests/helpers/stub.bash
  - tests/lib.bats
  - naust.example.yaml
  - .env.example
  - .gitignore
---

The library is the contract every later script relies on: config through yq, state as key=value files, a mkdir lock with stale reclaim, and a literal .env reader lifted from gdd-sandbox so a secret file is never evaluated.
```

Run: `ws commit naust .commits/naust-skeleton.md`

### Task 3: `notify.sh` — the Discord webhook

**Files:**
- Create: `components/naust/bin/notify.sh`, `components/naust/tests/notify.bats`

**Interfaces:**
- Consumes: `lib.sh` (`env_value`, `json_escape`, `log`).
- Produces: `naust notify say <text> [--file <path>]`. Posts `{"content": <text>}` to `NAUST_DISCORD_WEBHOOK` as multipart `payload_json`, attaching the file when given. Exit 0 and a log line when no webhook is configured (notification is optional); exit 1 when curl fails. Text longer than 1900 characters is truncated with ` …`.

- [ ] **Step 1: Write the failing tests**

Create `components/naust/tests/notify.bats`:

```bash
#!/usr/bin/env bats
load helpers/stub

setup() {
    naust_setup
    make_stub curl 'exit 0'
}

@test "say posts the text as payload_json to the webhook" {
    printf 'NAUST_DISCORD_WEBHOOK=https://discord.invalid/hook\n' > "$NAUST_ENV_FILE"
    run_naust notify say 'PR #7 by @x needs a "nod"'
    [ "$status" -eq 0 ]
    grep -q -- '-F payload_json={"content":"PR #7 by @x needs a \\"nod\\""} https://discord.invalid/hook' "$STUB_LOG"
}

@test "say attaches a file when asked" {
    printf 'NAUST_DISCORD_WEBHOOK=https://discord.invalid/hook\n' > "$NAUST_ENV_FILE"
    touch "$BATS_TEST_TMPDIR/shot.png"
    run_naust notify say 'done' --file "$BATS_TEST_TMPDIR/shot.png"
    [ "$status" -eq 0 ]
    grep -q -- "-F file=@$BATS_TEST_TMPDIR/shot.png" "$STUB_LOG"
}

@test "say without a webhook is a no-op that says so" {
    run_naust notify say 'hello'
    [ "$status" -eq 0 ]
    grep -q "no NAUST_DISCORD_WEBHOOK" "$NAUST_LOG"
    [ ! -s "$STUB_LOG" ]
}

@test "say fails when curl fails" {
    printf 'NAUST_DISCORD_WEBHOOK=https://discord.invalid/hook\n' > "$NAUST_ENV_FILE"
    make_stub curl 'exit 22'
    run_naust notify say 'hello'
    [ "$status" -ne 0 ]
}

@test "say truncates long text" {
    printf 'NAUST_DISCORD_WEBHOOK=https://discord.invalid/hook\n' > "$NAUST_ENV_FILE"
    long="$(printf 'x%.0s' $(seq 1 2500))"
    run_naust notify say "$long"
    [ "$status" -eq 0 ]
    grep -q -- 'xxx …"}' "$STUB_LOG"
    [ "$(grep -o 'x' "$STUB_LOG" | wc -l)" -le 1901 ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash components/naust/tests/run.sh test tests/notify.bats`
Expected: all fail (`notify.sh` missing).

- [ ] **Step 3: Implement `bin/notify.sh`**

```bash
#!/usr/bin/env bash
# Post to the Discord webhook from outside any agent session. Optional: with no
# webhook configured every call is a logged no-op, so a bay machine without
# Discord still runs jobs.
#
#   notify.sh say <text> [--file <path>]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/lib.sh
. "$HERE/lib.sh"

MAX_CONTENT=1900   # Discord's ceiling is 2000; leave room for the ellipsis

cmd_say() {
  local text="" file="" hook
  while [ $# -gt 0 ]; do
    case "$1" in
      --file) file="$2"; shift 2 ;;
      *) text="$1"; shift ;;
    esac
  done
  [ -n "$text" ] || die "notify say: text is required"
  hook="$(env_value NAUST_DISCORD_WEBHOOK)"
  if [ -z "$hook" ]; then
    log "no NAUST_DISCORD_WEBHOOK in $NAUST_ENV_FILE; not posting: ${text:0:80}"
    return 0
  fi
  if [ "${#text}" -gt "$MAX_CONTENT" ]; then
    text="${text:0:$MAX_CONTENT} …"
  fi
  local payload
  payload="{\"content\":\"$(json_escape "$text")\"}"
  if [ -n "$file" ]; then
    [ -f "$file" ] || die "notify say: no such file $file"
    curl -fsS --connect-timeout 5 --max-time 60 -F "payload_json=$payload" -F "file=@$file" "$hook" >/dev/null
  else
    curl -fsS --connect-timeout 5 --max-time 30 -F "payload_json=$payload" "$hook" >/dev/null
  fi
}

case "${1:-}" in
  say) shift; cmd_say "$@" ;;
  *) echo "usage: notify.sh say <text> [--file <path>]" >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash components/naust/tests/run.sh test tests/notify.bats`
Expected: 5 pass.

- [ ] **Step 5: Commit**

`.commits/naust-notify.md`:

```markdown
---
message: "feat: notify say posts to the Discord webhook, with an optional file"
add:
  - bin/notify.sh
  - tests/notify.bats
---

A webhook rather than a bot: no token with chat scope on the bay machine, no session, and the screenshot rides along as a multipart file. Absent webhook is a no-op so a bay without Discord still works.
```

Run: `ws commit naust .commits/naust-notify.md`

### Task 4: `bay.sh` — provision, reset, states

**Files:**
- Create: `components/naust/bin/bay.sh`, `components/naust/tests/bay.bats`
- Modify: `components/naust/tests/helpers/stub.bash` (add `make_bay_repo`, `make_bay`)

**Interfaces:**
- Consumes: `lib.sh`; profile keys `component`, `repo`, `upstream_remote`, `default_branch`, `nested` (globs), `nested_default_branch`, `init.modules` (optional distro name for `groovyw module init`), `runtime_dirs` (relative to the component dir), `steps.compile_all`, `hooks.after_add`, `hooks.after_reset`, `bay.ready_ttl_days`.
- Produces: `naust bay add <name> --profile <p>`, `naust bay reset <name> [--deep]` (exit 1 and state `broken` when any repository fails), `naust bay list` (tab-separated `name state profile job age_seconds`), `naust bay release <name>`, and the internal `naust bay claim <name> <jobid>` (exit 1 unless `free`), `naust bay set <name> <state>`, `naust bay free-for <profile>` (prints a bay name or exits 1; expires `ready` bays past the TTL first), `naust bay repos <name>` (the component dir and every nested repo, one per line), `naust bay dir <name>`.
- Bay state file `<bays_root>/<name>/bay.state`: `state`, `profile`, `job`, `since`. States: `provisioning free busy ready held broken`.
- Environment every hook and profile command receives: `NAUST_BAY_DIR`, `NAUST_BAY_NAME`, `NAUST_WS_DIR` (`<bay>/yggdrasil`), `NAUST_COMP_DIR`, `NAUST_REALM_DIR`, `NAUST_PROFILE`, `GRADLE_USER_HOME`; cwd is `NAUST_COMP_DIR`.

- [ ] **Step 1: Fixture helpers**

Append to `components/naust/tests/helpers/stub.bash`:

```bash
# A real repository on <branch> whose remote <remote> is a local bare repo that
# already holds the branch. Reset tests need both ends to be real git.
make_bay_repo() { # <dir> <remote-name> <branch>
  local dir="$1" remote="$2" branch="$3" bare="$1.git"
  mkdir -p "$dir"
  git -C "$dir" init -q -b "$branch"
  git -C "$dir" config user.email t@example.invalid
  git -C "$dir" config user.name T
  printf 'seed\n' > "$dir/seed.txt"
  git -C "$dir" add seed.txt
  git -C "$dir" commit -qm seed
  git init -q --bare "$bare"
  git -C "$dir" remote add "$remote" "$bare"
  git -C "$dir" push -q "$remote" "$branch"
}

# A bay directory with a state file and a real component repo (MovingBlocks
# remote, develop) holding one real nested module (origin remote, develop).
make_bay() { # <name> <state>
  local dir="$NAUST_HOME/bays/$1"
  mkdir -p "$dir/yggdrasil/scripts" "$dir/yggdrasil/components"
  cp "$STUB_BIN/ws" "$dir/yggdrasil/scripts/ws" 2>/dev/null || printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/yggdrasil/scripts/ws"
  printf 'state=%s\nprofile=terasology\njob=\nsince=%s\n' "$2" "$NAUST_NOW" > "$dir/bay.state"
  make_bay_repo "$dir/yggdrasil/components/terasology" MovingBlocks develop
  make_bay_repo "$dir/yggdrasil/components/terasology/modules/Cooking" origin develop
  printf '/build/\n' > "$dir/yggdrasil/components/terasology/.gitignore"
  git -C "$dir/yggdrasil/components/terasology" add .gitignore
  git -C "$dir/yggdrasil/components/terasology" commit -qm gitignore
  git -C "$dir/yggdrasil/components/terasology" push -q MovingBlocks develop
  BAY_DIR="$dir"
}
```

- [ ] **Step 2: Write the failing tests**

Create `components/naust/tests/bay.bats`:

```bash
#!/usr/bin/env bats
load helpers/stub

setup() {
    naust_setup
    make_stub compile-all-stub
    make_stub after-add-stub
    make_stub after-reset-stub
}

@test "add provisions in order and leaves the bay free" {
    make_stub ws 'case "$1" in clone) mkdir -p "$(dirname "$0")/../components/$2" ;; esac'
    # clone creates the workspace skeleton with the ws stub inside; every other
    # git call is a silent success so the closing reset passes on empty repos.
    make_stub git 'if [ "$1" = clone ]; then d="${@: -1}"; mkdir -p "$d/scripts"; cp "$STUB_BIN/ws" "$d/scripts/ws"; fi; exit 0'

    run_naust bay add bay-1 --profile terasology

    [ "$status" -eq 0 ]
    grep -n '' "$STUB_LOG" >&2
    [[ "$(sed -n 1p "$STUB_LOG")" == git\ clone* ]]
    grep -q '^ws realm ' "$STUB_LOG"
    grep -q '^ws realm use realm-test --trust' "$STUB_LOG"
    grep -q '^ws clone terasology' "$STUB_LOG"
    grep -q '^ws build terasology' "$STUB_LOG"
    grep -q '^compile-all-stub' "$STUB_LOG"
    grep -q '^after-add-stub' "$STUB_LOG"
    grep -q '^after-reset-stub' "$STUB_LOG"
    [ "$(sed -n 's/^state=//p' "$NAUST_HOME/bays/bay-1/bay.state")" = "free" ]
    [ "$(sed -n 's/^profile=//p' "$NAUST_HOME/bays/bay-1/bay.state")" = "terasology" ]
}

@test "add refuses an existing bay" {
    make_bay bay-1 free
    run_naust bay add bay-1 --profile terasology
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "reset returns engine and module to their remote default branch, clean" {
    make_bay bay-1 ready
    comp="$BAY_DIR/yggdrasil/components/terasology"
    # dirt of every kind: a local branch with a commit, a tracked edit, an
    # untracked file, a runtime dir, an ignored build dir, module dirt
    git -C "$comp" switch -q -c pr/7
    printf 'x\n' > "$comp/pr.txt"; git -C "$comp" add pr.txt; git -C "$comp" commit -qm pr
    printf 'edited\n' >> "$comp/seed.txt"
    printf 'stray\n' > "$comp/stray.txt"
    mkdir -p "$comp/logs/run1" "$comp/build/classes"; touch "$comp/logs/run1/a.log" "$comp/build/classes/A.class"
    printf 'lb\n' > "$comp/modules/Cooking/src.txt"
    mkdir -p "$BAY_DIR/yggdrasil/.outputs/naust/old"; touch "$BAY_DIR/yggdrasil/.outputs/naust/old/report.md"

    run_naust bay reset bay-1

    [ "$status" -eq 0 ]
    [ "$(git -C "$comp" rev-parse --abbrev-ref HEAD)" = "develop" ]
    [ "$(git -C "$comp" rev-parse HEAD)" = "$(git -C "$comp" rev-parse MovingBlocks/develop)" ]
    [ -z "$(git -C "$comp" status --porcelain)" ]
    [ ! -e "$comp/stray.txt" ]
    [ ! -e "$comp/logs" ]
    [ -e "$comp/build/classes/A.class" ]          # Gradle output survives a plain reset
    [ -z "$(git -C "$comp/modules/Cooking" status --porcelain)" ]
    [ ! -e "$BAY_DIR/yggdrasil/.outputs/naust/old" ]
    grep -q '^after-reset-stub' "$STUB_LOG"
    [ "$(sed -n 's/^state=//p' "$BAY_DIR/bay.state")" = "free" ]
}

@test "reset --deep also drops ignored files" {
    make_bay bay-1 ready
    comp="$BAY_DIR/yggdrasil/components/terasology"
    mkdir -p "$comp/build/classes"; touch "$comp/build/classes/A.class"
    run_naust bay reset bay-1 --deep
    [ "$status" -eq 0 ]
    [ ! -e "$comp/build" ]
}

@test "reset marks the bay broken and names the repo when a nested fetch fails" {
    make_bay bay-1 ready
    git -C "$BAY_DIR/yggdrasil/components/terasology/modules/Cooking" remote set-url origin "$BATS_TEST_TMPDIR/does-not-exist.git"
    run_naust bay reset bay-1
    [ "$status" -ne 0 ]
    grep -q "FAILED in .*modules/Cooking" "$NAUST_LOG"
    [ "$(sed -n 's/^state=//p' "$BAY_DIR/bay.state")" = "broken" ]
    ! grep -q '^after-reset-stub' "$STUB_LOG"
}

@test "claim takes a free bay once; release frees a ready or held bay" {
    make_bay bay-1 free
    run_naust bay claim bay-1 job-1
    [ "$status" -eq 0 ]
    [ "$(sed -n 's/^state=//p' "$BAY_DIR/bay.state")" = "busy" ]
    [ "$(sed -n 's/^job=//p' "$BAY_DIR/bay.state")" = "job-1" ]
    run_naust bay claim bay-1 job-2
    [ "$status" -ne 0 ]
    run_naust bay set bay-1 ready
    run_naust bay release bay-1
    [ "$status" -eq 0 ]
    [ "$(sed -n 's/^state=//p' "$BAY_DIR/bay.state")" = "free" ]
    run_naust bay set bay-1 busy
    run_naust bay release bay-1
    [ "$status" -ne 0 ]
}

@test "free-for finds a free bay of the profile and expires a stale ready one" {
    make_bay bay-1 ready
    make_bay bay-2 held
    run_naust bay free-for terasology
    [ "$status" -ne 0 ]
    # ready for 8 days with a 7-day TTL: back in the pool
    printf 'state=ready\nprofile=terasology\njob=old\nsince=%s\n' $((NAUST_NOW - 8*86400)) > "$NAUST_HOME/bays/bay-1/bay.state"
    run_naust bay free-for terasology
    [ "$status" -eq 0 ]
    [ "$output" = "bay-1" ]
    run_naust bay free-for other-profile
    [ "$status" -ne 0 ]
}

@test "list prints every bay with state, profile, job and age" {
    make_bay bay-1 free
    make_bay bay-2 busy
    run_naust bay list
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == bay-1$'\t'free$'\t'terasology$'\t'$'\t'0 ]]
    [[ "${lines[1]}" == bay-2$'\t'busy* ]]
}

@test "repos lists the component and its nested repos" {
    make_bay bay-1 free
    run_naust bay repos bay-1
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$BAY_DIR/yggdrasil/components/terasology" ]
    [ "${lines[1]}" = "$BAY_DIR/yggdrasil/components/terasology/modules/Cooking" ]
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash components/naust/tests/run.sh test tests/bay.bats`
Expected: all fail (`bay.sh` missing).

- [ ] **Step 4: Implement `bin/bay.sh`**

```bash
#!/usr/bin/env bash
# Bays: sibling yggdrasil workspaces, provisioned once and reset between jobs.
#
#   bay.sh add <name> --profile <p>     bay.sh reset <name> [--deep]
#   bay.sh list                         bay.sh release <name>
#   bay.sh claim <name> <jobid>         bay.sh set <name> <state>
#   bay.sh free-for <profile>           bay.sh repos <name>      bay.sh dir <name>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/lib.sh
. "$HERE/lib.sh"
load_config

RESET_PARALLEL="${NAUST_RESET_PARALLEL:-8}"

bay_dir() { printf '%s/%s\n' "$BAYS_ROOT" "$1"; }
bay_state_file() { printf '%s/%s/bay.state\n' "$BAYS_ROOT" "$1"; }
bay_state() { kv_get "$(bay_state_file "$1")" state; }
bay_profile() { kv_get "$(bay_state_file "$1")" profile; }
bay_exists() { [ -f "$(bay_state_file "$1")" ]; }
bay_require() { bay_exists "$1" || die "no bay named '$1' under $BAYS_ROOT"; }

bay_set_state() { # <name> <state> [job]
  local f; f="$(bay_state_file "$1")"
  kv_set "$f" state "$2"
  kv_set "$f" job "${3-$(kv_get "$f" job)}"
  kv_set "$f" since "$(now)"
}

# Export what hooks and profile commands rely on, and cd to the component.
bay_env() { # <name>
  local dir profile comp
  dir="$(bay_dir "$1")"; profile="$(bay_profile "$1")"
  comp="$(prof "$profile" .component)"
  [ -n "$comp" ] || die "profile $profile has no component"
  export NAUST_BAY_DIR="$dir" NAUST_BAY_NAME="$1" NAUST_PROFILE="$profile"
  export NAUST_WS_DIR="$dir/yggdrasil"
  export NAUST_COMP_DIR="$dir/yggdrasil/components/$comp"
  export NAUST_REALM_DIR="$dir/yggdrasil/realms/$REALM"
  export GRADLE_USER_HOME="$GRADLE_HOME"
  WS="$NAUST_WS_DIR/scripts/ws"
}

# Run a profile command or hook in the component dir; empty means skip.
bay_run_in_comp() { # <label> <command>
  [ -n "$2" ] || return 0
  log "$1: $2"
  (cd "$NAUST_COMP_DIR" && bash -c "$2")
}

cmd_repos() {
  bay_require "$1"; bay_env "$1"
  local g d
  printf '%s\n' "$NAUST_COMP_DIR"
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    for d in "$NAUST_COMP_DIR"/$g; do
      [ -d "$d/.git" ] && printf '%s\n' "$d"
    done
  done < <(prof_list "$NAUST_PROFILE" .nested)
}

# Fetch, hard-reset and switch one repository to <remote>/<branch>, then clean.
# Writes <fails>/<key> on any failure so the parallel caller can report it.
reset_one() { # <dir> <remote> <branch> <deep:yes|no> <fails-dir>
  local d="$1" remote="$2" branch="$3" deep="$4" fails="$5" key clean="-qfd"
  key="$(printf '%s' "$d" | tr '/:' '__')"
  [ "$deep" = yes ] && clean="-qfdx"
  if git -C "$d" fetch --quiet "$remote" \
     && git -C "$d" reset -q --hard \
     && git -C "$d" switch -q -C "$branch" "$remote/$branch" \
     && git -C "$d" clean $clean; then
    return 0
  fi
  printf '%s\n' "$d" > "$fails/$key"
  return 0
}

cmd_reset() {
  local name="$1" deep=no
  [ "${2:-}" = "--deep" ] && deep=yes
  bay_require "$name"; bay_env "$name"
  local up br nbr fails running=0 r failed=0 rd started
  started="$(now)"
  up="$(prof "$NAUST_PROFILE" .upstream_remote origin)"
  br="$(prof "$NAUST_PROFILE" .default_branch main)"
  nbr="$(prof "$NAUST_PROFILE" .nested_default_branch "$br")"
  fails="$(mktemp -d)"
  log "reset $name: $(cmd_repos "$name" | wc -l) repositories to $up/$br (modules: origin/$nbr), deep=$deep"
  while IFS= read -r r; do
    if [ "$r" = "$NAUST_COMP_DIR" ]; then
      reset_one "$r" "$up" "$br" "$deep" "$fails" &
    else
      reset_one "$r" origin "$nbr" "$deep" "$fails" &
    fi
    running=$((running + 1))
    if [ "$running" -ge "$RESET_PARALLEL" ]; then wait -n; running=$((running - 1)); fi
  done < <(cmd_repos "$name")
  wait
  for r in "$fails"/*; do
    [ -e "$r" ] || continue
    log "reset $name: FAILED in $(cat "$r")"
    failed=1
  done
  rm -rf "$fails"
  if [ "$failed" -ne 0 ]; then
    bay_set_state "$name" broken
    die "reset $name: bay marked broken"
  fi
  while IFS= read -r rd; do
    [ -n "$rd" ] || continue
    rm -rf "${NAUST_COMP_DIR:?}/$rd"
  done < <(prof_list "$NAUST_PROFILE" .runtime_dirs)
  rm -rf "$NAUST_WS_DIR/.outputs/naust"
  bay_run_in_comp "after_reset" "$(prof "$NAUST_PROFILE" .hooks.after_reset)"
  while IFS= read -r r; do
    if [ -n "$(git -C "$r" status --porcelain)" ]; then
      log "reset $name: $r is still dirty after reset"
      failed=1
    fi
  done < <(cmd_repos "$name")
  if [ "$failed" -ne 0 ]; then
    bay_set_state "$name" broken
    die "reset $name: bay marked broken"
  fi
  bay_set_state "$name" free ""
  log "reset $name: free in $(( $(now) - started )) s"
}

cmd_add() {
  local name="$1" profile="" dir comp repo distro
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --profile) profile="$2"; shift 2 ;;
      *) die "bay add: unknown argument '$1'" ;;
    esac
  done
  [ -n "$profile" ] || die "bay add: --profile <name> is required"
  [ -f "$PROFILE_DIR/$profile.yaml" ] || die "bay add: no profile $PROFILE_DIR/$profile.yaml"
  dir="$(bay_dir "$name")"
  [ ! -e "$dir" ] || die "bay add: $dir already exists"
  mkdir -p "$dir" "$GRADLE_HOME"
  printf 'state=provisioning\nprofile=%s\njob=\nsince=%s\n' "$profile" "$(now)" > "$dir/bay.state"
  bay_env "$name"
  comp="$(prof "$profile" .component)"
  repo="$(prof "$profile" .repo)"
  log "add $name: cloning yggdrasil"
  git clone --quiet "$(cfg .yggdrasil_repo https://github.com/SiliconSaga/yggdrasil.git)" "$NAUST_WS_DIR"
  (cd "$NAUST_WS_DIR" && bash "$WS" realm "$(cfg .realm_repo "https://github.com/SiliconSaga/$REALM.git")")
  (cd "$NAUST_WS_DIR" && bash "$WS" realm use "$REALM" --trust)
  (cd "$NAUST_WS_DIR" && bash "$WS" clone "$comp")
  local up; up="$(prof "$profile" .upstream_remote origin)"
  if ! git -C "$NAUST_COMP_DIR" remote get-url "$up" >/dev/null 2>&1; then
    git -C "$NAUST_COMP_DIR" remote add "$up" "https://github.com/$repo.git"
  fi
  git -C "$NAUST_COMP_DIR" fetch --quiet "$up"
  distro="$(prof "$profile" .init.modules)"
  if [ -n "$distro" ]; then
    log "add $name: module distro $distro"
    (cd "$NAUST_COMP_DIR" && bash ./groovyw module init "$distro")
  fi
  (cd "$NAUST_WS_DIR" && bash "$WS" build "$comp")
  bay_run_in_comp "compile_all" "$(prof "$profile" .steps.compile_all)"
  bay_run_in_comp "after_add" "$(prof "$profile" .hooks.after_add)"
  cmd_reset "$name"
}

cmd_list() {
  local f name state profile job since
  for f in "$BAYS_ROOT"/*/bay.state; do
    [ -f "$f" ] || continue
    name="$(basename "$(dirname "$f")")"
    state="$(kv_get "$f" state)"; profile="$(kv_get "$f" profile)"
    job="$(kv_get "$f" job)"; since="$(kv_get "$f" since)"
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$state" "$profile" "$job" "$(( $(now) - ${since:-$(now)} ))"
  done
}

cmd_claim() {
  bay_require "$1"
  [ "$(bay_state "$1")" = free ] || { log "claim $1: not free ($(bay_state "$1"))"; return 1; }
  bay_set_state "$1" busy "$2"
}

cmd_release() {
  bay_require "$1"
  case "$(bay_state "$1")" in
    ready|held) bay_set_state "$1" free "" ;;
    *) die "release $1: state is $(bay_state "$1"), only ready or held can be released" ;;
  esac
}

cmd_set() {
  bay_require "$1"
  case "$2" in free|busy|ready|held|broken) ;; *) die "set: unknown state '$2'" ;; esac
  bay_set_state "$1" "$2"
}

cmd_free_for() {
  local profile="$1" f name ttl since
  ttl="$(prof "$profile" .bay.ready_ttl_days 7)"
  for f in "$BAYS_ROOT"/*/bay.state; do
    [ -f "$f" ] || continue
    [ "$(kv_get "$f" profile)" = "$profile" ] || continue
    name="$(basename "$(dirname "$f")")"
    if [ "$(kv_get "$f" state)" = ready ]; then
      since="$(kv_get "$f" since)"
      if [ $(( $(now) - since )) -gt $(( ttl * 86400 )) ]; then
        log "free-for: $name ready for more than $ttl days, back in the pool"
        bay_set_state "$name" free ""
      fi
    fi
    if [ "$(kv_get "$f" state)" = free ]; then printf '%s\n' "$name"; return 0; fi
  done
  return 1
}

case "${1:-}" in
  add)      shift; [ $# -ge 1 ] || die "bay add <name> --profile <p>"; cmd_add "$@" ;;
  reset)    shift; [ $# -ge 1 ] || die "bay reset <name> [--deep]"; cmd_reset "$@" ;;
  list)     cmd_list ;;
  release)  shift; cmd_release "$1" ;;
  claim)    shift; cmd_claim "$1" "$2" ;;
  set)      shift; cmd_set "$1" "$2" ;;
  free-for) shift; cmd_free_for "$1" ;;
  repos)    shift; cmd_repos "$1" ;;
  dir)      shift; bay_require "$1"; bay_dir "$1" ;;
  *) echo "usage: bay.sh {add|reset|list|release|claim|set|free-for|repos|dir} ..." >&2; exit 2 ;;
esac
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash components/naust/tests/run.sh test tests/bay.bats`
Expected: 9 pass. If the `add` test fails on `ws build`, the `ws` stub's `clone` case must create the component directory before `cd` reaches it; the stub body in the test does that via `$(dirname "$0")/../components/$2`.

- [ ] **Step 6: Commit**

`.commits/naust-bay.md`:

```markdown
---
message: "feat: bays — provision once, reset to base in parallel, state machine"
add:
  - bin/bay.sh
  - tests/bay.bats
  - tests/helpers/stub.bash
---

A reset keeps Gradle outputs on purpose: with ~144 module subprojects a clean -fdx turns every job into a cold compile, and the thing a job must not inherit is tracked-tree state and runtime directories, which clean -fd plus the profile's runtime_dirs cover. --deep exists for the day a bay needs a cold start. Fetches run eight at a time; one failure anywhere marks the bay broken rather than running a job on a half-reset tree.
```

Run: `ws commit naust .commits/naust-bay.md`

### Task 5: `gate.sh` — the trust decision

**Files:**
- Create: `components/naust/bin/gate.sh`, `components/naust/tests/gate.bats`
- Modify: `components/naust/bin/naust` (dispatch `gate poll queue` as internal commands)

**Interfaces:**
- Consumes: `lib.sh` (`trust`, `trust_list`); `gh api` for the PR's `labeled` events and comments.
- Produces: `naust gate decide <profile> <repo> <number> <author> <head_repo> <labels-csv>` printing one line, `run<TAB><reason>` or `nod<TAB><reason>`, exit 0 either way. A label nod requires the label to be present now and its most recent `labeled` event's actor to be in `maintainers`; a comment nod requires a comment containing `nod_phrase` (case-insensitive) by a maintainer. Non-maintainer nods are named in the reason after `ignored:`.

- [ ] **Step 1: Dispatch the internal commands**

In `bin/naust`, change the dispatch line to `tick|bay|run|job|report|notify|gate|poll|queue)`.

- [ ] **Step 2: Write the failing tests**

Create `components/naust/tests/gate.bats`:

```bash
#!/usr/bin/env bats
load helpers/stub

setup() {
    naust_setup
    export GATE_EVENTS="" GATE_COMMENTS=""
    make_stub gh 'case "$*" in *events*) printf "%s\n" "$GATE_EVENTS" ;; *comments*) printf "%s\n" "$GATE_COMMENTS" ;; esac'
}

decide() { run_naust gate decide terasology MovingBlocks/Terasology 7 "$@"; }

@test "a maintainer's own PR runs" {
    decide Cervator Cervator/Terasology ""
    [ "$status" -eq 0 ]
    [ "$output" = $'run\tauthor Cervator is a maintainer' ]
}

@test "a trusted login or a trusted head repository runs" {
    decide trustedbot trustedbot/Terasology ""
    [ "$output" = $'run\tauthor trustedbot is trusted' ]
    decide stranger siliconsaga/terasology ""
    [ "$output" = $'run\thead repository siliconsaga/terasology is trusted' ]
}

@test "an unknown author with no nod needs one" {
    decide stranger stranger/Terasology "Category: Doc"
    [ "$output" = $'nod\tneeds a nod from a maintainer' ]
}

@test "the label counts only when a maintainer applied it, and only while present" {
    export GATE_EVENTS=$'stranger\njdrueckert'
    decide stranger stranger/Terasology "Category: Doc,ok-to-test"
    [ "$output" = $'run\tlabel ok-to-test applied by maintainer jdrueckert' ]
    export GATE_EVENTS=$'jdrueckert\nstranger'
    decide stranger stranger/Terasology "ok-to-test"
    [[ "$output" == nod$'\t'*"ignored: label ok-to-test applied by stranger"* ]]
    export GATE_EVENTS="jdrueckert"
    decide stranger stranger/Terasology ""
    [ "$output" = $'nod\tneeds a nod from a maintainer' ]
}

@test "the phrase counts from a maintainer, is ignored from anyone else" {
    export GATE_COMMENTS="Cervator"
    decide stranger stranger/Terasology ""
    [ "$output" = $'run\t"ok to test" from maintainer Cervator' ]
    export GATE_COMMENTS=$'stranger\nsomeoneelse'
    decide stranger stranger/Terasology ""
    [[ "$output" == nod$'\t'*'ignored: "ok to test" from stranger; "ok to test" from someoneelse'* ]]
}

@test "the gate asks GitHub for the events and comments of the right PR" {
    decide stranger stranger/Terasology ""
    grep -q 'gh api repos/MovingBlocks/Terasology/issues/7/events --paginate' "$STUB_LOG"
    grep -q 'gh api repos/MovingBlocks/Terasology/issues/7/comments --paginate' "$STUB_LOG"
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash components/naust/tests/run.sh test tests/gate.bats`
Expected: all fail.

- [ ] **Step 4: Implement `bin/gate.sh`**

```bash
#!/usr/bin/env bash
# The trust gate: may this pull request run in a bay, and why.
#
#   gate.sh decide <profile> <repo> <number> <author> <head_repo> <labels-csv>
#
# Prints "run<TAB>reason" or "nod<TAB>reason". A nod is a maintainer's act: the
# label is read through the PR timeline so the actor is known, and the phrase
# through the comments so the author is known. Presence of the label alone
# proves nothing, since anyone with triage can apply one.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/lib.sh
. "$HERE/lib.sh"
load_config
require_tool gh

has_line() { grep -qxF -- "$1"; }          # stdin: one candidate per line
has_line_ci() { grep -qxiF -- "$1"; }

cmd_decide() {
  local profile="$1" repo="$2" number="$3" author="$4" head_repo="$5" labels="${6:-}"
  local maintainers trusted label phrase labeled_by commenters last a ignored=""
  maintainers="$(trust_list "$profile" .maintainers)"
  trusted="$(trust_list "$profile" .trusted)"
  if printf '%s\n' "$maintainers" | has_line "$author"; then
    printf 'run\tauthor %s is a maintainer\n' "$author"; return 0
  fi
  if printf '%s\n' "$trusted" | has_line "$author"; then
    printf 'run\tauthor %s is trusted\n' "$author"; return 0
  fi
  if printf '%s\n' "$trusted" | has_line_ci "$head_repo"; then
    printf 'run\thead repository %s is trusted\n' "$head_repo"; return 0
  fi
  label="$(trust "$profile" .nod_label ok-to-test)"
  phrase="$(trust "$profile" .nod_phrase 'ok to test')"
  labeled_by="$(gh api "repos/$repo/issues/$number/events" --paginate \
      --jq ".[] | select(.event == \"labeled\" and .label.name == \"$label\") | .actor.login" 2>/dev/null || true)"
  commenters="$(gh api "repos/$repo/issues/$number/comments" --paginate \
      --jq ".[] | select((.body | ascii_downcase) | contains(\"$(printf '%s' "$phrase" | tr '[:upper:]' '[:lower:]')\")) | .user.login" 2>/dev/null || true)"
  if printf ',%s,' "$labels" | grep -qF -- ",$label,"; then
    last="$(printf '%s\n' "$labeled_by" | grep -v '^$' | tail -n1 || true)"
    if [ -n "$last" ] && printf '%s\n' "$maintainers" | has_line "$last"; then
      printf 'run\tlabel %s applied by maintainer %s\n' "$label" "$last"; return 0
    fi
    [ -n "$last" ] && ignored="label $label applied by $last"
  fi
  for a in $commenters; do
    if printf '%s\n' "$maintainers" | has_line "$a"; then
      printf 'run\t"%s" from maintainer %s\n' "$phrase" "$a"; return 0
    fi
    ignored="${ignored:+$ignored; }\"$phrase\" from $a"
  done
  printf 'nod\tneeds a nod from a maintainer%s\n' "${ignored:+; ignored: $ignored}"
}

case "${1:-}" in
  decide) shift; [ $# -ge 5 ] || die "gate decide <profile> <repo> <number> <author> <head_repo> [labels]"; cmd_decide "$@" ;;
  *) echo "usage: gate.sh decide <profile> <repo> <number> <author> <head_repo> [labels-csv]" >&2; exit 2 ;;
esac
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash components/naust/tests/run.sh test tests/gate.bats`
Expected: 6 pass.

- [ ] **Step 6: Commit**

`.commits/naust-gate.md`:

```markdown
---
message: "feat: gate decide — maintainers, trusted logins and repos, nods by label or phrase"
add:
  - bin/naust
  - bin/gate.sh
  - tests/gate.bats
---

The nod is read as an act with an actor, not as a label's presence: the timeline says who applied it and the comments say who wrote the phrase, and only a login in maintainers counts. Anyone else's attempt is named in the reason so the notice on Discord says what was ignored.
```

Run: `ws commit naust .commits/naust-gate.md`

### Task 6: `poll.sh`, `queue.sh`, `run.sh` — candidates, debounce, the queue, manual runs

**Files:**
- Create: `components/naust/bin/poll.sh`, `components/naust/bin/queue.sh`, `components/naust/bin/run.sh`
- Create: `components/naust/tests/poll.bats`, `components/naust/tests/queue.bats`, `components/naust/tests/run.bats`

**Interfaces:**
- Consumes: `lib.sh`; `gate.sh decide`; profile keys `repo`, `poll.debounce_minutes`, `poll.skip_drafts`; trust key `nod_label`.
- Produces: `naust poll candidates <profile>` printing tab-separated `profile repo number sha base author head_repo labels` for every open PR whose head is new or moved, older than the debounce, not yet queued at that sha, and not a draft (unless it carries the nod label). Seen state in `state/seen/<owner>__<repo>/<number>` with keys `sha first_seen queued notified`; closed PRs are forgotten and their queue entry dropped. `naust poll mark <profile> <number> queued|notified <sha>`.
- Produces: `naust queue put <profile> <repo> <number> <head> <base> <author> <head_repo> [--priority N] [--with <csv>] [--bay <name>]` (a newer head replaces the entry; the same head is a no-op), `naust queue next` (prints the path of the best job: highest priority, then oldest; exit 1 when empty), `naust queue drop <path>`, `naust queue list`. Job file keys: `profile repo number head base author head_repo priority with bay enqueued`.
- Produces: `naust run <profile> <number> [--with <target>#<n>]... [--bay <name>]` — looks the PR up, gates it, queues it at priority 10; exit 1 with the gate's reason when a nod is needed.

- [ ] **Step 1: Write the failing tests**

Create `components/naust/tests/queue.bats`:

```bash
#!/usr/bin/env bats
load helpers/stub

setup() { naust_setup; }

put() { run_naust queue put terasology MovingBlocks/Terasology "$@"; }

@test "put writes a job file and the same head is a no-op" {
    put 7 abc123 develop stranger stranger/Terasology
    [ "$status" -eq 0 ]
    f="$NAUST_HOME/state/queue/MovingBlocks__Terasology__7.job"
    [ -f "$f" ]
    grep -q '^head=abc123$' "$f"
    grep -q '^priority=0$' "$f"
    grep -q "^enqueued=$NAUST_NOW$" "$f"
    put 7 abc123 develop stranger stranger/Terasology
    [[ "$output" == *"already queued"* ]]
}

@test "put with a newer head replaces the entry" {
    put 7 abc123 develop stranger stranger/Terasology
    put 7 def456 develop stranger stranger/Terasology
    [ "$status" -eq 0 ]
    f="$NAUST_HOME/state/queue/MovingBlocks__Terasology__7.job"
    grep -q '^head=def456$' "$f"
    [ "$(ls "$NAUST_HOME/state/queue" | wc -l)" -eq 1 ]
}

@test "next prefers priority, then the oldest; drop removes" {
    NAUST_NOW=100 run_naust queue put terasology MovingBlocks/Terasology 1 a develop x x/y
    NAUST_NOW=200 run_naust queue put terasology MovingBlocks/Terasology 2 b develop x x/y
    NAUST_NOW=300 run_naust queue put terasology MovingBlocks/Terasology 3 c develop x x/y --priority 10 --with "terasology/modules/Health#12" --bay bay-2
    run_naust queue next
    [ "$status" -eq 0 ]
    [[ "$output" == *"__3.job" ]]
    grep -q '^with=terasology/modules/Health#12$' "$output"
    grep -q '^bay=bay-2$' "$output"
    run_naust queue drop "$output"
    run_naust queue next
    [[ "$output" == *"__1.job" ]]
    run_naust queue drop "$output"
    run_naust queue next
    [[ "$output" == *"__2.job" ]]
    run_naust queue drop "$output"
    run_naust queue next
    [ "$status" -ne 0 ]
}
```

Create `components/naust/tests/poll.bats`:

```bash
#!/usr/bin/env bats
load helpers/stub

setup() {
    naust_setup
    export POLL_PRS=""
    make_stub gh 'case "$*" in *"pr list"*) printf "%s\n" "$POLL_PRS" ;; esac'
}

pr_line() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$1" "$2" develop "$3" "$3/Terasology" "${4:-false}" "${5:-}" 2026-10-08T00:00:00Z; }

@test "a new PR is remembered and waits out the debounce" {
    export POLL_PRS="$(pr_line 7 abc123 stranger)"
    run_naust poll candidates terasology
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    f="$NAUST_HOME/state/seen/MovingBlocks__Terasology/7"
    [ "$(sed -n 's/^sha=//p' "$f")" = "abc123" ]
    [ "$(sed -n 's/^first_seen=//p' "$f")" = "$NAUST_NOW" ]
    grep -q 'gh pr list --repo MovingBlocks/Terasology --state open --limit 100 --json' "$STUB_LOG"
}

@test "after the debounce it is a candidate once, until marked queued" {
    export POLL_PRS="$(pr_line 7 abc123 stranger)"
    run_naust poll candidates terasology
    NAUST_NOW=$((NAUST_NOW + 11*60)) run_naust poll candidates terasology
    [ "$status" -eq 0 ]
    [ "$output" = $'terasology\tMovingBlocks/Terasology\t7\tabc123\tdevelop\tstranger\tstranger/Terasology\t' ]
    run_naust poll mark terasology 7 queued abc123
    NAUST_NOW=$((NAUST_NOW + 11*60)) run_naust poll candidates terasology
    [ -z "$output" ]
}

@test "a moved head restarts the debounce and becomes a candidate again" {
    export POLL_PRS="$(pr_line 7 abc123 stranger)"
    run_naust poll candidates terasology
    run_naust poll mark terasology 7 queued abc123
    export POLL_PRS="$(pr_line 7 def456 stranger)"
    NAUST_NOW=$((NAUST_NOW + 60)) run_naust poll candidates terasology
    [ -z "$output" ]
    NAUST_NOW=$((NAUST_NOW + 12*60)) run_naust poll candidates terasology
    [[ "$output" == *$'\t'def456$'\t'* ]]
}

@test "drafts are skipped unless they carry the nod label" {
    export POLL_PRS="$(pr_line 7 abc123 stranger true)
$(pr_line 8 bbb222 stranger true 'ok-to-test,Category: Doc')"
    run_naust poll candidates terasology
    NAUST_NOW=$((NAUST_NOW + 11*60)) run_naust poll candidates terasology
    [[ "$output" != *$'\t7\t'* ]]
    [[ "$output" == *$'\t8\t'* ]]
}

@test "a closed PR is forgotten and its queued job dropped" {
    export POLL_PRS="$(pr_line 7 abc123 stranger)"
    run_naust poll candidates terasology
    run_naust queue put terasology MovingBlocks/Terasology 7 abc123 develop stranger stranger/Terasology
    export POLL_PRS=""
    run_naust poll candidates terasology
    [ "$status" -eq 0 ]
    [ ! -e "$NAUST_HOME/state/seen/MovingBlocks__Terasology/7" ]
    [ ! -e "$NAUST_HOME/state/queue/MovingBlocks__Terasology__7.job" ]
}
```

Create `components/naust/tests/run.bats`:

```bash
#!/usr/bin/env bats
load helpers/stub

setup() {
    naust_setup
    export GATE_EVENTS="" GATE_COMMENTS=""
    make_stub gh 'case "$*" in
      *"pr view"*) printf "%s\n" "$RUN_PR" ;;
      *events*) printf "%s\n" "$GATE_EVENTS" ;;
      *comments*) printf "%s\n" "$GATE_COMMENTS" ;;
    esac'
}

@test "run queues a maintainer PR at priority 10 with its extras" {
    export RUN_PR=$'abc123\tdevelop\tCervator\tCervator/Terasology\t'
    run_naust run terasology 7 --with terasology/modules/Health#12 --bay bay-2
    [ "$status" -eq 0 ]
    f="$NAUST_HOME/state/queue/MovingBlocks__Terasology__7.job"
    grep -q '^priority=10$' "$f"
    grep -q '^head=abc123$' "$f"
    grep -q '^with=terasology/modules/Health#12$' "$f"
    grep -q '^bay=bay-2$' "$f"
    grep -q 'gh pr view 7 --repo MovingBlocks/Terasology --json' "$STUB_LOG"
}

@test "run refuses a PR that needs a nod and says why" {
    export RUN_PR=$'abc123\tdevelop\tstranger\tstranger/Terasology\t'
    run_naust run terasology 7
    [ "$status" -ne 0 ]
    [[ "$output" == *"needs a nod from a maintainer"* ]]   # die echoes to stderr even when NAUST_LOG is set
    [ ! -e "$NAUST_HOME/state/queue/MovingBlocks__Terasology__7.job" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash components/naust/tests/run.sh test tests/queue.bats` then `tests/poll.bats` then `tests/run.bats`
Expected: all fail.

- [ ] **Step 3: Implement `bin/queue.sh`**

```bash
#!/usr/bin/env bash
# The job queue: one key=value file per pull request under state/queue/.
#
#   queue.sh put <profile> <repo> <number> <head> <base> <author> <head_repo> [--priority N] [--with <csv>] [--bay <name>]
#   queue.sh next        queue.sh drop <path>        queue.sh list
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/lib.sh
. "$HERE/lib.sh"
load_config

job_path() { printf '%s/queue/%s__%s.job\n' "$STATE_DIR" "${1//\//__}" "$2"; }

cmd_put() {
  local profile="$1" repo="$2" number="$3" head="$4" base="$5" author="$6" head_repo="$7"
  shift 7
  local priority=0 with="" bay="" f
  while [ $# -gt 0 ]; do
    case "$1" in
      --priority) priority="$2"; shift 2 ;;
      --with) with="$2"; shift 2 ;;
      --bay) bay="$2"; shift 2 ;;
      *) die "queue put: unknown argument '$1'" ;;
    esac
  done
  f="$(job_path "$repo" "$number")"
  if [ -f "$f" ] && [ "$(kv_get "$f" head)" = "$head" ]; then
    log "queue: $repo#$number at ${head:0:7} already queued"
    return 0
  fi
  [ -f "$f" ] && log "queue: $repo#$number moved to ${head:0:7}, replacing the queued head"
  printf 'profile=%s\nrepo=%s\nnumber=%s\nhead=%s\nbase=%s\nauthor=%s\nhead_repo=%s\npriority=%s\nwith=%s\nbay=%s\nenqueued=%s\n' \
    "$profile" "$repo" "$number" "$head" "$base" "$author" "$head_repo" "$priority" "$with" "$bay" "$(now)" > "$f"
  log "queue: $repo#$number at ${head:0:7} queued (priority $priority)"
}

cmd_next() {
  local f best
  best="$(for f in "$STATE_DIR"/queue/*.job; do
            [ -f "$f" ] || continue
            printf '%s\t%s\t%s\n' "$(kv_get "$f" priority)" "$(kv_get "$f" enqueued)" "$f"
          done | sort -t $'\t' -k1,1nr -k2,2n | head -n1 | cut -f3)"
  [ -n "$best" ] || return 1
  printf '%s\n' "$best"
}

cmd_drop() { rm -f "$1"; }

cmd_list() {
  local f
  for f in "$STATE_DIR"/queue/*.job; do
    [ -f "$f" ] || continue
    printf '%s#%s\t%s\tpriority %s\tenqueued %s\n' "$(kv_get "$f" repo)" "$(kv_get "$f" number)" "$(kv_get "$f" head)" "$(kv_get "$f" priority)" "$(kv_get "$f" enqueued)"
  done
}

case "${1:-}" in
  put)  shift; [ $# -ge 7 ] || die "queue put <profile> <repo> <number> <head> <base> <author> <head_repo> [...]"; cmd_put "$@" ;;
  next) cmd_next ;;
  drop) shift; cmd_drop "$1" ;;
  list) cmd_list ;;
  *) echo "usage: queue.sh {put|next|drop|list} ..." >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Implement `bin/poll.sh`**

```bash
#!/usr/bin/env bash
# Poll one profile's repository for open pull requests and emit the ones that
# deserve a job: new or moved heads, past the debounce, not yet queued at that
# head, not drafts unless nodded. Seen-state lives in state/seen/<repo>/<n>.
#
#   poll.sh candidates <profile>
#   poll.sh mark <profile> <number> queued|notified <sha>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/lib.sh
. "$HERE/lib.sh"
load_config
require_tool gh

PR_FIELDS='number,headRefOid,baseRefName,author,headRepositoryOwner,headRepository,isDraft,labels,updatedAt'
PR_SHAPE='.[] | [.number, .headRefOid, .baseRefName, .author.login, ((.headRepositoryOwner.login // "") + "/" + (.headRepository.name // "")), (.isDraft|tostring), ((.labels // []) | map(.name) | join(",")), .updatedAt] | @tsv'

seen_dir() { printf '%s/seen/%s\n' "$STATE_DIR" "${1//\//__}"; }

cmd_candidates() {
  local profile="$1" repo debounce skip_drafts label dir tmp open=" "
  local number sha base author head_repo draft labels updated f first_seen age
  repo="$(prof "$profile" .repo)"; [ -n "$repo" ] || die "profile $profile has no repo"
  debounce="$(prof "$profile" .poll.debounce_minutes 10)"
  skip_drafts="$(prof "$profile" .poll.skip_drafts true)"
  label="$(trust "$profile" .nod_label ok-to-test)"
  dir="$(seen_dir "$repo")"; mkdir -p "$dir"
  tmp="$(mktemp)"
  gh pr list --repo "$repo" --state open --limit 100 --json "$PR_FIELDS" --jq "$PR_SHAPE" > "$tmp"
  while IFS=$'\t' read -r number sha base author head_repo draft labels updated; do
    [ -n "$number" ] || continue
    open="$open$number "
    f="$dir/$number"
    if [ "$(kv_get "$f" sha)" != "$sha" ]; then
      kv_set "$f" sha "$sha"
      kv_set "$f" first_seen "$(now)"
      log "poll: $repo#$number at ${sha:0:7} (${author}) seen"
    fi
    if [ "$draft" = true ] && [ "$skip_drafts" = true ] && ! printf ',%s,' "$labels" | grep -qF -- ",$label,"; then
      continue
    fi
    [ "$(kv_get "$f" queued)" = "$sha" ] && continue
    first_seen="$(kv_get "$f" first_seen)"
    age=$(( $(now) - first_seen ))
    if [ "$age" -lt $(( debounce * 60 )) ]; then
      log "poll: $repo#$number debouncing (${age}s of $((debounce * 60))s)"
      continue
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$profile" "$repo" "$number" "$sha" "$base" "$author" "$head_repo" "$labels"
  done < "$tmp"
  rm -f "$tmp"
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    number="$(basename "$f")"
    case "$open" in
      *" $number "*) ;;
      *) log "poll: $repo#$number is no longer open; forgetting it"
         rm -f "$f" "$STATE_DIR/queue/${repo//\//__}__$number.job" ;;
    esac
  done
}

cmd_mark() {
  local profile="$1" number="$2" key="$3" sha="$4" repo
  repo="$(prof "$profile" .repo)"
  case "$key" in queued|notified) ;; *) die "poll mark: key must be queued or notified" ;; esac
  kv_set "$(seen_dir "$repo")/$number" "$key" "$sha"
}

case "${1:-}" in
  candidates) shift; cmd_candidates "$1" ;;
  mark) shift; [ $# -eq 4 ] || die "poll mark <profile> <number> queued|notified <sha>"; cmd_mark "$@" ;;
  *) echo "usage: poll.sh {candidates <profile>|mark <profile> <number> queued|notified <sha>}" >&2; exit 2 ;;
esac
```

- [ ] **Step 5: Implement `bin/run.sh`**

```bash
#!/usr/bin/env bash
# Queue a pull request by hand, ahead of polled ones. The trust gate still
# applies; the debounce does not.
#
#   run.sh <profile> <number> [--with <target>#<n>]... [--bay <name>]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/lib.sh
. "$HERE/lib.sh"
load_config
require_tool gh

profile="${1:-}"; number="${2:-}"
[ -n "$profile" ] && [ -n "$number" ] || die "usage: naust run <profile> <number> [--with <target>#<n>]... [--bay <name>]"
shift 2
with="" bay=""
while [ $# -gt 0 ]; do
  case "$1" in
    --with) with="${with:+$with,}$2"; shift 2 ;;
    --bay) bay="$2"; shift 2 ;;
    *) die "naust run: unknown argument '$1'" ;;
  esac
done
repo="$(prof "$profile" .repo)"; [ -n "$repo" ] || die "profile $profile has no repo"
IFS=$'\t' read -r head base author head_repo labels < <(gh pr view "$number" --repo "$repo" \
  --json headRefOid,baseRefName,author,headRepositoryOwner,headRepository,labels \
  --jq '[.headRefOid, .baseRefName, .author.login, ((.headRepositoryOwner.login // "") + "/" + (.headRepository.name // "")), ((.labels // []) | map(.name) | join(","))] | @tsv')
[ -n "$head" ] || die "naust run: could not read $repo#$number"
IFS=$'\t' read -r decision reason < <(bash "$HERE/gate.sh" decide "$profile" "$repo" "$number" "$author" "$head_repo" "$labels")
if [ "$decision" != run ]; then
  die "naust run: $repo#$number $reason"
fi
log "run: $repo#$number ($reason)"
bash "$HERE/queue.sh" put "$profile" "$repo" "$number" "$head" "$base" "$author" "$head_repo" --priority 10 ${with:+--with "$with"} ${bay:+--bay "$bay"}
bash "$HERE/poll.sh" mark "$profile" "$number" queued "$head"
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash components/naust/tests/run.sh test` (whole suite so far)
Expected: lib 8, notify 5, bay 9, gate 6, queue 3, poll 5, run 2 — all pass.

- [ ] **Step 7: Commit**

`.commits/naust-poll-queue.md`:

```markdown
---
message: "feat: poll candidates with debounce and seen-state, a file queue, naust run"
add:
  - bin/poll.sh
  - bin/queue.sh
  - bin/run.sh
  - tests/poll.bats
  - tests/queue.bats
  - tests/run.bats
---

Seen-state is one small file per PR so a moved head resets its own debounce without touching the others, and a PR that closes takes its queue entry with it. The queue is files too: a tick that dies leaves the job where the next tick finds it.
```

Run: `ws commit naust .commits/naust-poll-queue.md`

### Task 7: `tick.sh` — the scheduled entry point

**Files:**
- Create: `components/naust/bin/tick.sh`, `components/naust/tests/tick.bats`

**Interfaces:**
- Consumes: `lib.sh` (`with_lock`, `cfg_list`), `poll.sh candidates|mark`, `gate.sh decide`, `queue.sh put|next`, `bay.sh free-for|claim`, `notify.sh say`, and the job runner `bin/job.sh <bay> <jobfile>` (overridable by `NAUST_JOB_SCRIPT` for tests).
- Produces: `naust tick`. Exit 0 always except on a configuration error. One tick: take the lock or exit; for each profile, poll, gate each candidate, queue the runnable ones (marking them queued) and post one Discord notice per nod-needed head (marking it notified); take the best queued job, find a free bay (the job's pinned bay, else `free-for`), claim it, move the job file to `state/jobs/<jobid>.job`, run the job script, exit. Job id is `<owner>__<repo>-<number>-<7-char sha>`.

- [ ] **Step 1: Write the failing tests**

Create `components/naust/tests/tick.bats`:

```bash
#!/usr/bin/env bats
load helpers/stub

setup() {
    naust_setup
    export POLL_PRS="" GATE_EVENTS="" GATE_COMMENTS=""
    make_stub gh 'case "$*" in
      *"pr list"*) printf "%s\n" "$POLL_PRS" ;;
      *events*) printf "%s\n" "$GATE_EVENTS" ;;
      *comments*) printf "%s\n" "$GATE_COMMENTS" ;;
    esac'
    make_stub curl
    printf 'NAUST_DISCORD_WEBHOOK=https://discord.invalid/hook\n' > "$NAUST_ENV_FILE"
    export NAUST_JOB_SCRIPT="$BATS_TEST_TMPDIR/job-stub.sh"
    printf '#!/usr/bin/env bash\necho "job $*" >> "$STUB_LOG"\n' > "$NAUST_JOB_SCRIPT"
}

pr_line() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$1" "$2" develop "$3" "$3/Terasology" false "" 2026-10-08T00:00:00Z; }
aged() { printf 'sha=%s\nfirst_seen=%s\n' "$2" $((NAUST_NOW - 3600)) > "$NAUST_HOME/state/seen/MovingBlocks__Terasology/$1"; }

@test "a maintainer's PR is queued and marked; a stranger's gets one notice" {
    mkdir -p "$NAUST_HOME/state/seen/MovingBlocks__Terasology"
    aged 7 abc123; aged 8 bbb222
    export POLL_PRS="$(pr_line 7 abc123 Cervator)
$(pr_line 8 bbb222 stranger)"
    run_naust tick
    [ "$status" -eq 0 ]
    [ -f "$NAUST_HOME/state/queue/MovingBlocks__Terasology__7.job" ] || [ -f "$NAUST_HOME/state/jobs/MovingBlocks__Terasology-7-abc123.job" ]
    [ ! -e "$NAUST_HOME/state/queue/MovingBlocks__Terasology__8.job" ]
    [ "$(sed -n 's/^queued=//p' "$NAUST_HOME/state/seen/MovingBlocks__Terasology/7")" = "abc123" ]
    [ "$(sed -n 's/^notified=//p' "$NAUST_HOME/state/seen/MovingBlocks__Terasology/8")" = "bbb222" ]
    [ "$(grep -c '^curl ' "$STUB_LOG")" -eq 1 ]
    grep -q 'needs a nod' "$STUB_LOG"
    grep -q 'https://github.com/MovingBlocks/Terasology/pull/8' "$STUB_LOG"
    run_naust tick
    [ "$(grep -c '^curl ' "$STUB_LOG")" -eq 1 ]
}

@test "a queued job runs in a free bay and leaves the queue" {
    make_bay bay-1 free
    run_naust queue put terasology MovingBlocks/Terasology 7 abc1234 develop Cervator Cervator/Terasology
    run_naust tick
    [ "$status" -eq 0 ]
    grep -q "^job bay-1 $NAUST_HOME/state/jobs/MovingBlocks__Terasology-7-abc1234.job" "$STUB_LOG"
    [ ! -e "$NAUST_HOME/state/queue/MovingBlocks__Terasology__7.job" ]
    [ "$(sed -n 's/^job=//p' "$BAY_DIR/bay.state")" = "MovingBlocks__Terasology-7-abc1234" ]
}

@test "no free bay: the job stays queued" {
    make_bay bay-1 busy
    run_naust queue put terasology MovingBlocks/Terasology 7 abc1234 develop Cervator Cervator/Terasology
    run_naust tick
    [ "$status" -eq 0 ]
    grep -q "no free bay" "$NAUST_LOG"
    [ -f "$NAUST_HOME/state/queue/MovingBlocks__Terasology__7.job" ]
    ! grep -q '^job ' "$STUB_LOG"
}

@test "a pinned bay that is not free keeps the job queued" {
    make_bay bay-1 free
    make_bay bay-2 held
    run_naust queue put terasology MovingBlocks/Terasology 7 abc1234 develop Cervator Cervator/Terasology --bay bay-2
    run_naust tick
    [ "$status" -eq 0 ]
    [ -f "$NAUST_HOME/state/queue/MovingBlocks__Terasology__7.job" ]
    ! grep -q '^job ' "$STUB_LOG"
}

@test "a tick that finds the lock held does nothing" {
    mkdir -p "$NAUST_HOME/state/lock"
    printf '1\n' > "$NAUST_HOME/state/lock/pid"
    run_naust tick
    [ "$status" -eq 0 ]
    grep -q "another tick" "$NAUST_LOG"
    ! grep -q '^gh ' "$STUB_LOG"
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash components/naust/tests/run.sh test tests/tick.bats`
Expected: all fail.

- [ ] **Step 3: Implement `bin/tick.sh`**

```bash
#!/usr/bin/env bash
# One tick: poll, gate, queue, notify, run at most one job, exit. The OS
# scheduler calls this every few minutes; the lock makes overlapping ticks
# harmless and a crashed tick's lock is reclaimed after LOCK_STALE_HOURS.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/lib.sh
. "$HERE/lib.sh"
load_config
JOB_SCRIPT="${NAUST_JOB_SCRIPT:-$HERE/job.sh}"

if ! with_lock; then
  log "tick: another tick holds $STATE_DIR/lock; nothing to do"
  exit 0
fi

while IFS= read -r profile; do
  [ -n "$profile" ] || continue
  while IFS=$'\t' read -r p repo number sha base author head_repo labels; do
    [ -n "$number" ] || continue
    IFS=$'\t' read -r decision reason < <(bash "$HERE/gate.sh" decide "$p" "$repo" "$number" "$author" "$head_repo" "$labels")
    if [ "$decision" = run ]; then
      bash "$HERE/queue.sh" put "$p" "$repo" "$number" "$sha" "$base" "$author" "$head_repo"
      bash "$HERE/poll.sh" mark "$p" "$number" queued "$sha"
      log "tick: $repo#$number queued ($reason)"
    else
      seen="$STATE_DIR/seen/${repo//\//__}/$number"
      if [ "$(kv_get "$seen" notified)" != "$sha" ]; then
        bash "$HERE/notify.sh" say "PR #$number on $repo by @$author needs a nod before a bay runs it: https://github.com/$repo/pull/$number ($reason)" || true
        bash "$HERE/poll.sh" mark "$p" "$number" notified "$sha"
      fi
      log "tick: $repo#$number waiting ($reason)"
    fi
  done < <(bash "$HERE/poll.sh" candidates "$profile")
done < <(cfg_list .profiles)

job="$(bash "$HERE/queue.sh" next)" || { log "tick: queue empty"; exit 0; }
profile="$(kv_get "$job" profile)"
repo="$(kv_get "$job" repo)"; number="$(kv_get "$job" number)"; head="$(kv_get "$job" head)"
jobid="${repo//\//__}-$number-${head:0:7}"
bay="$(kv_get "$job" bay)"
if [ -z "$bay" ]; then
  bay="$(bash "$HERE/bay.sh" free-for "$profile")" || { log "tick: no free bay for $profile; $repo#$number stays queued"; exit 0; }
fi
if ! bash "$HERE/bay.sh" claim "$bay" "$jobid"; then
  log "tick: bay $bay is not free; $repo#$number stays queued"
  exit 0
fi
run="$STATE_DIR/jobs/$jobid.job"
mv "$job" "$run"
log "tick: running $jobid in $bay"
if bash "$JOB_SCRIPT" "$bay" "$run"; then
  log "tick: $jobid finished"
else
  log "tick: $jobid finished with failures (see the report)"
fi
exit 0
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash components/naust/tests/run.sh test tests/tick.bats`
Expected: 5 pass.

- [ ] **Step 5: Commit**

`.commits/naust-tick.md`:

```markdown
---
message: "feat: tick — poll, gate, queue, one notice per nod-needed head, run one job"
add:
  - bin/tick.sh
  - tests/tick.bats
---

A tick is the whole control loop and it exits: the scheduler is the daemon. One job per tick keeps the GPU and the display to one boot at a time, and a nod notice goes out once per head so a PR waiting a week does not page anyone every five minutes.
```

Run: `ws commit naust .commits/naust-tick.md`

### Task 8: `job.sh` — the nine steps

**Files:**
- Create: `components/naust/bin/job.sh`, `components/naust/tests/job.bats`
- Modify: `components/naust/bin/bay.sh` (add `env <name>`)

**Interfaces:**
- Consumes: `bay.sh env|reset|set|repos`, the bay's `scripts/ws` (`checkout --pr`, `build`, `test`, `review checks`, `review comment`), `report.sh render <jobdir>` (Task 9; overridable by `NAUST_REPORT_SCRIPT`), `notify.sh say`; profile keys `component`, `upstream_remote`, `default_branch`, `steps.compile_all`, `steps.headless`, `steps.smoke`, `known_dirt`, `report.comment`.
- Produces: `naust job <bay> <jobfile>`; exit 0 when every step that ran passed, 1 otherwise. The job directory `<bay>/yggdrasil/.outputs/naust/<jobid>/` holds `job.yaml` (`repo number head_polled head base merge_base author head_repo with bay started`), `steps.tsv` (`id<TAB>name<TAB>status<TAB>seconds`, status `pass|fail|skipped`), `diff.txt`, `scope.txt` (lines `class <Name> [integrationTest]` and/or `default`), `baseline/` and `reports/` (flattened JUnit XML plus `runs.tsv`: `command<TAB>exit`), `build.log`, `compile-all.log`, `headless.log`, `smoke.log`, `screenshot.png` (from the profile's scripts), `tree.txt`, `checks.txt`, `report.md`, `comment.md`. A copy lands in `state/jobs/<jobid>/`. The bay ends `ready` (or stays `broken` after a failed reset).
- Step ids: `1 reset`, `2 checkout`, `3 scope`, `4 baseline`, `5 build`, `5b compile-all`, `5c tests`, `6 headless`, `7 smoke`, `8 tree`, `9 report`. A failed `2` skips `3`–`8`; a failed `5` skips `5b`, `5c`, `6`, `7`.
- Environment for profile scripts (from `bay.sh env`) plus `NAUST_JOB_DIR`, `NAUST_PR_NUMBER`, `NAUST_PR_HEAD`, and `GH_TOKEN` from `.env`'s `GDD_GITHUB_TOKEN` when set.

- [ ] **Step 1: Add `bay.sh env`**

In `bin/bay.sh`, add after `cmd_repos`:

```bash
# Print the environment a job or a profile script needs, as export lines, so
# job.sh can eval them instead of recomputing paths.
cmd_env() {
  bay_require "$1"; bay_env "$1"
  local v
  for v in NAUST_BAY_DIR NAUST_BAY_NAME NAUST_PROFILE NAUST_WS_DIR NAUST_COMP_DIR NAUST_REALM_DIR GRADLE_USER_HOME; do
    printf 'export %s=%q\n' "$v" "${!v}"
  done
}
```

and to the dispatch: `env)      shift; cmd_env "$1" ;;`.

- [ ] **Step 2: Write the failing tests**

Create `components/naust/tests/job.bats`:

```bash
#!/usr/bin/env bats
load helpers/stub

# The ws inside the bay is a stub that does real git for checkout --pr (the
# verb Task 1 built) and fakes everything else, writing one JUnit file per
# test run so the collector has something to gather.
bay_ws_stub() {
cat > "$BAY_DIR/yggdrasil/scripts/ws" <<'EOF'
#!/usr/bin/env bash
echo "ws $*" >> "$STUB_LOG"
comp="$(cd "$(dirname "$0")/../components/terasology" && pwd)"
case "$1 $2" in
  "checkout terasology")
    [ "$3" = --pr ] || exit 1
    git -C "$comp" fetch -q MovingBlocks "refs/pull/$4/head" && git -C "$comp" switch -q -C "pr/$4" FETCH_HEAD ;;
  "checkout terasology/modules/Cooking") ;;
  "build terasology") exit "${WS_BUILD_EXIT:-0}" ;;
  "test terasology")
    mkdir -p "$comp/engine-tests/build/test-results/unitTest"
    printf '<testsuite name="%s" tests="1" failures="0" errors="0" skipped="0"><testcase name="t" classname="%s"/></testsuite>\n' "${3:-all}" "${3:-all}" \
      > "$comp/engine-tests/build/test-results/unitTest/TEST-${3:-all}.xml" ;;
  "review terasology") case "$3" in checks) echo "Checks: 1 pass, 0 fail, 0 pending" ;; comment) ;; esac ;;
esac
EOF
chmod +x "$BAY_DIR/yggdrasil/scripts/ws"
}

# A PR on the bay's MovingBlocks remote: one engine change, one plain test,
# one MTE-tagged test.
publish_bay_pr() {
    local comp="$BAY_DIR/yggdrasil/components/terasology"
    git -C "$comp" switch -q -c pr-work
    mkdir -p "$comp/engine/src/main/java/org/x" "$comp/engine-tests/src/test/java/org/x"
    printf 'class A {}\n' > "$comp/engine/src/main/java/org/x/A.java"
    printf 'class ATest {}\n' > "$comp/engine-tests/src/test/java/org/x/ATest.java"
    printf '@Tag("MteTest")\nclass BMteTest {}\n' > "$comp/engine-tests/src/test/java/org/x/BMteTest.java"
    git -C "$comp" add -A
    git -C "$comp" commit -qm "pr"
    PR_SHA="$(git -C "$comp" rev-parse HEAD)"
    git -C "$comp" push -q MovingBlocks "HEAD:refs/pull/7/head"
    git -C "$comp" switch -q develop
    git -C "$comp" branch -q -D pr-work
}

setup() {
    naust_setup
    make_stub compile-all-stub
    make_stub after-reset-stub
    make_stub headless-stub 'printf "Server started\n" > "$NAUST_JOB_DIR/headless.log"'
    make_stub smoke-stub 'touch "$NAUST_JOB_DIR/screenshot.png"'
    make_stub curl
    printf 'NAUST_DISCORD_WEBHOOK=https://discord.invalid/hook\nGDD_GITHUB_TOKEN=tok\n' > "$NAUST_ENV_FILE"
    export NAUST_REPORT_SCRIPT="$BATS_TEST_TMPDIR/report-stub.sh"
    printf '#!/usr/bin/env bash\necho "report $*" >> "$STUB_LOG"\nprintf "# report\\n" > "$2/report.md"\nprintf "comment\\n" > "$2/comment.md"\n' > "$NAUST_REPORT_SCRIPT"
    make_bay bay-1 busy
    bay_ws_stub
    publish_bay_pr
    JOBFILE="$NAUST_HOME/state/jobs/MovingBlocks__Terasology-7-${PR_SHA:0:7}.job"
    printf 'profile=terasology\nrepo=MovingBlocks/Terasology\nnumber=7\nhead=%s\nbase=develop\nauthor=Cervator\nhead_repo=Cervator/Terasology\npriority=0\nwith=\nbay=\nenqueued=1\n' "$PR_SHA" > "$JOBFILE"
    JOB="$BAY_DIR/yggdrasil/.outputs/naust/MovingBlocks__Terasology-7-${PR_SHA:0:7}"
}

step_status() { awk -F'\t' -v id="$1" '$1 == id { print $3 }' "$JOB/steps.tsv"; }

@test "the happy path runs every step in order and leaves the bay ready" {
    run_naust job bay-1 "$JOBFILE"
    [ "$status" -eq 0 ]
    for id in 1 2 3 4 5 5b 5c 6 7 8 9; do [ "$(step_status $id)" = pass ]; done
    comp="$BAY_DIR/yggdrasil/components/terasology"
    [ "$(sed -n 's/^head: //p' "$JOB/job.yaml")" = "$PR_SHA" ]
    [ "$(sed -n 's/^merge_base: //p' "$JOB/job.yaml")" = "$(git -C "$comp" rev-parse MovingBlocks/develop)" ]
    [ "$(git -C "$comp" rev-parse --abbrev-ref HEAD)" = "pr/7" ]
    grep -q '^class ATest $' "$JOB/scope.txt"
    grep -q '^class BMteTest integrationTest$' "$JOB/scope.txt"
    grep -q '^default$' "$JOB/scope.txt"
    ls "$JOB/baseline"/*.xml >/dev/null
    ls "$JOB/reports"/*.xml >/dev/null
    grep -q 'ws test terasology BMteTest --task integrationTest' "$STUB_LOG"
    [ "$(grep -c '^ws test terasology' "$STUB_LOG")" -eq 6 ]
    grep -q '^ws build terasology' "$STUB_LOG"
    grep -q '^compile-all-stub' "$STUB_LOG"
    grep -q '^headless-stub' "$STUB_LOG"
    grep -q '^smoke-stub' "$STUB_LOG"
    grep -q '^ws review terasology checks 7' "$STUB_LOG"
    grep -q "^ws review terasology comment 7 .outputs/naust/MovingBlocks__Terasology-7-${PR_SHA:0:7}/comment.md" "$STUB_LOG"
    grep -q "^report render $JOB" "$STUB_LOG"
    grep -q "file=@$JOB/screenshot.png" "$STUB_LOG"
    [ -f "$NAUST_HOME/state/jobs/MovingBlocks__Terasology-7-${PR_SHA:0:7}/report.md" ]
    [ "$(sed -n 's/^state=//p' "$BAY_DIR/bay.state")" = "ready" ]
    # build/test steps saw the bay environment
    grep -q "Checks: 1 pass" "$JOB/checks.txt"
}

@test "a failed build skips compile-all, tests and both boots but still reports" {
    export WS_BUILD_EXIT=1
    run_naust job bay-1 "$JOBFILE"
    [ "$status" -ne 0 ]
    [ "$(step_status 5)" = fail ]
    for id in 5b 5c 6 7; do [ "$(step_status $id)" = skipped ]; done
    [ "$(step_status 8)" = pass ]
    [ "$(step_status 9)" = pass ]
    grep -q '^ws review terasology comment 7' "$STUB_LOG"
    [ "$(sed -n 's/^state=//p' "$BAY_DIR/bay.state")" = "ready" ]
}

@test "a failed reset skips everything but the report and leaves the bay broken" {
    git -C "$BAY_DIR/yggdrasil/components/terasology/modules/Cooking" remote set-url origin "$BATS_TEST_TMPDIR/nope.git"
    run_naust job bay-1 "$JOBFILE"
    [ "$status" -ne 0 ]
    [ "$(step_status 1)" = fail ]
    for id in 2 3 4 5 5b 5c 6 7 8; do [ "$(step_status $id)" = skipped ]; done
    [ "$(step_status 9)" = pass ]
    [ "$(sed -n 's/^state=//p' "$BAY_DIR/bay.state")" = "broken" ]
}

@test "report.comment off posts nothing on the PR" {
    yq -i '.report.comment = "off"' "$BATS_TEST_TMPDIR/ws/realms/realm-test/naust/terasology.yaml"
    run_naust job bay-1 "$JOBFILE"
    ! grep -q '^ws review terasology comment' "$STUB_LOG"
}

@test "with targets are checked out too and recorded" {
    printf 'with=terasology/modules/Cooking#3\n' >> "$JOBFILE"
    run_naust job bay-1 "$JOBFILE"
    grep -q '^ws checkout terasology/modules/Cooking --pr 3' "$STUB_LOG"
    grep -q '^with: terasology/modules/Cooking#3$' "$JOB/job.yaml"
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash components/naust/tests/run.sh test tests/job.bats`
Expected: all fail (`job.sh` missing).

- [ ] **Step 4: Implement `bin/job.sh`**

```bash
#!/usr/bin/env bash
# Run one pull request through one bay: the mechanical half of the
# terasology-review skill's six checks, in its order, through the bay's own ws.
# Every step records pass/fail/skipped in steps.tsv; the report says which.
#
#   job.sh <bay> <jobfile>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/lib.sh
. "$HERE/lib.sh"
load_config
REPORT_SCRIPT="${NAUST_REPORT_SCRIPT:-$HERE/report.sh}"

BAY="$1"; JOBFILE="$2"
eval "$(bash "$HERE/bay.sh" env "$BAY")"
WS="$NAUST_WS_DIR/scripts/ws"
COMP="$(prof "$NAUST_PROFILE" .component)"
UP="$(prof "$NAUST_PROFILE" .upstream_remote origin)"

repo="$(kv_get "$JOBFILE" repo)"; number="$(kv_get "$JOBFILE" number)"
head_polled="$(kv_get "$JOBFILE" head)"; base="$(kv_get "$JOBFILE" base)"
author="$(kv_get "$JOBFILE" author)"; head_repo="$(kv_get "$JOBFILE" head_repo)"
with="$(kv_get "$JOBFILE" with)"
JOBID="$(basename "$JOBFILE" .job)"
JOB="$NAUST_WS_DIR/.outputs/naust/$JOBID"
STEPS="$JOB/steps.tsv"

token="$(env_value GDD_GITHUB_TOKEN)"
[ -n "$token" ] && export GH_TOKEN="$token"
export NAUST_JOB_DIR="$JOB" NAUST_PR_NUMBER="$number" NAUST_PR_HEAD="$head_polled"

FAILED=0
record() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$STEPS"; }
skip() { record "$1" "$2" skipped 0; }
# run_step <id> <name> <function>: the function's output goes to <name>.log.
run_step() {
  local id="$1" name="$2" fn="$3" t0 status=pass
  t0="$(now)"
  log "step $id $name"
  if "$fn" >> "$JOB/$name.log" 2>&1; then :; else status=fail; FAILED=1; fi
  record "$id" "$name" "$status" "$(( $(now) - t0 ))"
  [ "$status" = pass ]
}
in_ws() { (cd "$NAUST_WS_DIR" && "$@"); }
in_comp() { (cd "$NAUST_COMP_DIR" && "$@"); }
profile_cmd() { # <profile key>: run the command in the component dir; empty is a pass
  local c; c="$(prof "$NAUST_PROFILE" "$1")"
  [ -n "$c" ] || { echo "(no $1 in profile)"; return 0; }
  (cd "$NAUST_COMP_DIR" && bash -c "$c")
}

step_reset() { bash "$HERE/bay.sh" reset "$BAY" && bash "$HERE/bay.sh" set "$BAY" busy; }

step_checkout() {
  local w target n
  in_ws bash "$WS" checkout "$COMP" --pr "$number" --remote "$UP"
  for w in ${with//,/ }; do
    target="${w%#*}"; n="${w##*#}"
    in_ws bash "$WS" checkout "$target" --pr "$n"
  done
  git -C "$NAUST_COMP_DIR" fetch -q "$UP" "$base"
  HEAD_SHA="$(git -C "$NAUST_COMP_DIR" rev-parse HEAD)"
  MERGE_BASE="$(git -C "$NAUST_COMP_DIR" merge-base HEAD "$UP/$base")"
  {
    printf 'repo: %s\nnumber: %s\nhead_polled: %s\nhead: %s\nbase: %s\nmerge_base: %s\n' "$repo" "$number" "$head_polled" "$HEAD_SHA" "$base" "$MERGE_BASE"
    printf 'author: %s\nhead_repo: %s\nwith: %s\nbay: %s\nstarted: %s\n' "$author" "$head_repo" "$with" "$BAY" "$(now)"
  } > "$JOB/job.yaml"
  export NAUST_PR_HEAD="$HEAD_SHA"
  [ "$HEAD_SHA" = "$head_polled" ] || echo "note: fetched $HEAD_SHA, polled $head_polled (the PR moved)"
}

add_class() { # <path relative to the component>
  local name task=""
  name="$(basename "$1" .java)"
  if grep -qE '@Tag\("(MteTest|TteTest)"\)' "$NAUST_COMP_DIR/$1" 2>/dev/null; then task=integrationTest; fi
  printf 'class %s %s\n' "$name" "$task" >> "$JOB/scope.txt"
}
step_scope() {
  local f mod t default=no
  git -C "$NAUST_COMP_DIR" diff --name-only "$MERGE_BASE" HEAD > "$JOB/diff.txt"
  git -C "$NAUST_COMP_DIR" diff --stat "$MERGE_BASE" HEAD > "$JOB/diff-stat.txt"
  : > "$JOB/scope.txt"
  while IFS= read -r f; do
    case "$f" in
      */src/test/java/*Test.java) add_class "$f" ;;
      engine/src/main/*|engine-tests/src/main/*|build-logic/*|*.gradle.kts|gradle/*|facades/*) default=yes ;;
      modules/*/src/main/*)
        mod="${f#modules/}"; mod="${mod%%/*}"
        while IFS= read -r -d '' t; do add_class "${t#"$NAUST_COMP_DIR"/}"; done \
          < <(find "$NAUST_COMP_DIR/modules/$mod/src/test/java" -name '*Test.java' -print0 2>/dev/null) ;;
    esac
  done < "$JOB/diff.txt"
  [ "$default" = yes ] && echo default >> "$JOB/scope.txt"
  sort -u "$JOB/scope.txt" -o "$JOB/scope.txt"
  [ -s "$JOB/scope.txt" ] || echo default > "$JOB/scope.txt"
  cat "$JOB/scope.txt"
}

# Run every line of scope.txt and gather the JUnit XML it produced into <dest>.
run_scope() { # <dest>
  local dest="$1" marker kind name task x rel
  mkdir -p "$dest"
  marker="$(mktemp)"
  : > "$dest/runs.tsv"
  while read -r kind name task; do
    case "$kind" in
      default)
        in_ws bash "$WS" test "$COMP" && rc=0 || rc=$?
        printf 'ws test %s\t%s\n' "$COMP" "$rc" >> "$dest/runs.tsv" ;;
      class)
        in_ws bash "$WS" test "$COMP" "$name" ${task:+--task "$task"} && rc=0 || rc=$?
        printf 'ws test %s %s%s\t%s\n' "$COMP" "$name" "${task:+ --task $task}" "$rc" >> "$dest/runs.tsv" ;;
    esac
  done < "$JOB/scope.txt"
  while IFS= read -r -d '' x; do
    rel="${x#"$NAUST_COMP_DIR"/}"
    cp "$x" "$dest/$(printf '%s' "$rel" | tr '/' '_')"
  done < <(find "$NAUST_COMP_DIR" -path '*/build/test-results/*' -name '*.xml' -newer "$marker" -print0)
  rm -f "$marker"
}

step_baseline() {
  git -C "$NAUST_COMP_DIR" switch -q --detach "$MERGE_BASE"
  run_scope "$JOB/baseline"
  git -C "$NAUST_COMP_DIR" switch -q "pr/$number"
}
step_build() { in_ws bash "$WS" build "$COMP"; }
step_compile_all() { profile_cmd .steps.compile_all; }
step_tests() { run_scope "$JOB/reports"; }
step_headless() { profile_cmd .steps.headless; }
step_smoke() { profile_cmd .steps.smoke; }

step_tree() {
  local r line known unknown=0
  : > "$JOB/tree.txt"
  while IFS= read -r r; do
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      known=no
      while IFS= read -r pat; do
        [ -n "$pat" ] || continue
        case "$line" in *"$pat"*) known=yes ;; esac
      done < <(prof_list "$NAUST_PROFILE" .known_dirt)
      if [ "$known" = yes ]; then
        printf '%s\t%s\tknown\n' "${r#"$NAUST_WS_DIR"/components/}" "$line" >> "$JOB/tree.txt"
      else
        printf '%s\t%s\tunexpected\n' "${r#"$NAUST_WS_DIR"/components/}" "$line" >> "$JOB/tree.txt"
        unknown=1
      fi
    done < <(git -C "$r" status --porcelain)
  done < <(bash "$HERE/bay.sh" repos "$BAY")
  cat "$JOB/tree.txt"
  [ "$unknown" -eq 0 ]
}

step_report() {
  in_ws bash "$WS" review "$COMP" checks "$number" > "$JOB/checks.txt" 2>&1 || true
  bash "$REPORT_SCRIPT" render "$JOB"
  if [ "$(prof "$NAUST_PROFILE" .report.comment on)" = on ]; then
    in_ws bash "$WS" review "$COMP" comment "$number" ".outputs/naust/$JOBID/comment.md"
  fi
  if [ -f "$JOB/screenshot.png" ]; then
    bash "$HERE/notify.sh" say "$(head -c 1500 "$JOB/report.md")" --file "$JOB/screenshot.png" || true
  else
    bash "$HERE/notify.sh" say "$(head -c 1500 "$JOB/report.md")" || true
  fi
  rm -rf "$STATE_DIR/jobs/$JOBID"
  cp -r "$JOB" "$STATE_DIR/jobs/$JOBID"
}

mkdir -p "$JOB"
: > "$STEPS"
log "job $JOBID: $repo#$number by $author in $BAY"
if run_step 1 reset step_reset; then
  if run_step 2 checkout step_checkout; then
    run_step 3 scope step_scope || true
    run_step 4 baseline step_baseline || true
    if run_step 5 build step_build; then
      run_step 5b compile-all step_compile_all || true
      run_step 5c tests step_tests || true
      run_step 6 headless step_headless || true
      run_step 7 smoke step_smoke || true
    else
      skip 5b compile-all; skip 5c tests; skip 6 headless; skip 7 smoke
    fi
    run_step 8 tree step_tree || true
  else
    for s in "3 scope" "4 baseline" "5 build" "5b compile-all" "5c tests" "6 headless" "7 smoke" "8 tree"; do skip $s; done
  fi
else
  for s in "2 checkout" "3 scope" "4 baseline" "5 build" "5b compile-all" "5c tests" "6 headless" "7 smoke" "8 tree"; do skip $s; done
fi
run_step 9 report step_report || true
if [ "$(bash "$HERE/bay.sh" list | awk -F'\t' -v b="$BAY" '$1 == b { print $2 }')" != broken ]; then
  bash "$HERE/bay.sh" set "$BAY" ready
fi
log "job $JOBID: done, failed=$FAILED, outputs in $JOB"
exit "$FAILED"
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash components/naust/tests/run.sh test tests/job.bats`
Expected: 5 pass. Then the whole suite: `bash components/naust/tests/run.sh test` — everything green, and `bash components/naust/tests/run.sh lint` clean.

- [ ] **Step 6: Commit**

`.commits/naust-job.md`:

```markdown
---
message: "feat: job — the nine steps through the bay's own ws, with baseline and scope"
add:
  - bin/job.sh
  - bin/bay.sh
  - tests/job.bats
---

The scope is mechanical on purpose: changed test classes, every test class of a module whose main sources changed, and the adapter's default task when the engine itself changed. MTE-tagged classes route to integrationTest because unitTest excludes them. The same scope runs on the merge-base first, so a failure the PR inherited is never pinned on it. A failed build skips what depends on it and records the skip; nothing is reported as passed that did not run.
```

Run: `ws commit naust .commits/naust-job.md`

### Task 9: `report.sh` — the report and the PR comment

**Files:**
- Create: `components/naust/bin/report.sh`, `components/naust/tests/report.bats`, `components/naust/tests/fixtures/` (three JUnit XML files)

**Interfaces:**
- Consumes: a job directory as Task 8 leaves it (`job.yaml`, `steps.tsv`, `scope.txt`, `diff-stat.txt`, `baseline/*.xml`, `reports/*.xml`, `tree.txt`, `checks.txt`, `screenshot.png`, `headless.log`, `smoke.log`); profile key `persona`.
- Produces: `naust report render <jobdir>` writing `report.md` and `comment.md`. `report.md` has: a header line with PR, head, base and bay; a steps table; a tests table (PR vs baseline: tests, failures, errors, skipped) with the failing test names split into *new on this PR* and *also failing on the base*; the compile-all, headless and smoke outcomes (smoke names the screenshot); the clean-tree lines; the CI checks line; and a closing *What needs a human* list. `comment.md` is the same text without bay-local paths, signed by the persona, in the `oss-wide` register.
- Also produces the helper `naust report junit <dir>` printing `tests<TAB>failures<TAB>errors<TAB>skipped` on the first line and one `classname.name` per failing test case after it.

- [ ] **Step 1: Fixtures**

Create `components/naust/tests/fixtures/pass.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="org.x.ATest" tests="3" skipped="1" failures="0" errors="0" timestamp="2026-10-08T00:00:00" time="0.1">
  <testcase name="a" classname="org.x.ATest" time="0.01"/>
  <testcase name="b" classname="org.x.ATest" time="0.01"/>
  <testcase name="c" classname="org.x.ATest" time="0.01"><skipped/></testcase>
</testsuite>
```

Create `components/naust/tests/fixtures/fail-new.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="org.x.BTest" tests="2" skipped="0" failures="1" errors="0" timestamp="2026-10-08T00:00:00" time="0.1">
  <testcase name="ok" classname="org.x.BTest" time="0.01"/>
  <testcase name="broken" classname="org.x.BTest" time="0.01">
    <failure message="expected 1 but was 2" type="AssertionError">stack</failure>
  </testcase>
</testsuite>
```

Create `components/naust/tests/fixtures/fail-old.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="org.x.CTest" tests="1" skipped="0" failures="0" errors="1" timestamp="2026-10-08T00:00:00" time="0.1">
  <testcase name="flaky" classname="org.x.CTest" time="0.01">
    <error message="boom" type="RuntimeException">stack</error>
  </testcase>
</testsuite>
```

- [ ] **Step 2: Write the failing tests**

Create `components/naust/tests/report.bats`:

```bash
#!/usr/bin/env bats
load helpers/stub

setup() {
    naust_setup
    FIX="$BATS_TEST_DIRNAME/fixtures"
    JOB="$BATS_TEST_TMPDIR/job"
    mkdir -p "$JOB/baseline" "$JOB/reports"
    cat > "$JOB/job.yaml" <<'YAML'
repo: MovingBlocks/Terasology
number: 7
head_polled: abc1234abc
head: abc1234abc
base: develop
merge_base: 0000000aaa
author: Cervator
head_repo: Cervator/Terasology
with:
bay: bay-1
started: 1760000000
YAML
    printf '1\treset\tpass\t30\n2\tcheckout\tpass\t5\n3\tscope\tpass\t1\n4\tbaseline\tpass\t200\n5\tbuild\tpass\t300\n5b\tcompile-all\tpass\t400\n5c\ttests\tpass\t250\n6\theadless\tpass\t90\n7\tsmoke\tfail\t120\n8\ttree\tfail\t2\n9\treport\tpass\t1\n' > "$JOB/steps.tsv"
    printf 'class ATest \nclass BTest \ndefault\n' > "$JOB/scope.txt"
    printf ' engine/src/main/java/org/x/A.java | 2 +-\n 1 file changed\n' > "$JOB/diff-stat.txt"
    cp "$FIX/pass.xml" "$JOB/baseline/"; cp "$FIX/fail-old.xml" "$JOB/baseline/"
    cp "$FIX/pass.xml" "$JOB/reports/"; cp "$FIX/fail-old.xml" "$JOB/reports/"; cp "$FIX/fail-new.xml" "$JOB/reports/"
    printf 'terasology/modules/Health\t?? src/test/resources/logback-test.xml\tknown\nterasology\t?? natives/stray.dll\tunexpected\n' > "$JOB/tree.txt"
    printf 'Checks: 1 pass, 0 fail, 0 pending\n' > "$JOB/checks.txt"
    printf 'last line of smoke\n' > "$JOB/smoke.log"
    export NAUST_PROFILE=terasology
}

@test "junit sums a directory and lists failing cases" {
    run_naust report junit "$JOB/reports"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = $'6\t1\t1\t1' ]
    [ "${lines[1]}" = "org.x.BTest.broken" ]
    [ "${lines[2]}" = "org.x.CTest.flaky" ]
}

@test "render writes report.md with the verdicts a human needs first" {
    run_naust report render "$JOB"
    [ "$status" -eq 0 ]
    r="$JOB/report.md"
    grep -q '^# MovingBlocks/Terasology#7 — abc1234 onto develop, bay-1' "$r"
    grep -q '| 7 | smoke | fail |' "$r"
    grep -q '| PR | 6 | 1 | 1 | 1 |' "$r"
    grep -q '| base | 4 | 0 | 1 | 1 |' "$r"
    grep -q 'New on this PR' "$r"
    grep -q 'org.x.BTest.broken' "$r"
    grep -q 'Also failing on the base' "$r"
    grep -q 'org.x.CTest.flaky' "$r"
    grep -q 'natives/stray.dll' "$r"
    grep -q 'Checks: 1 pass, 0 fail, 0 pending' "$r"
    grep -q '## What needs a human' "$r"
    grep -q 'smoke boot failed' "$r"
    grep -q 'org.x.BTest.broken' "$r"
}

@test "comment.md is signed by the persona and names no bay path" {
    run_naust report render "$JOB"
    c="$JOB/comment.md"
    grep -q 'Gooey' "$c"
    ! grep -q "$BATS_TEST_TMPDIR" "$c"
    grep -q 'What needs a human' "$c"
}

@test "a skipped step reads as not run, never as passed" {
    printf '1\treset\tfail\t3\n2\tcheckout\tskipped\t0\n9\treport\tpass\t1\n' > "$JOB/steps.tsv"
    rm -f "$JOB/reports"/* "$JOB/baseline"/*
    run_naust report render "$JOB"
    grep -q '| 2 | checkout | not run |' "$JOB/report.md"
    grep -q 'reset failed' "$JOB/report.md"
    ! grep -q '| PR |' "$JOB/report.md"
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash components/naust/tests/run.sh test tests/report.bats`
Expected: all fail.

- [ ] **Step 4: Implement `bin/report.sh`**

```bash
#!/usr/bin/env bash
# Render a job directory into report.md (for the bay and Discord) and
# comment.md (for the PR). Verdicts come from the JUnit XML, never from exit
# codes, and a step that did not run says so.
#
#   report.sh render <jobdir>
#   report.sh junit <dir>        totals line, then one failing case per line
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/lib.sh
. "$HERE/lib.sh"
load_config

# Sum <testsuite> attributes and list failing <testcase>s across a directory.
cmd_junit() {
  local dir="$1" f
  local tests=0 failures=0 errors=0 skipped=0
  attr() { printf '%s' "$1" | sed -nE "s/.*[[:space:]]$2=\"([0-9]+)\".*/\1/p"; }
  for f in "$dir"/*.xml; do
    [ -f "$f" ] || continue
    suite="$(grep -o '<testsuite[^>]*>' "$f" | head -n1)"
    t="$(attr "$suite" tests)"; fl="$(attr "$suite" failures)"; e="$(attr "$suite" errors)"; sk="$(attr "$suite" skipped)"
    tests=$((tests + ${t:-0})); failures=$((failures + ${fl:-0})); errors=$((errors + ${e:-0})); skipped=$((skipped + ${sk:-0}))
  done
  printf '%s\t%s\t%s\t%s\n' "$tests" "$failures" "$errors" "$skipped"
  for f in "$dir"/*.xml; do
    [ -f "$f" ] || continue
    awk '
      /<testcase / { match($0, /name="[^"]*"/); n=substr($0, RSTART+6, RLENGTH-7);
                     match($0, /classname="[^"]*"/); c=substr($0, RSTART+11, RLENGTH-12); open=1; bad=0 }
      open && /<(failure|error)[ >]/ { bad=1 }
      open && (/\/>/ || /<\/testcase>/) { if (bad) print c "." n; open=0 }
    ' "$f"
  done | sort -u
}

yaml_get() { sed -n "s/^$2: //p" "$1" | head -n1; }

cmd_render() {
  local job="$1" persona repo number head base bay steps_rows="" id name status secs
  local pr_tot base_tot pr_fail base_fail new_fail old_fail human="" line
  persona="$(prof "${NAUST_PROFILE:-terasology}" .persona naust)"
  repo="$(yaml_get "$job/job.yaml" repo)"; number="$(yaml_get "$job/job.yaml" number)"
  head="$(yaml_get "$job/job.yaml" head)"; base="$(yaml_get "$job/job.yaml" base)"
  bay="$(yaml_get "$job/job.yaml" bay)"
  while IFS=$'\t' read -r id name status secs; do
    [ -n "$id" ] || continue
    case "$status" in skipped) status="not run" ;; esac
    steps_rows="$steps_rows| $id | $name | $status | ${secs}s |"$'\n'
    case "$status" in
      fail) human="$human- $name failed; see \`$name.log\`."$'\n' ;;
    esac
  done < "$job/steps.tsv"
  human="${human//- smoke failed; see \`smoke.log\`./- smoke boot failed: the game did not reach the renderer, or the screenshot is missing; read \`smoke.log\`.}"
  human="${human//- reset failed; see \`reset.log\`./- reset failed: the bay is marked broken and nothing ran; read \`reset.log\`.}"
  human="${human//- tree failed; see \`tree.log\`./- the working tree is not clean after the run; see the clean-tree section.}"

  local tests_section=""
  if ls "$job/reports"/*.xml >/dev/null 2>&1; then
    pr_tot="$(cmd_junit "$job/reports" | head -n1)"
    pr_fail="$(cmd_junit "$job/reports" | tail -n +2)"
    if ls "$job/baseline"/*.xml >/dev/null 2>&1; then
      base_tot="$(cmd_junit "$job/baseline" | head -n1)"
      base_fail="$(cmd_junit "$job/baseline" | tail -n +2)"
    else
      base_tot=$'-\t-\t-\t-'; base_fail=""
    fi
    new_fail="$(comm -23 <(printf '%s\n' "$pr_fail" | grep -v '^$' | sort) <(printf '%s\n' "$base_fail" | grep -v '^$' | sort) || true)"
    old_fail="$(comm -12 <(printf '%s\n' "$pr_fail" | grep -v '^$' | sort) <(printf '%s\n' "$base_fail" | grep -v '^$' | sort) || true)"
    tests_section="## Tests (scope: $(tr '\n' ';' < "$job/scope.txt"))

| run | tests | failures | errors | skipped |
|---|---|---|---|---|
| PR | ${pr_tot//$'\t'/ | } |
| base | ${base_tot//$'\t'/ | } |

**New on this PR:** ${new_fail:-none}

**Also failing on the base:** ${old_fail:-none}
"
    while IFS= read -r line; do
      [ -n "$line" ] && human="$human- $line fails on this PR and not on the base."$'\n'
    done <<< "$new_fail"
  fi

  local tree_section="" smoke_section="" checks_line
  if [ -s "$job/tree.txt" ]; then
    tree_section="$(awk -F'\t' '{ printf "- %s: `%s` (%s)\n", $1, $2, $3 }' "$job/tree.txt")"
    if grep -q 'unexpected$' "$job/tree.txt"; then
      human="$human- the tree has unexpected dirt after the run (see clean tree)."$'\n'
    fi
  else
    tree_section="clean"
  fi
  if [ -f "$job/screenshot.png" ]; then smoke_section="screenshot: \`screenshot.png\` (attached on Discord; in the bay at \`$job/screenshot.png\`)"
  else smoke_section="no screenshot; last lines of \`smoke.log\`:"$'\n\n```\n'"$(tail -n 5 "$job/smoke.log" 2>/dev/null || true)"$'\n```'; fi
  checks_line="$(cat "$job/checks.txt" 2>/dev/null | grep -m1 '^Checks:' || echo 'Checks: not read')"
  human="$human- Run the game and play the change; the boots only prove it starts."$'\n'

  cat > "$job/report.md" <<EOF
# $repo#$number — ${head:0:7} onto $base, $bay

Bay \`$bay\` at \`$job\`. Diff:

\`\`\`
$(cat "$job/diff-stat.txt" 2>/dev/null || echo "(no diff recorded)")
\`\`\`

## Steps

| step | name | status | took |
|---|---|---|---|
$steps_rows
$tests_section
## Boots

- headless: $(awk -F'\t' '$2 == "headless" { print $3 }' "$job/steps.tsv")
- smoke: $(awk -F'\t' '$2 == "smoke" { print $3 }' "$job/steps.tsv"); $smoke_section

## Clean tree

$tree_section

## CI

$checks_line

## What needs a human

$human
EOF
  {
    printf '%s\n' "**$persona checked this PR in a bay** (head \`${head:0:7}\`, base \`$base\`)."
    printf '\n'
    sed -e '1d' -e '/^Bay `/d' -e "s|$job|<bay>|g" "$job/report.md"
    printf '\n_This is an automated report; it says what was observed and not whether the change should merge. A maintainer decides that._\n'
  } > "$job/comment.md"
}

case "${1:-}" in
  render) shift; cmd_render "$1" ;;
  junit)  shift; cmd_junit "$1" ;;
  *) echo "usage: report.sh {render <jobdir>|junit <dir>}" >&2; exit 2 ;;
esac
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash components/naust/tests/run.sh test tests/report.bats`
Expected: 4 pass. The `junit` sum for the three fixtures is 6 tests, 1 failure, 1 error, 1 skipped; if the `eval`/`sed` attribute parse misreads an attribute order, replace it with three `sed -nE 's/.*tests="([0-9]+)".*/\1/p'` reads, one per attribute, which is order-independent.

- [ ] **Step 6: Commit**

`.commits/naust-report.md`:

```markdown
---
message: "feat: report render — steps, PR-vs-base test verdicts, boots, tree, CI, what needs a human"
add:
  - bin/report.sh
  - tests/report.bats
  - tests/fixtures/pass.xml
  - tests/fixtures/fail-new.xml
  - tests/fixtures/fail-old.xml
---

The one table that matters is PR against base: a failure the base already has is listed, not blamed. The comment is the report minus bay paths, opened by the persona and closed by a line saying it decides nothing, which is the oss-wide register's rule for anything posted on a contributor's PR.
```

Run: `ws commit naust .commits/naust-report.md`

### Task 10: naust README and AGENTS

**Files:**
- Create: `components/naust/README.md`, `components/naust/AGENTS.md`

- [ ] **Step 1: README**

Create `components/naust/README.md` (one line per paragraph):

```markdown
# naust

A boathouse for pull requests. Naust keeps *bays*, complete yggdrasil workspaces parked on an always-on machine, and runs a pull request through one: fetch the PR, build, compile every module, run the relevant tests on the PR and on its base, boot the game headless and with a window, take a screenshot, check the tree is clean, and leave a report in the bay, on Discord and on the PR. A human then opens the bay, plays the change and decides. Naust never merges.

Design of record: [`realm-siliconsaga/docs/plans/2026-10-08-naust-pr-bays-design.md`](https://github.com/SiliconSaga/realm-siliconsaga/blob/main/docs/plans/2026-10-08-naust-pr-bays-design.md).

## How it runs

`naust tick` is the whole control loop and it exits. The operating system's scheduler calls it every few minutes; a tick polls GitHub, gates each candidate against the realm's trust list, queues the ones that may run, posts one Discord notice per PR that needs a maintainer's nod, then runs at most one queued job in a free bay. A second tick arriving while a job runs finds the lock and leaves.

What a job does and which commands it uses for a given project is a *profile* in the realm (`realms/<realm>/naust/<profile>.yaml`), beside the trust list (`naust/trust.yaml`). Naust itself knows only that a bay is a yggdrasil workspace and drives it through that workspace's own `ws`.

## Setup

1. `cp naust.example.yaml naust.yaml` and `cp .env.example .env`, then edit both. The `.env` holds the machine account's fine-grained token (`GDD_GITHUB_TOKEN`, pull-requests: write on the watched repository) and the Discord webhook. Never a personal token.
2. `naust bay add bay-1 --profile terasology` (tens of minutes: clones the workspace and the realm, the component and its module set, warms the shared Gradle cache). Add a second bay so one can hold a finished job for a human while the other works.
3. Schedule `naust tick`. On Windows, as the logged-on user so the game window has a desktop and a GPU:

   ```text
   schtasks /Create /SC MINUTE /MO 5 /TN naust-tick /IT /TR "\"C:\Program Files\Git\bin\bash.exe\" -lc \"/d/Dev/GitWS/naust/bin/naust tick >> /d/Dev/GitWS/naust/state/tick.log 2>&1\""
   ```

   On Linux a systemd timer, on macOS a launchd agent, both calling `bin/naust tick`.

## Day to day

- `naust bay list` — every bay, its state (`free busy ready held broken`), its job and how long it has been in that state.
- `naust run terasology 5400 [--with terasology/modules/Health#12] [--bay bay-2]` — queue a PR by hand, ahead of polled ones. The trust gate still applies.
- A `ready` bay holds a finished job until you `naust bay release <name>` it or `bay.ready_ttl_days` passes. Open the bay's `.outputs/naust/<job>/report.md`, run the game from the bay's component directory, decide on GitHub.
- `naust bay reset <name>` puts a bay back to base by hand; `--deep` also drops Gradle outputs. A `broken` bay needs that after you fix whatever the tick log names.
- `naust report render <jobdir>` re-renders a report; `naust notify say <text>` tests the webhook.

## Trust

A PR runs on the host the moment Gradle configures it, so nothing runs without trust. The realm's `naust/trust.yaml` lists `maintainers` (their PRs run, and their nod counts) and `trusted` logins or head repositories. Anyone else needs a nod: the `ok-to-test` label applied by a maintainer, or a comment containing the nod phrase by a maintainer. Naust reads the PR timeline to see who applied the label; the label's presence alone is not a nod.

## Tests

`ws test naust` runs the bats suite with the workspace-vendored bats; `ws lint naust` runs shellcheck. Everything external (`gh`, `curl`, Gradle, the bay's `ws`) is a PATH stub in tests; only temporary git repositories are real.
```

- [ ] **Step 2: AGENTS.md**

Create `components/naust/AGENTS.md`:

```markdown
# naust — agent context

Bash only, `set -euo pipefail`, no jq on the host (shape JSON with `gh --jq`), YAML through `yq`. Tests are bats with PATH stubs; see `tests/helpers/stub.bash` and start every test file with `naust_setup`. Everything a job does inside a bay goes through that bay's `scripts/ws`; never call Gradle from naust itself.

Design of record and the reasoning behind each decision: the realm's `docs/plans/2026-10-08-naust-pr-bays-design.md`. The Phase 1 plan beside it lists the files and their contracts.

Secrets live in `.env`, read literally by `env_value`; never source it and never pass a token on a command line.
```

- [ ] **Step 3: Commit, push, open the CR**

`.commits/naust-docs.md`:

```markdown
---
message: "docs: README and AGENTS for naust"
add:
  - README.md
  - AGENTS.md
---
```

Run: `ws commit naust .commits/naust-docs.md`, `ws push naust`, then `ws cr naust "naust: PR bays, Phase 1" .crs/naust-phase1.md` with a change bodyfile summarising the tick, bays, gate, job and report, and a test plan of `ws test naust` plus the Dionysus bring-up in Task 15.

### Task 11: The Terasology profile, the trust list, the adapter and the realm entry (realm-siliconsaga)

**Files:**
- Create: `naust/terasology.yaml`, `naust/trust.yaml`, `adapters/naust.yaml`, `terasology/tests/run.sh`, `terasology/tests/profile.bats`
- Modify: `ecosystem.yaml` (after the `gdd-sandbox` entry)

**Interfaces:**
- Produces the profile keys naust reads (Tasks 4–9): `component repo upstream_remote default_branch nested nested_default_branch persona init.modules poll.* bay.ready_ttl_days runtime_dirs known_dirt steps.compile_all steps.headless steps.smoke hooks.after_add hooks.after_reset report.comment`.
- Produces the trust keys the gate reads: `terasology.maintainers terasology.trusted terasology.nod_label terasology.nod_phrase`.

- [ ] **Step 1: Branch**

```bash
ws checkout realm-siliconsaga feat/naust-terasology-profile -b
```

- [ ] **Step 2: Write the failing test**

Create `realms/realm-siliconsaga/terasology/tests/run.sh`:

```bash
#!/usr/bin/env bash
# Realm-side Terasology helper tests, on the workspace-vendored bats.
set -euo pipefail
cd "$(dirname "$0")/../.."                      # realm root
WS_ROOT="$(cd ../.. && pwd)"
BATS="$(command -v bats || true)"
BATS="${BATS:-$WS_ROOT/tests/vendor/bats-core/bin/bats}"
exec bash "$BATS" "${1:-terasology/tests/}"
```

Create `realms/realm-siliconsaga/terasology/tests/profile.bats`:

```bash
#!/usr/bin/env bats

REALM="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

@test "the Terasology profile carries every key naust reads" {
    for k in .component .repo .upstream_remote .default_branch .nested_default_branch .persona .init.modules \
             .poll.debounce_minutes .poll.skip_drafts .bay.ready_ttl_days .steps.compile_all .steps.headless \
             .steps.smoke .hooks.after_add .hooks.after_reset .report.comment; do
        v="$(yq "$k" "$REALM/naust/terasology.yaml")"
        [ -n "$v" ] && [ "$v" != null ] || { echo "missing $k"; false; }
    done
    [ "$(yq '.nested | length' "$REALM/naust/terasology.yaml")" -ge 1 ]
    [ "$(yq '.runtime_dirs | length' "$REALM/naust/terasology.yaml")" -ge 1 ]
    [ "$(yq '.known_dirt | length' "$REALM/naust/terasology.yaml")" -ge 1 ]
}

@test "the profile's scripts exist beside this test" {
    for s in pr-headless.sh pr-smoke.sh pr-seed.sh pr-lib.sh screenshot.ps1 seed-manifest.template.json; do
        [ -f "$REALM/terasology/$s" ] || { echo "missing terasology/$s"; false; }
    done
    grep -q 'pr-headless.sh' "$REALM/naust/terasology.yaml"
    grep -q 'pr-smoke.sh' "$REALM/naust/terasology.yaml"
    grep -q 'pr-seed.sh' "$REALM/naust/terasology.yaml"
}

@test "the trust list names at least one maintainer and both nod forms" {
    [ "$(yq '.terasology.maintainers | length' "$REALM/naust/trust.yaml")" -ge 1 ]
    [ "$(yq '.terasology.nod_label' "$REALM/naust/trust.yaml")" = "ok-to-test" ]
    [ "$(yq '.terasology.nod_phrase' "$REALM/naust/trust.yaml")" = "ok to test" ]
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash realms/realm-siliconsaga/terasology/tests/run.sh`
Expected: all three fail (files missing). The second stays red until Task 13.

- [ ] **Step 4: Write the profile**

Create `realms/realm-siliconsaga/naust/terasology.yaml`:

```yaml
# naust profile for Terasology — what a PR job does for this component.
# Build, test and run commands are NOT here: they are the adapter's, and naust
# calls them through the bay's own ws. This file adds only what the adapter
# does not say. Scripts referenced below live in ../terasology/ and run with
# the engine checkout as cwd and NAUST_* in the environment.
component: terasology
repo: MovingBlocks/Terasology           # the watched repository
upstream_remote: MovingBlocks           # the remote in a bay that tracks it
default_branch: develop
nested:                                  # the adapter's shape, repeated here because
  - "modules/*"                          # naust resets these to their own origin
  - "libs/*"
nested_default_branch: develop
persona: Gooey                           # the name on reports and comments

init:
  modules: omega                         # groovyw module init omega, once per bay

poll:
  debounce_minutes: 10                   # a push burst becomes one job on the last head
  skip_drafts: true                      # unless the draft carries the nod label

bay:
  ready_ttl_days: 7                      # a finished job waits this long for a human

# Gitignored directories the game writes into the checkout; wiped on reset.
runtime_dirs: [logs, saves, terasology-server]

# Dirt the clean-tree check names as known rather than unexpected.
known_dirt:
  - "src/test/resources/logback-test.xml"   # the harness copies it into every module it builds

steps:
  compile_all: "./gradlew compileJava"      # unqualified on purpose: every module in the set
  headless: "bash \"$NAUST_REALM_DIR/terasology/pr-headless.sh\""
  smoke: "NAUST_SETTLE_SECONDS=45 bash \"$NAUST_REALM_DIR/terasology/pr-smoke.sh\""

hooks:
  after_add: "bash \"$NAUST_REALM_DIR/terasology/pr-seed.sh\" generate"
  after_reset: "bash \"$NAUST_REALM_DIR/terasology/pr-seed.sh\" restore"

report:
  comment: on                            # the owner's call: GDD may post in the oss-wide register here
```

Create `realms/realm-siliconsaga/naust/trust.yaml`:

```yaml
# Who may vouch for a pull request. A PR by a maintainer or a trusted login,
# or from a trusted head repository, runs without a nod; anyone else's runs
# only after a maintainer applies the label or leaves the phrase. naust reads
# the PR timeline, so a label applied by anyone else is ignored.
terasology:
  maintainers: [Cervator]                # add the second core contributor when they opt in
  trusted: []                            # logins or owner/repo head repositories
  nod_label: ok-to-test
  nod_phrase: "ok to test"
```

- [ ] **Step 5: Adapter and realm entry**

Create `realms/realm-siliconsaga/adapters/naust.yaml`:

```yaml
# naust adapter — bash runner over bats and shellcheck, the gdd-sandbox shape.
commands:
  test: "bash tests/run.sh test"
  testFilter: "bash tests/run.sh test {}"
  lint: "bash tests/run.sh lint"

ai_context:
  - path: "AGENTS.md"
    description: "Agent guidelines for working on naust"
  - path: "README.md"
    description: "What naust does, how a tick runs, bay states, trust"
```

In `ecosystem.yaml`, after the `gdd-sandbox` entry:

```yaml
  # naust — the boathouse: bays (sibling yggdrasil workspaces) that check out,
  # build, test and smoke-boot pull requests for a human to judge, driven by a
  # scheduled tick. Like gdd-sandbox it runs on an operator's machine and ships
  # no chart, so it takes the supporting tier. Its Terasology profile and trust
  # list are realm content under naust/. See docs/plans/2026-10-08-naust-pr-bays-design.md.
  naust:
    tier: supporting
```

- [ ] **Step 6: Run the tests**

Run: `bash realms/realm-siliconsaga/terasology/tests/run.sh`
Expected: the profile and trust tests pass; the scripts test still fails (Task 13).

- [ ] **Step 7: Commit**

`.commits/realm-naust-profile.md` (paths relative to the realm root):

```markdown
---
message: "feat(naust): Terasology profile, trust list, naust adapter and realm entry"
add:
  - naust/terasology.yaml
  - naust/trust.yaml
  - adapters/naust.yaml
  - ecosystem.yaml
  - terasology/tests/run.sh
  - terasology/tests/profile.bats
---

The profile says only what the adapter does not: which repository to watch, the module set, the runtime directories a reset wipes, the dirt the clean-tree check already knows, and the three Terasology-specific scripts. Trust starts as one maintainer; the second core contributor is added when they opt in.
```

Run: `ws commit realm-siliconsaga .commits/realm-naust-profile.md`

### Task 12: `pr-seed.sh` — the seed save for `--create-last-game`

**Files:**
- Create: `terasology/pr-seed.sh`, `terasology/seed-manifest.template.json`, `terasology/tests/pr-seed.bats`

**Interfaces:**
- Consumes: `NAUST_BAY_DIR`; cwd is the engine checkout; module descriptors at `modules/<Name>/module.txt` and the engine's at `engine/src/main/resources/org/terasology/engine/module.txt`.
- Produces: `pr-seed.sh generate` writes `$NAUST_BAY_DIR/seed/manifest.json` with every `@Name@` in the template replaced by that module's `version`, failing with the module's name when a descriptor is missing. `pr-seed.sh restore` copies it to `saves/naust-seed/manifest.json` and touches it so it is the newest save.

- [ ] **Step 1: Write the failing tests**

Create `realms/realm-siliconsaga/terasology/tests/pr-seed.bats`:

```bash
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
    out="$NAUST_BAY_DIR/seed/manifest.json"
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
    cmp -s "$ENGINE/saves/naust-seed/manifest.json" "$NAUST_BAY_DIR/seed/manifest.json"
}

@test "restore without a generated seed fails and says to generate" {
    run bash "$SEED" restore
    [ "$status" -ne 0 ]
    [[ "$output" == *"generate"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash realms/realm-siliconsaga/terasology/tests/run.sh terasology/tests/pr-seed.bats`
Expected: all fail.

- [ ] **Step 3: Template and script**

Create `realms/realm-siliconsaga/terasology/seed-manifest.template.json`:

```json
{
  "title": "naust-seed",
  "seed": "naust",
  "time": 0,
  "registeredBlockFamilies": [],
  "blockIdMap": {},
  "worlds": {
    "main": { "title": "main", "seed": "naust", "time": 0, "worldGenerator": "CoreWorlds:facetedsimplex" }
  },
  "modules": [
    { "name": "engine", "version": "@engine@" },
    { "name": "CoreSampleGameplay", "version": "@CoreSampleGameplay@" },
    { "name": "CoreAssets", "version": "@CoreAssets@" },
    { "name": "CoreAdvancedAssets", "version": "@CoreAdvancedAssets@" },
    { "name": "CoreRendering", "version": "@CoreRendering@" },
    { "name": "CoreWorlds", "version": "@CoreWorlds@" },
    { "name": "Health", "version": "@Health@" },
    { "name": "Inventory", "version": "@Inventory@" },
    { "name": "BiomesAPI", "version": "@BiomesAPI@" }
  ],
  "moduleConfigs": {}
}
```

Create `realms/realm-siliconsaga/terasology/pr-seed.sh`:

```bash
#!/usr/bin/env bash
# The smoke boot's seed save. `--create-last-game` needs a latest game manifest
# to exist, and the engine treats any directory under saves/ holding a titled
# manifest.json as a save. The manifest names every module with a version, so
# the template carries @Name@ placeholders and `generate` fills them from the
# checkout's own descriptors; shipping versions would go stale with the next
# SNAPSHOT bump.
#
#   pr-seed.sh generate   cwd: the engine checkout. Writes $NAUST_BAY_DIR/seed/manifest.json.
#   pr-seed.sh restore    copies it to saves/naust-seed/manifest.json (after every reset).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$HERE/seed-manifest.template.json"
SEED_DIR="${NAUST_BAY_DIR:?pr-seed: NAUST_BAY_DIR is required}/seed"

module_version() { # <module name>
  local f
  if [ "$1" = engine ]; then
    f="engine/src/main/resources/org/terasology/engine/module.txt"
  else
    f="modules/$1/module.txt"
  fi
  [ -f "$f" ] || { echo "pr-seed: no module descriptor for $1 at $PWD/$f" >&2; return 1; }
  sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$f" | head -n1
}

cmd_generate() {
  local out="$SEED_DIR/manifest.json" name version
  mkdir -p "$SEED_DIR"
  cp "$TEMPLATE" "$out"
  for name in $(grep -oE '@[A-Za-z0-9]+@' "$TEMPLATE" | tr -d '@' | sort -u); do
    version="$(module_version "$name")" || exit 1
    [ -n "$version" ] || { echo "pr-seed: $name has no version in its descriptor" >&2; exit 1; }
    sed -i "s/@$name@/$version/g" "$out"
  done
  echo "pr-seed: wrote $out"
}

cmd_restore() {
  [ -f "$SEED_DIR/manifest.json" ] || { echo "pr-seed: no seed at $SEED_DIR/manifest.json; run 'pr-seed.sh generate' in the engine checkout first" >&2; exit 1; }
  mkdir -p saves/naust-seed
  cp "$SEED_DIR/manifest.json" saves/naust-seed/manifest.json
  touch saves/naust-seed/manifest.json
  echo "pr-seed: restored saves/naust-seed/manifest.json"
}

case "${1:-}" in
  generate) cmd_generate ;;
  restore)  cmd_restore ;;
  *) echo "usage: pr-seed.sh {generate|restore}" >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash realms/realm-siliconsaga/terasology/tests/run.sh terasology/tests/pr-seed.bats`
Expected: 4 pass.

- [ ] **Step 5: Commit**

`.commits/realm-naust-seed.md`:

```markdown
---
message: "feat(naust): pr-seed generates the smoke boot's seed manifest from the checkout"
add:
  - terasology/pr-seed.sh
  - terasology/seed-manifest.template.json
  - terasology/tests/pr-seed.bats
---

Read from the engine: a save is a directory under saves/ with a titled manifest.json, nothing else is consulted, and --create-last-game makes a fresh world from the newest one. The template names CoreSampleGameplay and its dependencies; versions are filled at provisioning because every one of them is a SNAPSHOT.
```

Run: `ws commit realm-siliconsaga .commits/realm-naust-seed.md`

### Task 13: `pr-lib.sh`, `pr-headless.sh`, `pr-smoke.sh`, `screenshot.ps1` — the two boots

**Files:**
- Create: `terasology/pr-lib.sh`, `terasology/pr-headless.sh`, `terasology/pr-smoke.sh`, `terasology/screenshot.ps1`, `terasology/tests/pr-boot.bats`

**Interfaces:**
- Consumes: cwd is the engine checkout; `NAUST_JOB_DIR`; the `gradlew` wrapper (`server` and `game` tasks); `jps` from the JDK; env overrides `NAUST_HEADLESS_TIMEOUT` (default 900), `NAUST_SMOKE_TIMEOUT` (900), `NAUST_SETTLE_SECONDS` (45), `NAUST_SCREENSHOT_CMD`, `NAUST_JPS_CMD`.
- Produces: `pr-headless.sh` exits 0 when `Server started` appears in `$NAUST_JOB_DIR/headless.log` within the timeout, 1 otherwise; copies `terasology-server/logs` to `$NAUST_JOB_DIR/headless-logs`. `pr-smoke.sh` exits 0 when `Initialising rendering class` appears in `$NAUST_JOB_DIR/smoke.log` and `$NAUST_JOB_DIR/screenshot.png` was written; copies `logs` to `$NAUST_JOB_DIR/game-logs`; exits 1 with no seed save, on timeout, or when the JVM exits early. Both always stop the game they started.
- `pr-lib.sh`: `wait_for_marker <file> <text> <timeout> [<pid>]`, `stop_game <pid>`, `terasology_jvms`, `screenshot <out.png>`.

- [ ] **Step 1: Write the failing tests**

Create `realms/realm-siliconsaga/terasology/tests/pr-boot.bats`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash realms/realm-siliconsaga/terasology/tests/run.sh terasology/tests/pr-boot.bats`
Expected: all fail.

- [ ] **Step 3: `pr-lib.sh`**

```bash
#!/usr/bin/env bash
# Shared by pr-headless.sh and pr-smoke.sh. Sourced.
PR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Poll <file> for <text> until <timeout> seconds pass or <pid> exits.
wait_for_marker() { # <file> <text> <timeout-seconds> [<pid>]
  local file="$1" text="$2" timeout="$3" pid="${4:-}" waited=0
  while [ "$waited" -lt "$timeout" ]; do
    if [ -f "$file" ] && grep -qF -- "$text" "$file"; then return 0; fi
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      echo "process $pid exited before '$text' appeared; last lines:" >&2
      tail -n 5 "$file" >&2 2>/dev/null || true
      return 1
    fi
    sleep 2; waited=$((waited + 2))
  done
  echo "timeout after ${timeout}s waiting for '$text' in $file" >&2
  return 1
}

# Terasology JVMs on this machine, by pid. jps ships with the JDK on every OS.
terasology_jvms() {
  ${NAUST_JPS_CMD:-jps -l} 2>/dev/null | awk '$2 ~ /org\.terasology\.engine\.Terasology$/ { print $1 }' || true
}

# Stop what a boot started. The gradlew wrapper execs the Gradle client, so
# killing <pid> disconnects the client and the daemon cancels the build, which
# kills its JavaExec child. If a Terasology JVM is still there after that, it is
# killed by pid; an orphaned game would hold the GPU for every later job.
stop_game() { # <gradlew pid>
  local pid="$1" waited=0 p
  kill "$pid" 2>/dev/null || true
  while [ "$waited" -lt 30 ]; do
    if ! kill -0 "$pid" 2>/dev/null && [ -z "$(terasology_jvms)" ]; then return 0; fi
    sleep 2; waited=$((waited + 2))
  done
  kill -9 "$pid" 2>/dev/null || true
  for p in $(terasology_jvms); do
    echo "stopping a lingering Terasology JVM, pid $p" >&2
    case "$(uname -s)" in
      MINGW*|MSYS*|CYGWIN*) taskkill //PID "$p" //F >/dev/null 2>&1 || kill -9 "$p" 2>/dev/null || true ;;
      *) kill -9 "$p" 2>/dev/null || true ;;
    esac
  done
}

# Capture the primary display to <out.png> with whatever this OS has.
screenshot() { # <out.png>
  if [ -n "${NAUST_SCREENSHOT_CMD:-}" ]; then $NAUST_SCREENSHOT_CMD "$1"; return; fi
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$PR_LIB_DIR/screenshot.ps1")" "$(cygpath -w "$1")" ;;
    Darwin) screencapture -x "$1" ;;
    *)
      if command -v import >/dev/null 2>&1; then import -window root "$1"
      elif command -v gnome-screenshot >/dev/null 2>&1; then gnome-screenshot -f "$1"
      else echo "no screenshot tool (install ImageMagick or gnome-screenshot)" >&2; return 1; fi ;;
  esac
}
```

- [ ] **Step 4: `pr-headless.sh`**

```bash
#!/usr/bin/env bash
# Headless pre-flight: boot the engine as a server (the facade's `server` task,
# --headless, home directory terasology-server/) and wait for the network layer
# to say "Server started", which means the engine initialised and a world
# loaded with no window involved. Headless setup builds its own manifest from
# the default module selection when no save exists, so no seed is needed.
#
# cwd: the engine checkout. Writes $NAUST_JOB_DIR/headless.log and headless-logs/.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=terasology/pr-lib.sh
. "$HERE/pr-lib.sh"
JOB="${NAUST_JOB_DIR:?pr-headless: NAUST_JOB_DIR is required}"
TIMEOUT="${NAUST_HEADLESS_TIMEOUT:-900}"
LOG="$JOB/headless.log"

rm -rf terasology-server
./gradlew server > "$LOG" 2>&1 &
pid=$!
rc=0
wait_for_marker "$LOG" "Server started" "$TIMEOUT" "$pid" || rc=1
stop_game "$pid"
if [ -d terasology-server/logs ]; then rm -rf "$JOB/headless-logs"; cp -r terasology-server/logs "$JOB/headless-logs"; fi
[ "$rc" -eq 0 ] && echo "headless: server started and stopped cleanly"
exit "$rc"
```

- [ ] **Step 5: `pr-smoke.sh`**

```bash
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
```

- [ ] **Step 6: `screenshot.ps1`**

```powershell
param([Parameter(Mandatory = $true)][string]$Path)
# Capture the primary display to a PNG. Needs an interactive, unlocked session;
# a locked desktop yields a black image, which the report then shows as such.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose(); $bitmap.Dispose()
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bash realms/realm-siliconsaga/terasology/tests/run.sh`
Expected: profile 3, pr-seed 4, pr-boot 5 — all pass (the boot tests take about 30 seconds between them because of the 2-second poll).

- [ ] **Step 8: Commit**

`.commits/realm-naust-boots.md`:

```markdown
---
message: "feat(naust): headless and windowed smoke boots with the engine's own log markers"
add:
  - terasology/pr-lib.sh
  - terasology/pr-headless.sh
  - terasology/pr-smoke.sh
  - terasology/screenshot.ps1
  - terasology/tests/pr-boot.bats
---

Markers come from a real client log on this machine: the facade sifts logs by phase, the world seed line marks the load, the renderer's "Initialising rendering class" marks the GPU being up, and nothing at info marks the in-game state exactly, so the renderer line plus a settle is the signal. The headless boot waits for "Server started" instead and needs no seed. Both stop what they started, and a Terasology JVM that outlives the Gradle client is killed by pid so one wedged job cannot hold the GPU for the next.
```

Run: `ws commit realm-siliconsaga .commits/realm-naust-boots.md`

### Task 14: Realm README section, push, CR

**Files:**
- Modify: `terasology/README.md` (new section)

- [ ] **Step 1: Document the helpers**

Append to `realms/realm-siliconsaga/terasology/README.md`:

```markdown
## naust: the PR-bay scripts

`../naust/terasology.yaml` is the naust profile for this component and `../naust/trust.yaml` the trust list; see the [design](../docs/plans/2026-10-08-naust-pr-bays-design.md). The profile points at three scripts here, all run by naust with the engine checkout as cwd and `NAUST_*` in the environment:

- `pr-seed.sh generate|restore` — the seed save that `--create-last-game` needs. `generate` runs once per bay and fills `seed-manifest.template.json` with the versions in the checkout; `restore` runs after every reset and puts it back under `saves/naust-seed/`.
- `pr-headless.sh` — boots the facade's `server` task and waits for `Server started`.
- `pr-smoke.sh` — boots `gradlew game --args="--create-last-game --no-splash --no-crash-report --no-save-games"`, waits for the renderer's `Initialising rendering class` line, settles, screenshots the primary display (`screenshot.ps1` on Windows) and stops the game. `pr-lib.sh` holds the marker wait, the stop and the screenshot.

Run them by hand from `components/terasology` with `NAUST_JOB_DIR` set to any directory to see what a job sees. Tests: `bash realms/realm-siliconsaga/terasology/tests/run.sh`.
```

- [ ] **Step 2: Commit, push, open the CR**

`.commits/realm-naust-readme.md`:

```markdown
---
message: "docs(naust): the PR-bay helper scripts in the Terasology README"
add:
  - terasology/README.md
---
```

Run: `ws commit realm-siliconsaga .commits/realm-naust-readme.md`, then `ws push realm-siliconsaga`, then `ws cr realm-siliconsaga "naust: Terasology profile, trust list and boot scripts" .crs/realm-naust.md` with a change bodyfile (summary: profile and trust as realm content, the three scripts and what each waits for, the seed template; test plan: the realm bats suite and the Dionysus bring-up).

### Task 15: Bring-up on Dionysus (operator runbook)

No code. Each step is a check with an expected result; a failure is a finding to fix in the task that owns the code, not a reason to patch the bay by hand.

- [ ] **Step 1: Merge order**

yggdrasil's `ws checkout --pr` CR merges first (bays clone yggdrasil from `main`). Then the naust CR, then the realm CR. Pull the dev workspace: `ws pull yggdrasil`, `ws pull realm-siliconsaga`, `ws clone naust`.

- [ ] **Step 2: Secrets and config**

In the dev workspace `components/naust`: `cp naust.example.yaml naust.yaml`, set `workspace: D:/Dev/GitWS/yggdrasil`, `bays_root: D:/Dev/GitWS/naust/bays`, `state_dir: D:/Dev/GitWS/naust/state`, `gradle_home: D:/Dev/GitWS/naust/gradle-home`. `cp .env.example .env`; paste the machine account's fine-grained token (pull-requests: write on MovingBlocks/Terasology, nothing else) and the Discord webhook. Check: `bash bin/naust notify say "naust is configured on Dionysus"` posts to the channel.

- [ ] **Step 3: First bay**

`bash bin/naust bay add bay-1 --profile terasology`. Expected: tens of minutes; ends with `reset bay-1: free`. Verify: `bash bin/naust bay list` shows `bay-1 free terasology`; `D:/Dev/GitWS/naust/bays/bay-1/yggdrasil/components/terasology/modules` holds the Omega set; `bays/bay-1/seed/manifest.json` has no `@` left. If `ws realm` or `ws realm use --trust` prompted, record what it asked: Task 4's `cmd_add` needs the non-interactive form of that verb and this is where it shows.

- [ ] **Step 4: The smoke boot by hand, before any job**

From `bays/bay-1/yggdrasil/components/terasology`, with `NAUST_JOB_DIR=D:/tmp/smoke` and `NAUST_BAY_DIR=D:/Dev/GitWS/naust/bays/bay-1`: `bash ../../realms/realm-siliconsaga/terasology/pr-seed.sh restore`, then `bash ../../realms/realm-siliconsaga/terasology/pr-smoke.sh`. Expected: a window opens, a world loads, `screenshot.png` shows it, the game is gone afterwards (`jps -l` lists no Terasology). If the log says a module is missing, add it to `seed-manifest.template.json`'s list (Task 12) and regenerate. If `last game not found`, the manifest was not where `PathManager` looks; compare with a save the game itself wrote.

- [ ] **Step 5: First job by hand**

Pick an open PR of your own on MovingBlocks/Terasology. `bash bin/naust run terasology <n>` then `bash bin/naust tick`. Expected: `tick: running …`, then within an hour a `ready` bay, `report.md` in the bay's `.outputs/naust/<job>/`, the screenshot on Discord, the comment on the PR under the machine account with the GDD banner. Read the report against the PR: the steps table, the PR-vs-base test table, the boots, the tree.

- [ ] **Step 6: Second bay and the scheduler**

`bash bin/naust bay add bay-2 --profile terasology`. Then the scheduled task, as the logged-on user (the `/IT` flag), every five minutes:

```text
schtasks /Create /SC MINUTE /MO 5 /TN naust-tick /IT /TR "\"C:\Program Files\Git\bin\bash.exe\" -lc \"/d/Dev/GitWS/yggdrasil/components/naust/bin/naust tick >> /d/Dev/GitWS/naust/state/tick.log 2>&1\""
```

Expected within ten minutes: `tick.log` shows `queue empty` lines. Push a trivial commit to the same PR: within the debounce plus one tick a job runs on the new head in a free bay while bay-1 stays `ready`. Lock the screen during a smoke boot once: the screenshot comes back black and the report says so; that is the known limit, not a bug.

- [ ] **Step 7: Hand-off and close**

`bash bin/naust bay release bay-1` after reading its report. Record in the Dionysus thalamus arc `naust-pr-bays` what the first runs took (provision time, job time, anything that needed a hand), and move the arc's `next` to Phase 2.

---

## Self-review notes

Spec coverage: placement (Tasks 2, 11), bays and states (4), events and tick (6, 7), trust gate with actor check (5), the nine steps (8), smoke boot markers and seed (12, 13), report and delivery (9, 8), security (2's `.env`, 8's `GH_TOKEN` scoping, 11's token note), Phase 1 done-criterion (15). Not in Phase 1 by the spec's own split: the judgement step, the container tier, Discord-driven approval, linked PRs, Hookdeck.

Review Focus pins: force-push → Task 6 (`put` replaces on newer head) and Task 8 (`job.yaml` `head` from `rev-parse`); non-maintainer label → Task 5; nested fetch failure → Task 4 (`broken`, repo named); renderer never logs → Task 13 (timeout test); overlapping ticks → Task 7 (lock test) and Task 2 (stale reclaim).

Known soft spots an executor should watch: `ws realm` and `ws realm use --trust` may prompt when run from `bay add` (Task 15 step 3 records it); `wait -n` needs bash ≥ 4.3 (Git Bash ships 5); `taskkill` is only reached when a Terasology JVM outlives the Gradle client, which the daemon normally prevents.
