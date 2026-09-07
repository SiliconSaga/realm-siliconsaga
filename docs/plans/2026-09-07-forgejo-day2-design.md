# Forgejo Day-2 — Design (revised)

**Status:** Design, approved in brainstorm; plan pending
**Date:** 2026-09-07
**Owner:** Rasmus Praestholm
**Supersedes:** [2026-05-15 Forgejo day-2 design](2026-05-15-forgejo-day2-design.md) (this realm, moved from yggdrasil), [nidavellir 2026-08-18 Forgejo cutover design](../../../../components/nidavellir/docs/plans/2026-08-18-forgejo-cutover-design.md), and [nidavellir platform-gitea notes](../../../../components/nidavellir/docs/platform-gitea.md). Those documents stay for history; this one is the design of record.
**Related:** [Nordri bootstrap](../../../../components/nordri/docs/bootstrap.md) · [Mimir DataService design](../../../../components/mimir/docs/plans/2026-08-17-dataservice-vending-design.md) · [Mimir offsite backups](../../../../components/mimir/docs/offsite-backups.md) · [Heimdall alerting and probes](../../../../components/heimdall/docs/plans/2026-07-27-alerting-hygiene-and-service-probes-design.md) · [Realm-owned stack config](2026-07-03-realm-owned-stack-config-design.md) · [ADR 0001 OpenBao-first](../adrs/0001-openbao-first-secrets-management.md) · [ADR 0002 minimal unseal](../adrs/0002-minimal-unseal-phase1.md)

## Why this revision

The May design predates most of what it depends on. Since then the stack gained the Mimir DataService operator and a shared Postgres with offsite pgBackRest backups, the platform wildcard certificate, OpenBao with External Secrets, realm-owned cluster config hydrated as its own seed repo, vendor mirrors with real history and tags, Velero on GKE, and Heimdall's blackbox probes and volume alerts. It also predates a second design in nidavellir that rejected the May doc's mirror direction.

The seed Gitea meanwhile lost its repositories four times in three weeks of August and September, once for sixteen hours of dead GitOps, because its repositories lived on an `emptyDir` while its Postgres survived on PVCs and kept insisting the repositories existed. On 2026-09-07 the live GKE seed was reinstalled in the shape nordri's bootstrap now pins: one SQLite pod, no subcharts, ephemeral and internally consistent, so a wipe is a clean wipe and hydration self-heals. That is Phase 0 of this design, and it is done.

This document reconciles the two earlier designs, records the decisions taken in the 2026-09-07 brainstorm, and moves the design of record into the realm. The cutover is SiliconSaga stack work spanning nordri, nidavellir, mimir and heimdall; it is not GDD workspace tooling, and any `ws`-level fallout is filed separately against yggdrasil.

## Goals

1. **GitOps stops dying on node rolls.** ArgoCD reads from a durable, PVC-backed, Mimir-backed Forgejo, not from an ephemeral seed.
2. **The bootstrap stays ephemeral and idempotent.** The seed Gitea remains a disposable chicken-and-egg breaker that a fresh cluster can always re-run. It is never hardened into the durable thing.
3. **GitHub stays the place where `main` is decided.** Code review, the GDD `ws cr` flow, and the public record stay on GitHub. Forgejo follows GitHub; it never leads it.
4. **The local-branch testing loop survives.** Pushing an unpushed working tree into the cluster's Git host and watching ArgoCD deploy it is what the seed exists for today, and Forgejo must offer the same.
5. **Graduation is a named, documented, repeatable step**, not an accumulation of commented-out lines and `suspend: true` flags.

## Non-goals

- **Forgejo → GitHub push mirroring.** Rejected: it makes Forgejo authoritative, leaks test branches to GitHub, and stores a GitHub token in Forgejo.
- **GitHub → Forgejo pull mirroring for maintained repos.** Rejected: mirrored repositories are read-only in Forgejo, which kills the local-branch loop. Pull mirroring is used only for vendor mirrors, where read-only is correct.
- **A GitHub credential anywhere in the cluster.** All SiliconSaga repositories are public; the puller does an anonymous `git fetch`, which is not subject to the GitHub API rate limit. A token enters only if repositories go private or a later consumer needs API calls.
- **SSO at cutover.** Forgejo ships with local break-glass admin accounts. Keycloak-brokered OIDC is the `full` maturity, designed separately.
- **Forgejo Actions, federation, a GitHub Action push-sync, homelab durable-storage decisions.** Recorded under Future work.
- **Any `ws` verb.** Hydration, graduation and on-demand sync are nordri scripts. If a workspace-level convenience proves wanted later it is a yggdrasil issue.

## Decisions

### Source of truth: GitHub authoritative, Forgejo writable, `main` synced by push from outside

