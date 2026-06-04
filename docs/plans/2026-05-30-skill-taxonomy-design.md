# SiliconSaga Skill Taxonomy Design

**Status:** revised 2026-06-01 — after first-pass implementation surfaced a tier-rule ambiguity; root-level infra skills moved to their owning components per the ownership test below.
**Original draft:** 2026-05-30.

## Goal

Reorganize the SiliconSaga realm's agent skills into a focused, gap-filling set: adopt mature community skills where they exist (notably `grafana/skills`), author only the genuine gaps, and place every skill at the tier where the knowledge is genuinely owned — so lower tiers defer upward instead of duplicating content.

## Principle

Each skill lives at the **highest tier where the knowledge is genuinely owned** — not just where it might be useful. Three tiers exist:

- **Workspace root** `.agent/skills/` — generic developer-workspace capabilities where no specific component owns the knowledge. Sibling in flavor to `tdd`, `bdd`, `scribe`, `gdd-housekeeping`: anyone in any workspace might need them, and no single component wrote the canonical content.
- **Realm** `realm-siliconsaga/.agent/skills/` — SiliconSaga ecosystem glue + the **skill index** pointing at component skills. Cross-component coordination, the stack narrative, the homelab-vs-GKE shape.
- **Component** `components/<repo>/.agent/skills/` — operational knowledge of whatever that component owns. The component is the experts-of-record for its own stack choices.

### The ownership test

If a knowledge area is the result of running an **opinionated platform choice** — AlertManager vs Grafana-managed alerting, ArgoCD vs Flux, Crossplane vs raw K8s OpenAPI — the skill belongs with the component that made that choice and operates it day-to-day, not at root. If no component owns the knowledge — kuttl, BDD test patterns, generic workspace tooling — root is the honest home.

The earlier draft's "highest applicable tier by *capability*" rule risked conflating *usability* (anyone might benefit → root) with *ownership* (the knowledge was earned operating a specific component → component). The refined test asks "where does the hard-won knowledge come from?", not "who might benefit?"

### Worked examples

