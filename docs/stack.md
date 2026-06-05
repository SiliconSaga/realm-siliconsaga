# SiliconSaga Stack — Overview

Human-readable companion to `ecosystem.yaml` (the machine-readable manifest) and the `siliconsaga-stack` agent skill (the AI-agent-facing navigation index).

This overview describes what SiliconSaga is, how the three tiers fit together, the naming convention, and the GitOps + cluster-identity patterns. **Per-tier details live in three companion docs:** [`stack-tier-1.md`](stack-tier-1.md) (foundation), [`stack-tier-2.md`](stack-tier-2.md) (platform), [`stack-tier-3.md`](stack-tier-3.md) (end-user applications). For operational depth on a specific capability, follow the pointers from each tier doc to the owning component's skill under `components/<name>/.agent/skills/`.

---

## What SiliconSaga Is

A community-built tiered stack designed for both **homelab** (single-machine staging on rancher-desktop) and **GKE** (production cloud), driven by GDD-style AI agents over a workspace CLI (`ws`).

Each component is an independent Git repo; the realm declares them in `ecosystem.yaml` and the workspace tooling clones and resolves whatever's needed. The design priorities are: cluster-identity-aware Crossplane Compositions so the same manifests run in both environments with environment-aware differences, GitOps everywhere via an in-cluster seed-Gitea (not GitHub), and explicit "who owns what" boundaries so a new contributor knows where to look.

SiliconSaga is **one realm of many possible** — the upstream Yggdrasil workspace tooling and GDD methodology are realm-agnostic. SiliconSaga happens to be where the original platform-engineering experimentation moved to so Yggdrasil could focus on GDD as a generic framework.

---

## The Tier Map

| Tier | Role | SiliconSaga components | Doc |
|------|------|-----------------------|-----|
| 🌱 — | Workspace root (not deployed) | `yggdrasil` itself — docs, agent skills, `ws` CLI, config | (see yggdrasil's [`docs/ecosystem-architecture.md`](../../../docs/ecosystem-architecture.md)) |
| **1** | Foundation — cluster substrate | `nordri` (Traefik, Crossplane, Velero, Longhorn, Garage, seed-Gitea, ArgoCD) | [`stack-tier-1.md`](stack-tier-1.md) |
| **2** | Platform services | `nidavellir`, `heimdall`, `mimir`, `vordu`, `tafl`, `bifrost` | [`stack-tier-2.md`](stack-tier-2.md) |
| **3** | End-user applications | `ymir`, `terasology`, `destinationsol`, `ting` (plus aspirational `demicracy` etc.) | [`stack-tier-3.md`](stack-tier-3.md) |

The full machine-readable declaration with chart versions and adapter wiring lives in `ecosystem.yaml` at the workspace root. `ws list` summarizes which components are cloned in your local workspace.

---

## Naming Conventions

SiliconSaga components follow Norse-mythology naming with a "mythological role — practical description" pair. The convention came from the pre-GDD platform-engineering era and stuck because it's both memorable and (gently) descriptive. It's a *community-style choice for this realm*, not a GDD requirement.

The `README.md` (and a couple component docs) of each project carry this header:

```markdown
# [Project Name] (e.g., Norðri)
*[Mythological Role] — [Practical Description]*

> "[Brief Mythological Context]"

**[Project Name]** is the [Functional Component] of the SiliconSaga realm.
It [Primary Action/Purpose].
```

Three worked examples drawn from active components:

### Norðri

```markdown
# Norðri
*The Foundation — Self-Hosted Infrastructure*

> "One of the four dwarves who hold up the sky, guarding the North."

**Norðri** is the **Infrastructure Layer** of the realm. It provides the resilient
Kubernetes substrate (K3s/Longhorn) that holds up the rest of the digital world.
```

### Nidavellir

```markdown
# Nidavellir
*The Forge — Platform & Tooling*

> "The dark fields where the dwarves forge the most powerful treasures of the gods."

**Nidavellir** is the **Platform Layer**. It is the workspace where we forge
applications, hosting CI/CD, dashboards, and identity systems.
```

### Yggdrasil

```markdown
# Yggdrasil
*The World Tree — GDD's Meta-Workspace*

> "An immense mythical tree that connects the nine worlds in Norse cosmology."

**Yggdrasil** is the **GDD framework + workspace tooling** — realm-agnostic.
It doesn't ship a deployable; it provides the soil everything else grows in.
```

---

## GitOps Model — How Code Reaches the Cluster

The single most surprising thing about SiliconSaga's deployment model: **pushing to GitHub does NOT reach the cluster.** Code review and remote backup happen on GitHub; the cluster syncs from an in-cluster seed-Gitea instance.

The flow:

1. You write code locally and commit + push to your GitHub fork (review happens here).
2. You re-hydrate the in-cluster seed-Gitea from your local working tree via `bash scripts/ws exec nordri ./update-embedded-git.sh <homelab|gke>`. This pushes your local branch into the cluster's Gitea.
3. ArgoCD (in namespace `argo` — NOT `argocd`, that namespace is reserved to avoid colliding with legacy installations) syncs from seed-Gitea.
4. Optionally hard-refresh: `kubectl annotate application <name> -n argo argocd.argoproj.io/refresh=hard --overwrite`.

**Implication: homelab = staging, GKE = production.** Rancher-desktop is resettable, so re-hydrating is also how you exercise a local branch. The same `update-embedded-git.sh` script targets either environment.

**Implication: `kubectl apply` against a `selfHeal: true` Application reverts within ~3 minutes.** ArgoCD's reconciliation wins. Test by changing the Git source (seed-Gitea), not by direct cluster edits. There's an incident-override escape hatch (disable selfHeal temporarily) documented in [Nordri's `argocd-gitops` skill](../../../components/nordri/.agent/skills/argocd-gitops/SKILL.md).

---

## Cluster Identity — Env-Aware Compositions

Crossplane Compositions branch on environment via the `cluster-identity` EnvironmentConfig — a manifest deployed at bootstrap that identifies the cluster as `homelab` or `gke` (and carries other per-env hints: storage class default, ingress class, replica targets). `function-environment-configs` reads it into the Composition's template context under `apiextensions.crossplane.io/environment`, and `function-go-templating` branches accordingly.

This is the seam where most cross-environment differences live. If a Claim renders differently on homelab vs GKE, it's almost always because the Composition is reading `cluster-identity` and choosing a different code path.

Deep dive: [Nordri's `crossplane-compositions` skill](../../../components/nordri/.agent/skills/crossplane-compositions/SKILL.md).

---

## Related References

- [`stack-tier-1.md`](stack-tier-1.md) / [`stack-tier-2.md`](stack-tier-2.md) / [`stack-tier-3.md`](stack-tier-3.md) — per-tier component narratives.
- [`dev-setup.md`](dev-setup.md) — local development environment for this realm (Rancher Desktop, WSL2 inotify, k3d for macOS, etc.).
- `ecosystem.yaml` (workspace root) — machine-readable manifest: components, tiers, chart versions, adapter wiring.
- [`siliconsaga-stack` realm skill](../.agent/skills/siliconsaga-stack/SKILL.md) — agent-facing navigation index (same shape map, for AI agents).
- [`terasology-testing` realm skill](../.agent/skills/terasology-testing/SKILL.md) — engine-level + MTE integration test patterns.
- `docs/plans/2026-05-30-skill-taxonomy-design.md` — design doc behind the skill structure.
- Yggdrasil's [`docs/ecosystem-architecture.md`](../../../docs/ecosystem-architecture.md) — the GDD-generic three-tier framing this realm inhabits.
