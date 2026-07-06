# Leiðangr Phase 3 — Community Domain Model (Design)

**Date:** 2026-07-06
**Status:** Draft
**Scope:** Define how the Leiðangr Backstage instance models the community domain in the catalog,
seed a representative MTL hierarchy, and stand up the Backstage admin surface. Builds on the
Phase 2 skeleton (`components/leidangr`, merged 2026-06-28/30).
**Supersedes/absorbs:** the pre-design decision aid worked through in session (three approaches →
hybrid → the two-family model); this doc is the canonical outcome.
**Related:** `2026-06-09-leidangr-design.md` (§3 architecture, §6 Phase 3 summary),
`2026-06-09-backstage-devex-workspace-design.md` (facility/org modeling, entity-kind table,
event-templates, calendaring), the parked *Saga* note (Loki Thalamus, 2026-06-25).

---

## 1. What Phase 3 Is

Phase 3 turns the empty Phase-2 skeleton into a **modeled community control-plane**: it defines the
catalog conventions and custom kinds for the community domain, seeds a representative Mountaintop
League (MTL) hierarchy, and makes the Backstage admin/power-user surface show something real.

It is **modeling and seeding**, not marketplace or parent-facing UX (Phase 4+). Per the umbrella
design, Backstage is the *admin/control-plane*; parents never see it (light front-ends relabel).

### Done signals

1. Two custom kinds (`Cycle`, `Saga`) are defined; `Cycle` is implemented (backend validation +
   relations) and `Saga` is designed (build deferred — see §12).
2. A representative MTL hierarchy is seeded and ingests cleanly (Group tree, facilities, a season
   `Cycle`, at least one "real" software System).
3. The Backstage catalog shows the entities with correct relations, filterable by kind/type;
   `ws test leidangr` stays green with new BDD coverage for the `Cycle` module + seed.

## 2. The Two-Family Model (the core decision)

The domain's "groupings" split into **two families by how their data originates** — this axis is
what determines representation:

| Family | Origin | Unique data in Backstage? | Representation |
|---|---|---|---|
| **Structured & ingestable** | scraped/ingested from a source system | little to none | **`Cycle`** custom kind (+ built-ins) |
| **Narrated & authored** | a human *writes* it | the narrative — kept in **Git**, not the DB | **`Saga`** custom kind |

A soccer season *is* a `Cycle` (`MTL Soccer v2026.1`) that always exists; it becomes a `Saga` only
if someone authors the epic about it. The same line separates a software **release** (a `Cycle`)
from a **retrospective** (a `Saga`).

**Everything else uses built-in kinds**, and **occurrences are not entities** (§6). The model is
deliberately generic so the same primitives serve PTA / Demicracy / small-business efforts later.

### Why these mechanics (grounded in the scaffold)

The instance runs Backstage's new frontend (`@backstage/frontend-defaults`) and new backend
(`createBackend()`) systems. Relevant facts:

- The catalog **ingests any `kind`** with no allowlist — custom kinds are stored, searchable, and
  filterable with zero code. A custom kind's cost is its **relations, curated page, and
  validation**, not ingestion.
- **`spec.type` gives in-kind filtering for free** on `Component`/`Resource`/`Group`. No kind is
  introduced merely to filter.
- **Built-in relations are homogeneous** (`System→Component`, `Group→Group`). Cross-kind or
  time-boxed links are **custom relations** emitted by a backend module — the real build cost.
- Entity pages are **filtered extensions**; an unmatched kind falls back to a usable default page,
  so curated pages are additive.

## 3. Built-in Kinds — Conventions

No custom kinds for these; conventions only.

- **People-org → `Group` tree**, typed via `spec.type`: `organization` → `sport` → `division`
  (optional) → `team`. Ownership and `parent`/`children` come free. Small sports skip the
  `division` level with no special-casing.
- **Facilities → `System` + `Resource`.** A facility is a `System` (`spec.domain: mtl`); its
  bookable spaces are `Resource`s with `spec.type: bookable-space` — rooms *and* fields share the
  one type so a single reservation UX serves both (per the devex reservable-Resource convention).
  Reservable resources carry the fully-qualified `siliconsaga.org/reservable`,
  `siliconsaga.org/calendar-provider`, and `siliconsaga.org/calendar-ref` annotations.
