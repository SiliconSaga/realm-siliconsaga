# Forgejo day-2 — Phase 3 design: generic Git, the promotion ladder, and the GKE cutover

**Status:** In review (realm#46). Decisions 1–5 settled with the owner on 2026-11-10; one implementation plan follows approval. Remaining open points are at the end.
**Date:** 2026-11-06, rewritten 2026-11-10
**Owner:** Rasmus Praestholm
**Parent:** [Forgejo day-2 design](2026-09-07-forgejo-day2-design.md) (design of record; this document settles Phase 3 and records where the record no longer holds) · [Phase 2 design](2026-09-19-forgejo-day2-phase2-design.md)

## Summary

Phase 3 gets ArgoCD reading each cluster's own Forgejo, starting with GKE. Designing it showed the record's cutover cannot work as written: Forgejo's `main` is meant to be GitHub's `main` verbatim, but every hydration today also stamps per-cluster values into the manifests, and a verbatim mirror carries none of them. So Phase 3 comes in two halves:

- **3a, generic Git.** Every per-cluster value moves out of Git into a cluster-local identity written once at bootstrap. Git becomes identical for every cluster, the hydration `sed` libraries go away, and ArgoCD reads one stable in-cluster Git address whichever server is behind it.
- **3b, graduation and promotion.** Changes climb a ladder of clusters (lab, test, homelab prod, GKE prod). GKE follows a `live` branch promoted after homelab soaks. `graduate.sh` moves a cluster from the seed Gitea to its Forgejo and later retires the seed.

## Where Phase 3 starts from

Phase 2 is merged and validated. On 2026-11-06 the owner tested it by hand on the Nano76 Docker Desktop cluster: logged in as the break-glass account, found the five maintained repositories and the vendor mirror, and edited a file on Forgejo's nordri `main` through the web UI. The next puller run was refused ("branch main is protected from force push"), the other four repositories synced, and the Job failed, as [`docs/forgejo.md`](../forgejo.md) describes. Recovery took three steps: delete the `main` rule, run the puller once (its `--force-with-lease` reset `main` to GitHub's), and recreate the rule with a one-off copy of the configure Job.

Facts this design builds on, checked on 2026-11-06 and 2026-11-10:

