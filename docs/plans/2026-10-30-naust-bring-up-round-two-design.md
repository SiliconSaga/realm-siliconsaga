# Naust bring-up findings and round two

**Status:** draft for the owner's review, 2026-10-30. Written during the first bay's provisioning and updated with its result. Nothing here is implemented yet.

**Context:** Phase 1 of the PR-bay runner is merged in yggdrasil (#178) and the realm (#42); naust #1 is open. The first `naust bay add` on Dionysus started on 2026-10-29 with the agent-refr token standing in for GooeyHub. Design of record: `2026-10-08-naust-pr-bays-design.md`. Owner asks that shaped this round: `naust bay list` must answer at once; a proper way to watch a bay; short-circuit clones from what the parent already has; whether worktrees could build a bay faster.

## What the first bring-up found

**The run itself (bay-1, Dionysus, 2026-10-30 UTC):** workspace, realm and engine clones plus `groovyw module init omega` took 10 minutes (03:36 to 03:46); the Gradle warm-up through `ws build` took 16 minutes; `compileJava` 15 seconds, all up to date; the seed manifest 20 seconds; then the closing `ws bay reset` refused after 45 seconds: the bay's realm is pinned to the parent's realm commit, which was the held round-two commit 992a1da, not on the remote. That refusal is correct by design (round one's ruling: a bay's realm follows the parent's reviewed, pushed commit) but it came 28 minutes in, and the bay was marked broken. Moving the parent's realm to the merged main and re-running `naust bay reset bay-1` is the recovery; see finding 7.

1. **The dispatcher costs forty seconds per call on this machine.** `ws run naust bay list` took 41.6 s beside the Gradle build and 36.6 s on an idle machine; `bash components/naust/bin/naust bay list` took 1.1 s. A stage timer on `ws-run.sh` put 24.3 s in `ws_resolve_target` and 11.1 s in `ws_read_trusted_adapter`. Both compute the realm trust fingerprint, which canonicalizes every adapter with its own `yq` process and runs a second `yq` per adapter to extract commands, plus a subshell per path-shaped token. The realm has 17 adapters, so one fingerprint is about 34 `yq` spawns and dozens of subshells; `ws run` computes it twice (once through `ws_resolve_ecosystem`, once through the captured-adapter check). Process spawn on Windows is the cost, and a Gradle build was running beside the measurement, so the idle number will be lower but the shape is the same. Every `ws bay exec` inside a naust job pays this too, in the bay's own ws, so a job with a dozen exec steps loses minutes to it. Naust itself is not slow.
2. **A bay being cloned is invisible to naust.** `naust bay add` writes the bay's state file after `ws bay add` returns, so during the clone and module fetch `naust bay list` prints nothing, while `ws bay list` already names the bay. Once the Gradle warm-up starts the state reads `provisioning` with an age in seconds and nothing else.
3. **Output reaches only the launcher.** Naust logs to stderr unless `NAUST_LOG` is set (the tests set it); `ws bay add` prints to stdout. Nothing writes a per-bay log on disk, so a human, a parallel agent session or the Discord head cannot watch a bay another process owns. Watching this run meant tailing a session temp file.
4. **The bay re-fetched what the parent already had.** The parent's engine checkout carries a 316 MB `.git` and 55 modules (304 MB); the bay cloned the engine again and `groovyw module init omega` fetched the full set from GitHub one module at a time. The fetcher skips a module directory that already exists (`retrieveItem` in `config/groovy/common.groovy`), so pre-seeding works.
5. **`naust.yaml` is required before any verb**, including `bay add`. The README says so; the first attempt skipped it. Not a defect.
6. **Discord with no webhook is a logged no-op**, as designed; the bring-up ran without one.
7. **The realm-pin check runs last, after the expensive work.** `ws bay add` clones and provisions for half an hour, and only the reset at the end of `naust bay add` discovers that the parent's realm commit is not on its remote. The same check belongs at the top of `ws bay add`, before the first clone, with the same message. Two smaller things surfaced on the way to recovery: the parent realm's local `main` was 11 commits stale, so `ws checkout realm-siliconsaga main` landed on a pre-#42 adapter and `ws pull` was needed; and `ws pull` refuses a tree dirty only with an untracked file, which was this draft.

## Round two, as bounded changes

Each is small enough for an in-chat design and a RED→GREEN test. They are independent except where noted, and they split across yggdrasil and naust as marked.

### A. One fingerprint per process, two `yq` spawns per fingerprint (yggdrasil, trust path)

Keep the fingerprint value and the trust semantics exactly as they are; change only how often and how expensively it is computed.

- Canonicalize every adapter in one `yq` call: `yq -o=json -I=0 'sort_keys(..)' adapters/*.yaml` prints one JSON document per file in argument order (yq v4.52 evaluates each file separately). Extract every adapter's commands and `provision.init` in a second call over those documents. The per-adapter work that remains is bash string handling plus `git hash-object` for referenced helpers, which the existing tests already pin.
- Memoize per process: `ws_realm_trust_fingerprint` caches the fingerprint and each adapter's canonical text in process variables keyed by realm. `ws_read_trusted_adapter` passes captured content today so the content consumed is the content fingerprinted; with the cache, the captured content is compared to the cached canonical for that adapter and the cached fingerprint is reused when they match, recomputed when they differ. That keeps the pull-during-read protection intact.
- Tests: existing `tests/ws-realm/trust.bats` fingerprints must not change (pin a known fingerprint for a fixture realm before touching the code); a new test counts `yq` invocations through a shim and asserts the count for a 17-adapter realm; a new test edits an adapter between resolve and read in the same process and asserts the read is refused.
- Expected: `ws run naust bay list` from 41 s to about 3 s here; every `ws bay exec` step the same. This is the fix for the owner's "bay list hangs" report, since naust was never the slow part. It is the trust surface, so it goes out as its own yggdrasil CR with the security review it deserves, ahead of the rest.

### B. A cloning bay is visible (naust)

`naust bay add` writes `state=provisioning` before calling `ws bay add`, not after. `naust bay list` then names the bay from the first second. No `--wait` flag: the hang was the dispatcher, not the listing. Test: a `ws` shim that sleeps inside `bay add` while the test reads the state file.

### C. Per-bay logs and `ws bay log` (yggdrasil and naust)

- `ws bay add` and `ws bay reset` append their own output to `bays/<name>/.outputs/bay.log`, with a timestamp per line. `.outputs/` is gitignored and the bay root is never deep-cleaned, so the file survives every reset.
- Naust defaults `NAUST_LOG` to that same file for bay-scoped commands (`bay add`, `bay reset`, the job runner), so provisioning, resets and job steps read as one stream; the per-job `.outputs/naust/<job>/` step logs stay where they are and the bay log names them.
- `ws bay log <name> [--follow] [--lines N]` tails the file. `--follow` is `tail -f`, which exists on every host ws supports. The hook allows it read-only.
- `naust bay list` gains a last-activity column: seconds since the newest write under `bays/<name>/.outputs/`, so a watcher can tell a working bay from a stuck one without reading the log.
- Tests: the log exists after an add through a stub realm; a reset appends; `ws bay log` prints the last N lines; naust's list shows the activity column.

### D. Seed a bay from the parent (yggdrasil, `ws bay add`)

Replace the network clone with a local one wherever the parent already has the repository, then point the clone at upstream.

- For each `--with` component the parent has checked out: `git clone --quiet <parent component dir> <bay component dir>` (a local clone hardlinks the object store, so it costs seconds and little disk; git objects are immutable so sharing is safe), then `git remote set-url <remote> <upstream url>` using the remote the adapter and ecosystem already resolve, `git fetch --prune`, and the existing reset to the remote's default branch. The bay never inherits the parent's working state: the reset to upstream is what it follows, as today.
- Nested repositories: for each trusted-adapter `nested` glob (`modules/*`, `libs/*` for Terasology), every matching directory in the parent that is a git repository is seeded the same way, before `provision.init` runs. The engine's fetcher then skips them and fetches only the rest of the set. The glob validation added in round one (`bay_nested_glob_ok`) already bounds what gets touched.
- Opt-out `--no-seed` for a clean-room bay. Default on, because the owner's ask is to stop re-fetching.
- This generalizes todo 6 (`--from-bay`) from the arc: the source is any workspace, the parent being the one always present.
- Tests: a parent fixture with a component and a nested repo; the bay's clone has the upstream URL and the parent's objects; a nested directory in the parent appears in the bay before init runs; `--no-seed` clones from upstream.
- Expected on Dionysus: the engine and 55 of the omega modules from local disk; the remaining modules still come from GitHub. The Gradle warm-up is unchanged and remains the long pole.

### E. Worktrees: not for bays; maybe a lane verb of their own

The owner's question was whether a bay could be a worktree of the parent's `.git` instead of a clone. Recommendation: no, for three reasons, and D gets the speed without them.

- A worktree shares `.git/config`, hooks and refs with the parent. Phase 1 runs PR code as the operator inside the bay; with a clone the blast radius is the bay, with a worktree it includes the parent's hooks and refs. The design's whole isolation story is "a bay is a separate workspace".
- Terasology's module set is 100-plus nested repositories under a gitignored directory. A worktree of the engine carries none of them, so the expensive part is unchanged.
- The bay's realm, ws scripts and local config are their own repositories with their own trust record; a worktree of yggdrasil would share the parent's trust state, which round one deliberately separated.

What the owner hit at work is a different need: several agents on one small repository, each in a worktree, and the awkwardness of addressing them. That is a `ws worktree` lane verb, not a bay: `ws worktree add <comp> <lane>` creating `components/<comp>/.worktrees/<lane>` (or registering the directory Claude Code's own worktree tool makes), `ws test <comp>@<lane>` routing an adapter command into it, `ws worktree list|rm`. It is worth its own bounded design once there is a GDD use for it; nothing in naust needs it.

### F. Names and phrases (realm and naust, already agreed)

`naust run` becomes `naust dock`; the `smoke` step becomes `launch` across the profile key, `pr-smoke.sh`, job labels, report rows and both READMEs, as one coordinated pair of commits; gate.sh's fallback phrase and the naust README follow the realm's *haul it in*.

### G. Fail before cloning when the realm pin cannot be met (yggdrasil, `ws bay add`)

`ws bay add` resolves the parent realm's commit and checks it is reachable from the realm remote's branch before cloning anything, with the message the reset prints today. `naust bay add` inherits it. Test: a parent realm one local commit ahead of its remote makes `ws bay add` exit before the workspace clone, and a bay directory is never created.

## Order

1. A, as its own yggdrasil CR, first: it changes every number below and is the trust surface.
2. B, C and G together, naust plus the `ws bay log` and pre-flight halves in yggdrasil, on the held `-next` branches.
3. D on the yggdrasil `-next` branch, measured by making bay-2 with it.
4. F with the naust CR update.
5. E parked as a question with a recommended shape.

The held round-one commits on `feat/ws-bays-next` and `feat/naust-terasology-next` stay unpushed until the first real `naust dock` against an engine PR has posted a report, per the owner.