- **`kuttl-testing`** → **root.** Kuttl is a generic K8s e2e test framework. Nordri, Heimdall, and Mimir all use it; none of them owns it. Sibling in flavor to TDD/BDD: cross-cutting developer-workspace tooling.
- **`alertmanager-config`** → **Heimdall.** AlertManager is one of several alerting choices with competing options. Heimdall is where the SiliconSaga stack made that choice and earned the operational knowledge (routing trees, Watchdog dead-man's-switch idiom, webhook payload/header templating decisions, severity→priority).
- **`kube-prometheus-stack`** → **Heimdall.** Heimdall is built on this chart. Heimdall is the experts-of-record.
- **`argocd-gitops`** → **Nordri.** ArgoCD is the opinionated GitOps choice; Nordri ships and operates it. Other components author Applications as *consumers* — the deep operational knowledge (CRD chicken-and-egg, sync waves, test-through-Git, parent-prune footgun) is Nordri's.
- **`crossplane-compositions`** → **Nordri.** Crossplane is part of Nordri's substrate. Multiple components *author* Compositions, but the platform knowledge (Pipeline mode, provider-kubernetes v1alpha2, CEL readiness, RWO/Recreate trap, GitOps flapping) is Nordri's lever.

## Skill Map

### Workspace root `.agent/skills/`

#### Keep as-is

- **`kuttl-testing`** — generic kuttl invocation, `--config kuttl-test.yaml` requirement, common timing pitfalls. No component owns kuttl; lower tiers defer here.

#### Not at root (revised from original draft)

The originally-planned root skills — `alertmanager-config`, `kube-prometheus-stack`, `crossplane-compositions`, `argocd-gitops` — were authored at root during initial Phase 1+2 work (yggdrasil PRs #78–81) per the draft taxonomy. After this review, they move to their owning components: each is an opinionated platform choice with competing alternatives, so the component that operates it is the experts-of-record. See the Component section below for landing places.

The pre-existing GDD methodology skills (`writing-yggdrasil-docs`, `scribe`, `gdd-housekeeping`, etc.) stay at root unchanged — they're explicitly the framework-of-GDD content the root was always meant to carry.

### Realm `realm-siliconsaga/.agent/skills/`

#### Keep as-is

- **`terasology-testing`** — untouched.

#### New — the index + glue

- **`siliconsaga-stack`** — *new* realm skill. Two jobs:
  - **Stack narrative** — how the SiliconSaga ecosystem fits together:
    - Substrate (nordri: Traefik, Crossplane, Velero, Longhorn, Garage S3, the in-cluster seed-gitea + ArgoCD).
    - Data (mimir: Kafka/Valkey/Percona PG/MySQL/MongoDB via Crossplane Compositions).
    - Observability (heimdall: kube-prometheus-stack + Loki + Tempo).
    - GitOps model: ArgoCD in the `argo` namespace syncs from in-cluster seed-gitea; seed-gitea is hydrated from local working trees via `update-embedded-git.sh <homelab|gke>`. The re-hydrate-to-test-a-local-branch workflow (homelab = staging).
    - Cluster identity / env-aware compositions (`cluster-identity` EnvironmentConfig pattern).
    - Notification delivery (ntfy + Tailscale operator + `tag:ntfy` ACL pattern).
  - **Skill index** — names which component owns which capability so an agent with a bare yggdrasil + realm checkout knows where to look:
    - AlertManager → `components/heimdall/.agent/skills/alertmanager-config/`
    - Kube-Prometheus-Stack → `components/heimdall/.agent/skills/kube-prometheus-stack/`
    - ArgoCD → `components/nordri/.agent/skills/argocd-gitops/`
    - Crossplane Compositions → `components/nordri/.agent/skills/crossplane-compositions/`
    - Heimdall composition specifics → `components/heimdall/.agent/skills/heimdall/`
    - Nordri bootstrap → `components/nordri/.agent/skills/nordri/`

  The index is navigation: a bare yggdrasil + realm checkout reads it and knows which component to clone for the deep content. Defers to root for genuinely generic content (`kuttl-testing`).

### Realm `realm-siliconsaga/docs/`

*(New section in this revision.)*

Stack-level **narrative documentation** lives here — not at root, not assembled-from-component-docs. The realm owns the prose explaining how its stack hangs together; `ecosystem.yaml` is already the machine-readable index of which components belong at which tier (this is how the whole stack was originally checked out in one go, even if it hasn't been the active workflow during months of stable workspaces). The docs dir is the human-readable companion.

Scope discipline: the realm docs describe **shape** (what Heimdall is, that AlertManager is its alerting choice, that ntfy is the notification destination), not **details** (the dead-man's-switch routing config — that's a Heimdall skill concern). The docs dir defers to component skills for operational depth.

### Component `.agent/skills/`

- **`components/heimdall/`** — *new + expanded scope* (becomes the home for AM + k-p-stack content, not just a thin Heimdall-specifics skill):
  - `alertmanager-config` — ported from yggdrasil PR #78.
  - `kube-prometheus-stack` — ported from yggdrasil PR #79.
  - `heimdall` — thin Heimdall-specific layer: claim parameters, ntfy receiver wiring, dormant Knarr seam, severity→priority mapping, how this specific stack instantiates the generic patterns from the two skills above.
- **`components/nordri/`** — *new + expanded scope*:
  - `argocd-gitops` — ported from yggdrasil PR #81.
  - `crossplane-compositions` — ported from yggdrasil PR #80.
  - Slim `nordri` bootstrap skill — Nordri-specific layers (Layer 2 Gitea, Layer 2.5/2.6/2.7/2.8 CRDs, Layer 3 ArgoCD adoption, Layer 4 root app, Layer 5 Garage init), pinned versions table, Garage + Velero specifics. Defers up to root for `kuttl-testing`, defers in-component for the ArgoCD/Crossplane operational depth.
- **`components/ymir/`** — `ymir-dev`, `ymir-api` — existing, untouched.

### Adopt (external)

- **[`grafana/skills`](https://github.com/grafana/skills)** — official Apache-2.0, ~30 CI-validated SKILL.md files. **Adopt** as a reference/dependency for PromQL, Grafana dashboards, Loki, Tempo. Caveat: LGTM/Grafana-Cloud-flavored (favors Mimir + Grafana-managed alerting). Not a drop-in for native AlertManager. Referenced from the Heimdall component skills.
- **Community ArgoCD skills** (optional, partial): ClaudSkills, julianobarbosa/claude-code-skills, etc. Unvetted community repos — reference at most, don't hard-depend. `argocd-gitops` (in Nordri) stays the authoritative skill for SiliconSaga's gotchas.

## Discovery + Surfacing (linked concern)

This taxonomy assumes the skills will actually surface. Today realm and component `.agent/skills/` skills aren't registered in Claude Code's native discovery path; surfacing depends on the GDD orientation skill enumerating them at session start (fragile — fails when orientation doesn't run).

The proposed fix lives in the parallel **skill discovery + enhancement mini-design** captured in `Loki-thalamus.md` → Design Notes. Headline: register skills into each agent's native discovery path via `ws realm use` / clone (agent-agnostic fan-out: Claude → `.claude/skills/`, Codex → its `AGENTS.md`, Cursor → `.cursor/rules/`, …), with hook nudges as the reactive cross-agent backstop. Demote orientation to a "what's relevant now" summarizer.

The component-level home for skills under this revised taxonomy makes the surfacing fix *more* important, not less — without discovery wiring, the realm index breadcrumb only helps agents who already know to read it. Issues to file in tandem.

## Implementation Order

Phases 1+2 in the original draft were executed against the root-placement plan and resulted in yggdrasil PRs #78–81 (clean, review-passed, awaiting merge). After this revision, those PRs **close without merging** and the content ports to the component repos.

1. **Phase 1-revised — port skills to components.** Open PRs against `components/heimdall` (`alertmanager-config`, `kube-prometheus-stack`) and `components/nordri` (`argocd-gitops`, `crossplane-compositions`). Reuse the SKILL.md content from yggdrasil PRs #78–81 verbatim — it's been review-cleaned and is ready. Close the yggdrasil PRs with a pointer to the component PRs explaining the taxonomy revision.
2. **Phase 2 — realm `siliconsaga-stack`.** Author the realm skill: stack narrative + skill index pointing at the component homes from Phase 1.
3. **Phase 3 — realm `docs/` dir.** Author `realms/realm-siliconsaga/docs/` for the high-level stack narrative (human-readable companion to `ecosystem.yaml`). Defers to component skills for operational depth.
4. **Phase 4 — slim `nordri` component skill.** Extract Nordri-specific bootstrap content from the realm's old `nordri-bootstrap-guide` into the new `components/nordri/.agent/skills/nordri/`. Realm AGENTS.md table updates to point there.
5. **Adoption wiring.** Reference `grafana/skills` from `kube-prometheus-stack` (now in Heimdall) and from `siliconsaga-stack`.

Each phase is independently shippable; dependencies are documentation-only (cross-references finalize at merge time).

## Naming Conventions

- **Capability-style:** lowercase-kebab-case, named after the capability or tool — `alertmanager-config`, `crossplane-compositions`, `kube-prometheus-stack`, `argocd-gitops`, `kuttl-testing`.
- **Stack-level:** ecosystem-prefixed where the scope is "how the ecosystem fits" — `siliconsaga-stack`.
- **Single-component:** the component name — `nordri`, `heimdall`.
- **Deprecated** (legacy "on-k3d" suffixes): drop. Skills are about the *capability*, not the cluster flavor; environment-specifics belong in the skill body.

## Open Questions

- **`grafana/skills` adoption mechanism** — git submodule, vendored sync, or documented references only? Lean: documented references for now; revisit if multi-repo skill marketplaces mature.
- **Skill split granularity** — does `alertmanager-config` need to split further (e.g. `alertmanager-routing`, `alertmanager-templating`)? Lean: start unified, split only if either grows past skill-size threshold (~250 lines).
- **Vetted community ArgoCD reference** — pick one (julianobarbosa/claude-code-skills looks most mature at 55 skills) or leave the field referenced as "any of these, check before adopting"? Lean: leave as an unvetted-pointer note; revisit once we actually need one.
- **(New)** **Index drift in the realm.** With skill homes spread across components, the realm's `siliconsaga-stack` index can drift if a component renames or moves a skill without updating the index. Worth a Tier-2 hook nudge: when a component adds/renames a `.agent/skills/<x>/SKILL.md`, prompt to update the realm index. Track as a concern in `Loki-thalamus.md`.

## Out of Scope

- The discovery/registration wiring (see linked mini-design).
- Writing the actual SKILL.md files (Phase 1+ uses `superpowers:writing-skills`; this spec is the brief).
- Reorganizing the workspace-root GDD / methodology skills (`gdd-*`, `scribe`, etc.) — they're a different concern (GDD methodology, not infra ownership).

## Self-Review Notes

- **Placeholders:** none.
- **Internal consistency:** the deferral chain is now component ← realm ← root for navigation, with content authored at the ownership tier. Worked examples and skill map align with the principle.
- **Scope:** focused on infra/observability skills (the user's "Heimdall set + reorg" framing). Component skills for ymir/terasology and root GDD/methodology skills are explicitly out of scope.
- **Revision integrity:** principle change is substantive (ownership vs usability tier rule). Existing yggdrasil PRs #78–81 are clean but go to component repos instead of merging at root; no work is wasted, only re-routed.
