---
status: accepted
date: 2026-06-10
decision-makers:
  - Cervator
consulted:
  - agent
---

# Minimal Unseal Posture in Phase 1, KMS Auto-Unseal Deferred

## Context and Problem Statement

An OpenBao server starts sealed and must be unsealed with key shares after every restart. Phase 1a needs a working substrate now; full production custody (auto-unseal, HA) is heavyweight and would gate everything behind cloud KMS wiring.

## Decision Drivers

* Phase 1a's consumers are staging-grade (homelab) plus a small GKE footprint — not yet holding community member data.
* Operational simplicity first; hardening as its own later phase rather than a blocker.
* The unseal flow must still be documented and repeatable, not tribal knowledge.

## Considered Options

* Minimal: single replica, Raft, manual init/unseal, init material parked in an in-cluster Secret
* KMS auto-unseal (GCP CKMS) from day one
* HA Raft cluster with auto-unseal

## Decision Outcome

Chosen option: "Minimal", because it ships the substrate in one phase with zero cloud coupling. Tradeoff accepted explicitly: anyone with cluster admin can read the `openbao-init` Secret (init JSON + root token as its own key). That is acceptable for staging and the current GKE scope, and is NOT production-grade custody — KMS auto-unseal supersedes this in a hardening phase. On live environments the unseal keys also get an off-cluster copy in the operator's password manager; on the test homelab they deliberately do not.

### Consequences

* Good, because no cloud KMS dependency; the composition deploys identically on homelab and GKE.
* Good, because the kuttl suite can read the parked token to exercise the full path.
* Bad, because every pod restart needs a manual unseal until auto-unseal lands.
* Bad, because in-cluster key custody is a known soft spot — tracked for the hardening phase.

### Confirmation

`openbao-init` Secret exists in the `openbao` namespace with `init.json` + `root_token` keys; the OpenBao pod readiness gates on unseal (StatefulSet kuttl assert proves the flow ran).

## More Information

* Source implementation plan: `docs/plans/2026-06-09-leidangr-phase1a-openbao-eso-plan.md` (Assumptions #4, Task A1.5)
* Implemented by: https://github.com/SiliconSaga/nidavellir/pull/13
