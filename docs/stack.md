# SiliconSaga Stack

Human-readable companion to `ecosystem.yaml` (the machine-readable manifest) and the `siliconsaga-stack` agent skill (the AI-agent-facing navigation index). This doc covers the **shape** of the SiliconSaga stack — what each tier and component is for and how the pieces fit together. For operational depth (the gotchas, the gnarly details, the "if X then Y" recipes) it points at the owning component's skills under `components/<name>/.agent/skills/`.

---

## What SiliconSaga Is

A community-built tiered stack designed for both **homelab** (single-machine staging on rancher-desktop) and **GKE** (production cloud), driven by GDD-style AI agents over a workspace CLI (`ws`). Each component is an independent Git repo; the realm declares them in `ecosystem.yaml` and the workspace tooling clones and resolves whatever's needed. The design priorities are: cluster-identity-aware compositions so the same manifests run in both environments with environment-aware differences, GitOps everywhere via an in-cluster seed-Gitea (not GitHub), and explicit "who owns what" boundaries so a new contributor knows where to look.

## The Tier Map (Skim This First)

| Tier | Component | What it is |
|------|-----------|------------|
| **1 — Substrate** | `nordri` | The cluster fundamentals: ingress, GitOps controller, storage, platform API, backup. Everything else assumes this layer is healthy. |
| **2 — Platform app-of-apps** | `nidavellir` | The home for platform-level Application manifests — `ntfy`, `tailscale-operator`, `keycloak`, `vegvisir`, etc. Adding a new platform service = adding its Application here. |
| **2 — Component** | `heimdall` | Observability — Prometheus + AlertManager + Grafana + Loki + Tempo. |
| **2 — Component** | `mimir` | Data services via Crossplane Compositions — Postgres, MySQL, Mongo, Kafka, Valkey. |
| **2 — Component** | `vordu` | BDD roadmap visualization. |
| **2 — Component** | `tafl`, `bifrost` | Board-game engine + bridge/gateway. |
| **3 — End-user** | `ymir`, `terasology`, `destinationsol`, `ting` | End-user platforms / games / civic tooling — the things real people interact with. |

The full declaration with chart versions and adapter wiring lives in `ecosystem.yaml` at the workspace root. `ws list` summarizes which components are cloned in your local workspace.

---

## Substrate — Nordri (Tier 1)

Nordri provides the cluster fundamentals:

- **Traefik** — ingress controller, Gateway API
- **Crossplane** — declarative platform API (Compositions describe high-level resources that decompose into Kubernetes manifests)
- **Velero** — cluster backup
- **Longhorn** — block storage (homelab)
- **Garage S3** — object storage (homelab)
- **In-cluster seed-Gitea** — the GitOps source of truth (this is where ArgoCD actually pulls from; see the GitOps Model section below)
- **ArgoCD** — deployment controller, namespace `argo`

Nordri's bootstrap follows numbered layers (Layer 2 Gitea, Layer 2.5–2.8 CRDs, Layer 3 ArgoCD adoption, Layer 4 root app, Layer 5 Garage init). The order matters because the GitOps controller can't manage CRDs that don't exist yet.

For ArgoCD operational depth — CRD chicken-and-egg patterns, app-of-apps prune cascades, the test-through-Git rule for `selfHeal: true` Applications — see `components/nordri/.agent/skills/argocd-gitops/`. For Crossplane Composition Pipeline mode (`function-go-templating`, `function-environment-configs`, the SSA-Recreate trap, CompositionRevision flapping diagnosis), see `components/nordri/.agent/skills/crossplane-compositions/`.

---

## Platform Application Home — Nidavellir (Tier 2)

Nidavellir is the platform-level app-of-apps. Its `apps/` directory holds Application manifests for services that are platform-wide rather than component-owned:

- `ntfy/` — notification destination (phone push)
- `tailscale-operator/` — Tailscale Kubernetes operator
- `keycloak/` — identity / SSO
- `vegvisir/` — TLS/Gateway certificate orchestration
- `mimir/` — Mimir's app-of-apps wiring lives here too (the component itself is Tier 2 below)

