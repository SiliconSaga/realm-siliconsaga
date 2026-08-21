# Terasology Documentation Status

**Surveyed:** 2026-08-01/02, six parallel clusters over every markdown file in `components/terasology/docs/`, with claims spot-checked against current source.

This file is metadata about upstream documentation, not a replacement for any of it. When a doc is wrong, the correction is recorded here as a dated annotation and the upstream fix is the real remedy — see [`agent-doc-layering.md`](agent-doc-layering.md) rule 3.

**This is also the upstream remediation backlog.** Rows leave this file as fixes land in `MovingBlocks/Terasology`. The file shrinking is the progress metric.

**Currency limit:** the *paths* here are checkable; the *claims* are not. `ws orient` renders each adapter `ai_context` pointer and marks unresolvable ones `(MISSING)` — that yggdrasil change has merged, and it caught two dead pointers in this realm's own adapter. `ws orient --check` turns the same computation into an exit code, so a schedule can block on a dead pointer instead of waiting for someone to read the output; that flag ships on the yggdrasil 1.1 branch, and nothing here runs it on a schedule yet. Neither form says whether a doc's *content* is true — a file that exists and is wrong passes both. That is what the survey date above is for.

## Keep and index

Verified current, high value to an agent. These are the routing targets in the `terasology` skill.

| Doc | Covers | Note |
|---|---|---|
| `Engine-Testing-Patterns.md` | MTE integration patterns, `awaitUntil`, singleton hygiene, DI rules | Strongest doc in the corpus; **absent from `_sidebar.md`** |
| `Module-Security.md` | Threat model, permission-check semantics, `@API` vs `@IndexInherited` | Matches `ModuleManager.setupSandbox` |
| `Module-Dependencies.md` | `module.txt` deps, version ranges, dependency dot-file | `groovyw module createDependencyDotFile` verified |
| `Entities-Components-and-Events-on-the-Network.md` | `@Replicate`, `FieldReplicateType`, `NetworkComponent` | Verified verbatim against source |
| `Block-Definitions.md` | Full `.block` JSON property reference | Best asset-authoring reference |
| `Developing-Commands.md` | Writing `@Command` console commands | Understates param types; harmless |
| `Code-Conventions.md` | Style, Checkstyle/PMD, JUnit5, Javadoc | — |
| `Contributor-Quick-Start.md` | Clone, `groovyw module init`, first run | Only doc stating Java 17, and it is correct |
| `5.3-Migrating-to-Project-Reactor.md` | `GameScheduler` and Flux over raw threads | Migration incomplete — `TaskMaster` still in `LocalChunkProvider` |
| `Event-Types.md` | Trigger/notification/collector event taxonomy | Dead links to never-created `Event-Patterns.md`, `Glossary.md` |
| `How-to-Work-on-a-PR-Efficiently.mediawiki` | PR etiquette, small diffs, commit structure | No tooling claims to rot |

## Fix cheaply

Structurally sound, factually wrong in specific ways. Ordered by how badly the error misleads an agent.