- **Forgejo has no force-push allowlist.** A protected branch refuses non-fast-forward pushes from every account, admins included. The record's local-branch flow ("the account is on the `main` and force-push allowlists") cannot be implemented.
- **Hydration stamps per-cluster values that GitHub never carries.** A verbatim mirror would deploy the unstamped form:

  | Repo | Stamped at hydration | By | Unstamped result on a mirror |
  |---|---|---|---|
  | nordri | `app-of-apps` path → `platform/fundamentals/overlays/<target>` | inline `sed` in both scripts | bare fundamentals: no cluster-identity, no Velero, no Garage |
  | nordri | `__GCP_PROJECT__` in `velero-gke.yaml` and `cluster-identity-gke.yaml` | `lib/patch-velero.sh` | Velero writes to a bucket named `__GCP_PROJECT__-velero`; OpenBao's KMS seal has no project |
  | nidavellir | vegvisir path `overlays/homelab` → `overlays/<target>` | `lib/patch-nidavellir.sh` | GKE gets the homelab certificate overlay |
  | nidavellir | `tailscale-operator-MACHINE`, `ntfy-MACHINE` (from the workstation's hostname) | `lib/patch-nidavellir.sh` | tailnet devices literally named `…-MACHINE` |
  | mimir | `shared-clusters` path `shared` → `shared/overlays/<target>` | `lib/patch-mimir.sh` | shared database clusters without their per-environment overlay |
  | realm | the seed repo holds only `cluster/`, so the realm root-app path is `.` | `hydrate_working_tree_repo` | a mirror holds the whole repo, so path `.` deploys the wrong tree |
  | all | repoURLs, seed form ↔ Forgejo form | `lib/patch-urls.sh` | covered by the record's URL train, but nothing else above is |

  `envs/<target>/values.yaml` is also copied into the hydrated tree, but nothing reads it.
- **Cluster identity is committed per environment, not per cluster.** `cluster-identity-{homelab,gke}.yaml` are Git content chosen by the overlay `sed`. Homelab's says `maturity: durable`, so any fresh homelab bootstrap, on any machine, comes up `durable` and gets Forgejo. `docs/cluster-identity.md`'s "bootstrap.sh always produces a bootstrap cluster" no longer holds. Two clusters on one site would share one identity.
- **ArgoCD cannot read a ConfigMap into an Application.** There is no `valuesFrom` (Flux has one; Argo does not). An ApplicationSet's cluster generator can read labels and annotations on Argo's cluster Secret, and Crossplane compositions read an EnvironmentConfig. The pinned `argo-cd` chart (10.9.1) ships the ApplicationSet controller.
- **Three of the five Applications that need per-cluster values carry `resources-finalizer`** (tailscale-operator, vegvisir, velero-gke). Deleting one while it has the finalizer deletes everything it deployed. `shared-clusters` deliberately has no finalizer and `prune: false`; `app-of-apps` has no finalizer.
- **18 Application manifests carry an in-cluster Git URL**, all still in the seed form: nordri 5, nidavellir 10, mimir 3, every one `targetRevision: HEAD`. The seed's repositories live under the user `nordri-admin`; Forgejo's under the org `siliconsaga`. Repository names already match (`nordri`, `nidavellir`, `mimir`, `heimdall`, `realm-siliconsaga`).
- **The root Application and the realm root Application are applied by `bootstrap.sh`**, not synced from Git, so they are already cluster-local.
- **Maturity today:** the Nano76 Docker Desktop cluster runs the homelab identity at `durable` with Forgejo; GKE runs `bootstrap`. The full-sized homelab server is arriving and will host `homelab-prod` and `homelab-test`.

## Terms

Each term answers one question.

| Term | Answers | Examples | Declared in |
|---|---|---|---|
| **Site** | Where is the hardware or provider? | `homelab`, `gke` | the cluster's `environment` |
| **Cluster** | Which Kubernetes cluster? | `homelab-prod`, `homelab-test`, `gke-prod`, `homelab-<hostname>` for a lab machine | cluster identity |
| **Maturity** | How durable is this cluster's platform? | `bootstrap`, `durable`, `full` | cluster identity |
| **Role** | What is this cluster for? | `lab`, `test`, `prod` | cluster identity |
| **Source ref** | Which GitHub branch does this cluster's Forgejo mirror? | `main`, `live` | cluster identity |

Every cluster that reaches `durable` runs its own Forgejo, and no cluster reads another's. Maturity and role are independent: a test cluster may be `durable` to exercise the durable layer, and a prod cluster may still be `bootstrap` while it graduates, as GKE is today.

## Decisions

### Decision 1 (settled 2026-11-10): changes climb a ladder of clusters; GKE follows a `live` branch

| Step | Cluster | Role | Maturity | Runs | Git server |
|---|---|---|---|---|---|
| 1 | `homelab-<hostname>`, a lab machine | `lab` | `bootstrap` | local checkouts | seed Gitea, filled by hydration |
| 2 | `homelab-test`, recycled at will | `test` | `bootstrap`, or `durable` to test the durable layer | local checkouts or topic branches | seed, or its own Forgejo filled by hydration |
| — | *merge the PRs on GitHub* | | | | |
| 3 | `homelab-prod` | `prod` | `durable` | GitHub `main` | its Forgejo; the puller follows `main`; the change soaks here |
| — | *`promote.sh gke`: fast-forward `live` to what `homelab-prod` runs* | | | | |
| 4 | `gke-prod` | `prod` | `durable` | GitHub `live` | its Forgejo; the puller follows `live` |

- **Lab and test clusters carry no real workloads.** They are recycled whenever a test calls for a clean start; nothing on them is backed up and nothing depends on them.
- **A test cluster's own Forgejo is its scratch space.** On a `durable` test cluster the canonical org is fed by hydration: unprotected, no puller. `role: test` is what tells the composition so. No prod cluster is ever pointed at a test source, so there is no forgotten test to alert on.
- **`main` is what homelab runs; `live` is what GKE runs.** The asymmetry is deliberate: `main` quietly means "homelab prod", and `live` means "promoted after the homelab soak". Applications keep `targetRevision: HEAD`; the puller maps the cluster's source ref onto Forgejo's `main`.
- **Promotion happens on GitHub**, as one set: see item 3b-2.
- **GKE-only changes take a GKE test cluster.** The homelab soak does not exercise the GKE Velero setup, KMS unseal or the wildcard certificate. A risky change there gets a temporary `gke-test`: step 2, run on GCP.
- **Backups cross sites around a promotion.** Homelab backs up before and after a change and uploads to GCP; GKE backs up before and after its promotion, to its own buckets and to homelab. A requirement on Phase 4's Velero scope, not built here.

Weighed and set aside: a scratch org per tester (superseded: a prod cluster never reads a test source); retargeting `targetRevision` per Application (needs a YAML-aware rewrite, since `targetRevision` also pins chart versions); removing protection around a test push (`main` diverges from GitHub, and the puller stops being the only writer); keeping the seed forever as the test target (it stays only as the `bootstrap`-maturity source); `argocd app set --revision` (a parent's `selfHeal` reverts it, and it leaves no record); lagging GKE by turning auto-sync off (GKE would show OutOfSync whenever it lags). Tags alone were first set aside because the puller would have to resolve "newest"; review then showed that is exactly what an all-five-repositories activation boundary needs, so 3b-2 pairs the `live` branch with numbered tag sets.

### Decision 2 (settled 2026-11-10): the canonical and vendor orgs only

| Class | Org | Fed by | Protection | Exists on |
|---|---|---|---|---|
| **canonical** | `siliconsaga` | the puller from the source ref; hydration on a `test` cluster | `main` protected, puller only; none on `test` | every Git server, seed included |
| **vendor** | `siliconsaga-vendor` | pull-mirrors from upstream, tags included | read-only mirrors | every Git server, seed included |

Rules for any org, now and later:

1. An org is a trust class: protection, writers, retention and backup are decided per org, never per repository.
2. A protected org mirrors a GitHub ref and is written only by a puller. Work never starts on Forgejo and is never promoted between orgs or servers; promotion is a GitHub branch moving.
3. An unprotected org is disposable, and exists only on `lab` and `test` clusters.
4. Names are `<realm>-<class>`, except the canonical org, which keeps the bare realm name.
5. The realm declares orgs; nidavellir never names one. The claim's `org` field becomes an `orgs` list with a `class` per entry.
6. Separation between classes comes from accounts: Forgejo token scopes go by category, not org, so each puller-written class gets its own bot account.

Recorded, not built: **preview** orgs (`siliconsaga-pr-123`) fed from trusted PR heads, gated on the realm's PR trust list as naust's PR bays are, with an expiry and a reaper. They wait for a preview cluster.

### Decision 3 (settled 2026-11-10): cluster identity is cluster-local, written at bootstrap; Git carries no per-cluster value

Rejected alternative: keep stamping, and have the puller run nordri's patch libraries on each pull so Forgejo's `main` is "GitHub plus this cluster's values". It keeps every `sed` and makes Forgejo's `main` differ from GitHub on every cluster.

**The record.** A ConfigMap `cluster-identity` in namespace `nordri`, written before anything else at bootstrap. It is the cluster's single source of per-cluster facts. It holds no secrets.

| Key | Example | Notes |
|---|---|---|
| `cluster` | `homelab-prod` | unique; identity-changing scripts refuse a mismatch with the name they were given |
| `environment` | `homelab` / `gke` | selects overlays; replaces the scripts' `gke` / `homelab` argument |
| `role` | `lab` / `test` / `prod` | |
| `maturity` | `bootstrap` / `durable` / `full` | unchanged meaning |
| `sourceRef` | `main` / `live` | read by the puller; ignored on `test` |
| `tailnetNode` | `homelab-prod`, `gke` | device suffix for `tailscale-operator-<node>` and `ntfy-<node>`; defaults to `cluster`. Cluster names are unique in the realm, so every cluster on the one tailnet gets distinct devices, even two clusters on one machine (which the hostname-based names today would collide on). GKE sets `gke` to keep today's device names and the phone's ntfy subscription |
| `storageClass`, `domain`, `harborRole`, `harborCentral` | | today's fields, unchanged |
| `gcpProject`, `gcpRegion` | | GKE only. The project id is already committed in mimir's and vegvisir's GKE overlays, so it is not treated as secret: it moves into the realm's cluster file, and those hardcoded copies are replaced (Decision 4) |
| `pullerSchedule` | | optional, as today |

**Where the values come from**, later layers winning:

1. nordri's environment defaults, `identity/defaults-<environment>.yaml` (storage class, domain and the rest of today's identity files, minus `maturity`).
2. The realm's `clusters/<cluster>.yaml`: role, maturity, source ref, tailnet node, overrides. Reviewed on GitHub like any change.
3. Values that must not be committed, from the environment at apply time. None exist today; the layer is kept so one never has to be committed.

A cluster name with no realm file gets lab defaults: `environment: homelab`, `role: lab`, `maturity: bootstrap`. A spare machine cannot come up `durable` by accident. GKE clusters must be declared.

**Projections.** One script, nordri `identity.sh apply <realm> <cluster>`, merges the layers, writes the ConfigMap, and projects it twice:

- the `cluster-identity` **EnvironmentConfig**, for Crossplane compositions, exactly as today's but cluster-local (applied once Crossplane's CRDs exist);
- labels and annotations on ArgoCD's **cluster Secret** for `in-cluster` (`argocd.argoproj.io/secret-type: cluster`), for ApplicationSets (Decision 4). Labels, for selection: `nordri.siliconsaga.org/cluster` and `nordri.siliconsaga.org/environment`. Annotations, for values: `nordri.siliconsaga.org/tailnet-node` and `nordri.siliconsaga.org/gcp-project`.

