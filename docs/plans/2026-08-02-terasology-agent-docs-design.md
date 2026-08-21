# Terasology Agent Documentation Layer — Design

**Status:** draft 2026-08-02.

## Goal

Give an agent working on Terasology the orientation layer that `ws orient` gives it for the GDD workspace: a cheap, task-shaped skeleton of what exists and where, with drill-down into the real documentation rather than a copy of it.

This spec covers the L0 index skill and the layering convention it implies. Process skills, agent-collaboration etiquette, the upstream documentation overhaul itself, Backstage audience tiers, and API access for binary dependencies are each separate cycles — see Out of Scope.

## Context — why an index and not a practice skill

The work started as a `terasology-review` skill: nine "traps this box hit" recorded in `Phoenix-thalamus.md`, to be assembled into review guidance.

Following `superpowers:writing-skills`, all nine were baseline-tested first — six pressure scenarios against fresh subagents with no skill, plus two re-runs after the first pass leaked its own answers into the prompts. **Every scenario passed.** Agents established merge-base diffs correctly, refused to accuse authors before checking their own tooling, declined to sweep 144 modules, ran positive controls on log-based inferences, and refused to inherit "known issue" folklore as grounds to dismiss a red test run. One item — a list of standing failures to ignore — would have made an agent *worse* than having no skill, because both failures had been fixed upstream five days earlier (#5352 and #5353, both verified merged 2026-08-01).

The nine items were also written as universal rules from single situations. The clearest example: a specific decision not to rebase one heavy PR, made because that PR needed no further changes and the rebased branch had already been tested locally, had been recorded as "do not advise rebasing." The situation was dropped and the conclusion kept. A Thalamus note is one observation; a standing instruction needs to hold when the situation changes.

What agents could not do unprompted was know this codebase. They paid for it: 12 tool calls and 28k tokens to prove two-dot versus three-dot diff behaviour empirically, 11 calls and 35k tokens to find that `logback-test.xml` pins `org.terasology` to `${logOverrideLevel:-info}` and that `terasology-metrics.gradle.kts` sets `showStandardStreams = false`.

**The gap is discovery, not judgement.** That is what this design addresses.

## Principle

### The placement test

For any fact we want an agent to know, ask two questions: would a contributor who has never heard of GDD benefit from this sentence, and does it avoid mentioning agents or `ws`?

Both yes → it belongs **upstream** in `components/terasology/docs/`, written plainly. Otherwise → it belongs in the **realm**.

Most of what the documentation survey surfaced passes this test and goes upstream. That `gradlew game` writes its home directory into the repository root, that the toolchain is Gradle 9.6.1 and Java 17, that `IO-API-for-Modules.md` documents its consumer types backwards — every contributor needs these, and none of them mention AI tooling. The realm layer stays small by design.

### The four rules

1. **Placement** — as above. Upstream carries facts about the codebase in contributor-neutral language; the realm carries how an agent should act on them.
2. **Route, don't copy** — the skill layer points at documentation. It never inlines doc prose. One source, both audiences.
3. **Corrections are dated annotations, never shadow docs** — when an upstream doc is wrong, record what is wrong and when it was checked, as metadata beside the pointer. Never write a corrected copy. The annotation deletes itself when the upstream fix lands.
4. **Examples live in tutorial repos that rebuild** — `TutorialEntitySystem`, `TutorialWorldGeneration` and siblings compile against the engine and break visibly when it drifts. Wiki snippets do not. Every "code that no longer compiles" finding in the survey was a pasted snippet: `Events-and-Systems.md` still documents `@ReceiveEvent(priority=)`, `Character-Module.md` uses the removed `Quat4f`. Snippets stay tiny and generic, or absent.

### Relationship to the skill taxonomy

`2026-05-30-skill-taxonomy-design.md` places each skill at the tier where the knowledge is genuinely owned, and its ownership test would put this skill in `components/terasology/.agent/skills/` — Terasology plainly owns this knowledge.

**This design deliberately deviates, and the deviation is the point.** Terasology is not an AI-first project and will not carry agent configuration in its repositories for now; pushing AI tooling into a fifteen-year-old contributor codebase would impose it on every contributor to serve a few. The realm is the honest home while that holds.

This is a case the taxonomy does not yet cover: knowledge owned by a component that cannot host agent files. The eventual destination is a Terasology-specific GDD realm split out from `realm-siliconsaga`, not the component. `realm-siliconsaga` is the interim host, and everything here is written to move as a unit.

## Artifacts

| Artifact | Path | Role |
|---|---|---|
| Index skill | `realm-siliconsaga/.agent/skills/terasology/SKILL.md` | Task-axis routing, loads on trigger |
| Triage doc | `realm-siliconsaga/docs/terasology-doc-status.md` | Per-doc currency and dated corrections; the upstream backlog |
| Convention | `realm-siliconsaga/docs/agent-doc-layering.md` | The four rules, for reuse beyond Terasology |
| Adapter | `realm-siliconsaga/adapters/terasology.yaml` | Fix dead pointers, scope every command |
| Orient rendering | `yggdrasil/scripts/ws-orient.sh` | Print `ai_context` rows — the always-on tier |
| Link test | `yggdrasil/tests/` (bats) | Assert every pointer resolves on disk |

Two repositories, so two code-review requests. The realm work does not depend on the yggdrasil work; only the always-on tier does.

## The index skill

Name `terasology`, matching the taxonomy's single-component naming convention. Target ~120 lines, comfortably under the taxonomy's ~250-line split threshold.

The frontmatter description states triggering conditions only and never summarizes the body. `superpowers:writing-skills` is explicit that a description summarizing workflow becomes a shortcut agents take instead of reading the skill.

Body sections, in order:

- **Overview** — two sentences: Terasology is a mega-workspace (engine, facades, ~144 nested module repositories, `libs/`), and this file routes rather than explains.
- **Orient first** — the two or three commands that establish workspace state, chiefly `groovyw` for module fetching and `ws test terasology --help` for the adapter.
- **Routing table** — the core, ~15 rows, columns `I need to… | Read | Run | ⚠`.
- **Facts with no documentation home** — short, and every row is a pending upstream doc PR, cross-referenced to the triage doc.
- **Where examples live** — the tutorial repositories, per rule 4.

A `⚠` in the routing table is only ever a marker pointing at a dated annotation in the triage doc. Corrections never appear inline, or the skill becomes the shadow corpus rule 3 forbids.

Rows are on the task axis, not the topic axis. The existing `_sidebar.md` is already a good topic index organized by audience; duplicating it adds nothing. The value is answering "I am reviewing an engine PR that touches events — what do I read, what do I run, what will bite me", which no current artifact answers.

## The triage doc

One row per surveyed document: path, what it covers, `CURRENT`/`AGED`/`DEAD`, agent value, dated correction, upstream action.

Grouped as **Keep and index** / **Fix cheaply** / **Archive or delist** / **Gaps with no doc at all**.

It has two jobs. It is where rule 3's annotations live, and it is the upstream remediation backlog — the input to work item D. Rows delete as fixes land upstream, so the file shrinking is the progress metric.

Seeded from the six-cluster survey run 2026-08-01/02, which covered every markdown document in `components/terasology/docs/` and spot-checked claims against current source. Headline findings, all of which the triage doc carries in full:

- `Engine-Testing-Patterns.md` is the strongest document in the corpus, verified claim-by-claim against `MainLoop`, `Engines` and `ModuleTestingHelper` — and it is absent from `_sidebar.md`, so it is discoverable only if you already know its filename.
- No document reflects the gestalt `@ReceiveEvent` migration. `Events-and-Systems.md` still documents `priority=` and `netFilter=` attributes that are now `@Priority` and `@NetFilterEvent`. An agent following it writes code that does not compile. This is the highest-value single upstream fix.
- The architecture cluster predates the `org.terasology.*` to `org.terasology.engine.*` repackaging, so package paths taken from those docs silently fail to match.
- No document states a Gradle version; the wrapper is 9.6.1. Java 17 is stated correctly, but only in `Contributor-Quick-Start.md`.
- `logOverrideLevel`, the test-side log knob, is documented nowhere.
- `IO-API-for-Modules.md` labels its `readFile`/`writeFile` consumer types backwards.
- Recommended for delisting: `GCI.md`, `Project-Overview.md`, `Why-Terasology.md`, `Markdown-and-Wiki.md`, and the Ludicious retrospective.

## Adapter and the always-on tier

`adapters/terasology.yaml` currently carries three `ai_context` pointers, two of which target files that do not exist — `CONTRIBUTING.md` and `docs/architecture.md`. Only `docs/Engine-Testing-Patterns.md` resolves. This is rule 3's failure mode already in the tree, and it is the argument for a mechanical guard.

`ws-orient.sh` mentions `ai_context` exactly once, in a comment stating that component skills are surfaced indirectly via adapter rows. No code reads or prints them; the intent was written down and the rendering never was. Implementing it gives the always-on tier from pure realm configuration afterwards, and it partially answers the discovery fragility the skill taxonomy flagged as an open concern.

The adapter's `test:` is also wrong for this workspace: it wires `ws test terasology` to `./gradlew test`, the bare root sweep across all 144 module test tasks that `Phoenix-thalamus.md` preferences explicitly forbid on this machine.

## Testing and anti-rot

**What was built at the time was weaker than this section originally claimed.** One of the two gaps has since closed; the other is inherent.

A companion yggdrasil change renders each adapter `ai_context` pointer in `ws orient` and appends `(MISSING)` when the path does not resolve under the component root. Its bats coverage exercises that rendering against synthetic fixtures — it proves the marker logic works, not that any real pointer resolves. The index skill's own doc paths were verified once, by hand, at authoring time.

So there are **two** limits, not one:

- **~~Nothing fails.~~ Closed 2026-08-21.** `ws orient --check` gives the same computation an exit code: non-zero when any declared pointer is `MISSING` or `INVALID PATH`, so a schedule or a CI step can block on rot instead of a human having to read the output. Plain `ws orient` stays exit-zero — it is the session-start command, and doc rot should not block orientation. Shipped on the yggdrasil 1.1 branch.
- **Paths, not truth.** Even a fully enforced check would only prove a file exists. A doc that is present and wrong passes. That is what the triage doc's survey date is for. This limit stands and is not scheduled to close — it is not mechanically checkable.

The first limit closed after this design was written. The enforcing behaviour landed as a flag on the command that already did the computation, rather than as the separate walk-the-live-adapters test sketched here: the rendering path already had the containment and symlink-refusal logic, and a second implementation would have been a second thing to keep true. Until that flag is wired into a schedule, pointer currency is enforceable but not yet enforced.

No subagent scenario testing for this skill. `superpowers:writing-skills` exempts pure reference — "don't test skills without rules to violate" — and the nine baselines recorded above are the evidence that the rule-shaped version was not warranted.

## Implementation order

1. **Triage doc** — transcribe the survey into `terasology-doc-status.md`. Everything else references it, and it is pure data entry from work already done.
2. **Convention doc** — `agent-doc-layering.md`, the four rules. Short. Written before the skill so the skill can be checked against it.
3. **Index skill** — `terasology/SKILL.md`, built against the triage doc so every row's target and every `⚠` is grounded.
4. **Adapter fix** — dead pointers out, every command scoped. No skill pointer: `ai_context` entries are documentation paths resolved under the component root, and a realm skill is neither. Step 5 is where the skill gets registered.
5. **Realm `AGENTS.md`** — add the skill index row, and cross-reference from `siliconsaga-stack` so the realm index points at this one.
6. **Yggdrasil: orient rendering plus bats test** — separate repository, separate CR, no dependency from steps 1-5.

Steps 1-5 are one realm CR. Step 6 is one yggdrasil CR.

## Open questions

- **Does the triage doc belong in the realm long-term?** It is metadata about another project's documentation. It works here while the realm is the interim host, but when the Terasology realm splits out it should move with the skill rather than stay with SiliconSaga.
- **How is currency re-established?** Subagent cost is explicitly not the binding constraint (owner, 2026-08-02), so a wholesale re-survey is affordable and the per-cluster ad-hoc alternative can be dropped. What remains open is the *trigger*: a fixed interval, or an event such as a major engine version or a large documentation merge. Lean toward re-surveying whenever the triage doc is next consulted and its survey date is more than a release old.
- **Should `⚠` rows carry severity?** "Says Java 11, actually 17" and "documents an annotation that no longer compiles" are not the same hazard. Lean: no, keep the skill flat and let the triage doc carry severity, and revisit if the skill's table becomes hard to read.

## Out of scope

- **Process skills** (`terasology-review` and siblings) — own cycle, will link into this index.
- **Agent collaboration etiquette** — how an agent deals with human contributors and their agents. Realm-level, not Terasology-specific, own cycle.
- **The upstream documentation fixes themselves** — this spec produces the backlog; landing it is separate work.
- **Backstage audience tiers and publishing** — presentation of a corpus that has not been triaged yet is premature. Depends on the upstream work, and connects to `2026-06-09-backstage-devex-workspace-design.md`.
- **Javadoc or MCP access for binary dependencies** — LWJGL, JOML, Reactor and similar have no local source. Independent and speculative.
- **Writing the SKILL.md prose itself** — this spec is the brief; authoring follows via `superpowers:writing-skills`.

## Self-review notes

- **Placeholders:** none.
- **Internal consistency:** rules 2 and 3 constrain the skill and triage doc respectively, and the artifact table matches the implementation order. The taxonomy deviation is stated explicitly rather than left implicit.
- **Scope:** one implementation plan's worth. Six artifacts across two repositories, five of them small, with the largest being data transcription already performed.
- **Ambiguity:** "small" for the index skill is pinned to ~120 lines against the taxonomy's ~250-line threshold. "Cheap" for the always-on tier is one line of `ws orient` output per component.
