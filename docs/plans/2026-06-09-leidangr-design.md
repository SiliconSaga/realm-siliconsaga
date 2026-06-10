# Leiðangr — Community Coordination Stack (Design)

**Date:** 2026-06-09
**Status:** Draft
**Scope:** Realm-level umbrella concept + multi-phase architecture. Phase 1 specified in full; later phases sketched at the architectural level for future sessions/arcs.
**Supersedes:** `leidangr.md` (a Gemini-authored scratch sketch; its useful bones are folded in here, its techno-utopian framing is dropped).
**Related:** `2026-05-10-ting-pilot-design.md`, `2026-04-02-knarr-design.md`, `2026-04-08-mtl-site-design.md`, the `schools` repo (manifesto), and `2026-06-09-backstage-devex-workspace-design.md` (reference material — balanced against current backstage.io docs, *not* treated as authoritative).

---

## 1. What Leiðangr Is

Leiðangr is not a component. It is the umbrella concept — the "spiritual layer" — that ties together several existing and planned SiliconSaga components into one mission: **mobilizing and coordinating volunteer communities, and keeping their intent and history alive across leadership turnover.**

The Old Norse *leiðangr* was a levy that mobilized a volunteer naval force from scattered coastal communities — the right metaphor for assembling help from busy, dispersed parents and volunteers. The name lives in the realm's `docs/plans/` and (eventually) in a realm narrative doc; it does **not** warrant its own component repo today. A component only becomes warranted if the dynamic marketplace backend (see §4.4 / §5.1) turns out to be real shared infrastructure — and even then it would be its own narrowly-scoped service, not a monolith called "Leiðangr."

This document is internal platform/architecture material. Anything that eventually reaches parents, school boards, or sports volunteers must follow the realm [Tone Guide](../../AGENTS.md) — grounded, service-oriented language, none of the techno-utopian vocabulary that fills the original scratch doc.

## 2. The Mandate

Traditional civic and volunteer tools fail when leadership shifts: proprietary platforms silo data, lock out history, and frustrate casual volunteers. Leiðangr's grounded goals:

- **Survive turnover.** Coordination state and history outlive any one chapter president or coach.
- **Low-friction intake.** A tired parent on a phone can offer or request something in seconds — no account, no jargon, ideally not even leaving the chat app they already use.
- **Meet people where they are.** Chat (Discord/Matrix/WhatsApp), SMS, a simple web form, or a survey response are all valid front doors. The platform adapts to the community, not the reverse.
- **A durable memory + discovery layer.** A central, queryable index of groups, resources, needs, and offers — even when the day-to-day conversation happens on "shadow tech."
- **Privacy and safety as primary requirements**, because this domain touches children, families, and locations (see §8).

## 3. Grounded Architecture

Each Leiðangr "role" maps to a real or planned component rather than to the idealized four-layer model in the scratch doc.

| Layer | Owner | Notes |
|---|---|---|
| Narrative / "why" | `schools` manifesto, later Demicracy | The pitch and philosophy, not a service. |
| Parent/volunteer frontend | **Ting** (as "the assembly") | Grows from anonymous survey tool into the light, mobile-first volunteer surface: Offer / Need / Volunteer. |
| Dynamic marketplace data | *Open question — see §5.1* | Offers, needs, claims, transfers, reservations, moderation state. High-churn, mutable, **not** YAML. |
| Catalog / control-plane | **Backstage** (new) | Admin/operator surface + stable entities (`CommunityGroup`, `Program`, `Activity`, `ResourceType`, `Facility`); docs, search, permissions, scorecards. |
| Transport / notify | **knarr** (+ Heimdall ntfy seam) | Already built — Matrix/Kafka/bridges. Carries inbound intent and outbound nudges. |
| Identity | **Keycloak** (Nidavellir) | OIDC sign-in for Backstage and Ting. Adult-only accounts by default. |
| Secrets | **OpenBao** (new) | + External Secrets Operator into Kubernetes. |
| Data services | **Mimir** | Postgres claims for Backstage and the marketplace DB. |
| Observability | **Heimdall** | Backstage/Ting metrics & logs, alert coverage. |

