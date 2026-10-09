# Naust — PR bays: design

**Status:** Reviewed twice by the owner on 2026-10-08, first the design and then its placement and trust model; both sets of decisions are folded in below and the [Phase 1 plan](2026-10-08-naust-pr-bays-phase1-plan.md) implements them.
**Date:** 2026-10-08
**Owner:** Rasmus Praestholm
**Arc:** `naust-pr-bays` on the Dionysus thalamus
**Related:** the [`terasology-review`](../../.agent/skills/terasology-review/SKILL.md) skill (this design automates the mechanical half of its six checks) · [`terasology-testing`](../../.agent/skills/terasology-testing/SKILL.md) · the [gdd-sandbox design](https://github.com/SiliconSaga/gdd-sandbox/blob/main/docs/plans/2026-07-20-gdd-sandbox-design.md) (the untrusted tier, later) · yggdrasil's [roadmap](https://github.com/SiliconSaga/yggdrasil/blob/main/docs/gdd/roadmap.md) tracks *Assisted access* and *Sandboxed workspaces* · the `terasology-agentic-next` arc (a Terasology-dedicated realm and fork org, which is where the Terasology half of this moves when it lands)

## The outcome

A pull request to one of the owner's hobby projects, Terasology first, is noticed within minutes of being opened or pushed. A machine that is already on checks it out into a complete local workspace, builds it, runs the relevant tests against both the PR and its base, boots the game once headless and once with a window, takes a screenshot, and writes a short report. When a human sits down, the workspace is waiting: they read the report, play the change, decide, and merge on GitHub. Merging stays human.

Everything mechanical is a script. An agent runs only where judgement is needed: deciding which tests matter, writing tests the change lacks, reading the screenshot, and writing the report in the register the project expects.

This is a Terasology initiative first. The proactive-PR need is there, not on the owner's other repositories, and the end state is public: a rapid first response for newer contributors, so a PR has a built, tested, booted verdict before a maintainer has had time to look. It starts with the owner and one other core contributor as the people who can vouch for a PR, and grows from there.

## Vocabulary

| Term | Meaning |
|---|---|
| **Naust** | Old Norse for a boathouse, where ships are drawn up between voyages. The component that keeps the bays and runs jobs through them. Project-agnostic: it knows that a bay is a yggdrasil workspace and drives it through `ws`. |
| **Bay** | A child workspace under `bays/<name>/` in the owner's yggdrasil workspace: a complete clone of yggdrasil with its own realm checkout, components, nested modules and warmed Gradle cache. Made and reset by `ws bay`; a human can use one for a parallel session, naust uses them for jobs. Reset to base between jobs, never recreated. |
| **Job** | One PR, later one PR plus its linked PRs, run through one bay. |
| **Profile** | A per-component file in the realm saying what a job does for that component. The Terasology profile names **Gooey** as its persona, the name the work appears under in reports and comments. |
| **Nod** | A maintainer's review on a PR, an Approve or a review saying *ok to test*, which admits exactly the commit GitHub recorded the review against. |
| **Tick** | One scheduler-driven run of naust: poll, enqueue, run at most one job, exit. |

## Scope

Phase 1 delivers, on the Dionysus Windows machine with two bays:

1. In yggdrasil: `bays/` and the `ws bay` verbs that make, list, reset and drive a child workspace, and `ws checkout <target> --cr <N>` (`--pr` and `--mr` as aliases) so a change request's head can be fetched into any component or nested module.
2. The naust component: configuration, the bay states, the tick, the trust gate, the job runner, the report.
3. In this realm: the Terasology profile, the trust list, a `provision:` block in the Terasology adapter, the smoke-boot script and the seed-manifest template, to move to the Terasology realm when that exists.

Phase 2 adds the judgement step (a fresh `claude -p` per job). Phase 3 covers everything trust-scaled or multi-host. Section *Phases* has the split; section *Not in scope* has what is deliberately absent.

## Shape

```text
 GitHub ──poll──► naust tick ──► queue ──► bay runner ─────────────► report
                    │                        │                         │
            trust list / review nod    reset bay, fetch PR,     .outputs/ in the bay,
            gate decides whether       build, scoped tests on   Discord webhook,
            a job may run              PR and base, headless    optional PR comment
                                       boot, windowed boot +
                                       screenshot, clean-tree
                                              │
                                       claude -p (Phase 2):
                                       scope check, extra tests,
                                       read screenshot, prose
```

**Tick, not daemon.** Naust is a script the operating system's scheduler runs every few minutes: Task Scheduler on Windows (*run only when user is logged on*, so a desktop session exists for the game window), a systemd timer on Linux, launchd on macOS. A tick takes a lock, polls, enqueues, runs at most one job to completion, and exits. The scheduler provides always-on for free on all three OSes, the lock prevents overlap, and there is no long-lived process to drift. gdd-sandbox documents what a long-lived session does over time, and a tick-based design never has one.

**One job at a time per host.** A job holds the CPU, the GPU and the display for up to an hour. Several bays on one host exist so that one can hold a finished job for a human while another is being worked, not so that two jobs run at once.

## Decisions

### Placement: three homes, one new repository

- **yggdrasil** gets `bays/`, a top-level directory beside `components/`, `realms/` and `hoards/` and gitignored the same way; the `ws bay` verbs (`add`, `list`, `reset`, `dir`, `exec`, `rm`); and `ws checkout <target> --cr <N>`. A bay is a workspace, and `ws` is what manages the directories under its root. The verbs are mechanics a human uses at a keyboard with no PR in sight: a second workspace for a parallel session, brought back to base, driven without a `cd`. Fetching a change request's head into a component is the same kind of thing.
- **`naust`**, a new SiliconSaga component, `tier: supporting` in `ecosystem.yaml` beside gdd-sandbox, holds `naust tick`, `naust run`, the trust gate, the queue, the job runner, the report, and the bay *states* (`free busy ready held broken`), with `naust bay add` and `naust bay reset` as the profile's hooks wrapped around `ws bay`. A long-running operational tool with its own release cadence, the same reasoning that gave gdd-sandbox its own repo. Bash, like `ws` and gdd-sandbox; Git Bash on Windows.
- **This realm**, until the Terasology realm exists, holds `naust/terasology.yaml` (the profile), `naust/trust.yaml`, a `provision:` block in `adapters/terasology.yaml`, and `terasology/pr-smoke.sh` with the seed-manifest template beside `clear-module-logback.sh`. Project knowledge is realm content already: adapters say how to build and test, skills say how to review. The adapter now also says how to provision and reset the component's tree; the profile adds only what none of those say. The Terasology-dedicated realm that `terasology-agentic-next` plans is the config's long-term home, and it is all the Terasology-side repository this needs.

gdd-sandbox is unchanged in Phases 1 and 2.

**Where the line between `ws` and naust runs.** `ws` owns workspace shape: what lives under the root and how to bring it to a known state. Naust owns behaviour over time: ticks, the queue, the gate, jobs, and what state a bay is in. gdd-sandbox sits on the naust side of that line today, since a container is not a directory under the root; if sandboxes ever become workspace shape, a `ws sandbox` verb is its own design, and it would look at sandbox flavours (NVIDIA OpenShell among them) at the same time. The ken-site sandbox is a tenant that holds its own workspace, the bay inside the sandbox so to speak, and stays as it is.

**Why not one thing.** The bay machinery is the same for every project the owner polls; the Terasology job differs from a Jekyll site's job in which commands run and what a smoke test means, and that difference is exactly what realm adapters and profiles already express. Folding the daemon into the realm would make the realm a program; folding Terasology knowledge into naust would make naust a Terasology tool.

**Why no Terasology-org repository.** What the community needs to see, the bot identity, the nod convention, a README for contributors, is realm content too, and the planned Terasology realm is where a contributor running GDD would already look. A separate repository would hold a profile and a README and nothing else.

**Provisioning needs no configuration by default.** The adapter's `provision:` block is optional: `init` (a command run after the clone), `runtime_dirs` (what a reset deletes by name), `known_dirt` (what the clean-tree check names as known), and `remote` and `branch` for a component with several remotes. A component without the block is cloned and reset with git alone. Terasology is the only component in GDD today with a tree complex enough to need all of it; a smaller project that ever reaches this volume of PRs gets a bay for the price of a `ws bay add`.

### Bays

**Layout.** Bays are children of the operator's workspace, under a `bays/` directory that yggdrasil ignores the way it ignores `components/` and `realms/`:

```text
D:/Dev/GitWS/yggdrasil/              # the operator's workspace
├── bays/                            # gitignored; only .gitkeep is tracked
│   ├── .naust/
│   │   ├── naust.yaml               # machine-local: profiles to watch, lock age
│   │   ├── state/                   # lock, queue, seen heads, bay states, job copies, tick log
│   │   └── gradle-home/             # shared GRADLE_USER_HOME for every bay
│   ├── bay-1/                       # a complete workspace: its own realm, components/terasology, modules
│   └── bay-2/
├── components/naust/                # naust runs from here
└── realms/realm-siliconsaga/naust/  # the profile and the trust list naust reads
```

The operator's own workspace is never a bay. Naust reads profiles and the trust list from the parent's realm checkout, so they are versioned in the realm and edited where the owner already works; secrets come from the parent's `.env`, and a bay holds none. A bay is linked to its parent by reading, not by symlinks or junctions, which behave differently on every OS and would let a bay dirty the parent: each bay has its own realm clone, pulled on every reset, and its own `ecosystem.local.yaml` with the parent's identity and a machine name of its own.

**A bay is a workspace first.** `ws bay add <name> [--with <component>]… [--realm <name>] [--hoard <url>]` is the generic verb; `naust bay add <name> --profile terasology` calls it with the profile's component and then warms the bay. A human uses the same verb for a parallel session: a second session in a bay runs on its own copy of the `ws` scripts, so hacking on GDD in one session cannot break the other, and `--hoard` clones a hoard into it with the bay's own `machine:` name (`Dionysus-bay-1`), so two workspaces sharing one hoard never collide on a Thalamus file. Naust's bays carry no hoard and no Thalamus: a bay is reset often, and what a job learns goes into its report; anything worth keeping across jobs goes into the realm profile or the owner's own Thalamus, placed there by a person, which is the line gdd-sandbox draws too.

**Provisioning** (`naust bay add bay-1 --profile terasology`): `ws bay add` clones yggdrasil from the parent's remote (or `--from`), writes the bay's `ecosystem.local.yaml`, clones the realm from the parent's realm remote and trusts it inside the bay, runs `ws clone terasology` in the bay, then the adapter's `provision.init` (`groovyw module init omega`) in the component. Naust then runs one `ws build terasology` and one unqualified compile to warm the shared Gradle cache, generates the smoke-boot seed manifest from the modules now present into the bay's `.tmp/naust/seed/`, and resets. A cold provision is tens of minutes, once per bay.

**Reset** (`naust bay reset bay-1`, which is `ws bay reset bay-1` plus the profile's `after_reset` hook), before every job: for the bay's own root, its realm, the engine and every nested module the adapter declares, fetch, hard-reset, switch to the remote's default branch, and `git clean -fd`; then the adapter's `provision.runtime_dirs` (`logs`, `saves`, `terasology-server`) and the previous job's `.outputs/naust` are removed explicitly. That sweeps the harness's `logback-test.xml` copies and anything a previous job wrote while keeping `build/` and `.gradle/`, so compiles stay incremental across jobs; `--deep` is the `-fdx` form for a cold start, applied to component and nested repositories only, never to the bay's root or realm, whose ignored paths are the clones themselves. Every repository must then report clean, or the bay is marked `broken` and the job is not run. The dependency cache survives too; it is outside every repository.

**Reaching into a bay.** Everything that runs inside a bay goes through `ws bay exec <name> <verb…>`, which runs the bay's own `scripts/ws` from the bay with the parent's roots unset: `ws` honours a pre-set `ROOT_DIR` and exports `ECOSYSTEM_LOCAL`, so a bay driven any other way would build and reset the parent.

**States.**

| State | Meaning | Leaves it when |
|---|---|---|
| `free` | reset and idle | a job claims it |
| `busy` | a job is running | the job ends |
| `ready` | holding a finished job for a human | `naust bay release`, or the profile's `ready_ttl_days` (default 7) elapses |
| `held` | a human is working in it | `naust bay release` |
| `broken` | reset or provisioning failed | an operator fixes it and resets |

A `ready` bay is never reused by the tick. A human never finds their bay reset under them.

**Module set.** A bay carries the full Omega set. With a warm Gradle cache the cost of ~144 subprojects is configuration time, not build time, and a bay that holds every module can compile every module, which is a check in its own right (step 5 below). What stays scoped is the tests: the adapter's own comment warns that an unqualified test run across the whole set answers the wrong question, so the job never runs more than the scope in step 3 plus the profile's fallback task. A reset touches every nested repository; fetches run in parallel and the reset is reported as one duration so a slow one shows up.

**Operating system.** A bay's OS is its host's. Phase 1 has Windows bays on Dionysus. Running one PR across hosts of different OSes is Phase 3, and it is the same job on a bay elsewhere, not a new mechanism.

### Events: polling, and the tick

Phase 1 polls. It works for any public repository without admin rights, needs no inbound endpoint, and at hobby scale a few minutes of latency costs nothing. Hookdeck or a GitHub webhook is a Phase 3 upgrade if the latency ever matters, and a cloud routine is a possible triage tier that never touches the home machine.

A tick, for each repository the profile watches:

1. `gh pr list --json number,headRefOid,baseRefName,author,headRepositoryOwner,headRepository,isDraft,updatedAt`, compared with the seen state under `bays/.naust/state/seen/`. (`author_association` is not among the fields `gh pr list` offers; it is on the REST object at `gh api repos/<o>/<r>/pulls/<n>`, and the gate below does not need it.)
2. A PR whose head changed is a candidate. Drafts are skipped; `naust run` runs one by hand. A candidate whose head changed less than `debounce_minutes` ago (default 10) waits for the next tick, so a burst of pushes yields one job on the last head.
3. The trust gate (next section) decides whether the candidate becomes a job or a notice.
4. If the queue has a job and a `free` bay with the right profile exists, the tick runs that job to completion and exits. A job already queued for the same PR is replaced by the newer head; a job already running finishes, and the newer head queues behind it.

`naust run terasology 5400 [--with terasology/modules/Health#12] [--bay bay-2]` enqueues by hand with priority. It skips the debounce, not the trust gate.

### The trust gate

PR code runs on the host the moment Gradle configures the build: a `build.gradle.kts` is code, and so is every test. In Phases 1 and 2 there is no isolated tier, so the gate is the only protection, and an ungated PR never runs.

`naust/trust.yaml` in the realm:

```yaml
terasology:
  maintainers: [Cervator, …]        # may nod, and their own PRs run without one
  trusted: [SiliconSaga/Terasology] # logins or head repositories whose PRs run without a nod
  nod_phrase: "ok to test"          # in a review's text; an Approve needs no phrase
```

| Author | What happens |
|---|---|
| in `maintainers` or `trusted`, by login or by head repository | the job runs |
| anyone else | no bay. Naust posts a notice to Discord: *PR #N at abc1234 by @x needs a nod.* A maintainer reviews the PR from any device with GitHub, an Approve or a review saying *ok to test*, and the next tick runs it. |

**A nod is a review, and a review names its commit.** GitHub records the head every review was submitted against (`commit.oid` on each entry of `gh pr view <n> --json reviews`), server side, where neither the author nor the reviewer can edit it. The gate reads the PR's reviews and accepts one as a nod only when its author is a login in `maintainers`, it is not dismissed, it is an Approve or its text contains the phrase, and its commit is the head about to run. A push after the nod needs a new nod, which costs the maintainer one click, and the job itself stops at checkout unless the head it fetched is the head the gate admitted. Labels are not nods: a label cannot say which commit it meant, so a nod given on one head would admit whatever was pushed after it. Reviews from outside the list, and a maintainer's reviews on older commits, are named in the gate's reason so the Discord notice says why a PR still waits. The review form is visible to the author, and it is one click more than the Jenkins comment this project's contributors know.

Discord-driven approval, where a maintainer's reply in a channel becomes the nod, is Phase 3; it needs a listening session, which gdd-sandbox already has the shape of. A container bay for untrusted PRs, so that a newcomer's first PR builds, tests and boots headless with no nod at all, is also Phase 3, and it is what turns this into the public rapid first response the owner wants. Until then a maintainer nod is the price of a bay.

### The job, step by step

The runner follows the `terasology-review` skill's checks in order, because they are already the right order. Every build, test and run command goes through the realm adapter via `ws`, so the profile never restates them.

| Step | What | Lands in `.outputs/naust/<job>/` |
|---|---|---|
| 1 | Claim the bay, `naust bay reset` (which is `ws bay reset` plus the profile's hook) | `reset.log` |
| 2 | `ws checkout terasology --cr N` through `ws bay exec`, plus `--with` targets for nested modules. Record head SHA, base branch, merge-base. Stop here, and say so in the report, unless the fetched head is the head the gate admitted. | `job.yaml` |
| 3 | Three-dot diff from the merge-base; file list. Mechanical scope: test classes that changed, plus every test class in a subproject whose main sources changed. The profile's `tests:` fallback (`ws test terasology`, the Jenkins `unitTest` stage) applies when the scope is empty. Classes carrying `@Tag("MteTest")` or `TteTest` are routed to `--task integrationTest`. | `diff.txt`, `scope.txt` |
| 4 | Baseline: check out the merge-base, run the same scope, keep the XML reports. The skill's check 2, and the only honest way to tell a PR's failure from an inherited one. | `baseline/` |
| 5 | Back on the PR head: `ws build terasology`, then the profile's `compile_all` command (`./gradlew compileJava`, unqualified on purpose, so every module in the Omega set compiles against the PR's engine), then the scoped `ws test terasology …` runs. Verdicts come from the XML reports, not the exit code. A module that stops compiling is a finding against the PR even when the engine's own tests pass. | `build.log`, `compile-all.log`, `reports/` |
| 6 | Headless pre-flight: the facade's `server` task (`--headless`, home directory `terasology-server/` inside the bay) boots the engine and loads a world with no window and no seed, since headless setup builds its own manifest from the default module selection when no save exists. Wait for `NetworkSystemImpl - Server started`, then stop it. | `headless.log` |
| 7 | Windowed smoke boot, section below. | `smoke.log`, `screenshot.png` |
| 8 | Clean-tree check over the engine and every nested module. Dirt the adapter's `provision.known_dirt` names (harness `logback-test.xml`, natives, case-variant asset pairs) is reported as known; anything else is listed as unexpected. | `tree.txt` |
| 9 | Report. Bay to `ready`. | `report.md` |

A failed step does not stop the job unless a later step depends on it (no build, no boot). The report says which steps ran, and a step that could not run is reported as not run, never as passed.

### The windowed smoke boot

This is the check the review skill says needs a human today: *a green build is not a working game*. It stays scripted, with no agent driving the UI.

- The command is the facade's `game` Gradle task with extra arguments: `./gradlew game --args="--create-last-game --no-splash --no-crash-report --no-save-games"`. `RunTerasology` extends `JavaExec`, so `--args` passes through.
- **The bay is its own home directory.** The `game` task unconditionally adds `--homedir=.`, so the game reads and writes inside the bay's engine tree exactly as it does for a developer at a keyboard. Nothing points it anywhere else, and the reset removes what it wrote by name: `logs`, `saves` and `terasology-server` are the adapter's `provision.runtime_dirs`, deleted explicitly because the ordinary `git clean -fd` leaves ignored files alone.
- `--create-last-game` needs a *latest game manifest* to exist; without one the facade logs *last game not found* and exits. A save is listed when its directory under `saves/` holds a `manifest.json` with a non-empty title; nothing else in the directory is read. The manifest names the world generator and every module with a version, so the realm ships a template and `naust bay add` fills the versions from the bay's own `module.txt` files and the engine, keeping the result in the bay's `.tmp/naust/seed/`; the runner copies it to `saves/naust-seed/manifest.json` after every reset. The flag then creates a fresh *New Created …* world from it each run, and `--no-save-games` keeps the run from writing one back. The seed names `CoreSampleGameplay` and its dependencies, the smallest set that produces a playable world.
- Readiness comes from the existing log. The facade's logback sifts by phase, so a run's log directory gains `Terasology-init.log`, then `Terasology-menu.log`, then `Terasology-<game title>.log` the moment a world starts loading. Inside that file, a real run on this machine shows `InitialiseWorld - World seed:` when the world loads, `WorldRendererImpl - Initialising rendering class` about six seconds later when the renderer is up on the GPU, and chunk-processing lines and `MusicDirectorImpl - Starting to play` about thirty seconds after that once the world is ticking. The runner waits for the renderer line, then the profile's `settle_seconds` (default 45), screenshots the primary display with the OS tool (PowerShell `CopyFromScreen` on Windows, `import` or `gnome-screenshot` on Linux, `screencapture` on macOS) and stops the process. Nothing at `info` marks the in-game state exactly; the renderer line plus a settle is close enough, and the whole game log is kept.
- The window needs a logged-in, unlocked desktop session on a GPU. On Windows that means the scheduled task runs as the logged-on user, which the owner has said they can provide. A `broken` desktop (locked screen, no GPU) shows up as a black or missing screenshot and is reported as such.

### Judgement (Phase 2)

A fresh `claude -p` per job, run from the bay's yggdrasil root so `AGENTS.md`, the hook, the realm and its skills load as in any GDD session:

- `--bare`, `--permission-mode auto`, `--allowedTools` limited to the `ws` verbs plus Read, Grep and Edit, `--output-format json`, `CLAUDE_CODE_OAUTH_TOKEN` as gdd-sandbox does, never an API key.
- `GDD_SANDBOX=terasology`, so a hook prompt becomes a refusal with a reason rather than a card nobody can answer.
- The brief carries the job directory, the diff, the reports, the screenshot path, and names the `terasology-review` and `terasology-testing` skills. It asks for: a check that the mechanical scope missed nothing, naming extra classes for naust to run; proof that the changed code path is reached (the skill's check 4); when the change lacks coverage, new tests on a scratch branch `naust/pr-N-tests` in the bay, run, never pushed; a reading of the screenshot; and the report's prose in the `oss-wide` register.
- One session per job, clean context, no `--continue`. `judgement.max_per_day` in the profile caps the spend; the debounce already collapses push bursts.

The sub-agent onboarding conventions apply (own co-author identity file, `ws orient` first), since this is a sub-agent with nobody watching.

### Report delivery and the human handoff

- **In the bay:** `.outputs/naust/<job>/report.md` plus everything in the table above. `.outputs/` is the existing convention for generated artifacts and `ws clean` already covers it.
- **Discord:** an outbound webhook posts the summary and the bay name. No bot, no session, no inbound anything. Optional, and the only Discord piece in Phase 1.
- **On the PR:** `ws review comment` posts the report with the GDD banner prepended, under the machine account, in the `oss-wide` register: what was observed, what decision it needs, no characterisation of the contribution. On for Terasology from the first job; the owner's call is that GDD posting in that register is welcome there, and the audience to start is the owner plus one core contributor. `report.comment: on|off` stays in the profile for any other repository.
- **Jenkins:** `ws review checks` state is quoted in the report. Naust does not wait for Jenkins and does not try to replace it; a local run that disagrees with Jenkins is itself a finding.
- **The human:** opens the bay, reads the report, runs `ws run terasology` and plays, decides, merges on GitHub, then `naust bay release`. The report ends with a *what needs a human* list so the first thing they read is the thing only they can do.

### Security

- The machine account's fine-grained PAT has `pull-requests: write` only on repositories where `report.comment` is on, and nothing on the rest. It reaches `gh` only in naust's own process, for polling, the gate and the report's comment; the job unsets it before anything the PR controls runs, which is Gradle, the tests, both boots and every profile script, and hands it back only to the two `ws review` calls of the report step. Fetching a public PR head needs no token at all. Personal tokens never reach a bay by environment.
- The filesystem is not a boundary in Phase 1: a bay sits under the workspace whose `.env` holds the operator's own tokens, and code with a shell can walk up two directories. Moving the machine account's token to another file, or to gh's keyring, would not change that: everything in a job runs as the operator's own account, and any credential store that account can read, including gh's (`gh auth token` prints it), a Gradle script can read too. What bounds the damage is the token's scope, pull-requests: write on one repository, and what prevents it is the gate: nothing runs without a maintainer's review of that exact commit. The container tier is Phase 3's first item because it is the only thing that makes the filesystem a boundary.
- The Claude token is the OAuth token, stored where gdd-sandbox stores its own, never in a bay.
- The Discord webhook URL is a secret: anyone holding it can post to the channel.
- The scheduled task runs as the logged-on user and the workspace is that user's. Nothing in a bay is privileged.
- Trusted-only execution on the host until a container tier exists. A nod is a human saying *I read this diff*; as a review it is visible to the author and bound to the commit they read, and nothing pushed after it runs without another.

## Phases

**Phase 1 — bays and the mechanical job.** yggdrasil: `bays/`, the `ws bay` verbs, `ws checkout --cr`. naust: `naust.yaml`, the bay states with `bay add` and `bay reset` over `ws bay`, `tick` with poll, debounce and the review-bound trust gate, the runner's nine steps, the report, the PR comment, the Discord webhook. Realm: the Terasology profile, `trust.yaml`, the adapter's `provision:` block, `pr-smoke.sh` and the seed-manifest template. Dionysus: the scheduled task and two bays. Done when a maintainer's PR to MovingBlocks/Terasology lands in a `ready` bay with build, compile-all and test reports, a headless log and a screenshot, and its report is on the PR, with nobody touching a keyboard.

**Phase 2 — judgement.** The `claude -p` step, the scope check loop, scratch-branch tests, report prose, and the `report.comment` switch with its first use on a SiliconSaga repository.

**Phase 3 — trust-scaled and multi-host.** A container bay from a Java flavour of the gdd-sandbox image, with the workspace on a volume, so untrusted PRs build, test and boot headless without a nod and without touching the host. Discord-driven approval through a listening session. Bays on Linux and macOS hosts, with `naust run … --host` to run one PR across OSes. Linked engine and module PRs, by a PR-body convention or the parked BOM thinking in `bom-architecture.md`. Hookdeck or a webhook if polling latency ever matters.

## Decisions from the owner's review (2026-10-08)

1. **Names.** `naust` for the component; Gooey as the persona in the Terasology profile; no Terasology-org repository, the planned Terasology realm holds the config.
2. **Commenting upstream.** On from the first job, as GDD in the `oss-wide` register.
3. **Module set.** Omega in every bay, scoped tests, and a compile of every module as its own step.
4. **The seed save.** A manifest template in the realm, versions filled from the bay at provisioning. Confirmed by reading the engine: a directory under `saves/` with a titled `manifest.json` is a save.
5. **The in-game marker.** Use what the log already says: the renderer line, then a settle. No upstream change needed.
6. **Nods.** Trust is a list of maintainers, and a nod counts only when a maintainer gave it.

## Decisions from the owner's second review (2026-10-08)

The first review's placement put bays outside any workspace and nods on labels; CodeRabbit's review of the design found the label gap, and the owner's questions about where bays live reopened the placement. Both changed.

7. **Bays live under `bays/` in the workspace**, as independent clones; naust's state lives in `bays/.naust/`. The earlier "siblings outside any workspace" layout is gone, and with it the argument against `ws bay` verbs.
8. **`ws bay` is a yggdrasil verb** and naust keeps the states and the jobs. The line: `ws` owns workspace shape, naust owns behaviour over time. gdd-sandbox stays independent for now; a `ws sandbox` verb, if sandboxes ever become workspace shape, is a separate design that would weigh sandbox flavours at the same time.
9. **Nods are reviews bound to a commit.** The `ok-to-test` label is gone. A maintainer's Approve, or a review saying *ok to test*, admits the commit GitHub recorded it against and nothing after it; the job verifies the head it fetched before building.
10. **The adapter's `provision:` block**, optional with sensible defaults, so a component without one is provisioned with git alone.
11. **`--cr` is the flag**, with `--pr` and `--mr` as aliases, and the ref follows the remote's provider.
12. **Hoards in bays.** A bay may carry a hoard (`ws bay add --hoard <url>`), with its own `machine:` name so Thalamus files never collide; the `machine:` override in `ecosystem.local.yaml` already existed and is what makes several workspaces on one host workable. Naust's bays carry none.
13. **Multi-realm and the Terasology realm split** are a sibling effort under `terasology-agentic-next`, not part of this plan. The profile and trust list move to that realm when it exists; nothing here depends on multi-realm support landing first.

Still to verify in Phase 1's first run rather than on paper: that a Task Scheduler job running as the logged-on user opens a GPU window, that a generated seed manifest loads on a fresh bay, and that `ws realm use --trust` runs non-interactively inside `ws bay add`.

## Not in scope

- An agent driving the game's UI. Computer use in the CLI is macOS-only, interactive-only and blocked under `-p`; the scripted boot plus a screenshot is the attended-free version of the check, and playing the change stays human.
- Replacing Jenkins, or waiting on it.
- Merging, releasing, or any write to a PR beyond a comment.
- A long-lived chat session as the control plane. Discord is an outbound notice in Phase 1 and an approval surface in Phase 3, not where jobs are run from.
- GitHub Actions on a self-hosted runner. Fork PRs executing on the owner's machine is the case GitHub itself warns against, and the trust gate here does the same job without exposing a runner.
- Multi-realm support in `ws`, and splitting a Terasology realm out of SiliconSaga. A sibling effort; this design's realm content moves there when it exists.
- A `ws sandbox` verb, or retrofitting gdd-sandbox onto bays. A sandbox holds its own workspace inside a container; it is distinct enough to stay as it is until it is not.