- **Environments / clusters → `Resource`** (`spec.type: environment`|`cluster`), the software-side
  peer of a field; other entities `dependsOn` them. Established Backstage practice, no custom kind.
- **"Real" software → `System` + `Component`** (e.g. a registration app), owned by the right Group.
- **Custom API group:** custom kinds and any custom spec annotations use the `siliconsaga.org`
  namespace (`apiVersion: siliconsaga.org/v1alpha1` for `Cycle`/`Saga`; `siliconsaga.org/*`
  annotations), consistent with the reservable convention.

## 4. `Cycle` — the Structured/Ingestable Custom Kind

`Cycle` is the general primitive for a **bounded, dated grouping of occurrences** owned by a
durable parent. One kind serves software and community; `spec.type` discriminates.

```yaml
apiVersion: siliconsaga.org/v1alpha1
kind: Cycle
metadata:
  name: soccer-2026-spring
spec:
  type: season                 # open vocab: season | release | series | production | drive | tournament | …
  timeframe: { start: 2026-03-01, end: 2026-06-15 }
  of: group:default/mtl-soccer # durable parent — a Group (league) or a Component (app)
  happensAt:                   # optional; the Resource(s) occurrences use
    - resource:default/field-1
  owner: group:default/mtl-soccer
```

- **Backend module** (`components/leidangr` catalog backend module): validates the `Cycle` spec
  (required `type`, `timeframe`, `of`) and **emits its relations** — `ownedBy` (from `owner`), and
  the *provisional* `cycleOf`/`hasCycle` (from `of`) and `happensAt`/`hosts` (from `happensAt`);
  the final relation vocabulary is decided at plan time (§14). Emitting relations is the module's
  real work, since custom-kind fields get no built-in relation processing.
- **Entity page:** the default page (About + Relations) is acceptable to start; a curated
  "timeframe + what this Cycle spans + occurrences" content extension (filtered to `kind: Cycle`)
  is a follow-up, not a Phase-3 blocker.
- **Naming & types:** `Cycle` (evoking a *Ring Cycle* / mythos) is domain-neutral and reusable;
  `spec.type` is an **open, org-extensible vocabulary** (`season`, `release`, `series`,
  `production`, `drive`, `tournament`, …), not a fixed enum. A *simple, one-time* event is **not**
  a Cycle — it's an occurrence (§6).

## 5. `Saga` — the Narrated Custom Kind (designed; build deferred)

A `Saga` is an authored **After-Action-Report for any effort or community event** — a season, a
talent show, a fundraiser, a software project — narrating what happened, who was involved, where,
and what was learned. It cannot be scraped, only written. (In the software domain it maps neatly to
a **retrospective**, but that's one instance of the general pattern, not the definition.) Design
captured now; **implementation deferred** (§12).

```yaml
apiVersion: siliconsaga.org/v1alpha1
kind: Saga
metadata:
  name: mpe-talent-show-2026
  annotations:
    siliconsaga.org/saga-doc: ./saga.md   # narrative body in Git, rendered blog/TechDocs-style
spec:
  skald: user:default/cervator            # the author, for a little flair
  timeframe: { start: 2026-04-01, end: 2026-05-10 }
  touches:                                # entity refs the Saga references
    - cycle:default/mpe-talent-show-2026
    - group:default/mpe-pta
    - resource:default/main-room
  owner: group:default/mpe-pta
```

- **Git is the source of truth.** Both the narrative (`saga.md`) and the entity
  (`catalog-info.yaml`) live in the org's repo, in a self-contained per-effort directory (the same
  shape event-templates use). Backstage's DB is a rebuildable cache — **nothing unique is lost if
  the instance is wiped.**
- **Skald ergonomics:** because `touches` is entity refs, the authoring UX offers catalog-backed
  dropdowns (`EntityPicker`) so linking to what the Saga touched is picking, not typing.
- **Dual surface:** the same `saga.md` renders as a blog post on an org site *and* is ingested by
  Backstage.
