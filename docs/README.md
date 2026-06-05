# SiliconSaga Realm — Docs

Human-readable documentation for the SiliconSaga realm. Companion to:

- `../ecosystem.yaml` — the machine-readable component manifest.
- `../.agent/skills/siliconsaga-stack/SKILL.md` — the AI-agent-facing navigation index.

## What's here

The stack narrative is split across one overview + three per-tier docs so each stays scannable:

- [`stack.md`](stack.md) — **start here.** Overview, tier map at a glance, Norse naming convention, GitOps model (`argo` ns + in-cluster seed-Gitea workflow that surprises every new user), cluster-identity EnvironmentConfig pattern.
- [`stack-tier-1.md`](stack-tier-1.md) — Tier 1 (foundation). Just `nordri`.
- [`stack-tier-2.md`](stack-tier-2.md) — Tier 2 (platform services). `nidavellir`, `heimdall`, `mimir`, `vordu`, `tafl`, `bifrost`. Plus the alert-pipeline cross-component narrative.
- [`stack-tier-3.md`](stack-tier-3.md) — Tier 3 (end-user applications). `ymir`, `terasology`, `destinationsol`, `ting`. Plus aspirational future projects from the original project-constellation map.

Plus a couple of operational / security topic pages:

- [`dev-setup.md`](dev-setup.md) — local dev environment for this realm (Rancher Desktop, WSL2 inotify, k3d on macOS, etc.).
- [`ai-agent-security-patterns.md`](ai-agent-security-patterns.md) — security framings for AI agent operations.
- [`agent-security/`](agent-security/) — deeper agent-security topic pages.
- [`plans/`](plans/) — dated design and implementation plan docs (historical record).

## What's NOT here

- **Operational depth for specific capabilities** — those live in component skills under `components/<name>/.agent/skills/` (e.g. AlertManager routing trees in `components/heimdall/.agent/skills/alertmanager-config/`).
- **GDD methodology** — that's a workspace-root concern; see `docs/gdd/` in the yggdrasil workspace.
- **Per-component README content** — each component repo has its own README.
- **The generic 3-tier framing** — that lives at workspace-root in yggdrasil's [`docs/ecosystem-architecture.md`](../../../docs/ecosystem-architecture.md). This realm-side narrative is the SiliconSaga-flavoured *instance* of that generic shape.