| Concern | Decision |
|---|---|
| Authority over `main` | GitHub. Review and merge happen there. |
| Forgejo repositories | Ordinary writable repositories, **not** Forgejo mirrors. |
| How `main` reaches Forgejo | An in-cluster **puller** CronJob fetches `main` from GitHub anonymously and pushes it to Forgejo with `--force-with-lease`. |
| Who may write `main` on Forgejo | Only the puller. Every other branch is free. |
| Schedule | Hourly by default; per-cluster value from cluster-identity so an idle homelab can say daily. On demand by creating a Job from the CronJob or by running the nordri hydrate script. |
| Vendor mirrors (`keycloak-k8s-resources` and any future `tier: vendor` component) | Forgejo native pull-mirror from the upstream, with tags. Read-only is correct for these. |
| Realm cluster config (`realm-siliconsaga/cluster/`) | Synced like any other maintained repository; the realm repo is public on GitHub. |
| ArgoCD | Reads only Forgejo. Never GitHub. |
| Forgejo → GitHub | Nothing. Cluster-side writes flow back through a human's workstation and a normal GitHub PR. |

This is the model the current hydrate scripts already implement against the seed, made durable and scheduled. It keeps the property the August design fought for (a writable in-cluster host) and the property the May design fought for (GitHub as the record) at the cost of one small CronJob.

A GitHub Action that pushes to Forgejo on merge is a possible latency optimisation for GKE only, since GitHub cannot reach a homelab Forgejo. It is deliberately not in scope.

### Platform maturity: `bootstrap` → `durable` → `full`

cluster-identity gains a `maturity` field. Compositions and app-of-apps entries gate on it exactly as they gate on `env` today. The word is *maturity*, not *tier*: the stack already uses tier for the Nordri / Nidavellir / end-user-app layering.

| Maturity | What is on | Git source ArgoCD reads |
|---|---|---|
| `bootstrap` | Everything today through Mimir vending databases, OpenBao with auto-unseal, Heimdall | Seed Gitea, hydrated from a workstation |
| `durable` | Forgejo (release, PVC, HTTPRoute, DataService, init Job, puller); Heimdall Forgejo probe and ArgoCD-Unknown alert; Velero covering the `forgejo` namespace | Forgejo, `main` pulled from GitHub |
| `full` | Keycloak unsuspended with realm import, Forgejo OIDC source against Keycloak, Harbor, later Backstage | Forgejo |

Bootstrap ends when the cluster can vend a database and OpenBao unseals itself. Graduating a cluster to `durable` is one commit bumping `maturity`, hydrated in, plus the cutover ceremony below. Graduating to `full` is another bump; its contents are a separate design.

`bootstrap.sh` continues to produce a `bootstrap`-maturity cluster and nothing more. A fresh Docker Desktop cluster therefore never tries to stand up Forgejo, Keycloak or Harbor. The human-gated steps that cannot be declarative live in a nordri `graduate.sh`, the successor to the old "swap cert-manager from staging to prod" step, documented as such.

The `durable` boundary is also where homelab's deferred storage questions belong: a real Velero target, the Garage-versus-SeaweedFS decision, bucket layout. They are recorded here as a consequence of the model, not designed here.

### Forgejo composition (nidavellir, Tier 2)

`nidavellir/forgejo/` becomes an XRD plus composition in the openbao / ntfy / heimdall / harbor pattern: `function-environment-configs` reads cluster-identity, `function-go-templating` renders the resources, one claim per cluster. Nidavellir stays generic; the realm supplies only the org name and the repository list through the claim.

The composition renders:

- The Forgejo Helm release from the native OCI chart `oci://code.forgejo.org/forgejo/forgejo`, with a PVC for repositories on the cluster default storage class, database settings read from the DataService Secret, and the admin credential read from the ESO-delivered Secret.
- An `HTTPRoute` for `forgejo.<domain>` on the shared Gateway's `websecure` listener. No per-route certificate; the platform wildcard covers it.
- The existing `DataService` claim (`engine: postgres`, `placement: shared`) — already in the repo, not yet wired.
- The **init Job** (below).
- The **puller CronJob** with its schedule from cluster-identity, and its Forgejo token from the Secret the init Job writes.
- Per-vendor-mirror configuration, applied by the init Job through Forgejo's API.

Claim fields: `org` (realm-supplied, `siliconsaga`), `repos` (realm-supplied list of `{name, github}`), `vendorMirrors` (list of `{name, upstream}`), `breakGlassAdmins` (list of usernames), `pullerSchedule` (defaulted from cluster-identity), and an optional `oidc` block that stays empty until `full` maturity.

Everything the composition renders is gated on `maturity >= durable`, so the claim can be committed and hydrated at `bootstrap` maturity without rendering anything.

### Credentials: generated in-cluster and written to OpenBao in the same step

