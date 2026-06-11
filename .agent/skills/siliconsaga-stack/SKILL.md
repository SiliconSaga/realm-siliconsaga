---
name: siliconsaga-stack
description: Use when working anywhere in the SiliconSaga ecosystem and needing the navigation map — which component owns which capability (alerting, GitOps, Compositions, observability, notifications, secrets), how the pipelines fit together (PrometheusRule → AlertManager → ntfy → phone; OpenBao → ESO → Kubernetes Secret), what to clone in a bare workspace to access a specific deep skill, the homelab-vs-GKE seam, or the in-cluster-Gitea GitOps model that differs from "push to GitHub." Index + stack narrative; defers to component skills for operational depth.
---

# siliconsaga-stack

## Overview

SiliconSaga is a tiered community stack declared in the workspace `ecosystem.yaml`. **Nordri** is the Tier 1 substrate (Traefik, Crossplane, Velero, Longhorn, Garage S3, seed-Gitea, ArgoCD). **Nidavellir** is the Tier 2 platform app-of-apps (the home for `ntfy`, `tailscale-operator`, `keycloak`, etc.). **Heimdall**, **Mimir**, and other Tier 2 components own specific capabilities. Tier 3 components (`ymir`, `terasology`, `destinationsol`, `ting`) are end-user-facing.

This skill is the realm **index + stack narrative**. Deep operational knowledge for each capability lives in the owning component's `.agent/skills/`; this skill points you at the right one and explains how the pieces hang together so you don't have to grep the whole workspace.

## When to Use

- "Where does the [AlertManager / ArgoCD / Crossplane / kube-prometheus-stack] knowledge live in this workspace?"
- "I'm adding a new service to the stack. What are the platform conventions for GitOps, observability, alerting?"
- "An alert just fired — what's the full path from PrometheusRule to my phone, and who owns each piece?"
- "I have a bare yggdrasil + realm checkout. What do I need to clone for X?"
- "How does the homelab cluster differ from GKE in this stack?"

NOT for the operational details of any single capability — those live in the owning component's skill (see Skill Index below). NOT for non-SiliconSaga realms (the index entries are SiliconSaga-specific).

## Stack Tier Map

| Tier | Component | Role |
|---|---|---|
| 1 (substrate) | **nordri** | Cluster substrate: Traefik (ingress), Crossplane (platform API), Velero (backup), Longhorn (block storage, homelab), Garage S3 (object storage, homelab), in-cluster seed-Gitea (GitOps source-of-truth), ArgoCD (deployment controller in ns `argo`). |
| 2 (platform app-of-apps) | **nidavellir** | Owns platform Application manifests — `ntfy/`, `tailscale-operator/`, `openbao/` (secrets), `external-secrets/` (ESO), `keycloak/`, `vegvisir/`, `mimir/`. Where you add a new platform Application. |
| 2 (component) | **heimdall** | Observability — kube-prometheus-stack (Prometheus + AlertManager + Grafana), Loki, Tempo. Owns the AM config that routes alerts. |
| 2 (component) | **mimir** | Data services via Crossplane Compositions — Kafka, Valkey, Percona PG/MySQL/MongoDB. |
| 2 (component) | **vordu** | BDD roadmap visualization. |
| 2 (component) | **tafl**, **bifrost** | Board-game engine + bridge/gateway. |
| 3 (end-user) | **ymir**, **terasology**, **destinationsol**, **ting** | End-user-facing platforms / games / parent-advocacy tooling. |

Source-of-truth: `ecosystem.yaml` at workspace root. `ws list` summarizes current clone state.

## Skill Index