**A recycled cluster keeps its name, so its tailnet devices must go with it.** A destroyed cluster's devices stay registered, and Tailscale gives a newcomer with a taken name a `-1` suffix: a recycled `homelab-test` would come back as `tailscale-operator-homelab-test-1`, and ntfy's advertised URL would be wrong. Recycling therefore removes the cluster's devices first, through the Tailscale API (a nordri `recycle.sh`, or a step in its runbook). Registering `lab` and `test` clusters' devices as ephemeral, so Tailscale drops them itself, is checked against the operator's options during planning.

It prints a diff against the live ConfigMap before applying and is safe to re-run. Graduating a cluster is: change `maturity` in the realm file, merge, run `identity.sh apply`. No hydration. Identity drift (cluster versus realm file) becomes a check in the sync-visibility work (3b-6).

**Secrets stay out.** New secrets follow the Phase 2 pattern: generated in OpenBao create-only at a conventional path, read through ExternalSecrets. The identity needs no pointers to them.

### Decision 4 (settled 2026-11-10): the five Applications with per-cluster values become ApplicationSets

Each uses a cluster generator selecting the `in-cluster` Secret by its `nordri.siliconsaga.org/cluster` label (`goTemplate: true`, `goTemplateOptions: ["missingkey=error"]`, so a missing key fails the render instead of producing an empty path), and renders the same single Application, by name, as today:

