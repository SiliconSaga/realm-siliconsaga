# OpenBao Go-Live Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take OpenBao live per the [go-live design](2026-09-16-openbao-go-live-design.md): fresh init under the auto seal with custody in the safe and in-cluster, the chart's snapshot agent shipping daily Raft snapshots to a dedicated bucket per environment, Heimdall rules and a tile, and a restore that has been exercised once.

**Architecture:** nordri gains two thin operator scripts over `lib/openbao.sh` and two provisioning steps (GCS HMAC on gke, Garage key on homelab). nidavellir's openbao composition enables the chart's `snapshotAgent` with per-environment S3 values and the claim graduates to `seal: auto`. heimdall gains two rules and one tile. All GDD conventions apply: `ws orient` at session start, `ws commit <comp> <bodyfile>`, `ws test`, rebase over merge, no key material in argv or shell variables.

**Tech Stack:** bash, Crossplane go-templating, openbao-helm 0.28.3 (`snapshotAgent`), s3cmd via `ghcr.io/openbao/openbao-snapshot-agent`, gcloud, Garage, kube-state-metrics, Grafana.

## Global Constraints

- Secret hygiene as in `lib/openbao.sh`: no key material in an argument list or a shell variable; values rest only in 0600 files under a 0700 directory, removed on success and named on failure.
- Bucket names: gke `${GCP_PROJECT}-openbao-backups`; homelab `openbao-backups` on Garage. Secret `openbao/openbao-backup-s3` with keys `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (the chart's contract).
- OpenBao role and policy name: `openbao-backup`; the policy allows exactly `path "sys/storage/raft/snapshot" { capabilities = ["read"] }`. The role binds ServiceAccount `openbao-snapshot` in namespace `openbao` (the chart's name).
- Schedule `0 5 * * *`; `S3_EXPIRE_DAYS` 30.
- Alert severities: warning, no `watched` label. Rule names `OpenBaoSnapshotStale`, `OpenBaoSnapshotNeverSucceeded`.
- nordri's held branch `fix/seal-key-crlf` (jq CRLF guards, `lib/kube-context.sh`) is the base for the nordri tasks.

---

### Task 1: `openbao-init.sh` and `openbao-configure.sh` (nordri)

**Files:**
- Modify: `lib/openbao.sh` (keep-file option; backup policy and role in `openbao_configure`)
- Create: `openbao-init.sh`, `openbao-configure.sh`
- Modify: `docs/bootstrap.md`, `tests/unit/openbao-seed-test.sh`

**Interfaces:**
- Consumes: `lib/openbao.sh` functions, `lib/kube-context.sh` `require_kube_context`.
- Produces: `OPENBAO_INIT_KEEP_FILE=<path>` honoured by `openbao_ensure_initialized` (a 0600 copy of init.json written there before the scratch dir is removed); `openbao_configure` creates policy `openbao-backup` and role `openbao-backup` bound to `openbao-snapshot`/`openbao`.

- [ ] **Step 1: keep-file in the lib.** In `openbao_ensure_initialized`, after the Secret reads back and before `openbao_scratch_rm`, when `OPENBAO_INIT_KEEP_FILE` is non-empty: `( umask 077; cp "$scratch/init.json" "$OPENBAO_INIT_KEEP_FILE" )`, then print `   📄 Init material also written to $OPENBAO_INIT_KEEP_FILE (0600) — move it to the password safe, then delete it.`
- [ ] **Step 2: backup policy and role in `openbao_configure`**, after eso-role:

```bash
    echo "   • openbao-backup policy and role (the chart's snapshot agent)"
    openbao_run_with_token 'bao policy write openbao-backup - >/dev/null' <<'EOF' || return 1
path "sys/storage/raft/snapshot" { capabilities = ["read"] }
EOF
    openbao_run_with_token 'bao write auth/kubernetes/role/openbao-backup bound_service_account_names=openbao-snapshot bound_service_account_namespaces=openbao policies=openbao-backup ttl=1h >/dev/null' </dev/null || return 1
