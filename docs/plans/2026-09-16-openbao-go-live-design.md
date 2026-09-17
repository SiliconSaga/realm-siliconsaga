# OpenBao Go-Live — Design

**Status:** Design, approved in brainstorm 2026-09-16; plan next
**Date:** 2026-09-16
**Owner:** Rasmus Praestholm
**Related:** [ADR 0002 minimal unseal](../adrs/0002-minimal-unseal-phase1.md) · [ADR 0004 auto-unseal](../adrs/0004-openbao-auto-unseal.md) · [Forgejo day-2 design](2026-09-07-forgejo-day2-design.md) · [Mimir offsite backups](https://github.com/SiliconSaga/mimir/blob/main/docs/offsite-backups.md) · [KubicValheim backups](https://github.com/SiliconSaga/KubicValheim/blob/main/docs/backups.md) · [nordri velero-gke](https://github.com/SiliconSaga/nordri/blob/main/docs/velero-gke.md)

## Why now

Every runbook in `nidavellir/docs/secrets-management.md` has been aspirational: OpenBao held nothing anyone would miss, so nothing depended on its custody being right or its backups existing. That changed on 2026-09-15. Keycloak runs on the shared database with the siliconsaga realm imported from values born in OpenBao, nordri's bootstrap Layer 5b seeds realm-declared paths on every fresh cluster, and the Forgejo day-2 design makes the vault a dependency of the durable tier. This is the moment the vault goes live, and going live means three things the stack does for every other stateful service already: a custody story a human can execute, an application-level backup that leaves the cluster, and alerts that fire when it stops.

The models are Mimir and KubicValheim: an engine-level backup on its own schedule to a dedicated off-site bucket, Velero's daily disk snapshot underneath as the crash-consistent net, and rules in Heimdall that distinguish "installed" from "working".

## Decisions

### Fresh init under the auto seal, not a migration

GKE's OpenBao is wiped and initialised again under the KMS seal, once `gke-provision.sh openbao-seal-setup` has run and the claim says `seal: auto`. Nothing of value is lost: the vault holds the demo canary and one OIDC pair that is re-seeded and re-imported. A migration would cost a snapshot and two typed shares to preserve two values that regenerate in seconds, and would leave the instance's history starting under Shamir. An instance born under the auto seal never has unseal keys at all; its three shares are recovery keys from the first second.

The local Docker Desktop homelab goes first, through the same path with the static seal, as the dress rehearsal. It is disposable, and bootstrap Layer 5b already handles a wiped instance next to a stale `openbao-init` Secret.

### Custody: ADR 0002's in-cluster posture, plus a shared safe

The full init output (three recovery keys and the root token) is parked in the in-cluster `openbao-init` Secret, and copied to the operator's password safe — a shared collection that trusted community members can reach, so no single person holds the only copy.

This was weighed, not defaulted. On GKE with a KMS seal, cluster-admin already holds everything the recovery keys would grant: every Secret ESO has materialised, the parked root token, and the pod that unseals itself through Workload Identity. Recovery keys add only `generate-root` and seal migration, both moot for whoever holds the root token. So the in-cluster copy costs nothing new. What it cannot do is survive losing the cluster and the Velero bucket together; that is what the safe is for. Two copies in two failure domains, and the bus factor is the safe's membership, not one head.

The named hardening step, unchanged from ADR 0004: replace the parked root token with a scoped operator token. Not this round.

What the safe *is* stays open here; this round uses whichever shared safe the operator already has. The candidate for later is a self-hosted Vaultwarden (Bitwarden-compatible) in the cluster, on the shared Mimir database behind Keycloak SSO, with each trusted member's Bitwarden client holding the encrypted vault in its offline cache. That cache is what makes it sound rather than circular: the clients are the off-cluster copies, readable without the server, so when the cluster is gone a member who has the stack checked out reads the recovery keys from their own device, re-inits or restores OpenBao, and the safe comes back with everything else. Two caveats for that design when it comes: SSO in Vaultwarden only authenticates, the vault is still encrypted under each member's master password, so onboarding is "log in with Keycloak, then set a master password"; and the safe's own backup (database plus attachments) has to exist before it is trusted with anything, the same rule as every other stateful service here. Its own design doc, not this one.

### The init runs from a script that never prints

`nordri/openbao-init.sh <gke|homelab> <output-file>` runs `bao operator init -format=json` with explicit share flags for the seal it finds (`-recovery-shares=3 -recovery-threshold=2` under an auto seal, `-key-shares=3 -key-threshold=2` under Shamir; the defaults are five and three, and the API refuses the wrong family), writes the JSON to the named file (0600, in a directory it creates 0700 or refuses if wider), parks `init.json` and `root_token` in the Secret from that file, verifies the Secret reads back, and prints only `bao status`. The operator moves the file's contents into the safe and deletes it. The same script refuses an initialised instance and refuses a target whose kubectl context does not fit, via the `lib/kube-context.sh` check both nordri scripts now share. It reuses `lib/openbao.sh`'s functions rather than duplicating them; the lib gains an `OPENBAO_INIT_KEEP_FILE` path so `openbao_ensure_initialized` can hand the material to a file the caller owns instead of removing it.

`nordri/openbao-configure.sh <gke|homelab> [realm]` exposes Layer 5b's configure and seed halves standalone (mount, Kubernetes auth, policies and roles, canary, realm seeds), so a live cluster is configured without re-running bootstrap. Both scripts are thin: argument handling, the context check, and calls into the lib.

### Backup: the chart's snapshot agent, daily, to a dedicated bucket

The OpenBao Helm chart ships a snapshot agent (`ghcr.io/openbao/openbao-snapshot-agent`), a CronJob that logs in through Kubernetes auth, runs `bao operator raft snapshot save`, uploads with s3cmd and expires objects older than `S3_EXPIRE_DAYS`. The composition enables it through chart values rather than rendering its own CronJob: it is the engine's own scheduler, the shape the Mimir doc argues for over a separate job that copies files, and upstream owns the image and the script. Schedule 05:00 UTC daily, an hour before Velero's 06:00 run.

The agent's role `openbao-backup` gets a policy that allows exactly `sys/storage/raft/snapshot` read and nothing else: the job can copy the vault out, encrypted, and can read no secret. Both are created by `openbao_configure` in Layer 5b, so a fresh cluster has them before the first run.

The agent is S3-only, so GKE reaches its bucket over the GCS S3-interop endpoint with an HMAC key, the precedent Mimir's MySQL backups set and documented, rather than keyless Workload Identity. That was weighed against a hand-rolled keyless CronJob and chosen for the smaller surface to own; the cost is one more static credential, bounded the same way as MySQL's. Targets, one bucket per environment (own retention, own IAM, a mistake in one cannot reach another):

| Environment | Target | Auth | Retention |
|---|---|---|---|
| gke | `gs://<project>-openbao-backups` via `storage.googleapis.com` | HMAC key of GSA `openbao-backup@<project>`, which holds `roles/storage.objectCreator` and `roles/storage.objectViewer` on that bucket only — create and read, never delete or overwrite, so a compromised backup pod cannot erase history; key in Secret `openbao/openbao-backup-s3` | 30-day bucket lifecycle rule alone; `S3_EXPIRE_DAYS` unset so the agent never tries to delete |
| homelab | Garage bucket `openbao-backups` at `garage.garage.svc.cluster.local:3900` — an in-cluster copy, not off-site: it survives a wiped OpenBao PVC, not a lost cluster, which is the accepted posture for a resettable homelab holding nothing that is not regenerable | Garage key `openbao-backup-key` (read/write, since the agent does its own expiry), in Secret `openbao/openbao-backup-s3` | `S3_EXPIRE_DAYS=30` |

GKE's bucket, GSA, grant, HMAC key and Secret come from a new `gke-provision.sh openbao-backup-setup` action, idempotent like `velero-setup` (the HMAC key is minted once and parked; re-runs leave an existing Secret alone). Homelab's bucket, key and Secret are created by bootstrap Layer 5 beside Velero's. The Secret's key names are the chart's contract: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, AWS-shaped names holding Google or Garage values, exactly as the MySQL backup Secret does.

The chart names the CronJob, its ServiceAccount and its ConfigMap `openbao-snapshot` (with `fullnameOverride: openbao`), so the Kubernetes-auth role binds ServiceAccount `openbao/openbao-snapshot`, and Jobs are named `openbao-snapshot-<ts>` — which Heimdall's `HeimdallDatabaseBackupFailed` rule does not match today, since it looks for `*-backup-*`; the rule's pattern widens to cover `*-snapshot-*` too. The agent does not verify the upload beyond s3cmd's exit status; a failed put fails the Job, which that rule catches. The snapshot is the vault's own encrypted barrier; the bucket holds ciphertext that only the seal can open.

### Alerts and dashboard: kube-state-metrics, no exporter

The CronJob is the metric source. Two new rules in Heimdall's data-services group, and one widened:

- `OpenBaoSnapshotStale` — `time() - kube_cronjob_status_last_successful_time{namespace="openbao", cronjob="openbao-snapshot"} > 36h`, warning. One missed night before it speaks.
- `OpenBaoSnapshotNeverSucceeded` — the CronJob exists (`kube_cronjob_info`) but no success timestamp does, for 26h, warning. The absent() guard, scoped by the CronJob's presence so a cluster without the job stays silent.
- `HeimdallDatabaseBackupFailed` widens its Job-name pattern from `*-backup-*` to `*-(backup|snapshot)-*` so a failed upload fires the existing failure rule.

Neither carries `watched`. Local data is intact and Velero's disk snapshot still runs; this is backup plumbing, the heimdall-info tier, exactly as KubicValheim reasons about its upload alerts. The Backups dashboard gains a "time since last OpenBao snapshot" tile beside Velero's, reading the same CronJob metric, with the same "NEVER" no-value text.

### Restore, documented for real

`secrets-management.md` replaces its aspirational restore notes with two procedures. The first is the one the plan exercises (and did, on the local homelab, 2026-09-17); the second is documented from Velero's existing, verified gke schedule and is not drilled here:

- **Raft snapshot restore**: fetch the object, `bao operator raft snapshot restore` into an initialised, unsealed instance whose seal can open it: the same KMS key, or the same static key. `-force` is needed only when the target was re-initialised (its root token and cluster identity differ from the snapshot's), and it merely skips the consistency check: it cannot make a different seal open the snapshot, and recovery keys cannot either, they authorise operations rather than decrypt the barrier. A changed seal means restoring into an instance that still has the original seal material and migrating afterwards; if that material is gone, the snapshot is unreadable.
- **Disk restore** (gke only; homelab Velero has no schedule): Velero restore of the `openbao` namespace brings back the PVC and the `openbao-init` Secret together; under `seal: auto` the pod unseals itself, provided the KMS key still exists.

And the sentence that matters most: the KMS key is now what opens the vault. It cannot be deleted outright (destruction is scheduled with a 24-hour minimum), and its key ring can never be deleted; the setup uses one dedicated key with one narrow grant for exactly that reason.

## Components and files

| Repo | Change |
|---|---|
| nordri | `openbao-init.sh`, `openbao-configure.sh`; `lib/openbao.sh` gains the keep-file option and the backup policy/role in `openbao_configure`; `gke-provision.sh openbao-backup-setup`; bootstrap Layer 5 creates the Garage bucket, key and `openbao-backup-s3` Secret on homelab; docs |
| nidavellir | openbao composition enables the chart's `snapshotAgent` with per-environment S3 values; `openbao/claim.yaml` gains `seal: auto`; render checks; `secrets-management.md` backup and restore sections |
| heimdall | two rules, one dashboard tile |
| realm | this design, the plan, ADR 0004 gains a note on the fresh-init path |

## Sequence

1. nordri, nidavellir, heimdall changes merged; nordri's held `fix/seal-key-crlf` branch (jq CRLF guards, kubectl context check) lands first since the scripts build on it.
2. Local homelab: wipe the OpenBao PVC, re-bootstrap; Layer 5b inits under the static seal, configures, seeds. Trigger the CronJob by hand, verify the object in Garage, verify the tile.
3. GKE: `openbao-seal-setup`, `openbao-backup-setup` (both yours to run). Hydrate the `seal: auto` claim, wait for the XR to render. Delete pod and PVC. `openbao-init.sh gke <file>`, material into the safe, file deleted. `openbao-configure.sh gke realm-siliconsaga`. Delete the siliconsaga realm through kcadm in the Keycloak pod and recreate the import CR so the re-seeded OIDC pair is what the realm holds. Trigger the CronJob, verify the object in GCS.
4. Restore drill on the local homelab: restore yesterday's snapshot into a fresh instance and read the canary back. The runbook is not done until this has happened once.

## Out of scope

HA, TLS on the listener, root-token rotation, and any consumer beyond what exists today.