The init Job is idempotent and runs once Forgejo reports ready **and** OpenBao is unsealed. It fails loudly if OpenBao is sealed rather than proceeding with a password nobody can recover later. It:

1. Generates the admin password (alphanumeric only, since it is embedded in remote URLs by hydration) and writes it to OpenBao at `secret/forgejo` in the same step; ESO delivers it as the `forgejo-admin` Secret the release consumes. No human ever holds it; break-glass is via OpenBao.
2. Creates the org and each repository in the claim's list, empty, with `auto_init` so `HEAD` resolves before the first pull.
3. Mints a **Forgejo** access token scoped to write those repositories and stores it as the puller's Secret. This is the only credential in the design, it is Forgejo-side, and it never leaves the cluster.
4. Configures each vendor mirror as a Forgejo pull-mirror with tag sync.
5. Creates the break-glass local admin accounts with generated passwords written to OpenBao under `secret/forgejo/admins/<user>`.

This departs from ADR 0001's "born in OpenBao" seeding pattern, where a human runs `bao kv put` first. Generating in-cluster and writing to OpenBao in the same automated step keeps OpenBao as the custody point while removing the manual seed that is the step most likely to be forgotten.

**Prerequisite: OpenBao auto-unseal.** OpenBao re-seals on every restart today, so an init Job that depends on it would fail on the first node roll. [ADR 0002](../adrs/0002-minimal-unseal-phase1.md) chose manual unseal deliberately and deferred KMS auto-unseal to a hardening phase; Forgejo depending on OpenBao is what makes that phase due. Auto-unseal is a small change to the openbao composition branching on cluster-identity: GCP KMS seal via Workload Identity on GKE, a static seal with key material in a Secret on homelab, which keeps the ADR's "no cloud coupling on homelab" property and accepts the same in-cluster custody it already accepts. It is a `bootstrap`-maturity change and a gate for Phase 2 below; it is tracked as its own task with its own ADR, not designed here.

### Repository URLs: Git holds the durable state, bootstrap patches the transient one

Under this model Forgejo's `main` is GitHub's `main` verbatim, so the repoURLs committed on GitHub **must be the Forgejo URLs**, or the puller's first run would undo the cutover.

- Committed form: `http://forgejo-http.forgejo.svc.cluster.local:3000/siliconsaga/<repo>.git`.
- `bootstrap.sh` and `update-embedded-git.sh` rewrite that to `http://gitea-http.gitea.svc.cluster.local:3000/nordri-admin/<repo>.git` at hydration time, exactly as they already rewrite overlay paths and stamp the GCP project. The seed URL exists only in hydrated copies.
- The realm's `defaults.gitea.internalUrl` becomes `defaults.forgejo.internalUrl`; call sites move with it. Hard cut, no alias.
- Sixteen manifests across nordri (`platform/argocd/*`, `platform/fundamentals/apps/garage.yaml`, `platform/root-app.yaml`), nidavellir (`apps/*`), mimir (`argocd/apps/*`), plus nordri's realm root-app template, change in one coordinated PR train. The org rename from `nordri-admin` to `siliconsaga` rides the same change since every URL is touched anyway. The seed keeps `nordri-admin`; it is the patched form.

### Cutover ceremony (`graduate.sh durable`)

Unchanged in shape from the May design. Pre-condition: `maturity: durable` committed and hydrated, Forgejo composition Ready, init Job succeeded, puller's first run has populated every repository and vendor mirror from GitHub, and the gates below are green.

1. **Verify Forgejo holds the truth.** Each repository's `main` on Forgejo matches GitHub's `main`, which by construction carries the Forgejo repoURLs.
2. **Push the swap commit into the seed.** One hydration into the seed *without* the URL patch, so every Application manifest the seed serves now points at Forgejo.
3. **ArgoCD re-registers** each Application against Forgejo, finds the desired state present, and continues syncing.
4. **Verify** every Application reports `Synced` and `Healthy` against a Forgejo `repoURL`, and that Heimdall's Forgejo probe is green.

Reversible before step 2 by doing nothing. Reversible after step 2 by a counter-hydration into the still-running seed, which is why the seed lingers.

**The seed lingers a few days**, unreferenced, then `graduate.sh --retire-seed` uninstalls the Helm release and deletes the `gitea` namespace. The HTTPRoute for `gitea.<domain>` is ArgoCD-owned in nordri's fundamentals and is removed from the overlays in the same change. A fresh bootstrap still installs the seed; that is by design.

### Local-branch testing after cutover

`update-embedded-git.sh` grows a target for Forgejo. Hydrating a working tree pushes an orphan snapshot to Forgejo `main`, as it does to the seed today. Because the puller would restore GitHub's `main` within the hour, the script **suspends the puller CronJob** when it hydrates and a `--resume` flag, or the next `graduate.sh` run, clears the suspension and triggers an immediate pull. The suspension state is visible in `kubectl get cronjob`, so a forgotten test hydration is discoverable.