```

- [ ] **Step 3: `openbao-init.sh`** (`<gke|homelab> <output-file>`): source both libs, `require_kube_context`, refuse if the output file exists or its directory is not writable, `openbao_wait_running 600`, then `OPENBAO_INIT_KEEP_FILE="$2" openbao_ensure_initialized`, then `openbao_ensure_unsealed` (a no-op under the auto seal), then print `bao status`. Refuses an already-initialized instance (the lib prints "already initialized" and the script exits 2 with the message that init material is not re-mintable).
- [ ] **Step 4: `openbao-configure.sh`** (`<gke|homelab> [realm]`): source libs, `require_kube_context`, resolve `REALM_DIR` as bootstrap does, require initialized+unsealed, `openbao_configure`, then `openbao_seed_file "$REALM_DIR/openbao-seeds"` when present.
- [ ] **Step 5: unit test** for both scripts' argument handling with a kubectl stub (wrong context refused, existing output file refused, unknown target refused). Add to `tests/unit/openbao-scripts-test.sh`.
- [ ] **Step 6: docs** — `docs/bootstrap.md` Layer 5b section: the two standalone scripts, the keep-file, the backup role.
- [ ] **Step 7:** `ws test nordri`, commit: `feat(openbao): standalone init and configure scripts, snapshot-agent policy and role`.

### Task 2: `gke-provision.sh openbao-backup-setup` (nordri)

**Files:** `gke-provision.sh`, `docs/bootstrap.md`

- [ ] **Step 1:** New case `openbao-backup-setup)` modelled on `velero-setup`: bucket `${GCP_PROJECT}-openbao-backups` (uniform access, same location derivation), lifecycle rule age 30 days (`gcloud storage buckets update --lifecycle-file` from a heredoc JSON), GSA `openbao-backup` with the same IAM-propagation poll, `roles/storage.objectAdmin` on that bucket only. Then the HMAC key: if Secret `openbao/openbao-backup-s3` exists, leave it; else `gcloud storage hmac create "$SA" --project ... --format=json` to a 0600 scratch file, extract `accessId` and `secret` with jq into two 0600 files, `kubectl create secret generic openbao-backup-s3 -n openbao --from-file=AWS_ACCESS_KEY_ID=... --from-file=AWS_SECRET_ACCESS_KEY=...`, remove the scratch dir. The key value never enters argv or a variable.
- [ ] **Step 2:** usage text and `docs/bootstrap.md` "OpenBao snapshot backups (one-time)" section next to the seal setup.
- [ ] **Step 3:** `bash -n`, commit: `feat(gke): openbao-backup-setup — bucket, GSA, HMAC key parked for the snapshot agent`.

### Task 3: homelab Garage bucket and key in Layer 5 (nordri)

**Files:** `bootstrap.sh`

- [ ] **Step 1:** After the Velero credentials block inside the Garage-ready branch: create key `openbao-backup-key` (or `key info` if it exists), bucket `openbao-backups`, `bucket allow --read --write`, then if Secret `openbao/openbao-backup-s3` is absent create it with `--from-literal` of the parsed id and secret. Note: Layer 5 already holds Velero's key in variables and passes them via `--from-literal`; this task follows that existing shape and records in a comment that hardening both to files is a follow-up, rather than half-fixing one.
- [ ] **Step 2:** `bash -n`, commit: `feat(bootstrap): Garage bucket and key for OpenBao snapshots on homelab`.

### Task 4: snapshot agent in the openbao composition, claim to `seal: auto` (nidavellir)

**Files:** `openbao/composition.yaml`, `openbao/claim.yaml`, `tests/render/check-openbao.sh`, `docs/secrets-management.md`

- [ ] **Step 1:** In the Release values, add:

```yaml
                snapshotAgent:
                  enabled: true
                  schedule: "0 5 * * *"
                  s3CredentialsSecret: openbao-backup-s3
                  config:
                    baoAuthPath: kubernetes
                    baoRole: openbao-backup
                    s3ExpireDays: "30"
                    {{- if eq $env "gke" }}
                    s3Host: storage.googleapis.com
                    # s3cmd's --host-bucket takes a host TEMPLATE; a plain host
                    # means path-style, which is what GCS interop and Garage want.
                    s3Bucket: storage.googleapis.com
                    s3Uri: s3://{{ $identity.gcpProject }}-openbao-backups/openbao/
                    s3cmdExtraFlag: ""
                    {{- else }}
                    s3Host: garage.garage.svc.cluster.local:3900
                    s3Bucket: garage.garage.svc.cluster.local:3900
                    s3Uri: s3://openbao-backups/openbao/
                    s3cmdExtraFlag: "--no-ssl"
                    {{- end }}
```

  Guard: the agent runs regardless of `$seal`, since a Shamir cluster can snapshot too. Add a `fail` if gke and `gcpProject` is missing or a placeholder (already present for the seal; reuse the condition).
- [ ] **Step 2:** `openbao/claim.yaml`: add `seal: auto` with a comment that this is the graduation (ADR 0004) and what it triggers on each environment.
- [ ] **Step 3:** render checks: both envs render `kind: CronJob` with `name: openbao-snapshot`, `S3_EXPIRE_DAYS: "30"`, `BAO_ROLE: openbao-backup`; gke has `S3_HOST: storage.googleapis.com` and `s3://example-project-openbao-backups/`; homelab has `garage.garage.svc.cluster.local:3900` and `--no-ssl`; the shamir fixture still renders the CronJob.
- [ ] **Step 4:** `docs/secrets-management.md`: new "Backups" section (what the agent does, the bucket per env, the Secret contract, how to trigger a run by hand: `kubectl create job --from=cronjob/openbao-snapshot openbao-snapshot-manual -n openbao`, how to list objects), and "Restore" replacing the aspirational text with the two procedures from the design.
- [ ] **Step 5:** `bash tests/render/check-openbao.sh`, commit: `feat(openbao): daily Raft snapshots via the chart's snapshot agent; graduate the claim to seal: auto`.