If you're adding a brand-new platform service that isn't owned by any one component, this is where it goes. New manifests here get picked up by the GitOps controller on the next sync (subject to the re-hydration step described below).

---

## Observability — Heimdall (Tier 2)

The observability stack:

- **Prometheus** — metrics scrape + rule evaluation
- **AlertManager** — alert routing
- **Grafana** — dashboards (admin password via `existingSecret`, not plaintext in helm values)
- **Loki** — logs
- **Tempo** — traces

Heimdall ships the `kube-prometheus-stack` Helm chart with adjustments: noisy default `*Down` rules disabled for managed-K8s control planes (which don't expose `kube-controller-manager`, `kube-scheduler`, etc.), single-replica RWO Deployments use `strategy: Recreate` to avoid Multi-Attach deadlock, and on GKE there's a Cloud Logging dual-stack-cost discipline section (drop fluent-bit-GKE meta-chatter so you don't double-pay for ingestion of your own observability stack's noise).

The opinionated choices: **AlertManager** (not Grafana-managed alerting) for routing, and **ntfy** as the notification destination. AlertManager's `webhook_configs` posts to ntfy; severity → priority mapping happens **server-side in ntfy** (via the `?template=<name>` URL parameter and ntfy's `--template-dir`), not in AlertManager. This is the single biggest "wait, where does that happen?" gotcha in the alert pipeline.

For routing trees, the Watchdog dead-man's-switch idiom, webhook payload + header templating, `amtool` validation — see `components/heimdall/.agent/skills/alertmanager-config/`. For chart wiring, the `release:` label requirement on ServiceMonitors and PrometheusRules, single-replica RWO `Recreate` strategy, and the GKE dual-stack-cost recipe — see `components/heimdall/.agent/skills/kube-prometheus-stack/`.

---

## Data Services — Mimir (Tier 2)

Mimir provides database and messaging services via Crossplane Compositions. Components don't run their own Postgres; they file a Claim against Mimir's API and Mimir's Composition provisions the actual operator-managed instance.

- **Postgres** (Percona PG operator)
- **MySQL** (Percona MySQL operator)
- **MongoDB** (Percona Server for MongoDB operator)
- **Kafka** (Strimzi operator)
- **Valkey** (Redis-compatible KV)

The Composition reads the `cluster-identity` EnvironmentConfig (see GitOps Model below) to branch on environment — homelab uses Longhorn-backed PVCs and modest replica counts; GKE uses PD-backed storage and HA replication. So the same Claim YAML lands the right shape in both environments.

---

## End-User Components — Tier 3

These are the public-facing components — what real people actually use:

- **Ymir** — end-user platform.
- **Terasology** — voxel sandbox game (fork of upstream Terasology engine).
- **Destinationsol** — open-source space shooter (fork).
- **Ting** — parent-advocacy and school-board civic tooling.

End-user components consume the platform: they emit metrics that Heimdall scrapes, file Claims against Mimir for databases, route notifications through Heimdall's AlertManager → ntfy chain, deploy via Nordri's ArgoCD.

---

## GitOps Model — How Code Reaches the Cluster

The single most surprising thing about SiliconSaga's deployment model: **pushing to GitHub does NOT reach the cluster.** Code review and remote backup happen on GitHub; the cluster syncs from an in-cluster seed-Gitea instance.

The flow:

1. You write code locally and commit + push to your GitHub fork (review happens here).
2. You re-hydrate the in-cluster seed-Gitea from your local working tree via `bash scripts/ws exec nordri ./update-embedded-git.sh <homelab|gke>`. This pushes your local branch into the cluster's Gitea.
3. ArgoCD (in namespace `argo` — NOT `argocd`, that namespace is reserved to avoid colliding with legacy installations) syncs from seed-Gitea.
4. Optionally hard-refresh: `kubectl annotate application <name> -n argo argocd.argoproj.io/refresh=hard --overwrite`.

