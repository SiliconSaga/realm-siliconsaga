---
status: accepted
date: 2026-06-10
decision-makers:
  - Cervator
consulted:
  - agent
---

# OpenBao-First Secrets Management

## Context and Problem Statement

The SiliconSaga stack needs a secrets substrate before Keycloak (Leiðangr Phase 1b) and Backstage (Phase 2) can hold credentials properly. Secrets were previously ad hoc: created out-of-band (`operator-oauth`), plain-text in deployment env (seed Gitea admin), or absent. The substrate must be self-hostable, env-aware (homelab + GKE), and consumable by Kubernetes workloads without app-side SDK coupling.

## Decision Drivers

* Self-hosted, open-source-licensed, community-governed — fits the realm's sovereignty posture.
* Vault-compatible API surface so the surrounding ecosystem (ESO, client libraries, docs) just works.
* Must deploy through the existing GitOps + Crossplane composition pattern, env-aware via cluster-identity.

## Considered Options

* OpenBao (Linux Foundation fork of Vault, MPL-licensed)
* HashiCorp Vault (BUSL license)
* Kubernetes Secrets only (no external manager)

## Decision Outcome

Chosen option: "OpenBao", because it keeps the Vault-compatible API and ecosystem while staying open-source under the Linux Foundation — Vault's BUSL license is a long-term governance risk for a community stack, and bare Kubernetes Secrets have no audit, versioning, or central policy story.

### Consequences

* Good, because ESO and the broader Vault tooling ecosystem work unchanged over the compatible API.
* Good, because the composition pattern (heimdall/ntfy style) extends naturally — OpenBao is just another env-aware platform component.
* Bad, because OpenBao is younger than Vault; some upstream features/docs lag (release checksum hygiene was already observed wanting).

### Confirmation

`openbao/` composition exists in nidavellir; `bao` API serves at `openbao.openbao.svc:8200`; ESO reads through it (see ADR 0003 and the `tests/platform/` kuttl smokes).

## Pros and Cons of the Options

### OpenBao

* Good, because open-source (MPL) under Linux Foundation governance — no license-flip risk.
* Good, because Vault-compatible API keeps the whole ecosystem (ESO, clients, docs) usable.
* Bad, because younger project — smaller community, rougher release hygiene.

### HashiCorp Vault

* Good, because most mature and best documented.
* Bad, because BUSL-licensed — a governance risk a community stack shouldn't anchor on.

### Kubernetes Secrets only

* Good, because zero extra moving parts.
* Bad, because no central policy, versioning, audit, or cross-cluster story — exactly what later phases need.

## More Information

* Source design: realm-siliconsaga `docs/plans/2026-06-09-leidangr-design.md` §7 (realm PR #10)
* Source implementation plan: `docs/plans/2026-06-09-leidangr-phase1a-openbao-eso-plan.md`
* Implemented by: https://github.com/SiliconSaga/nidavellir/pull/13