| Today | Templated from identity |
|---|---|
| nordri `platform/argocd/app-of-apps.yaml` | `path: 'platform/fundamentals/overlays/{{ index .metadata.labels "nordri.siliconsaga.org/environment" }}'` |
| nidavellir `apps/vegvisir-app.yaml` | `path: 'vegvisir/manifests/overlays/{{ index .metadata.labels "nordri.siliconsaga.org/environment" }}'` |
| nidavellir `apps/tailscale-operator-app.yaml` | `hostname: 'tailscale-operator-{{ index .metadata.annotations "nordri.siliconsaga.org/tailnet-node" }}'` |
| mimir `argocd/apps/shared-clusters.yaml` | `path: 'shared/overlays/{{ index .metadata.labels "nordri.siliconsaga.org/environment" }}'` |
| nordri `platform/fundamentals/apps/velero-gke.yaml` | bucket, service account and project from `index .metadata.annotations "nordri.siliconsaga.org/gcp-project"` |

**Per-cluster cloud targets.** The GCP project is also hardcoded outside these templates: mimir's `shared/overlays/gke` (the pgBackRest service account and bucket, the MySQL backup bucket) and vegvisir's GKE overlay and base `cert-manager-app.yaml` (the DNS-01 service account and project). A `gke-test` would inherit prod's backup targets. In 3a every one of them reads `gcpProject` instead: the mimir and vegvisir ApplicationSets pass it in as `kustomize.patches` on the Application they render. And every backup destination gains the cluster name as its path prefix (Velero's `prefix`, pgBackRest's repository path, the MySQL backup path), so two clusters in one project never write to the same place. A `lab` or `test` cluster may switch cloud backups off entirely through its role.