| Capability | Skill | Home | Bare-workspace? |
|---|---|---|---|
| Crossplane Compositions (Pipeline mode, `crossplane render`, RWO+Recreate, CompositionRevision flapping) | `crossplane-compositions` | `components/nordri/.agent/skills/` | `ws clone nordri` |
| ArgoCD GitOps (CRD chicken-and-egg, test-through-Git, app-of-apps prune, SSA for large CRDs, hard-refresh) | `argocd-gitops` | `components/nordri/.agent/skills/` | `ws clone nordri` |
| AlertManager config (routing trees, Watchdog dead-man's-switch, webhook payload templating, amtool) | `alertmanager-config` | `components/heimdall/.agent/skills/` | `ws clone heimdall` |
| kube-prometheus-stack (chart wiring, `release:` label requirement, RWO+Recreate, GKE dual-stack-cost) | `kube-prometheus-stack` | `components/heimdall/.agent/skills/` | `ws clone heimdall` |
| Secrets (OpenBao sealing/unseal + init runbooks, ESO ClusterSecretStore, KV v2 `data/` path gotcha, key custody) | doc, not skill yet: `docs/secrets-management.md` | `components/nidavellir/docs/` | `ws clone nidavellir` |
| Kuttl end-to-end testing (Claim→Ready, AM config-reload assertions) | `kuttl-testing` | workspace-root `.agent/skills/` | always available |
| Terasology engine + MTE integration tests | `terasology-testing` | `realms/realm-siliconsaga/.agent/skills/` | always available |
| Nordri bootstrap (Layer 2 Gitea, Layer 2.5–2.8 CRDs, Layer 3 ArgoCD adoption, Layer 5 Garage init) | `nordri` | `components/nordri/.agent/skills/` | `ws clone nordri` |
| Heimdall composition (claim params, ntfy receiver wiring, Knarr escalation seam) | `heimdall` | `components/heimdall/.agent/skills/` | `ws clone heimdall` |
| GDD methodology (session orientation, housekeeping, review triage, vault capture, doc writing, permissions, BDD, branch workflow, GitHub-issue filing, workflow audit, MCP, …) | `gdd-*` family — see workspace-root `.agent/skills/` for the canonical list | workspace-root `.agent/skills/` | always available |

If a capability isn't listed: grep the realm and component `.agent/skills/` dirs as a fallback. Missing entries are Tier-2 housekeeping candidates — flag.

## Alert Pipeline (End-to-End)

```text
PrometheusRule (your component, labeled `release: <chart>`)
   → Prometheus scrape + rule evaluation (Heimdall)
   → AlertManager routing by `severity` label (Heimdall, ns `monitoring`)
   → webhook_configs receiver, default envelope POSTed
   → ntfy in-cluster (Nidavellir, ns `ntfy`)
     - URL `?template=<name>` triggers server-side templating
     - severity→priority mapping happens HERE, not in AM
   → ntfy push to subscribed phone
```

**Component ownership of each segment:**

- Rule (the `PrometheusRule` CR) — your component owns it. Label with `release: <chart-release>` or the Operator selector silently ignores it (the #1 silent-invisibility cause).
- Prometheus + AlertManager — **Heimdall**. Deep skill: `alertmanager-config` (covers the three-way choice between native AM payload templating vs server-side ntfy templating vs a bridge; SiliconSaga chose server-side ntfy).
- ntfy receiver + server-side template (`heimdall-template.yaml`) — **Nidavellir**. The `?template=<name>` URL form is the seam where severity becomes priority.
- Phone subscription — out-of-band, user-side.

**Common stack mistake:** assuming AM owns severity→priority. It doesn't here. Nidavellir's ntfy template does.

## GitOps Model

ArgoCD lives in namespace **`argo`** (NOT `argocd`). It syncs from the **in-cluster seed-Gitea** in ns `gitea`, NOT from GitHub directly. The seed-Gitea is hydrated from local working trees via `update-embedded-git.sh <homelab|gke>`.

**Implication:** pushing to GitHub does NOT reach the cluster. Testing a local branch on staging = re-hydrate the seed-Gitea + hard-refresh the ArgoCD app. Pushing to GitHub merges code but doesn't touch the running cluster until re-hydration.

**Environment shape:** **homelab = staging** (rancher-desktop, resettable), **GKE = production**. Re-hydrate locally, exercise on homelab, then promote.

Deep dives: Nordri's `argocd-gitops` skill (the operational gotchas — test-through-Git, parent-prune, etc.), plus Nordri's component skill `nordri` (the bootstrap layer sequence).

## Cluster Identity / Env-Aware Compositions

The **`cluster-identity` EnvironmentConfig** carries which environment a cluster is (`homelab` / `gke`) so Crossplane Compositions can branch on it: storage class (Longhorn vs PD-backed), ingress class, replica count, observability scrape config, etc. `function-environment-configs` reads it into the template context under the key `apiextensions.crossplane.io/environment`.

This is the seam most cross-env behavior lives at. Deep dive: Nordri's `crossplane-compositions` skill.

## Bare-Workspace Recipe

Working with only `yggdrasil` + `realms/realm-siliconsaga/` cloned? This skill IS your map. For deep operational work clone what you need:

| You need... | Clone | Then read |
|---|---|---|
| Alerts / metrics / dashboards / Grafana / Loki | `ws clone heimdall` | `alertmanager-config`, `kube-prometheus-stack` |
| GitOps deploy / Compositions / Crossplane providers | `ws clone nordri` | `argocd-gitops`, `crossplane-compositions` |
| ntfy receiver / secrets (OpenBao + ESO) / Keycloak / Tailscale operator / platform Application manifests | `ws clone nidavellir` | `docs/secrets-management.md`; component skill is future Phase-4 work |
| Database claim (Postgres, Mongo, Kafka, etc.) | `ws clone mimir` | (Phase 4) `mimir` |

`ws list` shows current clone state.

## Common Mistakes

- **Grepping the whole workspace for `SKILL.md` instead of consulting this index first.** Trees like `NemoClaw/node_modules/openclaw/skills/...` create heavy noise. The index above is faster and authoritative.
- **Assuming AlertManager owns severity→priority mapping.** It doesn't — Nidavellir's ntfy template does. AM POSTs its default envelope; ntfy formats title/message/priority server-side via `?template=<name>`.
- **Pushing to GitHub to test on the cluster.** GitHub isn't the cluster's source. `update-embedded-git.sh <env>` hydrates the in-cluster seed-Gitea — that's the actual source. Push to GitHub is for code review + remote backup, not deployment.
- **`kubectl apply` against a `selfHeal: true` Application.** Controller reverts within ~3 minutes. Test through Git (re-hydrate seed-Gitea + hard-refresh). Covered in Nordri's `argocd-gitops` skill.
- **Forgetting `release: <chart-release>` label** on `ServiceMonitor` / `PrometheusRule`. Operator selector silently ignores them — alert never fires. Covered in Heimdall's `kube-prometheus-stack` skill.
- **Treating a sealed OpenBao as broken.** `openbao-0` at `0/1 Running` after any restart is by design — it's waiting for a manual unseal (2 of 3 key shares), and readiness deliberately gates on seal status. Runbook: `components/nidavellir/docs/secrets-management.md`.
- **Treating tier as ordering only.** Tier 1/2/3 reflects dependency direction (substrate → platform → end-user), not deploy order. Real deploy order in Nordri's bootstrap is layered Crossplane providers + ProviderConfigs + ArgoCD adoption, documented separately.

## Sources

- Workspace declaration: `ecosystem.yaml` at workspace root (machine-readable index of components + tiers).
- Realm manifest: `realms/realm-siliconsaga/AGENTS.md`.
- Component skills referenced above (Heimdall, Nordri; Mimir + Nidavellir component skills are future Phase-4 work).
- Skill taxonomy + ownership rule: `realms/realm-siliconsaga/docs/plans/2026-05-30-skill-taxonomy-design.md`.
- Realm `docs/` (Phase 3) will carry the long-form stack narrative for human readers; this skill is the agent-facing index.