**Implication: homelab = staging, GKE = production.** Rancher-desktop is resettable, so re-hydrating is also how you exercise a local branch. The same `update-embedded-git.sh` script targets either environment.

**Implication: `kubectl apply` against a `selfHeal: true` Application reverts within ~3 minutes.** ArgoCD's reconciliation wins. Test by changing the Git source (seed-Gitea), not by direct cluster edits. There's an incident-override escape hatch (disable selfHeal temporarily) documented in Nordri's `argocd-gitops` skill.

---

## Cluster Identity — Env-Aware Compositions

Crossplane Compositions branch on environment via the `cluster-identity` EnvironmentConfig — a manifest deployed at bootstrap that identifies the cluster as `homelab` or `gke` (and carries other per-env hints: storage class default, ingress class, replica targets). `function-environment-configs` reads it into the Composition's template context under `apiextensions.crossplane.io/environment`, and `function-go-templating` branches accordingly.

This is the seam where most cross-environment differences live. If a Claim renders differently on homelab vs GKE, it's almost always because the Composition is reading `cluster-identity` and choosing a different code path.

Deep dive: `components/nordri/.agent/skills/crossplane-compositions/`.

---

## The Alert Pipeline End-to-End

A real example of how the pieces collaborate, since the alert path crosses three components:

```text
1. Your component fires a PrometheusRule (labeled `release: <chart-release>`)
2. Prometheus (Heimdall) scrapes + evaluates
3. AlertManager (Heimdall, ns `monitoring`) routes by `severity` label
4. webhook_configs receiver POSTs default envelope
5. ntfy (Nidavellir, ns `ntfy`) receives — URL `?template=<name>` triggers
   server-side templating; severity → priority mapping happens HERE
6. ntfy push to your phone
```

Component ownership of each segment:

- **The rule** — your component. Forget the `release:` label and the Operator's selector silently ignores the rule (the #1 silent-invisibility cause).
- **Prometheus + AlertManager** — Heimdall.
- **ntfy receiver + server-side template (`heimdall-template.yaml`)** — Nidavellir.
- **Phone subscription** — out-of-band, user-side.

The "wait, where does severity become priority?" answer: in Nidavellir's ntfy template, NOT in AlertManager. This is the gotcha worth memorizing.

---

## How to Read This Workspace

A few pointers depending on what you're doing:

- **Just looking around:** start here, then skim `realms/realm-siliconsaga/.agent/skills/siliconsaga-stack/SKILL.md` for the agent-facing skill index (same shape map, indexed for AI agents).
- **Adding a new service to the stack:** read this doc top-to-bottom, decide which tier your service belongs in, then file an Application manifest in the right place (Nidavellir for platform-wide, your component repo for component-specific).
- **Debugging an alert:** Heimdall's `alertmanager-config` skill + Nidavellir's ntfy template are the deep dives.
- **Wondering how `homelab` differs from `gke`:** see the "Cluster Identity" section above plus Nordri's `crossplane-compositions` skill.
- **Onboarding to GDD-driven contribution:** read `docs/gdd/` in the yggdrasil workspace (the GDD methodology docs).

---

## Related References

- `ecosystem.yaml` (workspace root) — machine-readable manifest: components, tiers, chart versions, adapter wiring.
- `realms/realm-siliconsaga/.agent/skills/siliconsaga-stack/SKILL.md` — agent-facing navigation index (same shape map, for AI agents).
- `realms/realm-siliconsaga/.agent/skills/terasology-testing/SKILL.md` — engine-level + MTE integration test patterns for the Terasology end-user component.
- `docs/plans/2026-05-30-skill-taxonomy-design.md` — the design doc that motivated this structure (why ownership-not-usability is the right tier rule, where each kind of skill lives).
- Component skills under `components/<name>/.agent/skills/` — operational depth.