| Doc | Correction | Upstream action |
|---|---|---|
| `Events-and-Systems.md` | Documents `@ReceiveEvent(priority=, netFilter=)`; these are now `@Priority` and `@NetFilterEvent`, and the annotation is `org.terasology.gestalt.entitysystem.event.ReceiveEvent` taking only `components()`. **Code written from this doc does not compile.** (2026-08-02) | Rewrite the annotation sections against gestalt |
| `IO-API-for-Modules.md` | Consumer types are labelled backwards; the real API is `readFile(String, Consumer<InputStream>)` / `writeFile(String, Consumer<OutputStream>)` (2026-08-02) | Swap the two signatures |
| `Entity-System-Architecture.md` | No `AbstractEvent`, no `EventHandler` interface; data-type list names `Quat4f`/`Color4f`/`Vector3f`, all removed for JOML. Events/Systems sections duplicate `Events-and-Systems.md` more badly (2026-08-02) | Delete the duplicated sections, fix the type list |
| `Setup-a-headless-server.md` | States Java 11; `build.gradle.kts` asserts 17 (2026-08-02) | One-line version fix |
| `Testing-Modules.md` | Claims Logback 1.2; modules pin `ch.qos.logback:logback-classic:1.6.0`. Omits the JUnit5 `integrationenvironment.jupiter` extension API (2026-08-02) | Version fix plus a pointer to the extension |
| `Multi-Repo-Workspace.md` | Calls the directory `libraries`; on disk and in `settings.gradle.kts` it is `libs` (2026-08-02) | Rename throughout |
| `Playing.md` | Documents trailing `-PworldGen` / `-PextraModules` gradle properties that do not exist. Otherwise the best CLI reference in the corpus — `--homedir`, `--headless`, `--override-default-config` are all accurate (2026-08-02) | Drop the two dead properties |
| `Module.txt.md` | Example depends on the long-gone `Core` module; omits `author`; `isAsset` bullet is mangled into the `isAugmentation` line (2026-08-02) | Fix example and bullets |
| `Serialization-Overview.md` | Code moved to `subsystems/TypeHandlerLibrary`; `AbstractSerializer`/`GsonSerializer`/`ProtobufSerializer` are now `persistence.serializers.Serializer<D>`; all three GitHub deep links point at removed paths (2026-08-02) | Repath links, rename classes |
| `Textures.md`, `Translation-Guide.md` | Asset paths predate the move to `org/terasology/engine/assets/`; block tiles now in CoreAssets (2026-08-02) | Path updates only |
| `Interactive-Blocks.md` | Single snippet mixes `Core:` and `CoreAssets:` tile URIs (2026-08-02) | Fix the snippet |
| `Rendering.md` | Claims OpenGL 2.1 / GLSL 1.2; `LwjglGraphics` requests a 3.3 core profile. Sample says `implements WorldRenderer`, should be `RenderSystem` (2026-08-02) | Version and sample fix |
| `Shape-File-Specifications.md` | The 1.1 section is an unimplemented 2020 proposal; `JsonBlockShapeLoader` still enforces 1.0 (2026-08-02) | Mark 1.1 as proposed, not shipped |
| `Randomness-and-Noise.md` | Names a `FastNoise` class that does not exist; closest are `WhiteNoise`/`DiscreteWhiteNoise`/`NoiseTable` (2026-08-02) | Fix the class list |
| `Troubleshooting-Developer.md` | JDK 11 / AdoptOpenJDK against a required Java 17; stack traces use pre-`core.subsystem` paths (2026-08-02) | Version and path fix |
| `Using-Locally-Developed-Libraries.md` | Cites `settings.gradle` and gestalt 5.1.5; actual files are `.kts` and gestalt is 8.0.1-SNAPSHOT (2026-08-02) | Version and filename fix |

## Archive or delist

Recommend removing from `_sidebar.md` and moving under an `archive/` prefix rather than deleting — they are project history.

| Doc | Why |
|---|---|
| `GCI.md` | Google Code-in discontinued 2019; every task link 404s |
| `Project-Overview.md` | Java applets, Flash, Google+, IRC, forum-as-main-site; superseded by `Codebase-Structure.md` |
| `Why-Terasology.md` | Actively misdescribes the engine (claims 65k biome IDs; no `Biome` type exists) |
| `Markdown-and-Wiki.md` | Documents editing a GitHub wiki that was folded into `docs/`; premise invalid |
| `What-we-learned-as-an-org-attending-Ludicious.mediawiki` | 2018 event retrospective; last `.mediawiki` besides the PR guide |
| `Character-Module.md` | Never-built brainstorm; sample uses removed `Quat4f` |
| `Play-Test-Setup.md` | DigitalOcean/Jenkins-era ops; `run_linux.sh` is not produced by the current dist |

## Gaps

No document covers these at all. Each is a candidate upstream addition, and until one exists the fact lives in the `terasology` skill's "facts with no documentation home" section.

