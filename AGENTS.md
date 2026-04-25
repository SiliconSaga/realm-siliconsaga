# SiliconSaga Realm — AI Agent Context

This realm declares the SiliconSaga ecosystem components, identity, and
component-specific skills. It is loaded automatically when present in
`realms/realm-siliconsaga/`.

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

Skills in this realm live in `.agent/skills/<name>/SKILL.md` (relative to
this realm directory). They are discovered automatically by the GDD
orientation skill during trust verification.

| Skill Name | Description | Target Component(s) |
| :--- | :--- | :--- |
| **ArgoCD Bootstrap on K3d** | Bootstrapping ArgoCD app-of-apps on k3d, CRD chicken-and-egg fixes, portable shell scripts | nordri |
| **Crossplane on K3d** | Guide for configuring Crossplane in local K3d clusters, Composition Pipeline mode | mimir |
| **Nordri Bootstrap Guide** | Bootstrapping Nordri (refr-k8s) on k3d, Mimir integration, ArgoCD sync troubleshooting | nordri |
| **Terasology Testing** | Engine-level and MTE integration test patterns, network event gotchas, Gradle execution | terasology |


## Tone Guide

While most repos can follow any communication style that seems appropriate, some are user-facing in sensitive areas:

* demicracy - next generation civics platform, likely tech-skeptical audience focused on local community topics
* schools - parents, union members, school board, etc - may contain highly sensitive content that risks conflicts between groups
* mtl-site - sports volunteers, not likely very technical, needs minimal jargon and low barrier to entry

When writing anything that might reach these groups:

- **Avoid techno-utopian vocabulary.** "Post-scarcity," "cyber,"
  "decentralized," "crypto," "DAO" all read as cult-of-Silicon-Valley
  to the audience and poison the message before it lands.
- **Prefer grounded, service-oriented language.** "Gentle cost reduction,"
  "community self-sufficiency," "overhead removal," "coordination tools."
- **Avoid "Demicracy" branding until live.** Talk about
  "coordination tools" or "community platform" in the abstract. The
  brand name is fine on demicracy.org, which is aimed at people who
  opted in.
- **The audience is not platform engineers.** Parents and board members
  are the primary readers. Board members skim. Parents are tired.

This distinction between public-facing civics content and internal
platform/infra work matters — other components can use the normal 
engineering vocabulary because the audience opted in.
