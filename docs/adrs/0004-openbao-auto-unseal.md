---
status: accepted
date: 2026-09-07
decision-makers:
  - Cervator
consulted:
  - agent
---

# OpenBao Auto-Unseal per Environment

## Context and Problem Statement

ADR 0002 chose manual init/unseal for Phase 1 and deferred KMS auto-unseal to a hardening phase. Every OpenBao restart since has needed a human, and the GKE instance was found sealed on 2026-09-07 with nobody having noticed. The Forgejo day-2 design makes OpenBao a dependency of the durable tier: the Forgejo credentials Job writes to OpenBao and refuses to run while it is sealed. A substrate that re-seals on every node roll cannot hold that role.

## Decision Drivers

* No human in the loop after a restart, on either environment.
* Homelab keeps ADR 0002's "no cloud coupling" property.
* The custody model does not get worse than ADR 0002 accepted.

## Considered Options

* GCP Cloud KMS seal on gke via Workload Identity, static seal on homelab
* GCP Cloud KMS seal everywhere (homelab reaches out to GCP)
* Keep manual unseal, add an alerting nudge

## Decision Outcome

Chosen option: "KMS on gke, static on homelab", selected by cluster-identity `environment` in the openbao composition when the claim sets `seal: auto`. The XRD default is `shamir`, so landing the composition changes nothing on a running cluster; graduation is the operator setting `auto` on the claim once the seal prerequisites exist, then deleting the pod (the chart's StatefulSet is `OnDelete`) and running the one-time `unseal -migrate`. gke unwraps the barrier key through `roles/cloudkms.cryptoKeyEncrypterDecrypter` on one key, bound to the `openbao/openbao` ServiceAccount through Workload Identity; homelab reads a 32-byte key from Secret `openbao-seal-key` that nordri bootstrap creates once.

### Consequences

* Good, because restarts self-heal and the durable tier can depend on OpenBao.
* Good, because homelab stays offline-capable and identical in shape.
* Bad, because homelab custody is the same soft spot ADR 0002 accepted: anyone who can read Secrets in `openbao` holds the seal key. Accepted for a homelab, as before.
* Bad, because the gke Workload Identity binding is unconditioned (the providerId condition does not match on this cluster, per the Velero finding of 2026-09-01), so identity sameness across clusters in the project is unmitigated until a second cluster exists.

### Confirmation

`tests/platform/openbao/01-restart.yaml` deletes the pod and asserts it returns Ready unaided; `tests/render/check-openbao.sh` asserts the seal seams render per environment.

## Pros and Cons of the Options

### KMS on gke, static seal on homelab

* Good, because each environment uses the seal that fits it: a managed key service where one exists, a local key where cloud coupling is unwanted.
* Good, because the composition already branches on cluster-identity `environment`, so this is one more seam of the same kind, not a new mechanism.
* Bad, because two seal types mean two runbooks and two failure modes to know.
* Bad, because the homelab key sits in a Kubernetes Secret, the same exposure ADR 0002 accepted.

### KMS everywhere

* Good, because one seal type and one runbook.
* Bad, because a homelab cluster would need GCP credentials and network reach to unseal, which breaks the "no cloud coupling on homelab" property and makes an offline homelab unable to start.

### Keep manual unseal, add an alerting nudge

* Good, because zero new infrastructure.
* Bad, because a page still needs a human, and the Forgejo credentials Job would fail on every node roll until someone acted; the durable tier cannot depend on that.

## More Information

* Realm design: `docs/plans/2026-09-07-forgejo-day2-design.md` (Credentials § Prerequisite)
* Plan: `docs/plans/2026-09-07-forgejo-day2-phase1-plan.md`
* Supersedes the unseal posture of ADR 0002; ADR 0002's init material becomes the recovery keys.
* OpenBao seal references: static seal (`current_key` accepts `env://` and `file://`, 32-byte AES-256-GCM-96 key) at https://openbao.org/docs/configuration/seal/static/ ; gcpckms seal (application default credentials, so Workload Identity needs no `credentials` field) at https://openbao.org/docs/configuration/seal/gcpckms/ ; seal migration at https://openbao.org/docs/concepts/seal/ . Chart contract verified with `helm template openbao/openbao --version 0.28.3`: `server.serviceAccount.annotations` lands on the ServiceAccount, `server.extraSecretEnvironmentVars` becomes a `secretKeyRef` env on the server container, and the StatefulSet's `updateStrategy` is `OnDelete`.