| Gap | Fact |
|---|---|
| Test log levels | `engine-tests/src/test/resources/logback-test.xml` pins `org.terasology` to `${logOverrideLevel:-info}`. Raise with `-DlogOverrideLevel=debug`. `build-logic/src/main/kotlin/terasology-metrics.gradle.kts:69` sets `showStandardStreams = false`, so test output goes to a report directory, not the console. Reports are per-project *and* per-task: `engine-tests/build/reports/tests/test/`, `engine-tests/build/reports/tests/integrationTest/` |
| Gradle version | Wrapper is 9.6.1. No doc states any Gradle version |
| Home directory on gradle runs | `RunTerasology.initConfig()` unconditionally adds `--homedir=.`, so `gradlew game` writes saves and logs into the repo root. `:facades:PC:run` is a stock `application`-plugin task and does not |
| Headless as pre-flight | No doc frames `:facades:PC:server` as a cheap GL-free smoke test before a windowed run |
| Engine-tests task set | `engine-tests/build.gradle.kts` defines `unitTest`, `integrationTest`, `integrationTestFlaky`, `integrationTestDiagnostic`, `filesystemSideEffectTest`; `test` excludes the `filesystemSideEffects` and `diagnostic` tags |
| Module catalogue drift | `Modules.md` lists 176 entries against ~140 on disk. Read `modules/*/module.txt` instead |
| Case-only duplicate filenames | Some module repos track two spellings of one asset — `ManualLabor` had `CampFire.block` and `Campfire.block`; `GooeyDefence` has seven such pairs across `assets/ui/` and `assets/prefabs/`. They cannot coexist on a case-insensitive filesystem, so Windows and macOS check out one and report the other as deleted. It reads as someone's uncommitted deletion and is nothing of the kind; the fix is upstream, dropping one spelling |
| The build harness writes into module source trees | A harness build installs `templates/module.logback-test.xml` as each module's `src/test/resources/logback-test.xml`, and `templates/build.gradle` over each module's own — so most module repos read as dirty afterwards. Mostly noise, except where a module is meant to differ: `Kallisti` carries a deliberately different `build.gradle` (it is half engine extension, supplying JNLua for `KComputers`), so there the overwrite destroys intent rather than adding noise |
| Asset JSON is lenient, not RFC 8259 | `UIFormat` and `UISkinFormat` call `JsonReader.setLenient(true)`, and the block and prefab formats go through `Gson.fromJson`, lenient by default. Licence-header comments, inline `//` notes and trailing commas are normal in shipped assets — `CoreAssets` alone has dozens. A strict parser rejects content the engine loads happily |
| Nothing in CI runs the game | Jenkins builds and tests; no job launches the client. MTE is headless, so `:engine-tests:test` never initializes an LWJGL display. A fully green build is therefore compatible with a game that cannot start at all — `./gradlew game` is the check that catches that, and it is a human's to run |
| Baseline a failure before attributing it | No doc tells a reviewer to re-run a failing command on the unmodified base branch before blaming the PR. Copying CI's own invocation locally is the correct-looking instinct and it is how a reviewer ends up telling a contributor they broke 21 tests that were already failing. Not Terasology-specific, so it may belong in contributor docs rather than engine docs |
| TestFX headless does not work on macOS/aarch64 (TerasologyLauncher) | Copying `JAVA_TOOL_OPTIONS` out of `.github/workflows/push-validation.yml` brings `-Dtestfx.headless=true`, which swaps in Monocle; `openjfx-monocle:17.0.10` ships no macOS/aarch64 native, so 21 of 75 tests die in `FxToolkit.registerPrimaryStage` before any assertion. Drop the flag and all 75 pass. JPMS `--add-exports`/`--add-opens` cannot rescue it — each flag advances the error one layer until it fails inside Monocle's own constructor. An Intel Mac never sees this, so it is an aarch64 fact rather than a macOS one. Belongs in the **launcher's** own testing docs, not the engine's |
