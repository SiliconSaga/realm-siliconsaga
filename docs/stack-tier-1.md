# SiliconSaga — Tier 1 (Foundation)

The substrate every other tier depends on. **One component**: `nordri`.

See also: [`stack.md`](stack.md) (overview + tier map), [`stack-tier-2.md`](stack-tier-2.md), [`stack-tier-3.md`](stack-tier-3.md).

---

## Norðri — The Foundation

> *One of the four dwarves who hold up the sky, guarding the North.*

Repo: `components/nordri` ([SiliconSaga/nordri](https://github.com/SiliconSaga/nordri))

Nordri provides the cluster fundamentals:

| Subsystem | Purpose | Notes |
|-----------|---------|-------|
| **Traefik** | Ingress controller + Gateway API | Pinned chart 38.x / 3.6.5 (Gateway-provider cert regression in 3.7.x — see Loki-thalamus). |
| **Crossplane** | Declarative platform API | Compositions describe high-level resources that decompose into Kubernetes manifests. `function-go-templating` + `function-environment-configs` + `provider-kubernetes` v1alpha2. |
| **Velero** | Cluster backup | Object-storage target (Garage S3 on homelab, GCS on GKE). |
| **Longhorn** | Distributed block storage | Homelab only — GKE uses PD-backed `standard-rwo`. |
| **Garage S3** | Self-hosted object storage | Homelab only — GKE uses GCS. |
| **seed-Gitea** | GitOps source of truth | In-cluster Gitea, namespace `gitea`. Hydrated from local working trees via `update-embedded-git.sh`. |
| **ArgoCD** | Deployment controller | Namespace `argo` (NOT `argocd` — reserved to avoid colliding with legacy installations). |

Nordri's bootstrap follows numbered layers (Layer 2 Gitea, Layer 2.5–2.8 CRDs, Layer 3 ArgoCD adoption, Layer 4 root app, Layer 5 Garage init). The order matters because the GitOps controller can't manage CRDs that don't exist yet. Details live in `components/nordri/docs/bootstrap.md`.

## Operational depth

For the gotchas — what bites you in practice, where the live-cluster traps are — see Nordri's component skills:

- [`crossplane-compositions`](../../../components/nordri/.agent/skills/crossplane-compositions/SKILL.md) — Pipeline mode patterns, `crossplane render` for offline validation, the SSA-Recreate trap on Deployment strategy migrations, CompositionRevision flapping diagnosis (GitOps controller fighting Crossplane, mutating-webhook fights, stale-revision Automatic-policy pinning).
- [`argocd-gitops`](../../../components/nordri/.agent/skills/argocd-gitops/SKILL.md) — CRD chicken-and-egg fix (sync waves + `SkipDryRunOnMissingResource` + `ServerSideApply` + retry/backoff), the "Test Through Git" one rule for `selfHeal: true` Applications, app-of-apps parent-prune cascade footgun, `ServerSideApply` for >262KB CRDs (and why `Replace=true` is the wrong escape hatch), Kustomize `helmCharts` + JSON6902 for patching unexposed chart values, the stuck-sync three-step recovery cookbook.

## Dependencies on / from this tier

- **Below:** none. Nordri assumes only a Kubernetes API server (k3s/k3d/GKE) plus a Bash-compatible shell on the bootstrap host.
- **Above:** every Tier 2 platform service deploys *through* Nordri's ArgoCD (the `nidavellir-apps.yaml` Application is Nordri's entry point into Tier 2).
