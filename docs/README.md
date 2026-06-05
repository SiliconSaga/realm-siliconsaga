# SiliconSaga Realm — Docs

Human-readable documentation for the SiliconSaga realm. Companion to:

- `../ecosystem.yaml` — the machine-readable component manifest.
- `../.agent/skills/siliconsaga-stack/SKILL.md` — the AI-agent-facing navigation index.

## What's here

- [`stack.md`](stack.md) — **start here.** The shape of the stack: what each tier and component is for, the GitOps model, the cluster-identity pattern, and the alert pipeline end-to-end.
- [`ai-agent-security-patterns.md`](ai-agent-security-patterns.md) — security framings for AI agent operations in the workspace.
- [`agent-security/`](agent-security/) — deeper agent-security topic pages.
- [`plans/`](plans/) — dated design and implementation plan docs (historical record).

## What's NOT here

- **Operational depth for specific capabilities** — those live in component skills under `components/<name>/.agent/skills/` (e.g. AlertManager routing trees in `components/heimdall/.agent/skills/alertmanager-config/`).
- **GDD methodology** — that's workspace-root concern; see `docs/gdd/` in the yggdrasil workspace.
- **Per-component README content** — each component repo has its own README.
