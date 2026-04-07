# SiliconSaga Overlay — AI Agent Context

This overlay declares the SiliconSaga ecosystem components, identity, and
component-specific skills. It is loaded automatically when present in
`overlays/overlay-yggdrasil-live/`.

For workspace-level instructions (GDD methodology, ws CLI, git workflow,
auth setup), see the root [`AGENTS.md`](../../AGENTS.md).

---

## Repo Roles (Community Components)

| Repo | Tier | Role | Path |
|------|------|------|------|
| `nordri` | 1 | Cluster substrate (Traefik, Crossplane, Velero, ArgoCD) | `components/nordri` |
| `nidavellir` | 2 | Platform app-of-apps (Vegvísir, Mimir, Keycloak, …) | `components/nidavellir` |
| `mimir` | 2 component | Data services via Crossplane + operators | `components/mimir` |
| `vordu` | 2 component | BDD roadmap visualization | `components/vordu` |
| `heimdall` | 2 component | Observability stack | `components/heimdall` |
| `tafl` | 2 | Board game engine service | `components/tafl` |
| `bifrost` | 2 | Bridge/gateway service | `components/bifrost` |
| `ymir` | 3 | End-user platform | `components/ymir` |
| `terasology` | 3 | Voxel game (fork) | `components/terasology` |
| `destinationsol` | 3 | Space shooter game (fork) | `components/destinationsol` |

---

## Component-Specific Skills

Skills in this overlay live in `.agent/skills/<name>/SKILL.md` (relative to
this overlay directory). They are discovered automatically by the GDD
orientation skill during trust verification.

| Skill Name | Description | Target Component(s) |
| :--- | :--- | :--- |
| **ArgoCD Bootstrap on K3d** | Bootstrapping ArgoCD app-of-apps on k3d, CRD chicken-and-egg fixes, portable shell scripts | nordri |
| **Crossplane on K3d** | Guide for configuring Crossplane in local K3d clusters, Composition Pipeline mode | mimir |
| **Nordri Bootstrap Guide** | Bootstrapping Nordri (refr-k8s) on k3d, Mimir integration, ArgoCD sync troubleshooting | nordri |
