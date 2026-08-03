# Terasology Agent Documentation Layer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give an agent working on Terasology a cheap, task-shaped index of what documentation and tooling exists, without duplicating any of it.

**Architecture:** A small realm skill routes on the task axis and points at upstream docs; a triage doc beside it holds per-doc currency and dated corrections and doubles as the upstream remediation backlog; `ws orient` renders adapter `ai_context` rows so dead pointers surface in normal output.

**Tech Stack:** Markdown, YAML adapters, Bash (`scripts/ws-orient.sh`), bats + `yq`.

**Spec:** `realms/realm-siliconsaga/docs/plans/2026-08-02-terasology-agent-docs-design.md`

## Global Constraints

- **No hard-wrapped prose.** One line per paragraph and per bullet; renderers wrap. Tables, code blocks and YAML frontmatter are exempt. (Workspace `AGENTS.md` rule 6.)
- **Route, don't copy.** No task may inline prose from an upstream Terasology doc into a realm file.
- **Corrections are dated annotations only.** Format: `— <what is wrong> (<YYYY-MM-DD>)`. Never write a corrected copy of a doc.
- **Change-note style is `terse`.** Commit subjects do the talking; bodies get at most 3 lines, and only for something the diff cannot show.
- **Commits go through `ws commit <component> <bodyfile>`** with a bodyfile under `.commits/`. Never raw `git commit`.
- Realm repo work happens on branch `docs/terasology-agent-docs-design`, which already exists and carries the design doc commit.
- Index skill target size ~120 lines; hard ceiling 250 (the taxonomy's split threshold).

## File Structure

| File | Repo | Responsibility |
|---|---|---|
| `docs/terasology-doc-status.md` | realm | Per-doc currency, dated corrections, upstream backlog |
| `docs/agent-doc-layering.md` | realm | The four placement/routing rules, reusable beyond Terasology |
| `.agent/skills/terasology/SKILL.md` | realm | Task-axis routing table |
| `adapters/terasology.yaml` | realm | Correct `ai_context` pointers and `test:` command |
| `AGENTS.md` | realm | Skill index row |
| `.agent/skills/siliconsaga-stack/SKILL.md` | realm | Cross-reference to the new skill |
| `scripts/ws-orient.sh` | yggdrasil | Render `ai_context` rows, mark missing paths |
| `tests/ws-orient/orient.bats` | yggdrasil | Cover the rendering + missing-path logic |

Tasks 1-5 are one realm CR. Task 6 is one yggdrasil CR and has no dependency on tasks 1-5.

---

### Task 1: Doc triage document

**Files:**
- Create: `realms/realm-siliconsaga/docs/terasology-doc-status.md`

**Interfaces:**
- Produces: the anchor names `#keep-and-index`, `#fix-cheaply`, `#archive-or-delist`, `#gaps`. Task 3 links to these from the skill's `⚠` markers.

- [ ] **Step 1: Create the file with header and survey provenance**

```markdown
# Terasology Documentation Status

**Surveyed:** 2026-08-01/02, six parallel clusters over every markdown file in `components/terasology/docs/`, with claims spot-checked against current source.

This file is metadata about upstream documentation, not a replacement for any of it. When a doc is wrong, the correction is recorded here as a dated annotation and the upstream fix is the real remedy — see [`agent-doc-layering.md`](agent-doc-layering.md) rule 3.

**This is also the upstream remediation backlog.** Rows leave this file as fixes land in `MovingBlocks/Terasology`. The file shrinking is the progress metric.

**Currency limit:** the `ws orient` link check verifies that pointer *paths* resolve. It cannot verify that a doc's *content* is still true. That is what the survey date above is for.
```

- [ ] **Step 2: Add the "Keep and index" section**

```markdown
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
```

- [ ] **Step 3: Add the "Fix cheaply" section — this is the ordered upstream backlog**

```markdown
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
| `Module.txt.md` | Example depends on the long-gone `Core` module; omits `author`; `isAsset` bullet is mangled into the `isAugmentation` line (2026-08-02) | Fix example and bullets |
| `Serialization-Overview.md` | Code moved to `subsystems/TypeHandlerLibrary`; `AbstractSerializer`/`GsonSerializer`/`ProtobufSerializer` are now `persistence.serializers.Serializer<D>`; all three GitHub deep links point at removed paths (2026-08-02) | Repath links, rename classes |
| `Textures.md`, `Translation-Guide.md` | Asset paths predate the move to `org/terasology/engine/assets/`; block tiles now in CoreAssets (2026-08-02) | Path updates only |
| `Interactive-Blocks.md` | Single snippet mixes `Core:` and `CoreAssets:` tile URIs (2026-08-02) | Fix the snippet |
| `Rendering.md` | Claims OpenGL 2.1 / GLSL 1.2; `LwjglGraphics` requests a 3.3 core profile. Sample says `implements WorldRenderer`, should be `RenderSystem` (2026-08-02) | Version and sample fix |
| `Shape-File-Specifications.md` | The 1.1 section is an unimplemented 2020 proposal; `JsonBlockShapeLoader` still enforces 1.0 (2026-08-02) | Mark 1.1 as proposed, not shipped |
| `Randomness-and-Noise.md` | Names a `FastNoise` class that does not exist; closest are `WhiteNoise`/`DiscreteWhiteNoise`/`NoiseTable` (2026-08-02) | Fix the class list |
| `Troubleshooting-Developer.md` | JDK 11 / AdoptOpenJDK against a required Java 17; stack traces use pre-`core.subsystem` paths (2026-08-02) | Version and path fix |
| `Using-Locally-Developed-Libraries.md` | Cites `settings.gradle` and gestalt 5.1.5; actual files are `.kts` and gestalt is 8.0.1-SNAPSHOT (2026-08-02) | Version and filename fix |
```

- [ ] **Step 4: Add "Archive or delist" and "Gaps"**

```markdown
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

No document covers these at all. Each is a candidate upstream addition, and until one exists the fact lives in the `terasology` skill's "facts with no doc home" section.

| Gap | Fact |
|---|---|
| Test log levels | `engine-tests/src/test/resources/logback-test.xml` pins `org.terasology` to `${logOverrideLevel:-info}`. Raise with `-DlogOverrideLevel=debug`. `build-logic/src/main/kotlin/terasology-metrics.gradle.kts:69` sets `showStandardStreams = false`, so test output goes to `build/reports/tests/`, not the console |
| Gradle version | Wrapper is 9.6.1. No doc states any Gradle version |
| Home directory on gradle runs | `RunTerasology.initConfig()` unconditionally adds `--homedir=.`, so `gradlew game` writes saves and logs into the repo root. `:facades:PC:run` is a stock `application`-plugin task and does not |
| Headless as pre-flight | No doc frames `:facades:PC:server` as a cheap GL-free smoke test before a windowed run |
| Engine-tests task set | `engine-tests/build.gradle.kts` defines `unitTest`, `integrationTest`, `integrationTestFlaky`, `integrationTestDiagnostic`, `filesystemSideEffectTest`; `test` excludes the `filesystemSideEffects` and `diagnostic` tags |
| Module catalogue drift | `Modules.md` lists 176 entries against ~140 on disk. Read `modules/*/module.txt` instead |
```

- [ ] **Step 5: Commit**

Write `.commits/terasology-doc-triage.md`:

```markdown
---
message: "docs(terasology): add documentation triage and upstream backlog"

add:
  - docs/terasology-doc-status.md
---

Seeded from a six-cluster survey of every markdown file in components/terasology/docs/, spot-checked against current source. Doubles as the upstream fix backlog — rows leave as fixes land.
```

Run: `ws commit realm-siliconsaga .commits/terasology-doc-triage.md`

---

### Task 2: Layering convention document

**Files:**
- Create: `realms/realm-siliconsaga/docs/agent-doc-layering.md`

**Interfaces:**
- Consumes: nothing.
- Produces: rule numbers 1-4, referenced by Task 1's header and Task 3's skill body as "rule N".

- [ ] **Step 1: Write the document**

```markdown
# Agent Documentation Layering

How agent-facing documentation relates to a project's own documentation, when the project is not AI-first and should not be made to carry agent configuration.

Written for Terasology, but nothing here is Terasology-specific.

## The problem

An agent needs orientation a project's docs do not provide: which doc answers which task, which commands exist, what will silently mislead it. The lazy fix is to write an agent-flavoured copy of the project's documentation in a place we control. That produces two corpora that drift, and the copy is always the one that rots, because only the original gets read by the people changing the code.

## Rule 1 — Placement

For any fact, ask: would a contributor who has never heard of GDD benefit from this sentence, and does it avoid mentioning agents or `ws`?

Both yes → **upstream**, written plainly, in the project's own docs. Otherwise → **realm**.

Most facts pass. That a build task writes into the repository root, that the toolchain is a given version, that an API's documented signature is backwards — every contributor needs these and none of them mention AI tooling. The realm layer stays small by design, and the project gets better docs as a side effect.

## Rule 2 — Route, don't copy

The skill layer points at documentation. It never inlines doc prose. One source, both audiences.

A skill that starts explaining the thing it links to has become a second copy, and the link is now decoration.

## Rule 3 — Corrections are dated annotations, never shadow docs

When an upstream doc is wrong, record **what** is wrong and **when** it was checked, as metadata beside the pointer. Never write a corrected copy.

An annotation is a claim about a document. A corrected copy is a competing document. The first deletes itself when the upstream fix lands; the second survives, unnoticed, and eventually contradicts reality on its own.

## Rule 4 — Examples live in code that rebuilds

Prefer pointing at tutorial repositories, sample modules, or tests that compile against the real thing. They break visibly when the code drifts. Documentation snippets do not — they rot silently and stay plausible.

Where a snippet is genuinely needed, keep it tiny and generic.

## What this does not solve

Link checking catches dead paths. Nothing mechanical catches a doc that is still present and now wrong. Currency is a periodic review, and the review's date is part of the record.
```

- [ ] **Step 2: Verify no rule contradicts the spec**

Read `docs/plans/2026-08-02-terasology-agent-docs-design.md` § Principle. The four rules here must match it in substance. Fix any divergence in this file, not the spec.

- [ ] **Step 3: Commit**

Write `.commits/agent-doc-layering.md`:

```markdown
---
message: "docs: add the agent documentation layering convention"

add:
  - docs/agent-doc-layering.md
---

Generalizes past Terasology — the placement test and the annotation-not-shadow-doc rule apply to any project we index but do not own.
```

Run: `ws commit realm-siliconsaga .commits/agent-doc-layering.md`

---

### Task 3: The `terasology` index skill

**Files:**
- Create: `realms/realm-siliconsaga/.agent/skills/terasology/SKILL.md`

**Interfaces:**
- Consumes: Task 1's anchors (`terasology-doc-status.md#fix-cheaply`, `#gaps`), Task 2's rule numbers.
- Produces: the skill name `terasology`, referenced by Task 4's adapter pointer and Task 5's index rows.

- [ ] **Step 1: Verify every command before writing it into the table**

Do not skip this. The whole artifact is a claim that these commands exist.

Run each and confirm it does not error with "unknown command" or "task not found":

```bash
ws exec terasology ./groovyw usage
ws exec terasology ./gradlew :facades:PC:tasks --all
ws test terasology --help
```

`./groovyw usage` is the command the owner recalls; `config/groovy/util.groovy` is the actual dispatcher and lists the real subcommands. **If `usage` is not a valid groovyw verb, use whatever the dispatcher prints for a bare `./groovyw` invocation instead** and write that into the table.

From the `:facades:PC:tasks` output, confirm both `run` and `server` exist. Both are expected: `run` from the `application` plugin, `server` as a `RunTerasology` task.

- [ ] **Step 2: Write the skill**

```markdown
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

- `./groovyw <verb>` — workspace CLI; fetches modules, libs, facades. See `docs/Multi-Repo-Workspace.md`
- `ws test terasology --help` — what the adapter actually runs before you run it

## Routing

A ⚠ means the doc is wrong in a specific, recorded way — read the row, then [the annotation](../../../docs/terasology-doc-status.md#fix-cheaply) before trusting the doc.

| I need to… | Read | Run |
|---|---|---|
| Orient in the multi-repo workspace | `docs/Multi-Repo-Workspace.md` ⚠ | `./groovyw` |
| Fetch modules | `docs/Contributor-Quick-Start.md` | `./groovyw module init omega` |
| Write or debug a test | `docs/Engine-Testing-Patterns.md` + skill `terasology-testing` | `ws test terasology <ClassName>` |
| Raise log level in a test | *no doc* — see [gaps](../../../docs/terasology-doc-status.md#gaps) | `./gradlew :engine-tests:test -DlogOverrideLevel=debug`, then read `build/reports/tests/` |
| Run the game | `docs/Playing.md` ⚠, `facades/PC/README.md` | `./gradlew :facades:PC:run` |
| Run headless as a pre-flight | `docs/Setup-a-headless-server.md` ⚠ | `./gradlew :facades:PC:server` |
| Write an event handler or system | `docs/Events-and-Systems.md` ⚠⚠ | — |
| Name and shape a new event type | `docs/Event-Types.md` | — |
| Understand the ECS model | `docs/Entity-System-Architecture.md` ⚠ | — |
| Replicate state over the network | `docs/Entities-Components-and-Events-on-the-Network.md` | — |
| Declare module dependencies | `docs/Module-Dependencies.md`, `docs/Module.txt.md` ⚠ | `./groovyw module createDependencyDotFile` |
| Work with the sandbox / `@API` | `docs/Module-Security.md` | — |
| Define blocks or assets | `docs/Block-Definitions.md`, `docs/Interactive-Blocks.md` ⚠ | — |
| Add a console command | `docs/Developing-Commands.md` | — |
| Do concurrency or scheduling | `docs/5.3-Migrating-to-Project-Reactor.md` ⚠ | — |
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
```

- [ ] **Step 3: Check size**

Run: `wc -l realms/realm-siliconsaga/.agent/skills/terasology/SKILL.md`
Expected: under 120. If over 250, split per the taxonomy's threshold — but it should not be close.

- [ ] **Step 4: Verify every doc path in the table resolves**

```bash
grep -o 'docs/[A-Za-z0-9._-]*\.\(md\|mediawiki\)' realms/realm-siliconsaga/.agent/skills/terasology/SKILL.md | sort -u | while read -r p; do
    [ -f "components/terasology/$p" ] || echo "MISSING: $p"
done
```

Expected: no output. Any `MISSING:` line is a typo — fix it before committing.

- [ ] **Step 5: Commit**

Write `.commits/terasology-index-skill.md`:

```markdown
---
message: "feat(skill): add the terasology index skill"

add:
  - .agent/skills/terasology/SKILL.md
---

Routes on the task axis rather than the topic axis — `_sidebar.md` already indexes by topic for humans, and duplicating it would add nothing. Baseline testing showed agents reason fine unprompted but pay 25-35k tokens rediscovering local facts; this is aimed at that, not at judgement.
```

Run: `ws commit realm-siliconsaga .commits/terasology-index-skill.md`

---

### Task 4: Fix the adapter

**Files:**
- Modify: `realms/realm-siliconsaga/adapters/terasology.yaml`

**Interfaces:**
- Consumes: nothing. The adapter gets no skill pointer — `ai_context` entries are documentation paths resolved under the component root, and a realm skill is neither. Task 5 registers the skill in the two indexes that exist for that.
- Produces: `ai_context` entries that Task 6's `ws orient` rendering will display.

- [ ] **Step 1: Confirm the two pointers are actually dead**

```bash
ls components/terasology/CONTRIBUTING.md components/terasology/docs/architecture.md
```

Expected: both report "No such file or directory". This is the justification for the change — record it, do not assume it.

- [ ] **Step 2: Rewrite the file**

```yaml
# terasology adapter — build/test commands and AI context pointers
commands:
  build: "./gradlew :facades:PC:build"
  test: "./gradlew :engine-tests:test"
  lint: "./gradlew :engine:checkstyleMain :engine:pmdMain"
  run: "./gradlew :facades:PC:run"
  clean: "./gradlew :engine:clean :engine-tests:clean :facades:PC:clean"

ai_context:
  - path: "docs/Engine-Testing-Patterns.md"
    description: "Engine test patterns: MTE, network events, context isolation, Gradle execution"
  - path: "docs/Codebase-Structure.md"
    description: "Repo layout: engine, facades, modules, libs"
  - path: "docs/Contributor-Quick-Start.md"
    description: "Clone, fetch modules, first run; the only doc stating the Java version correctly"
```

Rationale for scoping — the previous `test:` was `./gradlew test`, the bare root sweep across all 144 module test tasks, which `Phoenix-thalamus.md` preferences forbid on this machine for two independently-established reasons. The same reasoning applies to any unqualified task name: `checkstyleMain`, `pmdMain` and `clean` all match across every subproject in the build. `ws test terasology <ClassName>` still resolves and scopes per-class; this only changes the bare forms.

Only `test` and `lint` are executed by a `ws` verb — `ws-test.sh` reads `.commands.test`, `ws-lint.sh` reads `.commands.lint`. `build`, `run` and `clean` are documentation. They are still hashed into the realm trust fingerprint and printed in the trust summary, so an unscoped value there is a footgun someone can copy even though nothing runs it.

- [ ] **Step 3: Verify the new commands exist**

```bash
ws exec terasology ./gradlew :engine-tests:test --dry-run
ws exec terasology ./gradlew :engine:checkstyleMain :engine:pmdMain --dry-run
```

Expected: both print a task execution plan and exit 0, planning ~20 tasks each with no module subprojects pulled in. `--dry-run` runs nothing.

**If the scoped lint tasks do not resolve**, drop the `lint:` key entirely rather than wiring a command that fails — an adapter that lies is worse than an adapter with a gap.

- [ ] **Step 4: Verify orient still parses the adapter**

Run: `ws orient`
Expected: the `terasology` block lists `ws test`, `ws lint` and `ws build` rows with the new commands, and does **not** print "adapter present but YAML parse failed".

- [ ] **Step 5: Commit**

Write `.commits/terasology-adapter-fix.md`:

```markdown
---
message: "fix(adapter): repoint terasology ai_context and scope the test command"

add:
  - adapters/terasology.yaml
---

Two of three ai_context paths pointed at files that do not exist (CONTRIBUTING.md, docs/architecture.md) — verified absent. The bare `test:` wired `ws test terasology` to the 144-module root sweep this workspace forbids.
```

Run: `ws commit realm-siliconsaga .commits/terasology-adapter-fix.md`

---

### Task 5: Register the skill in the realm indexes

**Files:**
- Modify: `realms/realm-siliconsaga/AGENTS.md` (skill table, ~line 43)
- Modify: `realms/realm-siliconsaga/.agent/skills/siliconsaga-stack/SKILL.md` (skill index section)

**Interfaces:**
- Consumes: skill name `terasology` from Task 3.

- [ ] **Step 1: Add the row to the realm AGENTS.md skill table**

The table has columns `Skill Name | Description | Target Component(s)`. Add, after the `terasology-testing` row:

```markdown
| terasology | Task-axis index: which doc, command, or skill covers what; known-wrong docs flagged | terasology |
```

- [ ] **Step 2: Cross-reference from `siliconsaga-stack`**

Read `realms/realm-siliconsaga/.agent/skills/siliconsaga-stack/SKILL.md` and find its skill-index section (the taxonomy design describes it as naming which component owns which capability). Add a line in the same format the existing entries use:

```markdown
- Terasology docs + tooling index → `realms/realm-siliconsaga/.agent/skills/terasology/`
```

Match the surrounding formatting exactly rather than the sample above if it differs.

- [ ] **Step 3: Verify orient lists the new skill**

Run: `ws orient`
Expected: `[realm:realm-siliconsaga] terasology` appears in the Skills section. The skill index is built by scanning `.agent/skills/*/SKILL.md` frontmatter, so this confirms the frontmatter parses.

- [ ] **Step 4: Commit**

Write `.commits/terasology-skill-index.md`:

```markdown
---
message: "docs(realm): index the terasology skill"

add:
  - AGENTS.md
  - .agent/skills/siliconsaga-stack/SKILL.md
---

The taxonomy's open question flags index drift as the known failure mode here; both indexes are hand-maintained, so both get the row.
```

Run: `ws commit realm-siliconsaga .commits/terasology-skill-index.md`

---

### Task 6: Render `ai_context` in `ws orient`

**Files:**
- Modify: `scripts/ws-orient.sh` — `_emit_one_adapter()` at lines 339-363
- Modify: `tests/ws-orient/orient.bats`

**Interfaces:**
- Consumes: nothing from tasks 1-5. Uses bats fixtures, so this task is independent and can ship first.
- Produces: output lines of the form `    → <path> — <description>` and `    → <path> — <description> (MISSING)`.

**Why this shape:** the spec called for a separate link checker, but a checker in yggdrasil validating realm files creates a cross-repo dependency and a second thing to run. Marking unresolvable paths in the output the agent already reads surfaces rot at the moment it matters, and needs no new command.

- [ ] **Step 1: Write the failing tests**

Append to `tests/ws-orient/orient.bats`:

```bash
# ─── adapter ai_context rendering ───────────────────────────────────

# Build a fixture realm with one cloned component and an adapter
# carrying both a resolvable and an unresolvable ai_context path.
_fixture_ai_context() {
    mkdir -p "$WORK/components/demo/docs"
    echo "# real" > "$WORK/components/demo/docs/real.md"
    mkdir -p "$WORK/realms/realm-fixture/adapters"
    cat > "$WORK/realms/realm-fixture/adapters/demo.yaml" <<'YAML'
commands:
  test: "echo test"
ai_context:
  - path: "docs/real.md"
    description: "A doc that exists"
  - path: "docs/gone.md"
    description: "A doc that does not"
YAML
    cat > "$ECOSYSTEM_LOCAL" <<'YAML'
identity:
  human_account: testuser
realm: realm-fixture
YAML
}

@test "ws orient: renders ai_context rows under the component" {
    _fixture_ai_context
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"docs/real.md"* ]]
    [[ "$output" == *"A doc that exists"* ]]
}