Seed hydration keeps working unchanged at `bootstrap` maturity.

### Monitoring, backup, gates

Heimdall additions, at `durable` maturity:

- A blackbox `Probe` on Forgejo's `/api/healthz` in the **watched** tier, so an unreachable Forgejo pages within three minutes.
- **A new alert on ArgoCD Applications sitting in sync status `Unknown` for more than five minutes.** This is the blind spot every seed wipe exposed: everything reported Healthy while nothing had reconciled for sixteen hours. It is worth having regardless of Forgejo and is the single most valuable rule in this design.
- The existing volume-fill and volume-shrink rules already cover the repository PVC by construction.

Backup:

- Velero's GKE and homelab schedules include the `forgejo` namespace; the repository PVC is not labelled reconstructible, because after cutover it is not.
- The database rides the shared Postgres's pgBackRest, including repo2 in GCS on GKE.

Gates before `--retire-seed`, all true at once, not a sequence:

- [ ] Repository PVC survives pod deletion, verified by deleting the pod.
- [ ] A restore drill of the shared Postgres from repo2 has been run once. Neither pgBackRest repo has ever been restored from.
- [ ] A Velero restore of the `forgejo` namespace into a scratch namespace has been run once.
- [ ] Puller has completed on schedule for every repository for the soak period, and an on-demand trigger has been exercised.
- [ ] Every Application `Synced` and `Healthy` against Forgejo for the soak period.
- [ ] The local-branch loop has been exercised against Forgejo, including suspend and resume.
- [ ] `bootstrap.sh` has been re-run from scratch on a scratch cluster with the URL rewrite in place, since a fresh bootstrap is the documented recovery path.

Known risk carried, not resolved here: the shared Postgres is a single instance. Forgejo becoming load-bearing for GitOps is the point at which that stops being free, and raising it to two instances with a PodDisruptionBudget belongs with the Mimir backup work.

## Phasing

| Phase | Work | Gated on |
|---|---|---|
| 0 | Slim, ephemeral, internally consistent seed live on GKE | **Done 2026-09-07** |
| 1 | OpenBao auto-unseal; `maturity` in cluster-identity with existing components unaffected; URL rewrite in nordri hydration libs (a no-op while manifests still carry seed URLs) | nothing |
| 2 | Forgejo composition, init Job, puller, vendor-mirror config; validate end to end on a homelab or Docker Desktop cluster at `durable` maturity | 1 |
| 3 | Coordinated URL PR train (nordri, nidavellir, mimir, realm); `graduate.sh`; GKE graduation and cutover; soak | 2 |
| 4 | Heimdall probe and ArgoCD-Unknown alert; Velero scope; restore drills; `--retire-seed` on GKE | 3 and the gates |
| 5 | `full` maturity: Keycloak unsuspended, Forgejo OIDC, Harbor. Own design. | 4 |

Phase 1 can start immediately and is safe on the live cluster. The ArgoCD-Unknown alert from Phase 4 can be pulled forward at any time; it needs nothing from Forgejo.

## Open questions

Resolved during the plan, not blockers for the design.

1. **Sync wave for the Forgejo composition** relative to Mimir (wave 6), ESO (9) and OpenBao (10). It must follow all three; the exact number is settled against the current wave layout in the plan.
2. **How the puller enumerates repositories.** Reading the claim's `repos` list rendered into a ConfigMap is the obvious answer; the alternative is querying Forgejo for non-mirror repositories in the org. The plan picks one.
3. **Forgejo chart values that matter for a single-replica PVC deployment**: `persistence`, `strategy: Recreate`, and whether the chart's bundled Postgres and Valkey subcharts default on the way Gitea's do. Verify against the chart's own values before Phase 2, since the seed's eight-pod surprise came from exactly that assumption.
4. **Rotation of the puller token and the admin password.** Both are init-Job products; re-running the Job with a `--rotate` flag is the natural shape. Document during Phase 2.
5. **Whether `graduate.sh` lives in nordri or the realm.** It touches nordri's hydration libs and reads the realm's claim; nordri is the lean.

## Future work

- **GitHub Action push-sync for GKE** as a latency optimisation over hourly polling, if the delay ever matters.
- **Forgejo Actions runners**, and where they live relative to eitri as the software-factory home.
- **Federation.** The Forgejo-not-Gitea decision keeps this open.
- **Homelab `durable`-maturity storage**: Velero target, Garage versus SeaweedFS, bucket layout.
- **A GitHub token for the puller** only if repositories go private or a consumer such as Jenkins needs API calls beyond anonymous fetch.
- **`ws`-level convenience** for on-demand sync or hydration, filed against yggdrasil if wanted; not part of this stack work.
