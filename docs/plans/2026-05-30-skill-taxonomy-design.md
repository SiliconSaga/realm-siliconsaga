# SiliconSaga Skill Taxonomy Design

**Status:** draft — pending user review
**Date:** 2026-05-30

## Goal

Reorganize the SiliconSaga realm's agent skills into a focused, gap-filling set: adopt mature community skills where they exist (notably `grafana/skills`), author only the genuine gaps, and place every skill at the highest applicable tier so lower tiers defer upward instead of duplicating content.

## Principle

Each skill lives at the **highest applicable tier** by capability. Lower-tier skills point at higher-tier skills (defer up) instead of copying their content. Three tiers exist in this workspace:

- **Workspace root** `.agent/skills/` — generic capabilities reusable by any realm/cluster.
- **Realm** `realm-siliconsaga/.agent/skills/` — SiliconSaga ecosystem-specific (cross-component).
- **Component** `components/<repo>/.agent/skills/` — repo-specific.

A capability that genuinely applies to any realm (e.g. kuttl, Crossplane patterns, ArgoCD gotchas, AlertManager config) belongs at root. A capability that's intrinsically about how *our* nordri+mimir+heimdall fit together belongs at realm. A capability that's about one repo's internals belongs in that component.

## Skill Map

### Workspace root `.agent/skills/`

#### Keep as-is

- **`kuttl-testing`** — generic kuttl invocation, `--config kuttl-test.yaml` requirement, common timing pitfalls. Realm/component skills defer here for all kuttl content.

#### Move + enhance (from realm)

- **`crossplane-compositions`** — move `crossplane-on-k3d` to root + rename + add:
  - `crossplane render <comp> <xr> <functions>` for **offline composition validation** (faster than deploy-and-inspect; what we should have used during the ntfy work).
  - The **RWO + RollingUpdate → `Recreate` deadlock** for single-replica RWO-backed Deployments (surfaced on GKE during the ntfy rollout: Multi-Attach error stalls the rollout indefinitely; `strategy: Recreate` is the fix).
  - The **SSA in-place migration trap**: you can't SSA-patch an existing `RollingUpdate` Deployment to `Recreate` — the API rejects `strategy.rollingUpdate` under `type: Recreate`. The live Deployment must be deleted once so Crossplane recreates it cleanly.
  - **"Flapping CompositionRevision counter = something else is reconciling"** as the tell that a Crossplane-managed resource is GitOps-managed (we kept fighting ArgoCD self-heal).
  - Citation: official Crossplane docs.

- **`argocd-gitops`** — move `argocd-bootstrap-on-k3d` to root + rename + add:
  - **Test through GitOps, not kubectl**: ArgoCD self-heal reverts direct `kubectl apply` to managed resources. Re-hydrate the source instead.
  - Project convention: apps live in the **`argo`** namespace (not `argocd`).
  - Hard-refresh via the `argocd.argoproj.io/refresh=hard` annotation when an app needs a kick.
  - **A stale seed-gitea makes staging inauthentic** — re-hydrate first when testing local branches.
  - Community wild ArgoCD skills (ClaudSkills, julianobarbosa/claude-code-skills, etc.) cover general ArgoCD usage well but are unvetted community repos — reference at most, don't hard-depend like we do on `grafana/skills`. This skill stays focused on the operational gotchas above.

#### Author new (genuine gaps)

- **`alertmanager-config`** — native AlertManager: routing trees, the `null` blackhole / Watchdog idiom, inhibit/silence rules, notification templating, `amtool check-config` for CI validation, severity→priority via server-side templating (the ntfy-template pattern). No mature wild skill exists for this — `grafana/skills`'s `alerting-irm` covers Grafana-managed alerting, not native AlertManager. Cites the official [AlertManager config reference](https://prometheus.io/docs/alerting/latest/configuration/) and [`amtool`](https://github.com/prometheus/alertmanager).

