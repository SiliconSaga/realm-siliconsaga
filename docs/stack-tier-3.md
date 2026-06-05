# SiliconSaga — Tier 3 (End-User Applications)

What real people actually interact with. Consumes Tier 2 platform services (Heimdall for observability, Mimir for databases, Vegvísir for ingress, Nidavellir's ntfy for notifications).

See also: [`stack.md`](stack.md) (overview + tier map), [`stack-tier-1.md`](stack-tier-1.md), [`stack-tier-2.md`](stack-tier-2.md).

---

## Ymir — End-User Platform

Repo: `components/ymir` ([SiliconSaga/ymir](https://github.com/SiliconSaga/ymir))

End-user-facing platform. (See the component's own README + design docs for current scope.)

Component skills: [`ymir-dev`](../../../components/ymir/.agent/skills/ymir-dev/SKILL.md), [`ymir-api`](../../../components/ymir/.agent/skills/ymir-api/SKILL.md).

---

## Terasology — Voxel Sandbox Game

Repo: `components/terasology` (fork of upstream [MovingBlocks/Terasology](https://github.com/MovingBlocks/Terasology))

Open-source voxel sandbox engine. SiliconSaga's fork carries the realm's customizations and integrations (BDD-style testing patterns, observability hooks, Bifrost federation when that lands).

Realm-tier skill: [`terasology-testing`](../../.agent/skills/terasology-testing/SKILL.md) — engine-level + MTE (Module Test Environment) integration test patterns, network event gotchas, Gradle execution.

---

## Destinationsol — Open-Source Space Shooter

Repo: `components/destinationsol` (fork)

Open-source space shooter. Forked into the realm for similar reasons as Terasology — to apply the platform's observability + federation patterns and to host the game-server lifecycle through Tafl.

---

## Ting — Parent-Advocacy / Civic Tooling

Repo: `components/ting` ([SiliconSaga/ting](https://github.com/SiliconSaga/ting))

Civic-engagement tooling oriented at school-board-style local advocacy: surveys, weighted feedback, sentiment-over-time visualization. Has its own MVP plan + iteration backlog in the component's `docs/plans/`.

Uses: Mimir Postgres (responses + summaries), Heimdall (operational metrics + alerts), Vegvísir TLS / wildcard cert.

---

## Aspirational / Future Tier-3 Projects

The original Yggdrasil "project constellation" map carried several aspirational tier-3 components that aren't yet in `ecosystem.yaml` but remain on the roadmap. Listed here so readers don't lose track of them:

- **Demicracy** — design/governance portal (Backstage-based). The "Constitution" of the wider ecosystem. Public face: `demicracy.github.io`.
- **Uplifted Mascot (UM)** — RAG-style librarian bot that ingests Demicracy docs to answer user questions. Python / ChromaDB / Docker. The "Brain" of the chatops chain.
- **Autoboros** — ChatOps "Doer" bot. Python/Django + Discord API. The "Hands" that creates PRs in response to chat instructions. Pairs with UM.
- **Knarr** — viking-merchant integration/bridging layer (and a [board game](https://boardgamegeek.com/boardgame/379629/knarr) the user enjoys). Lives in a separate workspace today; potentially incorporates OpenClaw for agentic work. The "Grand Unification" workflow originally envisioned Knarr as the message-and-event substrate between Demicracy designs, UM intelligence, Autoboros execution, and Nidavellir identity verification.

None of these are in the current `ecosystem.yaml` declaration; if/when any graduates, it gets a `components/<name>/` entry and `realms/realm-siliconsaga/ecosystem.yaml` declaration.

---

## Public Faces (Static Sites — Outside the Cluster)

Not Kubernetes components, but part of the public surface area:

- **Front State** (`frontstate.github.io`) — the philosophical companion (civics).
- **Demicracy** (`demicracy.github.io`) — the platform's public-facing pages (tech).
- **Cervator** (`Cervator.github.io`) — personal blog adjacent to the project.

---

## Dependencies on / from this tier

- **Below:** consumes Tier 2 platform services (Heimdall, Mimir, Vegvísir, Nidavellir/ntfy). Filing Crossplane Claims against Mimir is the standard pattern for data needs.
- **Above:** humans 🙂
