# Naust — PR bays: design

**Status:** Reviewed by the owner in conversation on 2026-10-08; the decisions are folded in below and the [Phase 1 plan](2026-10-08-naust-pr-bays-phase1-plan.md) implements them.
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
| **Bay** | One complete, reusable yggdrasil workspace parked on a machine: realm, components, nested modules, warmed Gradle cache. Reset to base between jobs, never recreated. |
| **Job** | One PR, later one PR plus its linked PRs, run through one bay. |
| **Profile** | A per-component file in the realm saying what a job does for that component. The Terasology profile names **Gooey** as its persona, the name the work appears under in reports and comments. |
| **Tick** | One scheduler-driven run of naust: poll, enqueue, run at most one job, exit. |

## Scope

Phase 1 delivers, on the Dionysus Windows machine with two bays:

1. `ws checkout <target> --pr <N>` in yggdrasil, so a PR head can be fetched into any component or nested module.
2. The naust component: configuration, bay provisioning and reset, the tick, the trust gate, the job runner, the report.
3. The Terasology profile, trust list, smoke-boot script and seed-manifest template in this realm, to move to the Terasology realm when that exists.

Phase 2 adds the judgement step (a fresh `claude -p` per job). Phase 3 covers everything trust-scaled or multi-host. Section *Phases* has the split; section *Not in scope* has what is deliberately absent.

## Shape

```text
 GitHub ──poll──► naust tick ──► queue ──► bay runner ─────────────► report
                    │                        │                         │
            trust list / label         reset bay, fetch PR,     .outputs/ in the bay,
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

| Where | What | Why there |
|---|---|---|
| **`naust`**, a new SiliconSaga component, `tier: supporting` in `ecosystem.yaml` beside gdd-sandbox | `naust tick`, `naust bay add`, `naust bay reset`, `naust bay list`, `naust bay release`, `naust run`, the runner, the report | A long-running operational tool with its own release cadence, the same reasoning that gave gdd-sandbox its own repo. Bash, like `ws` and gdd-sandbox; Git Bash on Windows. |
| **yggdrasil** | `ws checkout <target> --pr <N>` | Fetching a PR head into a component or nested module is useful to humans at a keyboard, not only to naust. |
| **this realm**, until the Terasology realm exists | `naust/terasology.yaml` (the profile), `naust/trust.yaml`, `terasology/pr-smoke.sh` and the seed-manifest template beside `clear-module-logback.sh` | Project knowledge is realm content already: adapters say how to build and test, skills say how to review. The profile adds only what those do not say. The Terasology-dedicated realm that `terasology-agentic-next` plans is the config's long-term home, and it is all the Terasology-side repository this needs. |

gdd-sandbox is unchanged in Phases 1 and 2.

**Why not one thing.** The bay machinery is the same for every project the owner polls; the Terasology job differs from a Jekyll site's job in which commands run and what a smoke test means, and that difference is exactly what realm adapters and profiles already express. Folding the daemon into the realm would make the realm a program; folding Terasology knowledge into naust would make naust a Terasology tool.

**Why no Terasology-org repository.** What the community needs to see, the bot identity, the nod convention, a README for contributors, is realm content too, and the planned Terasology realm is where a contributor running GDD would already look. A separate repository would hold a profile and a README and nothing else.

**Why not `ws bay …` verbs.** `ws` operates inside one yggdrasil workspace. Bays are sibling workspaces, and the thing that manages siblings should not be inside one of them.

### Bays

**Layout.** A naust root on each machine, outside any workspace, holds the bays and shared state:

```text
D:/Dev/GitWS/naust/
├── naust.yaml              # machine-local config: workspace, bays root, schedule, webhook
├── state/                  # lock, queue, last-seen PR heads, tick logs
├── gradle-home/            # shared GRADLE_USER_HOME for every bay
└── bays/
    ├── bay-1/
    │   ├── bay.yaml        # state, profile, current job, held-by
    │   └── yggdrasil/      # a complete workspace: realm, components/terasology, modules
    └── bay-2/