- **`kube-prometheus-stack`** — chart wiring, Prometheus Operator CRDs (ServiceMonitor/PrometheusRule selectors), RWO+Recreate for stateful bits, taming the noisy default criticals (`TargetDown`/`Kube{Proxy,Scheduler,ControllerManager}Down`/`AlertmanagerClusterFailedToSendAlerts` etc. on managed K8s where the control plane isn't scraped). Includes a **"Running on managed K8s: dual-stack cost discipline"** section covering:
  - The two-pipes architecture (container stdout → GKE/EKS/AKS native logging *and* → Promtail/Loki) and that you pay the cloud regardless.
  - The **fluent-bit ↔ GKE-plugin meta-chatter** pattern on `127.0.0.1:2021` (fluent-bit logs every successful HTTP forward to its sidecar plugin; that meta-log itself ships to Cloud Logging).
  - The **Cloud Logging sink-exclusion recipe** (`gcloud logging sinks update _Default --add-exclusion=...` with reversal command). Includes the bucket-vs-sink distinction (`--restricted-fields` on a bucket is access control, NOT ingestion exclusion).
  - References `grafana/skills` for PromQL, Grafana dashboards, Loki, Tempo.
  - Cites the [kube-prometheus-stack chart README](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) and the [Prometheus Operator CRD docs](https://prometheus-operator.dev/docs/).

### Realm `realm-siliconsaga/.agent/skills/`

#### Leave alone (out of scope)

- **`terasology-testing`** — untouched.

#### Split (from `nordri-bootstrap-guide`)

- **`siliconsaga-stack`** — *new*. How the SiliconSaga ecosystem fits together:
  - **Substrate** (nordri: Traefik, Crossplane, Velero, Longhorn, Garage S3, the in-cluster seed-gitea + ArgoCD).
  - **Data** (mimir: Kafka/Valkey/Percona PG/MySQL/MongoDB via Crossplane Compositions).
  - **Observability** (heimdall: kube-prometheus-stack + Loki + Tempo).
  - **GitOps model**: ArgoCD in the `argo` namespace syncs from the in-cluster seed-gitea; the seed-gitea is hydrated from local working trees via `update-embedded-git.sh <homelab|gke>`. The **re-hydrate-to-test-a-local-branch** workflow (homelab = staging).
  - **Cluster identity / env-aware compositions** (the `cluster-identity` EnvironmentConfig pattern; homelab vs GKE differences).
  - **Notification delivery** (ntfy + Tailscale operator + the `tag:ntfy` ACL pattern).
  - Defers to root `crossplane-compositions` / `argocd-gitops` / `kuttl-testing` / `alertmanager-config` / `kube-prometheus-stack` for generic content; covers only the SiliconSaga-specific glue.

- **`nordri`** — *slimmed* from `nordri-bootstrap-guide`. Only nordri-specific content:
  - The actual bootstrap sequence (Layer 2 Gitea, Layer 2.5/2.6/2.7/2.8 CRDs, Layer 3 ArgoCD adoption, Layer 4 root app, Layer 5 Garage init).
  - Pinned versions table.
  - Garage + Velero specifics.
  - Generic content (kuttl conventions, ArgoCD CRD ordering, Crossplane provider setup, ServerSideApply, Kustomize `helmCharts`) — *defer up* to root skills.

### Component `.agent/skills/`

- **`components/ymir/`** — `ymir-dev`, `ymir-api` — existing, untouched.
- **`components/heimdall/`** — *new* thin Heimdall component skill: documents only the specific Heimdall composition / claim parameters / the ntfy receiver wiring / the dormant Knarr seam. Defers to root `alertmanager-config` + `kube-prometheus-stack` + `crossplane-compositions` for everything else.

### Adopt (external)

- **[`grafana/skills`](https://github.com/grafana/skills)** — official Apache-2.0, ~30 CI-validated SKILL.md files. **Adopt** as a reference/dependency for PromQL, Grafana dashboards, Loki, Tempo. Caveat: LGTM/Grafana-Cloud-flavored (favors Mimir + Grafana-managed alerting). Not a drop-in for native AlertManager. Referenced from `kube-prometheus-stack` and the heimdall component skill.

- **Community ArgoCD skills** (optional, partial): ClaudSkills, julianobarbosa/claude-code-skills, etc. Unvetted community repos — reference at most, don't hard-depend. `argocd-gitops` stays the authoritative skill for our gotchas.

## Discovery + Surfacing (linked concern)

This taxonomy assumes the skills will actually surface. Today realm `.agent/skills/` skills aren't registered in Claude Code's native discovery path; surfacing depends on the GDD orientation skill enumerating them at session start (fragile — fails when orientation doesn't run).

The proposed fix lives in the parallel **skill discovery + enhancement mini-design** captured in `Loki-thalamus.md` → Design Notes. Headline: register skills into each agent's native discovery path via `ws realm use` / clone (agent-agnostic fan-out: Claude → `.claude/skills/`, Codex → its `AGENTS.md`, Cursor → `.cursor/rules/`, …), with hook nudges as the reactive cross-agent backstop. Demote orientation to a "what's relevant now" summarizer.

That work is **out of scope for this spec** but blocks the value of the taxonomy: without surfacing, the skills are still dormant reference docs. Issues to file in tandem.

## Implementation Order

1. **Phase 1 — author the gaps (highest value).** Author the two new root skills using `superpowers:writing-skills`:
   - `alertmanager-config`
   - `kube-prometheus-stack` (includes the dual-stack-cost section + the GKE log-exclusion recipe).
2. **Phase 2 — move + enhance existing root capabilities.** Move `crossplane-on-k3d` → root `crossplane-compositions` (with the render / RWO-Recreate / SSA-migration / flapping additions). Move `argocd-bootstrap-on-k3d` → root `argocd-gitops` (with the test-through-GitOps / `argo`-ns / hard-refresh / stale-seed additions).
3. **Phase 3 — realm split.** Slim `nordri-bootstrap-guide` → realm `nordri`. Author realm `siliconsaga-stack`.
4. **Phase 4 — component thin layer.** Author `components/heimdall/.agent/skills/heimdall/`.
5. **Adoption wiring.** Add `grafana/skills` references from `kube-prometheus-stack` + the heimdall component skill. Optionally add a referenced (vetted) community Argo skill for general 101.

Each phase is independently shippable; the dependencies are documentation-only (e.g. nordri's slim skill references root skills that should exist first, but it can be authored in parallel and the references finalized at merge).

## Naming Conventions

- **Capability-style:** lowercase-kebab-case, named after the capability or tool — `alertmanager-config`, `crossplane-compositions`, `kube-prometheus-stack`, `argocd-gitops`.
- **Stack-level:** ecosystem-prefixed where the scope is "how the ecosystem fits" — `siliconsaga-stack`.
- **Single-component:** the component name — `nordri`, `heimdall`.
- **Deprecated** (legacy "on-k3d" suffixes): drop. The skills are about the *capability*, not the cluster flavor; environment-specifics belong in the skill body.

## Open Questions

- **`grafana/skills` adoption mechanism** — git submodule, vendored sync, or documented references only? Lean: documented references for now; revisit if multi-repo skill marketplaces mature.
- **Skill split granularity** — does `alertmanager-config` need to split further (e.g. `alertmanager-routing`, `alertmanager-templating`)? Lean: start unified, split only if either grows past skill-size threshold (~250 lines).
- **Vetted community ArgoCD reference** — pick one (julianobarbosa/claude-code-skills looks most mature at 55 skills) or leave the field referenced as "any of these, check before adopting"? Lean: leave as an unvetted-pointer note; revisit once we actually need one.

## Out of Scope

- The discovery/registration wiring (see linked mini-design).
- Writing the actual SKILL.md files (Phase 1+ uses `superpowers:writing-skills`; this spec is the brief).
- Reorganizing the workspace-root GDD / methodology skills (`gdd-*`, `scribe`, etc.) — they're a different concern (GDD methodology, not infra capabilities).

## Self-Review Notes

- **Placeholders:** none.
- **Internal consistency:** the deferral chain (component → realm → root) is symmetric across the skill list; `siliconsaga-stack` and `nordri` consistently defer up; component `heimdall` consistently defers further up.
- **Scope:** focused on infra/observability skills (the user's "Heimdall set + reorg" framing). Component skills for ymir/terasology and root GDD/methodology skills are explicitly out of scope.
- **Ambiguity:** the "thin" qualifier for the heimdall component skill and "slim" for realm `nordri` are described by what they *don't* contain (deferred up) rather than a hard line count — intentional, both will calibrate during Phase 3/4 authoring.