- **Distinct from `Cycle`:** a `Cycle` is refreshable current-state; a `Saga` is append-only
  narrative authored after the fact. A season exists as a `Cycle` with zero, one, or many `Saga`s
  about it.

## 6. Occurrences — Queried, Not Minted

Matches, deployments, and single event-instances are **occurrences**: a single point-in-time
happening, high-churn and numerous. They are **not catalog entities** — minting each churns the
catalog for no gain. They live in the source (calendar, TeamSnap, CI/CD) and are **queried** onto a
`Cycle`'s page by a plugin (the same stance the calendaring design takes: "occurrences are queried,
never minted as per-occurrence entities").

The line between an occurrence and a `Cycle` is **grouping, not calendar-vs-not**: a *simple,
one-time* event (one game, one meeting) is an occurrence; a bounded effort that *groups* several
occurrences under one theme — a multi-day talent show with rehearsals and two show-nights — is a
`Cycle` (`spec.type: production`) even though it is singular. "Singular vs recurring" is a nuance of
the Cycle's `spec.type`, not a separate kind.

This is where the earlier `Activity` concept **dissolves**: an Activity is either an occurrence (a
single match/deployment) or, if it groups occurrences, a `Cycle`.

## 7. MTL Seed — Representative Shape

Seed a representative multi-sport hierarchy (names are placeholders to refine, or to be supplied
later by the TeamSnap provider in §8):

```
Group: mtl                              (spec.type: organization)
 ├─ Group: mtl-soccer   (type: sport)   ▸ Cycle: soccer-2026-spring (type: season,
 │   ├─ Group: soccer-u8   (division)                                of: mtl-soccer, happensAt: field-1)
 │   │   └─ Group: u8-red  (team)        · matches = occurrences (queried, not seeded)
 │   └─ Group: soccer-u10  (division)
 ├─ Group: mtl-basketball (type: sport)  ← small: teams hang directly (no division level)
 │   └─ Group: bball-varsity (team)
 └─ Group: mtl-hockey     (type: sport)

Domain: mtl
 ├─ System: mtl-house        (facility)  ─ Resource: main-room (bookable-space)
 ├─ System: mtl-fields       (facility)  ─ Resource: field-1  (bookable-space)
 └─ System: mtl-registration ("real" SW) ─ Component: reg-web, Component: reg-api

External (referenced, not held):  System: teamsnap (spec.type: external / system-of-record)
```

The seed is hand-authored `catalog-info.yaml` files under the component (dev fixtures + the
example catalog location), shaped identically to what the TeamSnap entity provider will later emit.

## 8. TeamSnap Ingestion (designed; deferred)

MTL's real structure lives in **TeamSnap**, whose API is likely limited and which **archives old
seasons** (data-loss risk). The design — **built later, its own component**:

```
TeamSnap ─(periodic scrape)─► middleware DB ─(stable REST API)─► Backstage entity provider
 (limited API, archives)       (durable; PRESERVES               (custom catalog module →
                                archived seasons)                  Group tree + Cycle entities)
```

The middleware becomes the durable record (fixing archival loss); a Backstage **entity provider**
refreshes `Group`/`Cycle` entities from it on a schedule. Backstage reflects; TeamSnap+middleware
hold — consistent with "Backstage points at things, does not hold them." Phase 3 hand-authors the
seed (§7) with the *same entity shapes* so the provider swaps in without a remodel.

## 9. What Stays Out of Backstage

- **Occurrences** (matches, deployments, single events) — queried from source (§6).
- **Dynamic/high-churn data** (gear-swap offers/needs, chat, signups) — Knarr / Ting / app DBs.
- **External systems-of-record** (TeamSnap, Google Workspace) — referenced entities + one-way
  publishing, never two-master sync.
- **`Saga` prose + entities** — authored in and served from Git; Backstage only indexes (§5).

## 10. Testing — BDD Outside-In (mirrors Phase 2)

Continue the Phase-2 BDD approach (`jest.envelope.config.cjs`, jest-cucumber) plus TDD for the
`Cycle` module internals:

- **`Cycle` module (TDD):** validates required spec fields; rejects malformed specs
  (blank/absent `type`, `timeframe`, `of`); emits the expected relations for a valid entity.
