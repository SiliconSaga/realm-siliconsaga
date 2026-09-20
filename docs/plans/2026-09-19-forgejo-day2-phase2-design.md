# Forgejo day-2 — Phase 2 design: the composition, its Jobs, the puller, and ArgoCD watching itself

**Status:** Design, approved in brainstorm 2026-09-19; written as the hand-off to a fresh session. Plan next.
**Date:** 2026-09-19
**Owner:** Rasmus Praestholm
**Parent:** [Forgejo day-2 design](2026-09-07-forgejo-day2-design.md) (design of record; this document settles Phase 2's open questions and does not restate what it decides) · [OpenBao go-live design](2026-09-16-openbao-go-live-design.md) (Phase 1's last third) · [ADR 0004](../adrs/0004-openbao-auto-unseal.md)

## Where Phase 2 starts from

Phase 1 is complete as of 2026-09-17: OpenBao auto-unseals on both environments (KMS on GKE, static key on homelab), takes a daily Raft snapshot to a dedicated bucket, and has Heimdall rules; `maturity: bootstrap` sits on both cluster-identity manifests and nothing reads it yet; `lib/patch-urls.sh` rewrites repoURLs at hydration and is a no-op while manifests carry seed URLs. `nidavellir/forgejo/` holds one file, the unwired `DataService` claim.

Three of the parent design's open questions are answered by facts rather than choices:

- **Chart subcharts (open question 3).** The Forgejo chart at 17.1.7 (Forgejo 15.0.9) depends only on the bitnami `common` library. There is no bundled PostgreSQL or Valkey to switch off; the seed's eight-pod surprise cannot recur. `strategy: Recreate` and a 10Gi `ReadWriteOnce` PVC are the chart defaults, so the composition states them for legibility, not to override anything.
- **Sync wave (open question 1).** The app-of-apps has Mimir at 6, ESO at 9, OpenBao at 10, Keycloak at 12, Harbor at 13. Forgejo takes **11**: after everything it depends on, and ahead of the apps that will one day authenticate through it.
- **Runtime for the Jobs.** Nothing in the stack builds images yet, so the Jobs and the puller run bash on a pinned public image: `alpine/k8s:1.36.4`, verified to carry bash, curl, jq, git 2.55 and kubectl. OpenBao is driven over its HTTP API with Kubernetes auth (no `bao` binary), Forgejo over its REST API. One image to pin; nothing installed at Job start.

## Scope

Phase 2 delivers, validated on the disposable Docker Desktop cluster bumped to `durable`:

1. The Forgejo composition and claim, gated on maturity.
2. The two init Jobs and the puller CronJob, as designed by the parent, with the token and rotation semantics it specifies.
3. The ArgoCD-Unknown alert, pulled forward from Phase 4 as the parent allows, and with it ArgoCD adopting itself under GitOps.

Out of scope: the Heimdall Forgejo probe (Phase 3, when a real hostname exists), the URL PR train and `graduate.sh` (Phase 3), Velero scope and restore drills (Phase 4), SSH access to Forgejo (HTTP only; the puller and the workstation both push over HTTP with tokens), and any change on GKE.

## Decisions

### Placement: nidavellir owns the shape, the realm owns the claim

`nidavellir/forgejo/` gains `xrd.yaml` and `composition.yaml` (kind `XForgejo`, claim `ForgejoInstance`, group `nidavellir.siliconsaga.org`), registered by `apps/forgejo-app.yaml` at sync-wave 11 with `directory.include` limited to the XRD and composition, the Harbor app's shape. The existing `dataservice.yaml` is absorbed into the composition, which renders the `DataService` itself so the namespace, database and release are ordered by one owner.

The claim is realm content, at `realm-siliconsaga/cluster/forgejo/claim.yaml`, delivered by the realm root-app exactly as the Keycloak realm import is. Nidavellir never learns the org name or the repository list. Claim fields, all under `spec.parameters`:

| Field | Value for this realm | Notes |
|---|---|---|
| `chartVersion` | `"17.1.7"` | exact, never a range |
| `org` | `siliconsaga` | Forgejo organisation |
| `repos` | `[{name: nordri, github: SiliconSaga/nordri}, …]` for nordri, nidavellir, mimir, heimdall, realm-siliconsaga | the maintained repositories the puller writes |
| `vendorMirrors` | `[{name: keycloak-k8s-resources, upstream: https://github.com/keycloak/keycloak-k8s-resources.git}]` | Forgejo pull-mirrors with tag sync |
| `breakGlassAdmins` | `[cervator]` | local accounts whose passwords live in OpenBao |
| `pullerSchedule` | omitted | the composition resolves the schedule as cluster-identity `pullerSchedule` if present, else the claim's field, else `0 * * * *`. The claim is realm-owned and hydrated unchanged into every cluster, so a per-cluster cadence can only come from cluster-identity; Phase 2 writes the precedence into the composition but adds the identity field to no manifest yet |
| `storageSize` | `"10Gi"` | the chart default, stated |

The realm's `cluster/` README gains the `forgejo/` entry. The realm's `openbao-seeds` file is **not** used for Forgejo: its credentials are born in the credentials Job (below), which is the parent design's departure from ADR 0001.

### Maturity gate: the composition reads the field, everything else stays unaware

`$identity.maturity` is read once at the top of the template. Anything other than `durable` or `full` renders no resources at all, so the claim can sit on a `bootstrap` cluster indefinitely, and the app-of-apps entry, the XRD and the composition can merge and hydrate everywhere with no effect. A value outside `bootstrap | durable | full` fails the render with a message naming the field, the same posture the Harbor composition takes with `harborRole`. No other component reads `maturity` in Phase 2.

This is why Phase 2 can land on main before any cluster graduates: the code is inert until an identity says otherwise.

**Downgrade is fail-closed.** These are Crossplane-composed resources, so a render that returns nothing while composed resources exist would have Crossplane delete the release, the PVC and the DataService — repository and database data, gone on an identity edit. The template therefore checks `.observed.resources`: if `maturity` is below `durable` and any composed resource is observed, it `fail`s with a message naming the field, and nothing is touched. Teardown requires `parameters.allowTeardown: true` on the claim in the same hydration, which is a deliberate, committed act rather than a side effect of lowering maturity. On GKE the flag is never set.

### What the composition renders at `durable`