The ApplicationSet is only the way an Application reads the identity: one cluster, one generated Application. Running two copies of an app side by side, say to soak a new version beside the old, is possible with a second generator, but most of these apps own cluster-scoped objects (CRDs, webhooks, the Gateway) that two copies would fight over. The ladder is the soak mechanism; a side-by-side copy stays a per-app decision for apps that can tolerate it, such as a second database cluster in Mimir.

The other Applications stay plain. The ntfy claim drops its hostnames; the ntfy composition derives `ntfy-<tailnetNode>` and the base URL from the identity and a `tailnet` claim parameter. The `cluster-identity-*.yaml` manifests leave the fundamentals overlays.

**Safety settings on every one:** `syncPolicy.preserveResourcesOnDeletion: true` and `applicationsSync: create-update`, so a generator that matches nothing (a deleted label, a mistyped selector) cannot delete an Application or anything it deployed. A per-ApplicationSet `applicationsSync` is ignored unless the controller allows policy overrides, so `applicationsetcontroller.enable.policy.override: true` is set in ArgoCD's values in both places ArgoCD is installed from: `bootstrap.sh`'s install and the self-managed `argocd` Application. That lands, and is verified live, before any ApplicationSet does.

**Migrating a running cluster** is the risky part, and the first thing the ladder tests:

1. Remove `resources-finalizer` from the three Applications that carry it, in Git and on the live objects, before the conversion lands. Pruning the old Application then orphans its resources instead of deleting them.
2. Hand the EnvironmentConfig over in two steps, because while it is still in Git, `layer4-fundamentals` self-heals it back. Before the change lands, the live object is annotated `argocd.argoproj.io/sync-options: Prune=false`; ArgoCD reads that from the live object when pruning, and its apply does not remove an annotation it never set. The change then removes the manifest from Git, and ArgoCD leaves the object in place. Only after that sync does `identity.sh apply` strip ArgoCD's tracking metadata and the annotation and write the identity's values. Run earlier, while the object is still tracked, `identity.sh apply` only adds the annotation.
3. The conversion lands; the parent prunes each old Application and creates the ApplicationSet; the ApplicationSet creates an Application of the same name, which adopts the orphaned resources through the same tracking name.

Whether the ApplicationSet adopts an existing same-named Application or waits for the prune is checked on a lab cluster, not assumed.

### Decision 5 (settled 2026-11-10): one stable Git address; graduation repoints it

Committed repoURLs name one in-cluster address that never changes: `http://git.gitops.svc.cluster.local:3000/siliconsaga/<repo>.git` (vendor mirrors under `siliconsaga-vendor`). The Service `git` in namespace `gitops` is an `ExternalName` Service:

- created by `bootstrap.sh`, pointing at `gitea-http.gitea.svc.cluster.local`;
- repointed by `graduate.sh` at `forgejo-http.forgejo.svc.cluster.local`, and back for a rollback;
- cluster-local, never synced by ArgoCD, so no `selfHeal` fights a repoint.

Both servers listen on 3000 and both serve the same org and repository names: the seed creates the `siliconsaga` and `siliconsaga-vendor` orgs instead of using `nordri-admin`'s namespace, and the seed's realm repository holds the whole realm repo (realm root-app `path: cluster`), as Forgejo's mirror does.

This replaces the record's URL train, the `seed`/`forgejo`/`swap` modes, and the swap commit: the train becomes one literal rename of the 18 URLs, and `lib/patch-urls.sh` is deleted with the other patch libraries.