### Task 5: rules and tile (heimdall)

**Files:** `crossplane/composition.yaml`, `crossplane/backups-dashboard.yaml`, `docs/data-service-monitoring.md`

- [ ] **Step 1:** Widen `HeimdallDatabaseBackupFailed`'s `job_name=~".*-backup-.*"` to `".*-(backup|snapshot)-.*"`, with a comment naming the snapshot agent.
- [ ] **Step 2:** Add to the data-services group:

```yaml
                    - alert: OpenBaoSnapshotStale
                      expr: |
                        time() - kube_cronjob_status_last_successful_time{namespace="openbao", cronjob="openbao-snapshot"} > 36 * 3600
                      for: 10m
                      labels:
                        severity: warning
                        component: data-services
                      annotations:
                        summary: "OpenBao Raft snapshots have stalled"
                        description: "Last successful openbao-snapshot Job was {{ $value | humanizeDuration }} ago; the schedule is daily. Velero's disk snapshot still runs, so this is plumbing, not data loss — yet."
                    - alert: OpenBaoSnapshotNeverSucceeded
                      expr: |
                        kube_cronjob_info{namespace="openbao", cronjob="openbao-snapshot"}
                        unless on(namespace, cronjob) kube_cronjob_status_last_successful_time{namespace="openbao", cronjob="openbao-snapshot"}
                      for: 26h
                      labels:
                        severity: warning
                        component: data-services
                      annotations:
                        summary: "OpenBao snapshot CronJob has never succeeded"
                        description: "openbao-snapshot exists but no run has ever completed. Check the Job logs: the usual causes are the openbao-backup role missing in OpenBao or the openbao-backup-s3 Secret missing."
```

- [ ] **Step 3:** Backups dashboard: a stat tile "Time since last OpenBao snapshot" beside Velero's, `time() - kube_cronjob_status_last_successful_time{namespace="openbao", cronjob="openbao-snapshot"}`, same thresholds (yellow 90000, red 129600), `noValue: "NEVER — no snapshot on record"`.
- [ ] **Step 4:** Render with `crossplane render` against both fixtures; grep the rule names and the tile title. Doc table row. Commit: `feat(alerts): OpenBao snapshot staleness rules and a Backups tile`.

### Task 6: realm — ADR 0004 note and this plan

- [ ] ADR 0004 "More Information" gains one bullet: a fresh cluster (or a wiped instance) initialises directly under the auto seal; the migration procedure is only for an instance that was initialised under Shamir. Commit with the plan.

### Task 7: execution (HUMAN-GATED, in order)

- [ ] **Local homelab rehearsal.** Merge nordri and nidavellir tasks. `kubectl config use-context docker-desktop`. Delete pod and PVC `data-openbao-0`; `./update-embedded-git.sh homelab realm-siliconsaga` (claim now `seal: auto`); `./bootstrap.sh homelab realm-siliconsaga` re-runs and Layer 5b inits under the static seal (stale `openbao-init` kept under a timestamped name), configures, seeds. Trigger `openbao-snapshot` by hand; list the object in Garage (`kubectl exec -n garage garage-0 -- /garage bucket info openbao-backups`). Grafana tile reads a number.
- [ ] **GKE.** You run `./gke-provision.sh openbao-seal-setup` and `./gke-provision.sh openbao-backup-setup`. `kubectl config use-context gke_…`. Rehydrate (`update-embedded-git.sh gke realm-siliconsaga`), wait for the `openbao` XR to render `Synced=True`. `ws k8s delete pod openbao-0 -n openbao` and `ws k8s delete pvc data-openbao-0 -n openbao` (scope armed on openbao). Wait Running. `./openbao-init.sh gke <file in your home dir>`; move the file's contents to the safe; delete the file. `./openbao-configure.sh gke realm-siliconsaga`. Keycloak: `kcadm.sh` in `keycloak-0` deletes realm `siliconsaga` (admin creds from `keycloak-initial-admin`), then `ws k8s delete keycloakrealmimport siliconsaga-realm -n keycloak` and let the realm root-app recreate it; confirm the import Job completes. Trigger `openbao-snapshot`; `gcloud storage ls gs://teralivekubernetes-openbao-backups/openbao/`.
- [ ] **Restore drill (local).** Download the newest local snapshot from Garage, `bao operator raft snapshot restore` into the local instance, read `secret/demo` back. Record the result in the runbook's restore section and in the Loki thalamus.
