---
name: terasology
description: Use when working on the Terasology engine, its facades, or any module under components/terasology — reviewing a PR, writing or debugging a test, running the game to validate a change, or looking for which documentation covers something.
---

# Terasology

Terasology is a mega-workspace: an engine, facades, `libs/`, and ~144 independent module git repositories nested under `modules/`. Rows point at upstream documentation where it exists; where none does, the gap is tracked in [`terasology-doc-status.md`](../../../docs/terasology-doc-status.md), which also carries the corrections for docs that are wrong — see [`agent-doc-layering.md`](../../../docs/agent-doc-layering.md) rules 2 and 3. This is a router; one section below explains rather than routes — the facts with no documentation home — for the same reason the triage doc exists: there is no upstream page to point at yet. It leaves as upstream docs are written. The review procedure is its own skill, `terasology-review`.

## When to Use

- Reviewing or validating a Terasology PR, engine or module
- Writing or debugging engine tests or MTE integration tests
- Running the game to check a change
- Looking for which doc covers a topic, or whether one exists

## Orient first

- `./groovyw usage` — prints the workspace CLI's own reference. Item verbs take a type first (`groovyw module get <Name>`; types are `module`/`meta`/`lib`/`facade`), while `usage` and a few other global verbs take none
- `ws test terasology --help` — what the adapter actually runs, before you run it

## Routing

A ⚠ means [`terasology-doc-status.md`](../../../docs/terasology-doc-status.md) records something to read before trusting the row — usually a specific way the doc is wrong, occasionally a doc that is accurate while the code has not caught up with it. The annotation lives there and only there, so it stays in one place as it changes.

Paths in the Read column, and in the facts below, are relative to the component root — `components/terasology/` from the workspace root. This matches how the adapter interprets its own `ai_context` entries.

| I need to… | Read | Run |
|---|---|---|
| Orient in the multi-repo workspace | `docs/Multi-Repo-Workspace.md` ⚠ | `./groovyw usage` |
| Fetch modules | `docs/Contributor-Quick-Start.md` | `./groovyw module init omega` |
| Review a PR | `docs/How-to-Work-on-a-PR-Efficiently.mediawiki` + skill `terasology-review` | `ws review terasology <cr#>` |
| Write or debug a test | `docs/Engine-Testing-Patterns.md` + skill `terasology-testing` | `ws test terasology <ClassName>` |
| Raise log level in a test | *no doc* — see [gaps](../../../docs/terasology-doc-status.md#gaps) | `./gradlew :engine-tests:test -DlogOverrideLevel=debug`, then read `engine-tests/build/reports/tests/test/` |
| Run the game | `docs/Playing.md` ⚠, `facades/PC/README.md` | `./gradlew :facades:PC:run` |
| Run headless as a pre-flight | `docs/Setup-a-headless-server.md` ⚠ | `./gradlew :facades:PC:server` |
| Write an event handler or system | `docs/Events-and-Systems.md` ⚠⚠ | — |
| Name and shape a new event type | `docs/Event-Types.md` ⚠ | — |
| Understand the ECS model | `docs/Entity-System-Architecture.md` ⚠ | — |
| Replicate state over the network | `docs/Entities-Components-and-Events-on-the-Network.md` | — |
| Declare module dependencies | `docs/Module-Dependencies.md`, `docs/Module.txt.md` ⚠ | `./groovyw module createDependencyDotFile <Module>` |
| Work with the sandbox / `@API` | `docs/Module-Security.md` | — |
| Define blocks or assets | `docs/Block-Definitions.md`, `docs/Interactive-Blocks.md` ⚠ | — |
| Add a console command | `docs/Developing-Commands.md` | — |
| Do concurrency or scheduling | `docs/5.3-Migrating-to-Project-Reactor.md` ⚠ | — |
| Serialize types | `docs/Serialization-Overview.md` ⚠ | — |
| Match code style | `docs/Code-Conventions.md` | — |
| Fork, branch, open a PR | `docs/Dealing-with-Forks.md`, `docs/How-to-Work-on-a-PR-Efficiently.mediawiki` | `ws cr terasology <title> <bodyfile>` |

⚠⚠ on `Events-and-Systems.md` is deliberate: code written from that doc **does not compile**. The annotation is not cosmetic.

## Facts with no documentation home

The facts below are the ones that change what you do next, each a pending upstream doc PR. They are a selection, not the whole set — [gaps](../../../docs/terasology-doc-status.md#gaps) is the complete list and the place a new one gets recorded.

- **`gradlew game` writes into the repo root.** `RunTerasology.initConfig()` unconditionally adds `--homedir=.`. `:facades:PC:run` is a stock `application`-plugin task and does not.
- **The toolchain versions live in two files; read them, do not trust a number written here.** Gradle is pinned by `components/terasology/gradle/wrapper/gradle-wrapper.properties` and Java by the assertion in `components/terasology/build.gradle.kts`. An earlier revision of this bullet quoted both values and the Gradle one went stale within a week of being written, which is the whole argument for naming the file instead. Only `Contributor-Quick-Start.md` states the Java version upstream; nothing states Gradle.
- **`engine-tests` has more than `test`** — also `unitTest`, `integrationTest`, `integrationTestFlaky`, `integrationTestDiagnostic`, `filesystemSideEffectTest`. `test` excludes the `filesystemSideEffects` and `diagnostic` tags.
- **`modules/` is gitignored.** Gitignore-aware search finds nothing there; use plain `grep -r`.
- **Module repos are nested gits, addressable as `terasology/modules/<Name>`.** Every repo-touching verb resolves them — `ws checkout terasology/modules/Cooking fix/x -b`, `ws commit`, `ws push`, `ws cr`, and `ws clone-fork` to wire a fork in place. Work happens inside the engine tree, because a module cloned out on its own cannot build.
- **`Modules.md` is a stale snapshot.** Read `modules/*/module.txt` for what is actually present.
- **Some module repos track two spellings of one asset.** `GooeyDefence` had seven such pairs; `ManualLabor` had `CampFire.block` and `Campfire.block`. They cannot coexist on a case-insensitive filesystem, so Windows and macOS check out one and report the other as deleted — which reads as somebody's uncommitted deletion and is nothing of the kind. Verify the blobs are identical, then drop one spelling upstream.
- **A harness build writes into module source trees.** It installs `templates/module.logback-test.xml` as each module's `src/test/resources/logback-test.xml` and `templates/build.gradle` over each module's own. Modules gitignore `build.gradle`, so that copy is invisible; the logback file is not yet ignored everywhere and is the one that shows up as an untracked change. Where a module is meant to differ — `Kallisti` carries a deliberately different `build.gradle` (it supplies JNLua for `KComputers`) — the overwrite destroys intent.
- **Asset JSON is lenient, not RFC 8259.** `UIFormat` and `UISkinFormat` call `JsonReader.setLenient(true)`, and the block and prefab formats go through `Gson.fromJson`, lenient by default. Licence-header comments, inline `//` notes and trailing commas are normal in shipped assets — `CoreAssets` alone has dozens. A strict parser rejects content the engine loads happily.

## Where examples live

Prefer the tutorial repositories over doc snippets — they compile against the engine and break visibly when it drifts, which wiki snippets do not (rule 4). `TutorialAssetSystem`, `TutorialEntitySystem`, `TutorialEventsInteractions`, `TutorialI18n`, `TutorialMultiplayerExtras`, `TutorialNui`, `TutorialWorldGeneration` — all under the `Terasology` GitHub org.