```

The operator's own dev workspace is never a bay. Naust reads profiles and the trust list from the realm checkout inside that dev workspace (`workspace:` in `naust.yaml`), so they are versioned in the realm and edited where the owner already works.

**Provisioning** (`naust bay add bay-1 --profile terasology`): clone yggdrasil, `ws realm` the realm and trust it, `ws clone terasology`, fetch the Omega module set, one `ws build terasology` and one unqualified compile to warm the shared Gradle cache, generate the smoke-boot seed manifest from the modules now present, mark `free`. A cold provision is tens of minutes, once per bay.

**Reset** (`naust bay reset bay-1`), before every job: for the engine and every nested module, fetch, hard-reset, switch to the default branch at its remote, and `git clean -fd`; then the profile's runtime directories (`logs`, `saves`, `terasology-server`) and the previous job's `.outputs/naust` are removed explicitly. That sweeps the harness's `logback-test.xml` copies and anything a previous job wrote while keeping `build/` and `.gradle/`, so compiles stay incremental across jobs; `--deep` is the `-fdx` form for a cold start. Every repository must then report clean, or the bay is marked `broken` and the job is not run. The dependency cache survives too; it is outside the workspace.

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

1. `gh pr list --json number,headRefOid,baseRefName,author,headRepositoryOwner,headRepository,isCrossRepository,isDraft,labels,updatedAt`, compared with `state/<repo>.json`. (`author_association` is not among the fields `gh pr list` offers; it is on the REST object at `gh api repos/<o>/<r>/pulls/<n>`, and the gate below does not need it.)
2. A PR whose head changed is a candidate. Drafts are skipped unless labelled. A candidate whose head changed less than `debounce_minutes` ago (default 10) waits for the next tick, so a burst of pushes yields one job on the last head.
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
  nod_label: ok-to-test             # a maintainer's approval, as a label
  nod_phrase: "ok to test"          # or as a comment, the Jenkins convention
```

| Author | What happens |
|---|---|
| in `maintainers` or `trusted`, by login or by head repository | the job runs |
| anyone else | no bay. Naust posts a notice to Discord: *PR #N by @x needs a nod.* A maintainer adds the label or leaves the comment from any device with GitHub, and the next tick runs it. |

**A nod counts only when a maintainer gave it.** GitHub lets only people with triage access or above apply labels, so an author cannot label their own PR unless they already hold that access, and naust does not rely on that alone: it reads the PR's timeline (`gh api repos/<o>/<r>/issues/<n>/events`, where each `labeled` event names its `actor`) and the comments, and accepts the label or the phrase only from a login in `maintainers`. A label an unknown actor managed to apply is ignored and reported. The nod is visible to the author either way, and the comment form is the one Jenkins users of this project already know.

Discord-driven approval, where a maintainer's reply in a channel becomes the nod, is Phase 3; it needs a listening session, which gdd-sandbox already has the shape of. A container bay for untrusted PRs, so that a newcomer's first PR builds, tests and boots headless with no nod at all, is also Phase 3, and it is what turns this into the public rapid first response the owner wants. Until then a maintainer nod is the price of a bay.

### The job, step by step

The runner follows the `terasology-review` skill's checks in order, because they are already the right order. Every build, test and run command goes through the realm adapter via `ws`, so the profile never restates them.

| Step | What | Lands in `.outputs/naust/<job>/` |
|---|---|---|
| 1 | Claim the bay, `naust bay reset` | `bay.log` |
| 2 | `ws checkout terasology --pr N`, plus `--with` targets for nested modules. Record head SHA, base branch, merge-base. | `job.yaml` |
| 3 | Three-dot diff from the merge-base; file list. Mechanical scope: test classes that changed, plus every test class in a subproject whose main sources changed. The profile's `tests:` fallback (`ws test terasology`, the Jenkins `unitTest` stage) applies when the scope is empty. Classes carrying `@Tag("MteTest")` or `TteTest` are routed to `--task integrationTest`. | `diff.txt`, `scope.txt` |
| 4 | Baseline: check out the merge-base, run the same scope, keep the XML reports. The skill's check 2, and the only honest way to tell a PR's failure from an inherited one. | `baseline/` |
| 5 | Back on the PR head: `ws build terasology`, then the profile's `compile_all` command (`./gradlew compileJava`, unqualified on purpose, so every module in the Omega set compiles against the PR's engine), then the scoped `ws test terasology …` runs. Verdicts come from the XML reports, not the exit code. A module that stops compiling is a finding against the PR even when the engine's own tests pass. | `build.log`, `compile-all.log`, `reports/` |
| 6 | Headless pre-flight: the facade's `server` task (`--headless`, home directory `terasology-server/` inside the bay) boots the engine and loads a world with no window and no seed, since headless setup builds its own manifest from the default module selection when no save exists. Wait for `NetworkSystemImpl - Server started`, then stop it. | `headless.log` |
| 7 | Windowed smoke boot, section below. | `smoke.log`, `screenshot.png` |
| 8 | Clean-tree check: `ws status --nested`. Known dirt (harness `logback-test.xml`, natives, case-variant asset pairs) is named as known; anything else is listed. | `tree.txt` |
| 9 | Report. Bay to `ready`. | `report.md` |

A failed step does not stop the job unless a later step depends on it (no build, no boot). The report says which steps ran, and a step that could not run is reported as not run, never as passed.

### The windowed smoke boot

