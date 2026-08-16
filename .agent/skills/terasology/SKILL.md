---
name: terasology
description: Use when working on the Terasology engine, its facades, or any module under components/terasology — reviewing a PR, writing or debugging a test, running the game to validate a change, or looking for which documentation covers something.
---

# Terasology

Terasology is a mega-workspace: an engine, facades, `libs/`, and ~144 independent module git repositories nested under `modules/`. This skill routes; it does not explain. Rows point at upstream documentation where it exists; where none exists, the gap is tracked in [`terasology-doc-status.md`](../../../docs/terasology-doc-status.md), which also carries the corrections for docs that are wrong — see [`agent-doc-layering.md`](../../../docs/agent-doc-layering.md) rules 2 and 3.

## When to Use

- Reviewing or validating a Terasology PR, engine or module
- Writing or debugging engine tests or MTE integration tests
- Running the game to check a change
- Looking for which doc covers a topic, or whether one exists

## Orient first

- `./groovyw usage` — prints the workspace CLI's own reference. Most verbs take a type first (`groovyw module get <Name>`, types being `module`/`meta`/`lib`/`facade`); `usage` is one of the few that stands alone
- `ws test terasology --help` — what the adapter actually runs, before you run it

## Routing

A ⚠ means the doc is wrong in a specific, recorded way — read the row, then [the annotation](../../../docs/terasology-doc-status.md#fix-cheaply) before trusting the doc.

| I need to… | Read | Run |
|---|---|---|
| Orient in the multi-repo workspace | `docs/Multi-Repo-Workspace.md` ⚠ | `./groovyw usage` |
| Fetch modules | `docs/Contributor-Quick-Start.md` | `./groovyw module init omega` |
| Review a PR | `docs/How-to-Work-on-a-PR-Efficiently.mediawiki` + [Reviewing a PR](#reviewing-a-pr) below | `ws review terasology <cr#>` |
| Write or debug a test | `docs/Engine-Testing-Patterns.md` + skill `terasology-testing` | `ws test terasology <ClassName>` |
| Raise log level in a test | *no doc* — see [gaps](../../../docs/terasology-doc-status.md#gaps) | `./gradlew :engine-tests:test -DlogOverrideLevel=debug`, then read `engine-tests/build/reports/tests/test/` |
| Run the game | `docs/Playing.md` ⚠, `facades/PC/README.md` | `./gradlew :facades:PC:run` |
| Run headless as a pre-flight | `docs/Setup-a-headless-server.md` ⚠ | `./gradlew :facades:PC:server` |
| Write an event handler or system | `docs/Events-and-Systems.md` ⚠⚠ | — |
| Name and shape a new event type | `docs/Event-Types.md` | — |
| Understand the ECS model | `docs/Entity-System-Architecture.md` ⚠ | — |
| Replicate state over the network | `docs/Entities-Components-and-Events-on-the-Network.md` | — |
| Declare module dependencies | `docs/Module-Dependencies.md`, `docs/Module.txt.md` ⚠ | `./groovyw module createDependencyDotFile <Module>` |
| Work with the sandbox / `@API` | `docs/Module-Security.md` | — |
| Define blocks or assets | `docs/Block-Definitions.md`, `docs/Interactive-Blocks.md` ⚠ | — |
| Add a console command | `docs/Developing-Commands.md` | — |
| Do concurrency or scheduling | `docs/5.3-Migrating-to-Project-Reactor.md` | — |
| Serialize types | `docs/Serialization-Overview.md` ⚠ | — |
| Match code style | `docs/Code-Conventions.md` | — |
| Fork, branch, open a PR | `docs/Dealing-with-Forks.md`, `docs/How-to-Work-on-a-PR-Efficiently.mediawiki` | `ws cr terasology <title> <bodyfile>` |

⚠⚠ on `Events-and-Systems.md` is deliberate: code written from that doc **does not compile**. The annotation is not cosmetic.

## Reviewing a PR

The order matters more than any single step. Most wrong review conclusions here came from doing these out of order, not from missing knowledge.

1. **Establish the diff honestly.** `git diff develop` on a PR branch shows tip-to-tip drift, not the change — one PR read as 772 deletions that way against a true +15. Use three-dot (`develop...pr`) or `git log develop..pr`; GitHub already renders the merge-base diff correctly. To test against current `develop`, cherry-pick the PR's commits onto a scratch branch rather than testing an old base.

2. **Baseline before blaming the PR.** Re-run the failing command on the *unmodified base* and compare. An identical failure localises the cause to the environment rather than the change. Do this before writing anything: copying CI's own invocation is the correct-looking instinct that produces the wrong conclusion, and the failure mode is telling a contributor they broke something they did not. It also catches the case a known-failures list misses — a genuinely new failure hiding among familiar ones.

3. **Scope the run.** `ws test terasology <ClassName>` resolves the class on disk and scopes to one subproject; a name that does not resolve falls back to a root run across every module test task. Verify the class exists first, and remember `engine-tests` has six test tasks, not one — `test` excludes the `filesystemSideEffects` and `diagnostic` tags.

4. **Prove the code path was reached** before concluding "no error, therefore it works". A silent no-op and a working feature look identical from outside. Absence of a log line is not absence of behaviour either — check the level first, since a DEBUG line missing from an INFO run proves nothing.

5. **A green build is not a working game.** Nothing in CI launches the client, and MTE is headless, so a fully green pipeline is compatible with a game that cannot start. `./gradlew game` is the check that catches it, and it needs a human.

6. **Validate on a clean tree when the change touches generated or native files.** An additive change leaves the old artifacts in place, so every existing checkout keeps working and only a fresh one breaks — which reads as "works on my machine" on every machine that has one.

## Facts with no documentation home

Each of these is a pending upstream doc PR, tracked in [gaps](../../../docs/terasology-doc-status.md#gaps).

- **`gradlew game` writes into the repo root.** `RunTerasology.initConfig()` unconditionally adds `--homedir=.`. `:facades:PC:run` is a stock `application`-plugin task and does not.
- **Gradle is 9.6.1** (`gradle/wrapper/gradle-wrapper.properties`) **and Java is 17** (asserted in `build.gradle.kts`). Only `Contributor-Quick-Start.md` states the Java version; nothing states Gradle. Read the two files rather than trusting these numbers — that is the point of naming them.
- **`engine-tests` has more than `test`** — also `unitTest`, `integrationTest`, `integrationTestFlaky`, `integrationTestDiagnostic`, `filesystemSideEffectTest`. `test` excludes the `filesystemSideEffects` and `diagnostic` tags.
- **`modules/` is gitignored.** Gitignore-aware search finds nothing there; use plain `grep -r`.
- **Module repos are nested gits, addressable as `terasology/modules/<Name>`.** Every repo-touching verb resolves them — `ws checkout terasology/modules/Cooking fix/x -b`, `ws commit`, `ws push`, `ws cr`, and `ws clone-fork` to wire a fork in place. Work happens inside the engine tree, because a module cloned out on its own cannot build.
- **`Modules.md` is a stale snapshot.** Read `modules/*/module.txt` for what is actually present.

## Where examples live

Prefer the tutorial repositories over doc snippets — they compile against the engine and break visibly when it drifts, which wiki snippets do not (rule 4). `TutorialAssetSystem`, `TutorialEntitySystem`, `TutorialEventsInteractions`, `TutorialI18n`, `TutorialMultiplayerExtras`, `TutorialNui`, `TutorialWorldGeneration` — all under the `Terasology` GitHub org.
