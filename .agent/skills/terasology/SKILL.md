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
| Write or debug a test | `docs/Engine-Testing-Patterns.md` + skill `terasology-testing` | `ws test terasology <ClassName>` |
| Raise log level in a test | *no doc* — see [gaps](../../../docs/terasology-doc-status.md#gaps) | `./gradlew :engine-tests:test -DlogOverrideLevel=debug`, then read `build/reports/tests/` |
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

## Facts with no documentation home

Each of these is a pending upstream doc PR, tracked in [gaps](../../../docs/terasology-doc-status.md#gaps).

- **`gradlew game` writes into the repo root.** `RunTerasology.initConfig()` unconditionally adds `--homedir=.`. `:facades:PC:run` is a stock `application`-plugin task and does not.
- **Gradle is 9.6.1** (`gradle/wrapper/gradle-wrapper.properties`) **and Java is 17** (asserted in `build.gradle.kts`). Only `Contributor-Quick-Start.md` states the Java version; nothing states Gradle. Read the two files rather than trusting these numbers — that is the point of naming them.
- **`engine-tests` has more than `test`** — also `unitTest`, `integrationTest`, `integrationTestFlaky`, `integrationTestDiagnostic`, `filesystemSideEffectTest`. `test` excludes the `filesystemSideEffects` and `diagnostic` tags.
- **`modules/` is gitignored.** Gitignore-aware search finds nothing there; use plain `grep -r`.
- **Module repos are nested gits `ws` cannot address.** Module-level commits need raw git or `ws hook-bypass`.
- **`Modules.md` is a stale snapshot.** Read `modules/*/module.txt` for what is actually present.

## Where examples live

Prefer the tutorial repositories over doc snippets — they compile against the engine and break visibly when it drifts, which wiki snippets do not (rule 4). `TutorialAssetSystem`, `TutorialEntitySystem`, `TutorialEventsInteractions`, `TutorialI18n`, `TutorialMultiplayerExtras`, `TutorialNui`, `TutorialWorldGeneration` — all under the `Terasology` GitHub org.