### The hybrid discipline

The load-bearing rule (consistent with the Backstage reference doc's volunteer-coordination appendix): **stable, owned, documented things live in the Backstage catalog; volatile marketplace and signup data live in an application database behind an API; parents interact through a purpose-built mini-frontend and never touch YAML or Backstage terminology.**

### Intake spine vs. system of record

```text
  chat / SMS-to-bridge-phone / Ting offer / Backstage admin entry
                     │  (loose "intent" events)
                     ▼
        knarr Kafka  ──►  INTAKE BUS         (Kafka is a strong fit here)
                     │
                 processor (extract intent, dedupe, validate)
                     │
                     ▼
        Postgres (via Mimir)  ──►  SYSTEM OF RECORD   (a DB, not the log)
              ▲          │
   direct API │          └──►  Valkey cache (rebuildable from Postgres)
   (Ting / Backstage)
```

- **Kafka is the intake bus** (and later the outbound notification bus). Any channel drops a loose intent event onto a knarr topic; relevance-flagging and extraction happen downstream. This is the natural home for "ingest offers/wishes from chat."
- **Postgres is the source of truth** for queryable, mutable marketplace state. Kafka-as-sole-truth would force reliance on retention/compaction/replay for recovery; instead the DB is authoritative and is backed up (see the existing `pv-backups` arc). Valkey, if used, is a rebuildable cache only.

## 4. Key Design Decisions

1. **Realm umbrella, not a component.** Leiðangr is a coordinating narrative over existing components; no new "Leiðangr" repo at this stage.
2. **Hybrid Backstage.** Backstage is the admin/control-plane and catalog of stable entities — *not* the parent-facing UI and *not* the marketplace database.
3. **Ting is "the assembly" frontend.** The survey was the first slice; Ting generalizes into the low-friction volunteer/resource surface. Its existing anonymous, no-PII, code-per-cohort model is an asset for parent-facing flows.
4. **Intake bus ≠ system of record.** knarr/Kafka captures multi-channel intent; a real DB owns authoritative state (see §3, §5.1).
5. **Keycloak + OpenBao are generic platform elements**, not Leiðangr-specific. They are built and validated as reusable platform (Phase 1) and only *then* consumed by Backstage (Phase 2).
6. **Fresh Backstage, modern systems.** Generate with `@backstage/create-app` on the new frontend system (default since v1.49.0) and new backend system; Yarn 4. Do **not** transplant the legacy GKE Backstage instance. Apply a curated DevEx overlay (root envelope, layered config, stub-by-default local dev, strict per-plugin config schemas).
7. **Privacy and safety are product requirements, not afterthoughts** (see §8).
8. **Plans distill into ADRs.** Heavy design/plan docs are post-processed into compact MADR-style ADRs once decisions are real, preserving rationale while letting bulky plans age out (see §9).

## 5. Open Questions

### 5.1 Where does the dynamic marketplace data live? *(resolve before Phase 4)*

Default lean: a **dedicated marketplace service** owning a Postgres DB (Mimir claim) + API, fed by the knarr processor and by direct API writes from Ting/Backstage. Backstage administers it via a plugin (later) or links out to it.

Candidate implementations:

| Option | Pros | Cons |
|---|---|---|
| **Django** *(current lean for a custom store)* | Free admin panel (covers Phase-4 operator UI cheaply), ORM, DRF API; prior experience (Autoboros) | Heavier; a new framework alongside Ting/knarr |
| FastAPI | Lighter; matches Ting/knarr Python; consistent toolchain | Build the admin UI yourself (or defer to a Backstage plugin) |
| Backstage backend plugin (Node) | Stays inside Backstage; Backstage's own DB/API machinery | Node; couples marketplace lifecycle to Backstage |
| **Lightweight issue tracker as the store** *(strong contender — evaluate first)* | Offers/needs/wishes become issues with labels and other categorization; Backstage plugin widgets run filtered label searches on the relevant entity pages; free comment threads, mentions, and audit history; natural sync surface to real dev projects' GitHub issues and to knarr pokes; much less wheel-reinvention | Power-user-leaning — the busy-parent UX still needs Ting fronting it; claim/transfer/expiry/moderation semantics strain a generic issue model (labels can fake state machines only so far); marketplace data in a tracker needs the same privacy discipline (§8); choice of tracker matters (GitHub Issues = external dependency; self-hosted Forgejo — see the existing forgejo-day2 arc — keeps it in-stack) |

Note these compose rather than strictly compete: a tracker could be the system of record for *opportunity-shaped* things (wishes, volunteer offers, project ideas) while structured marketplace state (claims, transfers, inventory counts) lives in a DB — or the tracker IS the MVP store and a DB comes only when the semantics outgrow it. The Backstage reference doc's own "Skill Exchange Lite" guidance points the same way: "start with GitHub issue labels and a Backstage page/card that indexes them." Evaluate the tracker path before committing to custom DB work.

**Low-barrier capture flows** (orthogonal to the store choice — they feed the intake bus): browser highlight-something-make-it-an-insight (à la Jira Product Discovery's clipper, minus Atlassian), the Obsidian Web Clipper (already in the stack's orbit), chat/SMS via knarr. Each lowers the engagement barrier; all land on the same Kafka intake topic and get processed into whatever store wins. Django (or Backstage backend services) remains useful for one-off apps needing a quick API surface regardless.

### 5.2 Catalog source of truth & sync
Hand-authored `catalog-info.yaml` (GitHub discovery) for MTL is fine to start; a custom entity provider can come later if entities are generated from the marketplace DB.

### 5.3 Matching strategy evolution
Start with manual browse + moderator matching; add rule-based matching once fields stabilize; defer recommendation-style matching (privacy + opacity cost).

### 5.4 Legacy reference material
The old "Logistics" repo and the legacy GKE Keycloak+Backstage may hold reusable Keycloak realm/client config. Treated as an optional time-saver if it surfaces easily — **not** a dependency. Design fresh and generic regardless.

## 6. Phase Roadmap

| Phase | Title | Depends on | Done signal |
|---|---|---|---|
| **1** | Platform prerequisites (OpenBao + Keycloak; plans 1a + 1b) | — | Both deploy env-aware (homelab + GKE); green kuttl smoke; closed out as reusable platform |
| **2** | Backstage skeleton + DevEx | 1 | Full SDLC loop closes: change → CI → image → GitOps → running Backstage with SSO |
| **3** | Community domain model | 2 | Catalog kinds defined; MTL entities seeded; Backstage admin surface live |
| **4** | Gear-swap MVP | 3, 5.1 resolved | One MTL season run end-to-end (Offer/Need/claim/expiry + moderator matching) |
| **A** *(parallel)* | knarr community bootstrap | — (knarr already built; not gated on Keycloak) | Real community bridged (Discord/Matrix/WhatsApp + bridge-phone SMS); manual chat swaps happening |
| **5** | knarr intent ingestion | A, 4 | chat/SMS → Kafka → processor → marketplace store; outbound expiry/coverage nudges |
| **6** | Volunteer/skill exchange, facility reservations, season-readiness scorecards | 4 | — |
| **7+** | PTA/schools expansion, Demicracy narrative, ADR distillation | 6 | — |

**Parallelism note:** Track A (knarr community bootstrap) is independent of Keycloak and can run alongside Phases 1–2 to deliver manual chat-swap value before the platform exists. Phase 5 connects that community back into the platform once the store (Phase 4) is real.

### Phase summaries (high-level; expanded only for Phase 1 below)

- **Phase 2 — Backstage skeleton + DevEx.** Fresh modern Backstage as a SiliconSaga component. Root DevEx envelope (`doctor`/`deps`/`db`/`dev`/`test`/`config-check`), docker-compose Postgres for local, **stub mode by default**, Keycloak OIDC sign-in, GitHub App catalog discovery, TechDocs, GitHub Actions CI. Deployed via custom image → GHCR → Helm (`backstage/charts`) under ArgoCD, env-aware through `cluster-identity`, Postgres via a Mimir claim, secrets via OpenBao + ESO. Mind the demo-image startup-probe gotcha — build a real image, tune probes.
- **Phase 3 — Community domain model.** Define `CommunityGroup`, `Program`/`Season`, `Activity`, `ResourceType`, `Facility` as catalog-backed kinds (do not overload `Component`). Seed real MTL data. Build Backstage entity pages, docs, and search. Add catalog-hygiene scorecard checks.
- **Phase 4 — Gear-swap MVP.** Marketplace store (§5.1) with `ResourceOffer`, `ResourceNeed`, `Transfer`, moderation state. Ting flows: Offer / Need / browse / claim / expiry. Manual browse + moderator matching. Adult-only identity via Keycloak. Run one season-bound gear swap with explicit pickup rules.
- **Phase 5 — knarr intent ingestion.** A `knarr.leidangr.intent` topic; a processor that extracts structured offers/needs from chat and bridge-phone SMS (LLM-assisted), dedupes, and writes the marketplace store. Outbound notifications via the existing Heimdall→ntfy seam: expiry nudges, uncovered-volunteer alerts, moderation-queue counts.
- **Phase 6 — Expansion.** Volunteer/skill-exchange profiles ("can mentor / can help / want to learn"), facility reservation workflow, season-readiness scorecards (Tech Insights or a grouped-checks custom plugin), framed as operational status, not judgment.
- **Phase 7+ — Breadth + governance.** PTA/schools surfaces (more privacy-sensitive — gated on review), Demicracy narrative integration, and ADR distillation of these plans.

## 7. Phase 1 — Platform Prerequisites *(specified)*

**Goal:** Stand up OpenBao and Keycloak as generic, reusable platform services in the SiliconSaga stack, env-aware across homelab and GKE, validated with kuttl, and closed out independently of anything Leiðangr-specific. They complete the secret-management and SSO substrate that Phase 2's Backstage (and later Ting) will consume.

**Starting truth:** Nidavellir has **no Keycloak/OpenBao app manifests yet** — `apps/kustomization.yaml` carries TODO comment placeholders for both, and the realm's `stack-tier-2.md` lists them as planned. Both are greenfield here. The legacy GKE Keycloak is not in this workspace and is not assumed.

**Scope:**

- **OpenBao** deployed via its official Helm chart, with **External Secrets Operator** wired so Kubernetes Secrets are projected from OpenBao KV paths. Pin a version; keep provider-specific auth/paths behind a thin script/abstraction. Validate the exact auth method and KV/API paths intended for downstream use.
- **Keycloak** deployed as the ecosystem identity provider, with a realm and at least a placeholder client suitable for OIDC (the real Backstage/Ting clients are configured when those consumers arrive). If Keycloak needs Postgres, provision it via a **Mimir** claim, consistent with Ting/knarr.
- **Env-awareness** through the `cluster-identity` EnvironmentConfig (homelab vs GKE differences: storage class, replicas, hostnames), following the established Crossplane-composition pattern.
- **GitOps placement** in Nidavellir's app-of-apps, synced via ArgoCD from seed-Gitea (homelab = staging; test through Git re-hydration, not `kubectl apply`).

**Testing / done criteria:**

- Both components deploy cleanly on a fresh homelab bootstrap and on GKE.
- **kuttl smoke tests** assert: OpenBao reachable and unsealed/initialized as configured; an ESO `ExternalSecret` successfully materializes a Kubernetes Secret from an OpenBao KV path; Keycloak reachable and its OIDC discovery endpoint (`.well-known/openid-configuration`) responds for the realm.
- Phase closed out as a self-contained platform increment with its own CR(s) and (per §9) any durable decisions distilled to ADRs.

**Non-goals for Phase 1:** No Backstage. No Leiðangr domain modeling. No production hardening beyond a "very basic" working instance — the aim is a complete, testable SDLC substrate, not a fully tuned identity platform.

**Detailed implementation plans:** Phase 1 splits into two independent companion plans (the two subsystems share no dependency — Keycloak's Postgres comes from Mimir, not OpenBao):

- [`2026-06-09-leidangr-phase1a-openbao-eso-plan.md`](2026-06-09-leidangr-phase1a-openbao-eso-plan.md) — OpenBao + External Secrets Operator
- [`2026-06-09-leidangr-phase1b-keycloak-plan.md`](2026-06-09-leidangr-phase1b-keycloak-plan.md) — Keycloak (Operator-based, Mimir Postgres)

Both were produced via the writing-plans workflow after inspecting Nidavellir's app-of-apps, the heimdall composition pattern, and Mimir's Postgres claim + kuttl conventions.

## 8. Privacy, Safety, and Trust

This domain involves children, schools, families, and locations. Treat privacy and safety as primary product requirements from Phase 3 onward:

- **Adult accounts only** by default; avoid child accounts absent a deliberate legal/privacy review.
- **Minimal child data** — model age group / grade band / team / size when needed; never store children's names, photos, precise schedules, or education records. Prefer "size 2 cleats needed for U8 soccer" over any child identifier. (COPPA applies to services directed at under-13s; FERPA may apply if the platform touches education records — keep it focused on adult volunteers and non-educational operational data.)
- **Private by default** — offers, needs, and contact details visible only to the relevant group, approved volunteers, or moderators.
- **No exact public locations** — use managed pickup points or moderator-mediated handoffs, not home addresses.
- **Moderated exchange** — report/flag workflows and admin audit trails before any broad rollout.
- **Time-boxed data** — seasons end, children grow, needs expire. Every dynamic record has an expiry or archival path, and adults can remove their profile.
- **Trust over gamification** — recognition is fine; leaderboards that shame volunteers or expose family circumstances are not.

## 9. Provenance & Process

- **Realm convention:** a `*-design.md` (this doc — architecture across phases) pairs with phased `*-plan.md` docs (detailed implementation, early phases first), mirroring `knarr-design` + `knarr-phase0-phase1-plan`, `ting-pilot-design` + `ting-pilot-plan`, etc.
- **Brainstorm → plan → build:** this design exits the brainstorming flow into the writing-plans workflow for Phase 1.
- **Plan → ADR distillation:** once a phase's decisions are real, distill durable decisions (e.g., "Keycloak OIDC," "OpenBao-first secrets," "Backstage is control-plane, Ting is the parent UI," "intake bus vs. system of record") into compact MADR-style ADRs with commit-stable provenance links, so heavy plans can later be archived without losing rationale. A future `gdd-adr-distillation` skill could own this.
- **Tone discipline:** any user-facing surface (Ting flows, schools/PTA copy, MTL site) follows the realm Tone Guide; this engineering doc does not.

## 10. References

- Ting pilot: [`2026-05-10-ting-pilot-design.md`](2026-05-10-ting-pilot-design.md)
- knarr: [`2026-04-02-knarr-design.md`](2026-04-02-knarr-design.md)
- MTL site: [`2026-04-08-mtl-site-design.md`](2026-04-08-mtl-site-design.md)
- Backstage DevEx reference: [`2026-06-09-backstage-devex-workspace-design.md`](2026-06-09-backstage-devex-workspace-design.md)
- `schools` repo — manifesto/narrative (esp. `15-pta-coordination`, `19-community-sports`, `next-year.md`)
- Backstage new frontend default (v1.49.0): https://backstage.io/docs/frontend-system/
- Backstage on Kubernetes / Helm: https://backstage.io/docs/deployment/k8s/ · https://github.com/backstage/charts
- Backstage Keycloak OIDC: https://backstage.io/docs/auth/oidc/
- OpenBao on Kubernetes: https://openbao.org/docs/platform/k8s/ · ESO provider: https://external-secrets.io/latest/provider/openbao/
