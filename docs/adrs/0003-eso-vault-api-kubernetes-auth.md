---
status: accepted
date: 2026-06-10
decision-makers:
  - Cervator
consulted:
  - agent
---

# ESO Over the Vault-Compatible API With Kubernetes Auth

## Context and Problem Statement

Workloads need OpenBao-held values as plain Kubernetes Secrets without baking a Vault SDK or sidecar into every app. Something must bridge OpenBao to the Secret objects Deployments already consume.

## Decision Drivers

* Zero app-side coupling — consumers see ordinary Secrets.
* Declarative, GitOps-friendly wiring (CRDs, not init scripts).
* No static credentials for the bridge itself.

## Considered Options

* External Secrets Operator with the `vault` provider + Kubernetes auth
* OpenBao Agent injector sidecars (`injector.enabled`)
* App-side Vault/OpenBao SDK integration per service

## Decision Outcome

Chosen option: "ESO + vault provider + Kubernetes auth", because ESO's `ClusterSecretStore`/`ExternalSecret` CRDs are declarative and cluster-wide, the vault provider speaks OpenBao's compatible API unchanged, and Kubernetes auth means the only credential is ESO's ServiceAccount token (bound to the read-only `eso-read` policy via `eso-role`, 1h TTL). The injector is disabled in the composition — sidecars couple pod specs to the secrets backend and are unnecessary when Secrets suffice.

### Consequences

* Good, because any namespace can consume OpenBao values through a cluster-scoped store with no per-app setup.
* Good, because ESO is read-only against `secret/*` — blast radius of a compromised ESO is bounded.
* Bad, because secret values get materialized into etcd-backed Kubernetes Secrets (mitigations like etcd encryption are a cluster-level concern, out of scope here).

### Confirmation

`ClusterSecretStore/openbao-kv` reports Ready; the `tests/platform/external-secrets` kuttl case round-trips a KV write into a materialized Secret in an ephemeral namespace.

## More Information

* Source implementation plan: `docs/plans/2026-06-09-leidangr-phase1a-openbao-eso-plan.md` (Parts A2, A3)
* Implemented by: https://github.com/SiliconSaga/nidavellir/pull/13