@test "ws orient: marks an ai_context path that does not resolve" {
    _fixture_ai_context
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"docs/gone.md"*"(MISSING)"* ]]
}

@test "ws orient: does not mark a resolvable ai_context path as missing" {
    _fixture_ai_context
    run_ws orient
    [ "$status" -eq 0 ]
    # Pin the real doc's line specifically — a blanket MISSING check
    # would pass even if every row were marked.
    [[ "$(printf '%s\n' "$output" | grep 'docs/real.md')" != *"(MISSING)"* ]]
}

@test "ws orient: an adapter with no ai_context still renders its commands" {
    mkdir -p "$WORK/components/bare" "$WORK/realms/realm-fixture/adapters"
    cat > "$WORK/realms/realm-fixture/adapters/bare.yaml" <<'YAML'
commands:
  test: "echo bare"
YAML
    cat > "$ECOSYSTEM_LOCAL" <<'YAML'
identity:
  human_account: testuser
realm: realm-fixture
YAML
    run_ws orient
    [ "$status" -eq 0 ]
    [[ "$output" == *"ws test [runs: echo bare]"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/ws-orient/orient.bats`
Expected: the three `ai_context` tests FAIL (no such output). The fourth — commands with no `ai_context` — should already PASS, since it covers existing behaviour that must not regress.

- [ ] **Step 3: Implement the rendering**

In `scripts/ws-orient.sh`, inside `_emit_one_adapter()`, after the `for verb in test lint build; do ... done` loop and **before** the `if [[ $parse_failed -eq 1 ]]` block, insert:

```bash
    # ai_context pointers. Rendered here rather than checked by a
    # separate command: a dead pointer is only a problem at the
    # moment someone is about to follow it, which is exactly now.
    # Paths are relative to the component root, matching how the
    # adapter's own commands are interpreted.
    local ctx_count ctx_path ctx_desc i
    ctx_count="$(yq -r '.ai_context // [] | length' "$adapter_file" 2>/dev/null)" || ctx_count=0
    [[ "$ctx_count" =~ ^[0-9]+$ ]] || ctx_count=0
    for (( i = 0; i < ctx_count; i++ )); do
        ctx_path="$(CTX_I="$i" yq -r '.ai_context[env(CTX_I) | tonumber].path // ""' "$adapter_file" 2>/dev/null)" || continue
        ctx_desc="$(CTX_I="$i" yq -r '.ai_context[env(CTX_I) | tonumber].description // ""' "$adapter_file" 2>/dev/null)" || ctx_desc=""
        [[ -n "$ctx_path" && "$ctx_path" != "null" ]] || continue
        ctx_path="$(_ws_orient_display_text "$ctx_path")"
        ctx_desc="$(_ws_orient_display_text "$ctx_desc")"
        if [[ -f "$COMPONENTS_DIR/$comp/$ctx_path" ]]; then
            printf '    → %s — %s\n' "$ctx_path" "$ctx_desc"
        else
            printf '    → %s — %s (MISSING)\n' "$ctx_path" "$ctx_desc"
        fi
    done
```

`_ws_orient_display_text` is the existing sanitiser at line 335 — reuse it so a newline injected into an adapter value cannot forge output lines, matching how `commands` values are already handled.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/ws-orient/orient.bats`
Expected: all tests PASS, including the pre-existing ones.

- [ ] **Step 5: Run the full suite for regressions**

Run: `ws test yggdrasil`
Expected: PASS. `ws orient` output is asserted in several suites; this changes that output, so a break here is a real signal, not noise.

- [ ] **Step 6: Update the orient stale comment**

At `scripts/ws-orient.sh:365-367`, the comment says component skills are surfaced "indirectly via the component's adapter rows above (the ai_context paths)". That was aspirational until now. Change it to state that the rows are rendered, so the comment stops describing an intention and starts describing the code.

- [ ] **Step 7: Commit**

Write `.commits/orient-ai-context.md` in the yggdrasil root:

```markdown
---
message: "feat(orient): render adapter ai_context rows and flag missing paths"

add:
  - scripts/ws-orient.sh
  - tests/ws-orient/orient.bats
---

The ai_context field has been in adapters since they existed and was never rendered — a comment described the intent, no code did it. Found because two of three terasology pointers had rotted to files that no longer exist; marking them in the output the agent already reads beats a separate checker nobody runs.
```

Run: `ws commit yggdrasil .commits/orient-ai-context.md`

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task |
|---|---|
| Index skill, task axis, ~120 lines | 3 |
| Triage doc with dated corrections + backlog | 1 |
| Convention doc, four rules | 2 |
| Adapter: dead pointers, skill pointer, `test:` | 4 |
| `ws orient` renders `ai_context` | 6 |
| Link test | 6 (as fixture-backed rendering tests, plus Task 3 step 4 for the skill's own paths) |
| Realm `AGENTS.md` row | 5 |
| Two CRs, realm work independent of yggdrasil | Tasks 1-5 / Task 6 |

Two deliberate deviations from the spec, both narrowing scope rather than widening it:

1. **The spec's "adapter pointer to the skill"** is dropped from Task 4. `ai_context` entries are documentation paths under the component root; a realm skill is neither. Task 5 registers the skill in the two indexes that exist for that purpose instead.
2. **The link test** became rendering-with-a-marker rather than a standalone checker, for the cross-repo reason given in Task 6. Coverage of the skill's own doc paths moved to Task 3 step 4, so nothing is lost.

**Placeholder scan:** none. Every step has either exact content or an exact command with an expected result. Task 3 step 1 and Task 4 step 3 are deliberately conditional — they verify a command before committing to it, and state what to do if it does not resolve, rather than asserting an unverified command into a permanent artifact.

**Type consistency:** the output format `    → <path> — <description>` is defined once in Task 6's Interfaces and used identically in the implementation and all three assertions. Anchor names `#fix-cheaply` and `#gaps` are created in Task 1 and consumed in Task 3. The skill name `terasology` is consistent across tasks 3, 4 and 5.

**Known risk:** Task 6's `yq` expressions assume the Go implementation (mikefarah), matching the existing `.commands[strenv(ADAPTER_VERB)]` idiom in the same function. If the workspace is on Python `yq`, the array indexing syntax differs and step 4 will surface it.