- **Seed ingestion (BDD, source-assertion smokes now):** feature scenarios assert the seed produces
  the expected entities and relations (e.g. `soccer-2026-spring` is a `Cycle{season}` `cycleOf`
  `mtl-soccer`, `happensAt` `field-1`; `u8-red` is a `team` under `soccer-u8`).
- **Later:** a real `startTestBackend` catalog test replaces source-assertions (tracked as a loose
  item from the leidangr-domain arc).

## 11. Architecture Decision Records (to distill)

Per the realm plan→ADR convention, distill these into MADR-v3 ADRs in
`components/leidangr/docs/adrs/` once real:

1. **Two-family model** — structured/ingestable (`Cycle`) vs. narrated/authored (`Saga`), split by
   data origin.
2. **`Cycle` as a general custom kind** — one kind for the whole bounded-grouping family via an
   open `spec.type` vocabulary (season, release, series, production, drive, tournament, …);
   occurrences (single happenings) are queried, not minted.
3. **`Saga` is Git-backed** — narrative + entity in Git, Backstage DB is a cache; Skald authorship.
4. **Built-in mapping** — people-org = typed `Group` tree; facilities/fields/environments =
   `System` + typed `Resource`; real software = `System` + `Component`.
5. **Dropped/dissolved** — `ResourceType` (Resource is already typed; a Phase-4 vocabulary) and
   `Activity` (an occurrence, or a `Cycle` if it groups occurrences).
6. **TeamSnap via middleware + entity provider** — points-not-holds; preserves archived seasons.

## 12. Phase 3 Build vs. Defer

- **Build now:** built-in conventions (§3), the **`Cycle`** kind + backend module (§4), the
  hand-authored **MTL seed** (§7), and BDD coverage (§10). This delivers the Phase-3 done signals
  and "see some Backstage."
- **Design now, build later:** **`Saga`** (§5 — needs Git render + authoring UX; inherently
  Phase 4+) and the **TeamSnap middleware/entity-provider** (§8 — its own component).

## 13. Out of Scope (YAGNI for Phase 3)

- Parent-facing / marketplace UX (Phase 4).
- Reservation/calendaring plugins and event-templates (later phases).
- Scorecards / catalog-hygiene checks beyond what falls out of validation.
- Live GKE validation of the instance (human-gated; no rush per the arc).

## 14. Open Items — verify at plan time

- Exact new-frontend/new-backend API surface for (a) a catalog processor emitting custom relations
  and (b) an entity content extension filtered to a custom kind — confirm against the installed
  Backstage version before the plan fixes commands.
- Whether `cycleOf`/`happensAt` should be net-new relation type names or reuse existing relation
  vocabulary — decide in the plan.
- Follow-up: rename the 3 distributed-systems "saga pattern" uses in the realm event-publish design
  to "handoff/relay with a pending hold," freeing the `Saga` name (per the parked note).

## 15. Provenance & Process

- **Brainstorm → design → plan:** this doc exits the brainstorming flow; a companion
  `2026-07-06-leidangr-phase3-community-domain-plan.md` (writing-plans) follows.
- **Plan → ADR distillation:** §11 lists the durable decisions to distill once built.
- **Tone discipline:** engineering doc; any parent-facing surface (later) follows the realm Tone
  Guide.

## 16. References

- Umbrella design: [`2026-06-09-leidangr-design.md`](2026-06-09-leidangr-design.md) (§3, §6)
- Backstage devex reference: [`2026-06-09-backstage-devex-workspace-design.md`](2026-06-09-backstage-devex-workspace-design.md)
  (facility/org modeling, entity-kind table, event-templates, calendaring)
- Phase 2 skeleton: [`2026-06-21-leidangr-phase2-backstage-skeleton-design.md`](2026-06-21-leidangr-phase2-backstage-skeleton-design.md)
- Parked *Saga* note: Loki Thalamus, 2026-06-25 (narrative-records / Skald)
- Backstage custom kinds & processors: https://backstage.io/docs/features/software-catalog/extending-the-model
- Backstage entity providers: https://backstage.io/docs/features/software-catalog/external-integrations