- **Namespace** `forgejo`, ahead of everything.
- **DataService** `forgejo` (`engine: postgres`, `placement: shared`, `databaseName: forgejo`), which publishes `forgejo-dataservice` with `host`, `port`, `database`, `username`, `password`, `uri`.
- **ExternalSecrets** from the `openbao-kv` ClusterSecretStore: `forgejo-admin` (`username`, `password`, the chart's `gitea.admin.existingSecret` contract) from `secret/forgejo`, and one `forgejo-admin-<user>` per break-glass admin from `secret/forgejo/admins/<user>`. Until the credentials Job has written those paths they report `SecretSyncedError`, which is the gate, not a failure.
- **The credentials Job** (below), ordered before the release.
- **The Helm Release** from `oci://code.forgejo.org/forgejo-helm/forgejo` (the chart lives under the `forgejo-helm` organisation; `oci://code.forgejo.org/forgejo/forgejo` is the container image and fails a Helm pull — verified with `helm show chart` at 17.1.7) at the claim's version, `fullnameOverride: forgejo` so the Service is `forgejo-http` and the pod names are stable, `strategy: Recreate`, persistence on the cluster default storage class at the claim's size, `gitea.admin.existingSecret: forgejo-admin`, `gitea.config.database` pointing at the shared pgBouncer with `SSL_MODE: require` (the same JDBC-versus-libpq lesson Keycloak recorded: state it), the password reaching the pod through `additionalConfigFromEnvs` as `FORGEJO__DATABASE__PASSWD` from the DataService Secret (the `FORGEJO__` prefix and this exact spelling are the chart README's own external-database example; the chart imports only `FORGEJO__*` variables, so a `GITEA__` name is silently ignored), `ROOT_URL` set to `https://forgejo.<domain>/`, SSH disabled, metrics enabled with no ServiceMonitor yet. The release is ordered after the `forgejo-admin` Secret exists.
- **HTTPRoute** `forgejo.<domain>` on the shared Gateway's `websecure` listener, the OpenBao route's shape.
- **The configure Job** (below), ordered after the release is ready.
- **A ConfigMap `forgejo-repos`** rendered from the claim: one line per maintained repository, `<name> <github-upstream>`, plus the org. This is what the puller reads (open question 2, resolved: **the claim, via a ConfigMap, not a query to Forgejo**). A repository removed from the claim stops being pulled at the next hydration; a query to Forgejo would keep pulling anything that still existed there, which is the wrong direction for a source-of-truth mirror.
- **The puller CronJob** on the claim's schedule.
- **RBAC**, two ServiceAccounts with different blast radii. `forgejo-init` is OpenBao's Kubernetes-auth subject for the credentials Job and also runs the configure Job; its Role allows `get`, `create` and `update` on the one Secret named `forgejo-puller` in its own namespace (`resourceNames`), `update` being what `--rotate puller` needs to rewrite it. `forgejo-puller` runs the puller: no OpenBao role, no Role at all, `automountServiceAccountToken: false`, the token reaching the pod only as a mounted Secret volume. A compromised puller can push to Forgejo `main` as the token allows and nothing more; it cannot reach OpenBao.

### The credentials Job: create-only writes over the HTTP API

Runs as ServiceAccount `forgejo-init`. It logs in to OpenBao at `http://openbao.openbao.svc:8200/v1/auth/kubernetes/login` with role `forgejo-init` and its projected ServiceAccount token, then for the admin path and each break-glass path: reads `secret/metadata/forgejo/...`; if OpenBao answers 404, generates a 32-byte random password and writes `secret/data/forgejo/...` with `options.cas: 0`, so a concurrent or repeated write can never overwrite a value that exists; any other status is an error and the Job fails. It writes `username` alongside `password` so the ExternalSecret can materialise both keys. It never prints a value. A sealed or unreachable OpenBao fails the Job loudly; the composition's ordering means the release does not proceed.

The `forgejo-init` role and its policy are created by nordri's `openbao_configure` in `lib/openbao.sh`, beside `eso-role` and `openbao-backup`: bound to ServiceAccount `forgejo-init` in namespace `forgejo`; policy `create` and `update` on both `secret/data/forgejo` and `secret/data/forgejo/*`, and `read` on both `secret/metadata/forgejo` and `secret/metadata/forgejo/*`. Both forms are needed: the admin credential lives at the root path `secret/forgejo`, whose API paths are exactly `secret/data/forgejo` and `secret/metadata/forgejo`, and a trailing `/*` never matches the path it hangs off. Create-only is enforced by the `cas` option in the write, and the policy's `update` exists only because KV v2's data endpoint requires it for a `cas` write; the Job never sends a write without `cas: 0`. `openbao-configure.sh` on both clusters is how the role reaches the live vaults; Layer 5b does it on a fresh cluster.

### The configure Job: reconcile, and refuse to guess about tokens

Runs after the release is ready, authenticating to Forgejo's API as the admin with the password from the `forgejo-admin` Secret mounted as a file, never an argument. Every step is check-then-act:

1. Org exists; each claimed repository exists, empty, created with `auto_init` so `HEAD` resolves before the first pull. Existing repositories are never modified.
2. The `puller` token, by the parent's three-state rule: `forgejo-puller` Secret present and the token authenticates, keep; neither the Secret nor a token named `puller` on the admin account, mint one with scope `write:repository` and create the Secret; any other combination, stop: log one line naming the state (`PullerTokenInvalid`) and exit with a distinct code. The Job has no RBAC on the XR and writes no status itself; the failed Job leaves its composed `Object` not Ready, so the XR reports not Ready and the ArgoCD Application shows Degraded, which is the surface an operator already watches. Only `--rotate puller` (an env var on a manually created Job from the same template) revokes by name, mints, and rewrites the Secret.
3. `main` branch protection on every maintained repository: pushes and force-pushes allowed only for the admin and the break-glass accounts, required for the puller's force-with-lease and the workstation's branch loop.
4. Each vendor mirror as a Forgejo pull-mirror (`POST /repos/migrate` with `mirror: true`, `service: git`, the claim's upstream, tag sync on, default interval); an existing mirror whose upstream differs from the claim is updated.
5. Each break-glass account exists with the password ESO delivered, admin flag set.

Token scope names are validated against the pinned Forgejo version during the plan, since they were reworked across versions.

### The puller: anonymous fetch, authenticated force-with-lease

A CronJob on the resolved schedule (`0 * * * *` default), image `alpine/k8s:1.36.4`, ServiceAccount `forgejo-puller` (no OpenBao access, no API token mounted; the `forgejo-puller` Secret is a volume). For each line of `forgejo-repos`, in a fresh emptyDir:

1. `git init`, add `github` (`https://github.com/<upstream>.git`) and `forgejo` (`http://forgejo-http.forgejo.svc.cluster.local:3000/<org>/<name>.git`) as remotes.
2. A full, not shallow, `git fetch forgejo main` first, so `refs/remotes/forgejo/main` holds Forgejo's current tip; capture it as `expected` (an empty ref on a freshly `auto_init`ed repository is the one case where the lease is against that initial commit, not nothing).
3. `git fetch github main`.
4. `git push forgejo --force-with-lease=refs/heads/main:<expected> refs/remotes/github/main:refs/heads/main`, the `puller` token supplied through `GIT_ASKPASS`, never in the URL. The lease is what makes a concurrent workstation push (the local-branch loop, or a human) a refused push rather than a silent overwrite; the next run retries against the new tip.

Only `main` is written; branches on Forgejo are untouched. A failure on one repository does not stop the others; the Job's exit status is non-zero if any failed, so a Kubernetes-level alert catches it. No GitHub credential exists anywhere; public repositories and `git fetch` are not API-rate-limited.

Suspension for the local-branch loop is the parent design's `update-embedded-git.sh --target forgejo` work and belongs to Phase 3; Phase 2 only makes the CronJob's `suspend` field the switch that flow will flip.

### ArgoCD watches itself: the Unknown alert, and adopting its own install

Two facts shape this. ArgoCD is installed by bootstrap Layer 3 and nothing manages it afterwards; and its application-controller metrics are off, so `argocd_app_info` does not exist on either cluster today. The alert needs the metric, and the metric flag needs a durable home.

- **Adopt ArgoCD under GitOps** the way Traefik and Crossplane already are: `nordri/platform/fundamentals/apps/argocd.yaml`, an Application of the `argo-cd` chart with the same release name `argocd` in namespace `argo`, values held in Git (`dex.enabled: false`, `server.insecure`, the kustomize build options, and now `controller.metrics.enabled: true`). Bootstrap's Layer 3 `helm upgrade --install` stays as the chicken-and-egg step and mirrors those values, so the adoption is a no-op diff. ArgoCD updating itself from Git is the pattern the author's legacy instance already runs; the chart is designed for it, and a controller roll mid-sync resumes cleanly. This is `bootstrap` maturity, not `durable`: it is the same adopted-release pattern the other Layer 2 installs use.
- **Metrics Service** `argocd-metrics` on port 8082 comes from that flag. Heimdall renders a ServiceMonitor for it (label `release: heimdall-kube-prometheus`, the discovery label the stack uses) and the rule:

  ```
  ArgoCDApplicationUnknown: argocd_app_info{sync_status="Unknown"} == 1, for 5m, severity critical, watched
  ```

  with a description that names the app and says what Unknown means here: nothing has reconciled, and everything else still reports Healthy. This is the blind spot every seed wipe exposed, it needs nothing from Forgejo, and it is the single most valuable rule in the parent design.

### Validation on the disposable homelab

The Docker Desktop cluster is the Phase 2 surface. Its identity bump to `durable` is a local change to `cluster-identity-homelab.yaml` hydrated in (not committed as `durable`; the committed default stays `bootstrap`). The homelab storage decision the parent ties to `durable` stays parked, because this cluster is disposable and nothing on it is being graduated for real.

Proof list, all before Phase 2 is called done:

- [ ] Rendered offline: `tests/render/check-forgejo.sh` shows no resources at `bootstrap` maturity, the full set at `durable`, and a failure on an invalid value.
- [ ] Hydrated at `durable`: XR `Synced` and `Ready`, DataService Ready, both ExternalSecrets `SecretSynced`, credentials Job Complete, release Ready, `https://forgejo.homelab.local` answers `/api/healthz`.
- [ ] Configure Job Complete: org, five repositories, branch protection, the vendor mirror synced with tag `26.6.3` visible, break-glass login works with the password read from OpenBao.
- [ ] Puller: a triggered run brings GitHub `main` for every listed repository, matched by commit; the scheduled run repeats it; a non-existent repository in the list fails that entry and not the run.
- [ ] Pod delete: the repository PVC survives and the clone still matches.
- [ ] Re-hydrating at `bootstrap` without `allowTeardown` is refused: the XR reports the render failure, and every composed resource, the PVC included, is still there.
- [ ] Re-hydrating at `bootstrap` with `allowTeardown: true` on the claim tears everything down on this disposable cluster — the gate works in both directions, but only when told to.
- [ ] ArgoCD adopted: the `argocd` Application `Synced`/`Healthy` with no diff after bootstrap's install; `argocd_app_info` scraped; the rule loads; forcing an Application to `Unknown` (point it at a missing path) fires it within five minutes.
- [ ] `bootstrap.sh homelab realm-siliconsaga` re-run from scratch on the wiped cluster comes up green at `bootstrap` maturity with the Forgejo pieces present and inert.

## Components and files

| Repo | Change |
|---|---|
| nidavellir | `forgejo/xrd.yaml`, `forgejo/composition.yaml` (absorbs `dataservice.yaml`), `forgejo/scripts/{credentials,configure,puller}.sh` embedded into the ConfigMap by the composition, `apps/forgejo-app.yaml` (wave 11), `tests/render/check-forgejo.sh` + `forgejo-xr.yaml` fixtures at both maturities, `docs/forgejo.md` |
| nordri | `lib/openbao.sh` `openbao_configure` adds the `forgejo-init` policy and role; `platform/fundamentals/apps/argocd.yaml` adopting the Layer 3 release; Layer 3 values gain `controller.metrics.enabled=true`; `docs/bootstrap.md` |
| heimdall | ServiceMonitor for `argocd-metrics`; `ArgoCDApplicationUnknown` rule; Overview dashboard unchanged |
| realm | `cluster/forgejo/claim.yaml`, `cluster/kustomization.yaml`, `cluster/README.md`; this design and its plan |

Land order: nordri first (the role and the ArgoCD adoption are inert), then nidavellir and heimdall, then the realm claim. The validation runs on the local cluster after all four.

## For the session that picks this up

1. `ws orient`; read the Loki thalamus `forgejo-day2` arc note dated 2026-09-19, then this document, then the parent design's Forgejo composition, credentials and puller sections (not the whole parent).
2. Write the implementation plan as `2026-09-19-forgejo-day2-phase2-plan.md` in the shape of the OpenBao go-live plan: tasks per repo, the validation list above as the final task. The author does not review plans separately; implement inline and review the CRs.
3. The Docker Desktop cluster on Nano76Win11 is the validation surface and can be wiped on demand. Its OpenBao is fresh under the static seal and holds the realm's OIDC seeds; bootstrap re-runs are idempotent (Helm 4 `--force-conflicts` is in). Raw `kubectl` needs `ws hook-bypass k8s` and follows the current context, which the nordri scripts now refuse to run against the wrong target.
4. Windows quirks that cost time last round: the Write tool saves CRLF (strip before running scripts), Windows `jq -r` emits CRLF, MSYS rewrites `/path` arguments (`MSYS_NO_PATHCONV=1`), `mkdir -m` fails on NTFS, POSIX modes are emulated.
5. Review etiquette: fix and push, no per-thread replies, never resolve threads; rebase, never merge; hand force pushes to the author.

## Open questions left for the plan

- Forgejo 15's token scope names and the branch-protection API field names, checked against the pinned version before the configure script is written.
- The `forgejo-init` policy's exact HCL, verified against a live `cas: 0` write from a pod rather than assumed.