This is the check the review skill says needs a human today: *a green build is not a working game*. It stays scripted, with no agent driving the UI.

- The command is the facade's `game` Gradle task with extra arguments: `./gradlew game --args="--create-last-game --no-splash --no-crash-report --no-save-games"`. `RunTerasology` extends `JavaExec`, so `--args` passes through.
- **The bay is its own home directory.** The `game` task unconditionally adds `--homedir=.`, so the game reads and writes inside the bay's engine tree exactly as it does for a developer at a keyboard. Nothing points it anywhere else, and the reset removes what it wrote by name: `logs`, `saves` and `terasology-server` are the profile's runtime directories, deleted explicitly because the ordinary `git clean -fd` leaves ignored files alone.
- `--create-last-game` needs a *latest game manifest* to exist; without one the facade logs *last game not found* and exits. A save is listed when its directory under `saves/` holds a `manifest.json` with a non-empty title; nothing else in the directory is read. The manifest names the world generator and every module with a version, so the realm ships a template and `naust bay add` fills the versions from the bay's own `module.txt` files and the engine, writing `saves/naust-seed/manifest.json`; the runner copies it back in after every reset. The flag then creates a fresh *New Created …* world from it each run, and `--no-save-games` keeps the run from writing one back. The seed names `CoreSampleGameplay` and its dependencies, the smallest set that produces a playable world.
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

- The machine account's fine-grained PAT has `pull-requests: write` only on repositories where `report.comment` is on, and nothing on the rest. Fetching a public PR head needs no token at all. Personal tokens never reach a bay.
- The Claude token is the OAuth token, stored where gdd-sandbox stores its own, never in a bay.
- The Discord webhook URL is a secret: anyone holding it can post to the channel.
- The scheduled task runs as the logged-on user and the naust root is that user's. Nothing in a bay is privileged.
- Trusted-only execution on the host until a container tier exists. A nod is a human saying *I read this diff*; the label makes that visible to the author.

## Phases

**Phase 1 — bays and the mechanical job.** yggdrasil: `ws checkout --pr`. naust: `naust.yaml`, `bay add|reset|list|release`, `tick` with poll, debounce and the trust gate, the runner's nine steps, the report, the PR comment, the Discord webhook. Realm: the Terasology profile, `trust.yaml`, `pr-smoke.sh` and the seed-manifest template. Dionysus: the scheduled task and two bays. Done when a maintainer's PR to MovingBlocks/Terasology lands in a `ready` bay with build, compile-all and test reports, a headless log and a screenshot, and its report is on the PR, with nobody touching a keyboard.

**Phase 2 — judgement.** The `claude -p` step, the scope check loop, scratch-branch tests, report prose, and the `report.comment` switch with its first use on a SiliconSaga repository.

**Phase 3 — trust-scaled and multi-host.** A container bay from a Java flavour of the gdd-sandbox image, with the workspace on a volume, so untrusted PRs build, test and boot headless without a nod and without touching the host. Discord-driven approval through a listening session. Bays on Linux and macOS hosts, with `naust run … --host` to run one PR across OSes. Linked engine and module PRs, by a PR-body convention or the parked BOM thinking in `bom-architecture.md`. Hookdeck or a webhook if polling latency ever matters.

## Decisions from the owner's review (2026-10-08)

1. **Names.** `naust` for the component; Gooey as the persona in the Terasology profile; no Terasology-org repository, the planned Terasology realm holds the config.
2. **Commenting upstream.** On from the first job, as GDD in the `oss-wide` register.
3. **Module set.** Omega in every bay, scoped tests, and a compile of every module as its own step.
4. **The seed save.** A manifest template in the realm, versions filled from the bay at provisioning. Confirmed by reading the engine: a directory under `saves/` with a titled `manifest.json` is a save.
5. **The in-game marker.** Use what the log already says: the renderer line, then a settle. No upstream change needed.
6. **Nods.** Trust is a list of maintainers, and a nod counts only when a maintainer gave it, checked against the PR timeline.

Still to verify in Phase 1's first run rather than on paper: that a Task Scheduler job running as the logged-on user opens a GPU window, and that a generated seed manifest loads on a fresh bay.

## Not in scope

- An agent driving the game's UI. Computer use in the CLI is macOS-only, interactive-only and blocked under `-p`; the scripted boot plus a screenshot is the attended-free version of the check, and playing the change stays human.
- Replacing Jenkins, or waiting on it.
- Merging, releasing, or any write to a PR beyond a comment.
- A long-lived chat session as the control plane. Discord is an outbound notice in Phase 1 and an approval surface in Phase 3, not where jobs are run from.
- GitHub Actions on a self-hosted runner. Fork PRs executing on the owner's machine is the case GitHub itself warns against, and the trust gate here does the same job without exposing a runner.