**Both servers during the transition.** The seed keeps running behind its own `gitea-http` Service and HTTPRoute while Forgejo comes up beside it. Either is reachable directly or by port-forward; only the `git` Service decides which one ArgoCD reads.

**How the seed is finally dropped.** After the repoint, the seed lingers unreferenced as the rollback target: at least three days, and on a `prod` cluster until the record's retirement gates pass, which include the Postgres and Velero restore drills that Phase 4 delivers. An idle seed costs little, so a prod cluster keeps it through Phase 4. `graduate.sh --retire-seed` then re-checks every gate, uninstalls the Gitea release and deletes the `gitea` namespace. The seed's HTTPRoute moves out of nordri's overlays into bootstrap's seed install, in the `gitea` namespace, so it leaves with the namespace and no Git change is needed. A fresh bootstrap still installs a seed; that is by design.

## Phase 3a — generic Git

Delivered as one coordinated change across nordri, nidavellir, mimir and the realm, climbing the ladder before it merges.

### 3a-1. nordri

- `identity/defaults-{homelab,gke}.yaml` and `identity.sh` (`apply`, `show`, `diff`), with unit tests in the plain-bash suite covering layering, the lab default, the cluster-name guard and the projection.
- `bootstrap.sh <realm> <cluster>`: writes the identity first, creates the seed's orgs, the `git` Service and the in-cluster Secret, then hydrates and applies the root Applications. The org, Service and root-Application steps live in a library function (`lib/gitops.sh`) that is idempotent, so `migrate.sh` (3a-5) reuses it on a running cluster instead of duplicating it. The `gke|homelab` argument goes; the kube-context guard reads the environment from the identity.
- `update-embedded-git.sh <realm>` pushes working trees verbatim. Its target is whichever server the `git` Service points at: the seed, on any cluster that has not graduated; the cluster's Forgejo on a graduated `test` cluster; refused on a graduated `prod` cluster, whose Forgejo only its puller writes.
- Deleted: `lib/patch-velero.sh`, `lib/patch-urls.sh`, the overlay `sed`, the `envs/` copy, and nidavellir's and mimir's patch callers in `lib/hydrate.sh`. `lib/patch-nidavellir.sh` and `lib/patch-mimir.sh` go with them.
- `app-of-apps` and `velero-gke` become ApplicationSets; the identity manifests leave the overlays; nordri's five URLs are renamed.
- `docs/cluster-identity.md` rewritten for the cluster-local model.

### 3a-2. nidavellir

- vegvisir and tailscale-operator become ApplicationSets; their finalizers come off first (Decision 4, step 1).
- The ntfy composition derives its hostnames from the identity.
- The Forgejo composition reads `role` and `sourceRef`: on `role: test` it renders no puller CronJob, and the configure Job reconciles branch protection to the role, creating none and removing any rule left from an earlier `prod` role; otherwise the puller fetches `sourceRef` from GitHub and writes Forgejo's `main` (for `live`, the newest complete promotion tag set, 3b-2), and records what it wrote in `forgejo-puller-state`. The claim's `org` becomes the `orgs` list (Decision 2), with the vendor class.
- Render tests gain fixtures for `role: test` and `sourceRef: live`.
- Its ten URLs renamed, the keycloak-operator vendor pin to `siliconsaga-vendor`.

### 3a-3. mimir

- `shared-clusters` becomes an ApplicationSet (no finalizer to remove).
- Its three URLs renamed.

### 3a-4. realm

- `clusters/` with one file per declared cluster: `homelab-prod`, `homelab-test`, `gke-prod`, and `homelab-nano76win11` for today's Docker Desktop cluster (`role: test`, `maturity: durable`, since it runs Forgejo). When it is recycled into a generic lab its file is deleted and it takes the lab defaults.
- The Forgejo claim moves the vendor mirror to `siliconsaga-vendor`.
- `ecosystem.yaml`'s `defaults.gitea.internalUrl` becomes `defaults.git.internalUrl` with the stable address.

### 3a-5. Migration and gates

An existing cluster migrates with nordri `migrate.sh <realm> <cluster>`, safe to re-run, in this order:

1. Check that ArgoCD allows ApplicationSet policy overrides (Decision 4); stop if not.
2. `identity.sh apply`: writes the ConfigMap and the cluster Secret's labels, and marks the still-tracked EnvironmentConfig `Prune=false`.
3. Remove `resources-finalizer` from the three Applications that carry it.
4. `lib/gitops.sh`: create the seed's `siliconsaga` and `siliconsaga-vendor` orgs and the `git` Service if missing.
5. Hydrate the change into the seed's new orgs.
6. Re-apply both bootstrap-owned root Applications, which Git never updates: nordri's root with the stable address, and the realm root with the stable address and `path: cluster`. Then hard-refresh every Application and wait for them to sync.
7. `identity.sh apply` again, which now takes over the untracked EnvironmentConfig.

The old `nordri-admin` repositories stay in the seed, unreferenced, until the seed is retired. Gates before merging:

- A lab cluster bootstrapped from nothing comes up green with no stamping anywhere.
- The Nano76 cluster migrates in place: every Application healthy, no resource deleted and recreated (checked by UID on the Velero, tailscale, vegvisir and shared-cluster resources), Forgejo untouched.
- `grep` finds no `MACHINE`, `__GCP_PROJECT__`, `gitea-http`, `forgejo-http` or `nordri-admin` in any committed manifest.
- nordri's and nidavellir's test suites pass.

## Phase 3b — graduation and promotion

### 3b-1. `homelab-prod`

Bootstrapped on the new server as a declared `prod` cluster, raised to `durable`, and graduated with `graduate.sh`. It is the first cluster to run the whole path, before GKE. The current Nano76 cluster stays a `test` cluster.

### 3b-2. The `live` branch and `promote.sh`

Promotion has to move five repositories as one set, and GitHub cannot push to five repositories atomically. So a promotion is numbered, and the puller only acts on a complete one.

- **What gets promoted is what soaked.** The puller records, per repository, the commit it last wrote to Forgejo's `main` and when it first wrote it, in a ConfigMap `forgejo-puller-state` beside the Forgejo release (the same data 3b-6 scrapes). Forgejo's `main` can move ahead of what ArgoCD has synced, so that record alone is not proof. `promote.sh gke` freezes a candidate set from it on `homelab-prod`, then checks, per repository, that the commit has been on Forgejo for at least the soak window (default 24 hours; `--soak <duration>` changes it for one run) and that every Application reading that repository reports `Synced` at that commit and `Healthy`. Any failure refuses the whole promotion. It shows the log from the last promotion to each commit before pushing.
- **Each promotion is a tag set.** For promotion `n` it pushes, to every repository, the lightweight tag `live-<n>` at that repository's soaked commit, then fast-forwards the `live` branch to the same commit. A repository whose commit did not change still gets the tag.
- **The tag set is the activation boundary.** A puller whose source ref is `live` syncs each repository to the tag of the highest `n` present in all five. A promotion interrupted halfway (a push failure, a lost connection) leaves `n` incomplete, so GKE stays on `n-1` everywhere. Re-running `promote.sh gke` detects the incomplete `n` and finishes it with the same commits; it never reuses `n` for different commits.
- **`promote.sh --init`** is the first promotion, `live-1`, with the same checks on the same frozen set. It also creates the `live` branches. It never reads GitHub's `main`.
- **GitHub protects `live` and `live-*`:** no force pushes, no deletion, and only the owner may push or create them.
- `--to <repo>=<sha>` overrides one repository's commit for a deliberate partial promotion; the tag set is still written to all five. An overridden commit cannot be checked against the soak, so the option also needs `--unsoaked`, and the promotion's log records which repositories skipped the checks. A `ws` verb can wrap the script later.

### 3b-3. `graduate.sh`

In nordri. `graduate.sh <realm> <cluster>`:

- **Preconditions:** maturity is `durable`; Forgejo is healthy; every maintained repository's `main` and every vendor mirror exists on Forgejo; the puller's last run succeeded after the generic-Git change merged (a `test` cluster skips this one); every vendor tag an Application pins resolves on Forgejo.
- **Content check:** for each repository, the tree ArgoCD reads now (seed `HEAD`) is compared with Forgejo's `main`. Any difference is printed; the repoint changes what the cluster runs, so it needs `--accept-diff`.
- **Repoint:** the `git` Service's `externalName` moves to Forgejo, every Application is hard-refreshed, and the script waits for them to sync and report healthy. The repoint time is recorded on the Service as an annotation.
- **Rollback:** `graduate.sh --rollback` points the Service back at the seed. The seed stops receiving changes at the repoint, so by the time of a rollback it can be older than what the cluster runs. Rollback therefore runs the same content check in the other direction (Forgejo's `main` against the seed) and needs `--accept-diff` for any difference. `--refresh-seed` first re-hydrates the seed from Forgejo's current `main`, so a rollback that only needs to leave Forgejo, not undo changes, changes nothing the cluster runs.
- **`--retire-seed`:** refuses before three days after the repoint, and on a `prod` cluster until the record's retirement gates pass (the restore drills are Phase 4's). It re-checks every precondition, then uninstalls the seed. `--force` overrides only the duration. A `test` cluster may retire its seed after the three days, so the command is exercised in Phase 3.

### 3b-4. GKE order of operations

1. Before implementation finishes (owner's ordering): hydrate GKE from current `main` with today's scripts, plus heimdall's XRD.
2. After 3a merges: `migrate.sh realm-siliconsaga gke-prod` (as `bootstrap`). GKE now runs generic Git from its seed.
3. After `homelab-prod` has graduated and soaked: `promote.sh --init`, then set `gke-prod` to `durable` with `sourceRef: live` and apply. Forgejo comes up beside the seed, KMS-unsealed OpenBao, persistent disk, wildcard certificate; the puller fills it from `live`.
4. Soak with both servers running, then `graduate.sh`. The seed stays as the rollback target until Phase 4's restore drills pass, then `--retire-seed`.

### 3b-5. Forgejo health probe

The Heimdall blackbox probe on `https://forgejo.<domain>/api/healthz`, pulled in from Phase 2's out-of-scope list.

### 3b-6. Sync visibility (the owner's request of 2026-11-06)

The puller exposes per-repository state where Prometheus can scrape it. A mid-range alert, ntfy priority 3–4 and not a page: "repository X has not matched its source ref for N runs". A Grafana panel shows the last good pull per repository, whether Forgejo's `main` matches the source ref, how far `live` trails `main`, the vendor mirrors' last sync, which server the `git` Service points at, and identity drift. The probe and alert are Phase 3; the panel may slip to Phase 4 if it grows.

### 3b-7. Recovering a diverged `main`

The three steps from 2026-11-06 become a runbook entry in nidavellir, and the configure Job gains a mode that recreates branch protection, so recovery no longer needs a hand-built Job.

### 3b-8. Soak and gates

The record's gate list stands, with its local-branch line replaced by: one change has climbed the whole ladder (lab, `homelab-test`, `homelab-prod`, `promote.sh gke`, `gke-prod`), and one `graduate.sh --rollback` has been exercised on a test cluster.

## Out of scope

Restore drills and Velero scope (Phase 4, which gains the cross-site backup requirement), `full` maturity (Phase 5), SSH access, preview orgs.

## Later arcs

- **Cluster BOM.** A per-cluster bill of materials: a ref per component in the realm's `clusters/<cluster>.yaml`, with the per-repository parent Applications turned into ApplicationSets so children follow the chosen ref. It would let a durable cluster run a chosen mix of branches, and it is the way in for community members running their own variant of the stack. Decisions 3 and 4 are its foundation; Phase 3 does not need it.

## Settled in review (2026-11-10)

- **Names:** namespace `nordri` for the identity ConfigMap; Service `git` in namespace `gitops`; nordri scripts `identity.sh`, `migrate.sh`, `promote.sh`, `graduate.sh`.
- **Nano76:** declared as a `durable` test cluster until it is recycled into a generic lab.
- **Tailnet device names** come from the cluster name, unique on the one tailnet; recycling removes a cluster's devices first.
- **One implementation plan** covers 3a and 3b, in that order.

## Open for review

1. Whether `lab` and `test` clusters can register their tailnet devices as ephemeral, which would make the recycle step unnecessary.
2. The default soak window for `promote.sh` (24 hours).
