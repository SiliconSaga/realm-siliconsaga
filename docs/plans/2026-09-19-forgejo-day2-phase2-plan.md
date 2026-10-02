# Forgejo Day-2 Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status (2026-09-30):** written from the [Phase 2 design](2026-09-19-forgejo-day2-phase2-design.md) after checking its two open questions against the Forgejo v15.0 API spec and the live Docker Desktop cluster. The author does not review plans separately; the CRs are the review surface. Plan docs are not maintained past implementation.

**Goal:** Land the Forgejo composition, its two init Jobs and the puller CronJob (inert until a cluster-identity says `durable`), the `forgejo-init` OpenBao role, ArgoCD adopting its own install with controller metrics on, and the `ArgoCDApplicationUnknown` rule — validated end to end on the Docker Desktop cluster bumped to `durable`.

**Architecture:** nidavellir gains `forgejo/` (XRD, composition, scripts shipped as a kustomize-generated ConfigMap, Namespace) registered at sync-wave 11; the realm owns the `ForgejoInstance` claim. The composition reads `maturity` from cluster-identity and renders nothing below `durable`, refusing to render nothing while composed resources exist unless the claim says `allowTeardown: true`. Ordering inside the composition is by observed readiness: Release after the admin Secret and the DataService are Ready, configure Job after the Release, puller after the configure Job. nordri adds the OpenBao role and an ArgoCD Application for the Layer 3 release; heimdall adds a ServiceMonitor for the controller metrics and the rule.

**Tech Stack:** Crossplane 2.x (`function-environment-configs`, `function-go-templating` v0.4.0, `function-auto-ready`), provider-kubernetes v1.2.0 (`readiness.policy: DeriveFromCelQuery`), provider-helm v1.0.0 (OCI chart), forgejo-helm 17.1.7 (Forgejo 15.0.9), OpenBao HTTP API with Kubernetes auth, bash + curl + jq + git + kubectl on `alpine/k8s:1.36.4`, argo-cd chart 10.9.1, kube-prometheus-stack.

## Global Constraints

- Every GDD convention: `ws orient` at session start, `ws checkout <comp> <branch>` for topic branches, `ws commit <comp> <bodyfile>` (terse style: subject plus at most ~50 words), `ws push`, `ws cr <comp> <title> <bodyfile>`. Rebase, never merge; hand force pushes to the author; after fixing bot findings push and stop.
- No credential in argv or a shell variable outside the pod: passwords and tokens rest in 0600 files under a 0700 scratch dir, are handed to curl through `-K` config files or `--data @file`, and are never printed.
- Names are contracts across repos and must match exactly: namespace `forgejo`; ServiceAccounts `forgejo-init` and `forgejo-puller`; OpenBao role and policy `forgejo-init`; KV paths `secret/forgejo` and `secret/forgejo/admins/<user>` with keys `username` and `password`; Secrets `forgejo-admin`, `forgejo-admin-<user>`, `forgejo-puller` (key `token`), `forgejo-dataservice`; ConfigMaps `forgejo-scripts` and `forgejo-repos`; Service `forgejo-http:3000`; Forgejo token name `puller`, scope `write:repository`; ArgoCD metrics Service `argocd-application-controller-metrics` port `http-metrics` (8082), label `app.kubernetes.io/name: argocd-metrics`.
- Chart version `17.1.7` exact in the claim; image `alpine/k8s:1.36.4` exact in the composition; argo-cd chart `10.9.1` exact in both the Layer 3 install and the adopting Application.
- Land order: nordri (Tasks 1–2), then nidavellir (Task 3) and heimdall (Task 4) in parallel, then the realm claim (Task 5). Validation (Task 6) runs on the local cluster from the topic branches, before merge, because `update-embedded-git.sh` hydrates from the local checkouts.
- The committed homelab cluster-identity stays `maturity: bootstrap`. The `durable` bump for validation is a local, uncommitted edit that is hydrated in.

## Facts checked, and what they changed

Checked against `templates/swagger/v1_json.tmpl` on the Forgejo `v15.0/forgejo` branch (828 KB, parsed with jq), the chart's `values.yaml` at 17.1.7 (`helm show values`), the argo-cd 10.9.1 chart (`helm template`), and the local cluster's CRDs.

| Question | Answer | Consequence |
|---|---|---|
| Token scopes (Forgejo 15) | `POST /users/{username}/tokens` body `{name, scopes}`; scopes are `read:`/`write:` × `activitypub, admin, issue, misc, notification, organization, package, repository, user`, plus `all`. Basic auth only. `DELETE /users/{username}/tokens/{token}` accepts the token **name** when no id matches. `sha1` in the create response is the token, returned once. | As designed: `write:repository`, revoke by name. |
| Branch protection fields | `CreateBranchProtectionOption`: `rule_name` (`branch_name` deprecated), `enable_push`, `enable_push_whitelist`, `push_whitelist_usernames`, `push_whitelist_teams`, `push_whitelist_deploy_keys`, `enable_merge_whitelist`, …. **There is no force-push allowlist in Forgejo 15** (no `enable_force_push*` or `force_push_allowlist*` fields; zero matches in the spec). A protected branch rejects non-fast-forward pushes from everyone. `EditBranchProtectionOption` has the same fields minus `rule_name`. | Two changes from the design. (a) Maintained repositories are created **empty, not `auto_init`**: replacing an initial commit with GitHub's history would be a force push, which protection rejects. The puller's lease against an absent ref is `--force-with-lease=refs/heads/main:` (empty expectation = "must not exist"), so the first push creates `main`. (b) The puller's normal runs are fast-forwards; a genuine divergence (a Phase 3 hydration pushing an orphan snapshot to Forgejo `main`) will be **rejected** by protection and reported as a failed run. Phase 3's resume flow must handle that (drop and recreate the rule around the pull, or push a fast-forwardable state). Recorded here so Phase 3 does not rediscover it. |
| Pull-mirror upstream | `POST /repos/migrate` `{clone_addr, repo_name, repo_owner, mirror: true, service: "git", mirror_interval, private, wiki, issues, pull_requests, releases, labels, milestones, lfs}`. Nothing in the API changes a pull mirror's clone address afterwards; `EditRepoOption` only has `mirror_interval`. `Repository` exposes `mirror` and `original_url`. `POST /repos/{owner}/{repo}/mirror-sync` triggers a sync. | A vendor mirror whose `original_url` differs from the claim is **deleted and re-migrated** (a mirror is derived data, nothing is lost). If `original_url` is empty for a `service: git` migration, drift cannot be detected and the Job says so; Task 6 records what the field holds on 15.0.9. |
| `/api/healthz` | Not in the v1 spec (it is served outside `/api/v1`). | The configure Job polls it and treats anything but 200 as not ready; Task 6 confirms it answers unauthenticated. |
| Users | `POST /admin/users` requires `username`, `email`; has `password`, `must_change_password`, `send_notify`, `visibility`. `PATCH /admin/users/{username}` (`EditUserOption`) has `admin`; nothing required. | Break-glass accounts get `<user>@forgejo.<domain>` as the mandatory email. |
| Chart 17.1.7 values | `strategy.type: Recreate` default; `persistence.claimName` default `gitea-shared-storage`, `size 10Gi`, annotation `helm.sh/resource-policy: keep`; `gitea.admin.existingSecret` (keys `username`, `password`), `gitea.admin.email`, `passwordMode: keepUpdated`; `gitea.metrics.enabled` and `gitea.metrics.serviceMonitor.enabled`; `gitea.additionalConfigFromEnvs`; `gitea.config.<section>.<KEY>`; no database or cache subcharts. | The PVC is named `forgejo-data`; with the chart's default `keep` policy it **survives a teardown** and is deleted by hand — safer than the design's "everything", and stated in the runbook. |
| DataService Secret | The operator names the role after `databaseName` (`keycloak` → user `keycloak`) and publishes `host`, `port`, `database`, `username`, `password`, `uri` to `<name>-dataservice`. | USER and PASSWD reach Forgejo from the Secret through `FORGEJO__DATABASE__USER` / `FORGEJO__DATABASE__PASSWD`; HOST is the shared pgBouncer, stated. |
| provider-kubernetes readiness | v1.2.0 supports `SuccessfulCreate`, `DeriveFromObject`, `AllTrue`, `DeriveFromCelQuery` (`celQuery`, the object as `object`). | Jobs use `DeriveFromCelQuery` on `status.succeeded`; DataService, ExternalSecrets and the Release use `DeriveFromObject` (their `Ready` condition). A failed Job leaves its Object not Ready, so the XR is not Ready, as designed. |
| ArgoCD controller metrics | Chart 10.9.1 with `controller.metrics.enabled: true` renders Service `argocd-application-controller-metrics` in `argo`, labels `app.kubernetes.io/name: argocd-metrics`, `app.kubernetes.io/component: application-controller`, port `http-metrics` 8082. The live Layer 3 release is argo-cd 10.9.1 with values `dex.enabled=false`, `server.insecure=true`, `server.extraArgs=[--insecure]`, `configs.cm.kustomize.buildOptions`. Layer 3 does not pin the chart version. | The design's `argocd-metrics` is the label, not the Service name. Layer 3 gains `--version 10.9.1` so a fresh bootstrap and the adopting Application agree. |
| Realm root-app | Destination namespace `argo` with `CreateNamespace=true`; it creates no other namespace. | The `forgejo` Namespace ships in nidavellir's `forgejo/` directory (it did already, inside `dataservice.yaml`), not in the composition, so the claim has a namespace to live in at `bootstrap` maturity. |
| Scripts delivery | `function-go-templating` cannot read files; inlining three scripts in the template duplicates them and needs a hand-bumped cache-buster (the Harbor pattern). | `forgejo/kustomization.yaml` generates ConfigMap `forgejo-scripts` from `forgejo/scripts/*.sh` (`disableNameSuffixHash: true`), which also ships at `bootstrap` maturity, inert. Job re-runs on script change are driven by a `jobGeneration` constant in the composition, bumped with the scripts. |
| Rotation | The Phase 2 design specifies `--rotate puller` only. | `ROTATE=puller` is implemented; `admins` rotation is a documented manual procedure (regenerate in OpenBao, let ESO refresh, re-run the Job) and a follow-up. |

---

### Task 1: `forgejo-init` policy and role (nordri)

**Files:**
- Modify: `lib/openbao.sh` (`openbao_configure`, after the `openbao-backup` role)
- Create: `tests/unit/openbao-configure-test.sh`
- Modify: `docs/bootstrap.md` (Layer 5b paragraph)

**Interfaces:**
- Consumes: `openbao_run_with_token` from `lib/openbao.sh`.
- Produces: OpenBao policy `forgejo-init` and Kubernetes-auth role `forgejo-init` bound to ServiceAccount `forgejo-init` in namespace `forgejo`, reachable on a live vault through `openbao-configure.sh <target> [realm]` and on a fresh cluster through bootstrap Layer 5b. The credentials Job (Task 3) logs in with role `forgejo-init`.

- [ ] **Step 1: Write the failing test.** Create `tests/unit/openbao-configure-test.sh`: a kubectl stub answers `bao secrets list` with a KV v2 mount, `bao auth list` with kubernetes enabled, `bao kv metadata get secret/demo` with present, records every `policy write`/`write auth/kubernetes/role` snippet with its stdin, and the test asserts the forgejo-init policy body and role binding.

```bash
#!/usr/bin/env bash
# Unit test for lib/openbao.sh openbao_configure: with a kubectl stub standing
# in for the pod, assert the policies and roles it writes — in particular the
# forgejo-init policy (create-only KV writes under secret/forgejo) and the role
# bound to ServiceAccount forgejo-init in namespace forgejo (realm Forgejo
# day-2 Phase 2 design).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"

fails=0
check() { if eval "$2"; then echo "ok - $1"; else echo "NOT OK - $1"; fails=$((fails+1)); fi; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/calls"
export STUB_CALLS="$work/calls"

cat > "$work/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
if [[ "$1 $2" == "get secret" ]]; then
    case "$*" in *jsonpath*) printf '%s' "stub-root" | base64 ;; esac
    exit 0
fi
if [[ "$1" == "exec" ]]; then
    # Drop the token line the lib prepends; keep the payload for assertions.
    IFS= read -r _token
    payload=$(cat)
    case "$*" in
        *"bao secrets list"*) printf '{"secret/":{"type":"kv","options":{"version":"2"}}}\n'; exit 0 ;;
        *"bao auth list"*) printf '{"kubernetes/":{"type":"kubernetes"}}\n'; exit 0 ;;
        *"bao kv metadata get secret/demo"*) exit 0 ;;
        *"bao policy write "*)
            name=$(printf '%s\n' "$*" | sed -n 's/.*bao policy write \([^ ]*\) .*/\1/p')
            printf '%s\n' "$payload" > "$STUB_CALLS/policy-$name"; exit 0 ;;
        *"bao write auth/kubernetes/role/"*)
            name=$(printf '%s\n' "$*" | sed -n 's|.*auth/kubernetes/role/\([^ ]*\) .*|\1|p')
            printf '%s\n' "$*" > "$STUB_CALLS/role-$name"; exit 0 ;;
        *"bao write auth/kubernetes/config"*) exit 0 ;;
    esac
fi
echo "unexpected kubectl $*" >&2; exit 97
STUB
chmod +x "$work/bin/kubectl"
export PATH="$work/bin:$PATH"

# shellcheck source=../../lib/openbao.sh
source "$root/lib/openbao.sh"
openbao_configure >/dev/null; rc=$?
check "openbao_configure succeeds against the stub" "[ $rc -eq 0 ]"

p="$STUB_CALLS/policy-forgejo-init"
check "forgejo-init policy is written" "[ -f '$p' ]"
check "policy: create-only on secret/data/forgejo (the root path)" "grep -Fq 'path \"secret/data/forgejo\" { capabilities = [\"create\"] }' '$p'"
check "policy: create-only on secret/data/forgejo/*" "grep -Fq 'path \"secret/data/forgejo/*\" { capabilities = [\"create\"] }' '$p'"
check "policy: read on secret/metadata/forgejo" "grep -Fq 'path \"secret/metadata/forgejo\" { capabilities = [\"read\"] }' '$p'"
check "policy: read on secret/metadata/forgejo/*" "grep -Fq 'path \"secret/metadata/forgejo/*\" { capabilities = [\"read\"] }' '$p'"
check "policy grants nothing else (4 path stanzas)" "[ \"\$(grep -c '^path ' '$p')\" -eq 4 ]"

r="$STUB_CALLS/role-forgejo-init"
check "forgejo-init role is written" "[ -f '$r' ]"
check "role binds ServiceAccount forgejo-init" "grep -Fq 'bound_service_account_names=forgejo-init' '$r'"
check "role binds namespace forgejo" "grep -Fq 'bound_service_account_namespaces=forgejo' '$r'"
check "role carries policy forgejo-init only" "grep -Fq 'policies=forgejo-init ' '$r'"

# The pre-existing roles are still written — this test guards against a
# refactor dropping one.
check "eso-role still written" "[ -f '$STUB_CALLS/role-eso-role' ]"
check "openbao-backup role still written" "[ -f '$STUB_CALLS/role-openbao-backup' ]"

[ "$fails" -eq 0 ] && echo "openbao-configure-test: PASS"
exit "$fails"
```

- [ ] **Step 2: Run it to see it fail.** `ws exec nordri bash tests/unit/openbao-configure-test.sh` → `NOT OK - forgejo-init policy is written` and the four policy checks; exit non-zero.

- [ ] **Step 3: Add the policy and role.** In `lib/openbao.sh`, inside `openbao_configure`, after the `openbao-backup` role write and before `secret/demo canary`:

```bash
    # Forgejo's credentials Job (nidavellir forgejo/composition.yaml, realm
    # Forgejo day-2 Phase 2 design) mints the admin and break-glass passwords
    # in-cluster and writes them here create-only: every write carries
    # options.cas=0, and the policy grants `create` alone. Verified live
    # (2026-10-01): KV v2 authorizes a write to an absent path as `create`
    # and to an existing one as `update`, so `create` is all a cas=0 write
    # to a new path needs — and without `update` even a plain overwrite is
    # refused with 403, whereas with it the overwrite went through. Both the
    # bare path and the /* form are needed — the admin credential lives at
    # secret/forgejo itself, and a trailing /* never matches the path it
    # hangs off.
    echo "   • forgejo-init policy and role (Forgejo's credentials Job)"
    openbao_run_with_token 'bao policy write forgejo-init - >/dev/null' <<'EOF' || return 1
path "secret/data/forgejo" { capabilities = ["create"] }
path "secret/data/forgejo/*" { capabilities = ["create"] }
path "secret/metadata/forgejo" { capabilities = ["read"] }
path "secret/metadata/forgejo/*" { capabilities = ["read"] }
EOF
    openbao_run_with_token 'bao write auth/kubernetes/role/forgejo-init bound_service_account_names=forgejo-init bound_service_account_namespaces=forgejo policies=forgejo-init ttl=1h >/dev/null' </dev/null || return 1
```

  Also extend the function's header comment (the sentence listing what `openbao_configure` does) with "the forgejo-init policy and role Forgejo's credentials Job writes with".

- [ ] **Step 4: Run the test and the suite.** `ws exec nordri bash tests/unit/openbao-configure-test.sh` → `openbao-configure-test: PASS`. Then `ws test nordri` → `✅ nordri: syntax clean + all unit tests pass`.

- [ ] **Step 5: Docs.** In `docs/bootstrap.md`, the Layer 5b paragraph (line ~103) lists what `openbao_configure` creates; add the `forgejo-init` role: "and the `forgejo-init` policy and role (create-only writes under `secret/forgejo`, for Forgejo's credentials Job; nidavellir `docs/forgejo.md`)".

- [ ] **Step 6: Commit.** Branch `feat/forgejo-init-role` (from main). Bodyfile `.commits/nordri-forgejo-init-role.md`, `message: "feat(openbao): forgejo-init policy and role for Forgejo's create-only credentials Job"`, `add:` the three files. `ws commit nordri .commits/nordri-forgejo-init-role.md`.

### Task 2: ArgoCD adopts its own install, with controller metrics (nordri)

**Files:**
- Create: `platform/fundamentals/apps/argocd.yaml`
- Modify: `platform/fundamentals/overlays/homelab/kustomization.yaml`, `platform/fundamentals/overlays/gke/kustomization.yaml` (shared apps list)
- Modify: `bootstrap.sh` (Layer 3, lines ~661–668)
- Modify: `tests/e2e/shared/argocd/00-assert.yaml`
- Modify: `docs/bootstrap.md` (Layer 3 and the Layer 4 table)

**Interfaces:**
- Produces: Application `argocd` in `argo`, chart `argo-cd` 10.9.1, release name `argocd`, values identical to Layer 3 plus `controller.metrics.enabled: true`; Service `argocd-application-controller-metrics` (port `http-metrics`) that Task 4's ServiceMonitor scrapes.

- [ ] **Step 1: The Application.** `platform/fundamentals/apps/argocd.yaml`:

```yaml
# ArgoCD managing its own Layer 3 install (realm Forgejo day-2 Phase 2 design).
#
# bootstrap.sh Layer 3 `helm upgrade --install`s this exact chart version with
# these exact values (the chicken-and-egg step; keep the two in step), then
# this Application adopts the release the way traefik.yaml and crossplane.yaml
# adopt theirs: the first sync is a no-op diff, and from then on ArgoCD
# updates itself from Git. The chart is designed for that; a controller roll
# mid-sync resumes cleanly. This is bootstrap maturity, not durable.
#
# controller.metrics.enabled is the reason this exists now: it renders Service
# argocd-application-controller-metrics (port http-metrics, 8082), which
# Heimdall scrapes for argocd_app_info — the series behind
# ArgoCDApplicationUnknown, the alert every seed wipe was missing.
#
# No resources-finalizer on purpose: deleting this Application must not
# cascade-delete ArgoCD itself, which could never finish the job.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "-4"
spec:
  project: default
  source:
    repoURL: 'https://argoproj.github.io/argo-helm'
    chart: argo-cd
    # Pinned. bootstrap.sh Layer 3 installs the same version (ARGOCD_CHART_VERSION).
    targetRevision: 10.9.1
    helm:
      releaseName: argocd
      values: |
        dex:
          enabled: false
        server:
          insecure: true
          extraArgs:
            - --insecure
        configs:
          cm:
            kustomize.buildOptions: --load-restrictor LoadRestrictionsNone --enable-helm
        controller:
          metrics:
            enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      # The Application CRD exceeds the last-applied annotation limit.
      - ServerSideApply=true
```

- [ ] **Step 2: Both overlays.** In `overlays/homelab/kustomization.yaml` and `overlays/gke/kustomization.yaml`, under `# Shared Apps` after `- ../../apps/crossplane.yaml`, add `- ../../apps/argocd.yaml`.

- [ ] **Step 3: Layer 3 pins the version and turns metrics on.** In `bootstrap.sh`, above the `helm upgrade --install argocd` line add `ARGOCD_CHART_VERSION="10.9.1"   # keep in step with platform/fundamentals/apps/argocd.yaml, which adopts this release`, and change the install to:

```bash
helm upgrade --install argocd argo/argo-cd --namespace argo --version "$ARGOCD_CHART_VERSION" "${HELM_APPLY_FLAGS[@]}" \
  --set dex.enabled=false \
  --set server.insecure=true \
  --set server.extraArgs={--insecure} \
  --set controller.metrics.enabled=true \
  --set configs.cm."kustomize\.buildOptions"="--load-restrictor LoadRestrictionsNone --enable-helm"
```

- [ ] **Step 4: e2e assert.** Append to `tests/e2e/shared/argocd/00-assert.yaml`:

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: argo
status:
  health:
    status: Healthy
  sync:
    status: Synced
---
apiVersion: v1
kind: Service
metadata:
  name: argocd-application-controller-metrics
  namespace: argo
spec:
  ports:
    - name: http-metrics
      port: 8082
```

- [ ] **Step 5: Docs.** `docs/bootstrap.md` Layer 3: "Installs **ArgoCD** via Helm (`argo` namespace, chart pinned to `ARGOCD_CHART_VERSION`, controller metrics on); Layer 4 then adopts the release under `platform/fundamentals/apps/argocd.yaml`, so ArgoCD updates itself from Git." Layer 4 table: add a row `| ArgoCD (adopted by ArgoCD) | ✅ | ✅ |`.

- [ ] **Step 6: Check and commit.** `ws test nordri` passes (`bash -n` covers bootstrap.sh). `kubectl kustomize platform/fundamentals/overlays/homelab` from the nordri root renders the `argocd` Application (run via `ws exec nordri kubectl kustomize platform/fundamentals/overlays/homelab`). Same branch as Task 1. Bodyfile `.commits/nordri-argocd-adopt.md`, `message: "feat(argocd): ArgoCD adopts its own Layer 3 release, with controller metrics on"`, body: "Chart pinned to 10.9.1 in both places. The metrics Service feeds Heimdall's ArgoCDApplicationUnknown rule." Commit, `ws push nordri`, `ws cr nordri "feat: forgejo-init OpenBao role and ArgoCD self-adoption (Forgejo Phase 2, nordri half)" .crs/nordri-forgejo-phase2.md` from `templates/change.md`.

### Task 3: The Forgejo composition, Jobs and puller (nidavellir)

**Files:**
- Delete: `forgejo/dataservice.yaml` (absorbed)
- Create: `forgejo/namespace.yaml`, `forgejo/kustomization.yaml`, `forgejo/xrd.yaml`, `forgejo/composition.yaml`, `forgejo/scripts/credentials.sh`, `forgejo/scripts/configure.sh`, `forgejo/scripts/puller.sh`, `forgejo/scripts/askpass.sh`
- Create: `apps/forgejo-app.yaml`; modify `apps/kustomization.yaml`
- Create: `tests/render/check-forgejo.sh`, `tests/render/forgejo-xr.yaml`, `tests/render/forgejo-xr-teardown.yaml`, `tests/render/cluster-identity-homelab-durable.yaml`, `tests/render/cluster-identity-homelab-bad-maturity.yaml`, `tests/render/forgejo-observed.yaml`
- Create: `docs/forgejo.md`; modify `docs/README.md`, `docs/platform-gitea.md` (pointer), `README.md` line 21

**Interfaces:**
- Consumes: OpenBao role `forgejo-init` (Task 1); ClusterSecretStore `openbao-kv`; DataService CRD; cluster-identity `maturity`, `domain`, `storageClass`, optional `pullerSchedule`.
- Produces: XRD `xforgejos.nidavellir.siliconsaga.org` with claim kind `ForgejoInstance` (Task 5 writes one); Service `forgejo-http` in `forgejo`; HTTPRoute `forgejo.<domain>`; CronJob `forgejo-puller`.

- [ ] **Step 1: Namespace and app wiring.** `forgejo/namespace.yaml` keeps the Namespace that `dataservice.yaml` carried (same labels, `argocd.argoproj.io/sync-wave: "-1"`, header comment: "Declared here rather than by the composition because the claim needs a namespace to live in at bootstrap maturity, before the composition renders anything"). Delete `forgejo/dataservice.yaml`. `forgejo/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
# The Forgejo platform component (realm Forgejo day-2 design, Phase 2). ArgoCD
# builds this directory with kustomize (apps/forgejo-app.yaml). Everything here
# is inert on a cluster whose identity says maturity: bootstrap — the
# composition renders nothing until durable — but it all merges and hydrates
# everywhere so a graduation is an identity edit, not a code change.
resources:
  - namespace.yaml
  - xrd.yaml
  - composition.yaml
configMapGenerator:
  # The Jobs and the puller run these. Shipped as a ConfigMap rather than
  # inlined in the composition so they stay one copy, lintable and testable.
  # Stable name: the composition mounts it by name. A script change is a
  # jobGeneration bump in composition.yaml (see there).
  - name: forgejo-scripts
    namespace: forgejo
    files:
      - scripts/credentials.sh
      - scripts/configure.sh
      - scripts/puller.sh
      - scripts/askpass.sh
generatorOptions:
  disableNameSuffixHash: true
```

  `apps/forgejo-app.yaml`:

```yaml
# ArgoCD Application for Forgejo — the durable-tier git platform (realm Forgejo
# day-2 design of record, 2026-09-07; Phase 2 design 2026-09-19).
#
# Deploys the XForgejo XRD + composition, the forgejo Namespace and the
# forgejo-scripts ConfigMap from nidavellir's forgejo/ (kustomize). The
# ForgejoInstance CLAIM is realm content (realm-siliconsaga cluster/forgejo/),
# delivered by the realm root-app: nidavellir never learns the org name or the
# repository list.
#
# Gated on cluster-identity maturity: at bootstrap the composition renders
# nothing, so this app is Synced/Healthy with a Namespace and a ConfigMap and
# no Forgejo. At durable it renders the DataService, the credentials Job, the
# Helm release, the configure Job and the puller, in that order.
#
# Sync-wave 11: after Mimir (6), ESO (9) and OpenBao (10) — everything it
# depends on — and before Keycloak (12) and Harbor (13), which will one day
# authenticate through it.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: forgejo
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "11"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: 'http://gitea-http.gitea.svc.cluster.local:3000/nordri-admin/nidavellir.git'
    targetRevision: HEAD
    path: forgejo
  destination:
    server: https://kubernetes.default.svc
    namespace: forgejo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - SkipDryRunOnMissingResource=true
      - ServerSideApply=true
```

  In `apps/kustomization.yaml` add `- forgejo-app.yaml` after `keycloak-app.yaml`, and replace the stale "GitHub stays the push-mirror target" paragraph with: "The destination is FORGEJO (realm Forgejo day-2 design): GitHub owns `main` and review, an in-cluster puller writes Forgejo `main`, and repoURLs move to Forgejo in Phase 3."

- [ ] **Step 2: The XRD.** `forgejo/xrd.yaml`:

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xforgejos.nidavellir.siliconsaga.org
spec:
  group: nidavellir.siliconsaga.org
  names:
    kind: XForgejo
    plural: xforgejos
  claimNames:
    kind: ForgejoInstance
    plural: forgejoinstances
  defaultCompositionRef:
    name: xforgejo-durable
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          description: "Singleton per cluster: the composition pins namespace forgejo and the workload/Service names (fullnameOverride forgejo, Service forgejo-http). Renders nothing unless cluster-identity maturity is durable or full. The claim is realm content; nidavellir supplies no org or repository names."
          properties:
            spec:
              type: object
              properties:
                parameters:
                  type: object
                  required: [org]
                  properties:
                    chartVersion:
                      type: string
                      default: "17.1.7"
                      description: "forgejo-helm chart version, exact (17.1.7 = Forgejo 15.0.9). The chart bundles no database or cache; Postgres comes from the Mimir DataService."
                    org:
                      type: string
                      description: "The Forgejo organisation the maintained repositories and vendor mirrors live in."
                    repos:
                      type: array
                      description: "Maintained repositories: created empty in the org, main written only by the puller from the GitHub upstream (owner/repo)."
                      items:
                        type: object
                        required: [name, github]
                        properties:
                          name: {type: string}
                          github: {type: string, description: "GitHub owner/repo, fetched anonymously."}
                    vendorMirrors:
                      type: array
                      description: "Forgejo pull-mirrors of third-party repositories, tags included; read-only by nature."
                      items:
                        type: object
                        required: [name, upstream]
                        properties:
                          name: {type: string}
                          upstream: {type: string, description: "Clone URL."}
                    breakGlassAdmins:
                      type: array
                      description: "Local admin accounts whose passwords are born in OpenBao at secret/forgejo/admins/<user>."
                      items: {type: string}
                    adminUsername:
                      type: string
                      default: forgejo-admin
                      description: "The chart's admin account, whose password is born in OpenBao at secret/forgejo and whose token the puller pushes with."
                    pullerSchedule:
                      type: string
                      description: "Cron schedule for the puller. Precedence: cluster-identity pullerSchedule, then this field, then hourly (0 * * * *). A per-cluster cadence can only come from cluster-identity since the claim is hydrated unchanged everywhere."
                    storageSize:
                      type: string
                      default: "10Gi"
                      description: "Repository PVC size (the chart default, stated)."
                    domain:
                      type: string
                      description: "Override the cluster-identity domain for the ingress host. When unset, the HTTPRoute host is forgejo.<cluster-identity domain>."
                    allowTeardown:
                      type: boolean
                      default: false
                      description: "Lowering cluster-identity maturity below durable while Forgejo resources exist is refused (it would delete the release, the PVC and the database). Set true, in the same hydration, to tear down deliberately. Never on GKE."
      additionalPrinterColumns:
      - name: READY
        type: string
        jsonPath: .status.conditions[?(@.type=='Ready')].status
      - name: SYNCED
        type: string
        jsonPath: .status.conditions[?(@.type=='Synced')].status
```

- [ ] **Step 3: The scripts.** Write the four files below (LF line endings — strip CR if the editor added any: `sed -i 's/\r$//' forgejo/scripts/*.sh`). `bash -n` each.

  `forgejo/scripts/credentials.sh`:

```bash
#!/usr/bin/env bash
# credentials.sh — mint Forgejo's admin and break-glass passwords in OpenBao,
# create-only, over the HTTP API with Kubernetes auth. Runs once per claim
# generation as ServiceAccount forgejo-init (composition.yaml, credentials-job).
#
# For every path: read secret/metadata/<path>; 404 means absent, so generate a
# password and write secret/data/<path> with options.cas: 0, which OpenBao
# refuses if any version exists — a retry, or a concurrent writer, can never
# overwrite a value. Any other status is an error and the Job fails. A sealed
# or unreachable OpenBao fails before any write, loudly.
#
# Values rest only in 0600 files under a 0700 scratch dir; nothing is printed.
set -euo pipefail
: "${OPENBAO_ADDR:=http://openbao.openbao.svc:8200}"
: "${OPENBAO_ROLE:=forgejo-init}"
: "${ADMIN_USERNAME:=forgejo-admin}"
: "${BREAK_GLASS_ADMINS:=}"
: "${SA_TOKEN_FILE:=/var/run/secrets/kubernetes.io/serviceaccount/token}"

umask 077
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

health=$(curl -sS -o /dev/null -w '%{http_code}' "$OPENBAO_ADDR/v1/sys/health" || true)
case "$health" in
  200|429|472|473) ;;
  503) echo "OpenBao is SEALED ($OPENBAO_ADDR/v1/sys/health -> 503); refusing to continue." >&2; exit 2 ;;
  501) echo "OpenBao is not initialized (501); refusing to continue." >&2; exit 2 ;;
  *) echo "OpenBao unreachable or unhealthy (sys/health -> ${health:-no response})." >&2; exit 2 ;;
esac

jq -n --rawfile jwt "$SA_TOKEN_FILE" --arg role "$OPENBAO_ROLE" \
  '{role: $role, jwt: ($jwt | rtrimstr("\n"))}' > "$work/login.json"
if ! curl -fsS -X POST --data @"$work/login.json" "$OPENBAO_ADDR/v1/auth/kubernetes/login" > "$work/login-resp.json"; then
  echo "OpenBao Kubernetes-auth login as role $OPENBAO_ROLE failed — is the role configured (nordri openbao-configure.sh)?" >&2
  exit 2
fi
jq -r '"header = \"X-Vault-Token: " + .auth.client_token + "\""' "$work/login-resp.json" > "$work/curl.cfg"
rm -f "$work/login.json" "$work/login-resp.json"

ensure() { # $1 = KV path below secret/, $2 = username stored beside the password
  local path="$1" user="$2" code
  code=$(curl -sS -o /dev/null -w '%{http_code}' -K "$work/curl.cfg" "$OPENBAO_ADDR/v1/secret/metadata/$path")
  case "$code" in
    200) echo "present: secret/$path"; return 0 ;;
    404) ;;
    *) echo "reading secret/metadata/$path returned HTTP $code" >&2; return 1 ;;
  esac
  head -c 64 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32 > "$work/pw"
  [ "$(wc -c < "$work/pw")" -eq 32 ] || { echo "password generation for secret/$path came up short" >&2; return 1; }
  jq -n --rawfile pw "$work/pw" --arg u "$user" \
    '{options: {cas: 0}, data: {username: $u, password: $pw}}' > "$work/put.json"
  code=$(curl -sS -o "$work/put-resp.json" -w '%{http_code}' -K "$work/curl.cfg" \
    -X POST --data @"$work/put.json" "$OPENBAO_ADDR/v1/secret/data/$path")
  rm -f "$work/pw" "$work/put.json"
  case "$code" in
    200) echo "created: secret/$path" ;;
    400)
      if grep -q "check-and-set" "$work/put-resp.json"; then
        echo "created meanwhile by another writer: secret/$path"
      else
        echo "writing secret/$path returned HTTP 400: $(cat "$work/put-resp.json")" >&2; return 1
      fi ;;
    *) echo "writing secret/$path returned HTTP $code: $(cat "$work/put-resp.json")" >&2; return 1 ;;
  esac
}

ensure forgejo "$ADMIN_USERNAME"
for u in $BREAK_GLASS_ADMINS; do
  ensure "forgejo/admins/$u" "$u"
done
echo "forgejo credentials: done"
```

  `forgejo/scripts/configure.sh`:

```bash
#!/usr/bin/env bash
# configure.sh — reconcile Forgejo's org, repositories, puller token, branch
# protection, vendor mirrors and break-glass accounts from the claim. Runs after
# the release is ready, as ServiceAccount forgejo-init, authenticating to the
# REST API as the admin with the password ESO delivered (a mounted file, never
# an argument). Every step is check-then-act; existing maintained repositories
# are never modified. Exit codes: 0 done, 1 an API or tooling failure, 3 the
# puller token is in a state this Job refuses to repair (PullerTokenInvalid).
#
# ROTATE=puller revokes the Forgejo token named "puller", mints a replacement
# and rewrites Secret forgejo-puller. Run it as a one-off Job (docs/forgejo.md).
#
# Forgejo 15 has no force-push allowlist: a protected branch rejects
# non-fast-forward pushes from everyone. Repositories are therefore created
# EMPTY (no auto_init), so the puller's first push creates main instead of
# replacing an initial commit.
set -uo pipefail
: "${FORGEJO_URL:=http://forgejo-http.forgejo.svc.cluster.local:3000}"
: "${ORG:?set ORG}"
: "${ADMIN_USERNAME:=forgejo-admin}"
: "${ADMIN_PASSWORD_FILE:=/etc/forgejo-admin/password}"
: "${ADMINS_DIR:=/etc/forgejo-admins}"
: "${BREAK_GLASS_ADMINS:=}"
: "${EMAIL_DOMAIN:?set EMAIL_DOMAIN}"
: "${REPOS_FILE:=/etc/forgejo/repos}"
: "${MIRRORS_FILE:=/etc/forgejo/mirrors}"
: "${NAMESPACE:=forgejo}"
: "${PULLER_SECRET:=forgejo-puller}"
: "${PULLER_TOKEN_NAME:=puller}"
: "${ROTATE:=}"

umask 077
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
RESP="$work/resp"
AUTH_CFG="$work/auth.cfg"
printf 'user = "%s:%s"\n' "$ADMIN_USERNAME" "$(cat "$ADMIN_PASSWORD_FILE")" > "$AUTH_CFG"
fails=0

api() { # api <method> </v1 path> [curl args]  -> prints the HTTP status; body lands in $RESP
  local method="$1" path="$2"; shift 2
  curl -sS -o "$RESP" -w '%{http_code}' -K "$AUTH_CFG" -H 'Content-Type: application/json' \
    -X "$method" "$@" "$FORGEJO_URL/api/v1$path"
}
body() { cat "$RESP" 2>/dev/null | head -c 400; }

echo "waiting for $FORGEJO_URL/api/healthz"
code=""
for _ in $(seq 1 60); do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "$FORGEJO_URL/api/healthz" || true)
  [ "$code" = 200 ] && break
  sleep 5
done
[ "$code" = 200 ] || { echo "Forgejo did not answer /api/healthz with 200 within 5 minutes (last: ${code:-none})" >&2; exit 1; }

# ── 1. organisation ────────────────────────────────────────────────────────
code=$(api GET "/orgs/$ORG")
case "$code" in
  200) echo "org $ORG: present" ;;
  404)
    jq -n --arg u "$ORG" '{username: $u, visibility: "public"}' > "$work/body.json"
    code=$(api POST /orgs --data @"$work/body.json")
    [ "$code" = 201 ] && echo "org $ORG: created" || { echo "creating org $ORG: HTTP $code $(body)" >&2; exit 1; } ;;
  *) echo "GET /orgs/$ORG: HTTP $code $(body)" >&2; exit 1 ;;
esac

# ── 2. maintained repositories, created empty ──────────────────────────────
while read -r name upstream; do
  [ -z "$name" ] && continue
  code=$(api GET "/repos/$ORG/$name")
  case "$code" in
    200) echo "repo $ORG/$name: present" ;;
    404)
      jq -n --arg n "$name" --arg d "main is written by the puller from https://github.com/$upstream" \
        '{name: $n, description: $d, private: false, auto_init: false, default_branch: "main"}' > "$work/body.json"
      code=$(api POST "/orgs/$ORG/repos" --data @"$work/body.json")
      [ "$code" = 201 ] && echo "repo $ORG/$name: created (empty)" || { echo "creating $ORG/$name: HTTP $code $(body)" >&2; fails=$((fails+1)); } ;;
    *) echo "GET /repos/$ORG/$name: HTTP $code $(body)" >&2; fails=$((fails+1)) ;;
  esac
done < "$REPOS_FILE"

# ── 3. the puller token: keep, mint, or refuse ─────────────────────────────
token_cfg="$work/token.cfg"
secret_present=false
if kubectl get secret -n "$NAMESPACE" "$PULLER_SECRET" >/dev/null 2>&1; then
  secret_present=true
  kubectl get secret -n "$NAMESPACE" "$PULLER_SECRET" -o jsonpath='{.data.token}' | base64 -d > "$work/token"
  printf 'header = "Authorization: token %s"\n' "$(cat "$work/token")" > "$token_cfg"
fi
token_valid=false
if $secret_present; then
  code=$(curl -sS -o "$RESP" -w '%{http_code}' -K "$token_cfg" "$FORGEJO_URL/api/v1/user")
  [ "$code" = 200 ] && token_valid=true
fi
code=$(api GET "/users/$ADMIN_USERNAME/tokens")
[ "$code" = 200 ] || { echo "listing $ADMIN_USERNAME's tokens: HTTP $code $(body)" >&2; exit 1; }
named_present=$(jq --arg n "$PULLER_TOKEN_NAME" '[.[] | select(.name == $n)] | length > 0' "$RESP")

mint_puller() {
  jq -n --arg n "$PULLER_TOKEN_NAME" '{name: $n, scopes: ["write:repository"]}' > "$work/body.json"
  code=$(api POST "/users/$ADMIN_USERNAME/tokens" --data @"$work/body.json")
  [ "$code" = 201 ] || { echo "minting token $PULLER_TOKEN_NAME: HTTP $code $(body)" >&2; return 1; }
  jq -r '.sha1' "$RESP" | tr -d '\n' > "$work/token"
  rm -f "$RESP"
  [ -s "$work/token" ] || { echo "token response carried no sha1" >&2; return 1; }
  kubectl create secret generic "$PULLER_SECRET" -n "$NAMESPACE" --from-file=token="$work/token" \
    --dry-run=client -o yaml > "$work/secret.yaml"
  if $secret_present; then kubectl replace -f "$work/secret.yaml" >/dev/null; else kubectl create -f "$work/secret.yaml" >/dev/null; fi
}

case "$ROTATE:$secret_present:$token_valid:$named_present" in
  puller:*)
    code=$(api DELETE "/users/$ADMIN_USERNAME/tokens/$PULLER_TOKEN_NAME")
    case "$code" in 204|404) ;; *) echo "revoking token $PULLER_TOKEN_NAME: HTTP $code $(body)" >&2; exit 1 ;; esac
    mint_puller || exit 1
    echo "puller token: rotated" ;;
  :true:true:true) echo "puller token: present and valid" ;;
  :false:false:false) mint_puller || exit 1; echo "puller token: minted" ;;
  *)
    echo "PullerTokenInvalid: Secret $NAMESPACE/$PULLER_SECRET present=$secret_present valid=$token_valid; Forgejo token '$PULLER_TOKEN_NAME' on $ADMIN_USERNAME present=$named_present. A token's value cannot be read back, so this Job will not mint another on its own: run it with ROTATE=puller (docs/forgejo.md)." >&2
    exit 3 ;;
esac

# ── 4. main branch protection on every maintained repository ───────────────
# Pushes allowed for the admin (the puller's token is the admin's) and the
# break-glass accounts only. Forgejo 15 protects against force pushes for
# everyone; there is no allowlist for that (see header).
printf '%s\n' "$ADMIN_USERNAME" $BREAK_GLASS_ADMINS | jq -R . | jq -sc . > "$work/allow.json"
jq -n --slurpfile users "$work/allow.json" '{
  enable_push: true, enable_push_whitelist: true, push_whitelist_usernames: $users[0],
  push_whitelist_teams: [], push_whitelist_deploy_keys: false,
  enable_merge_whitelist: false, enable_status_check: false, required_approvals: 0,
  block_on_rejected_reviews: false, block_on_outdated_branch: false,
  dismiss_stale_approvals: false, require_signed_commits: false}' > "$work/edit.json"
jq '. + {rule_name: "main"}' "$work/edit.json" > "$work/create.json"
while read -r name _; do
  [ -z "$name" ] && continue
  code=$(api GET "/repos/$ORG/$name/branch_protections/main")
  case "$code" in
    200)
      code=$(api PATCH "/repos/$ORG/$name/branch_protections/main" --data @"$work/edit.json")
      [ "$code" = 200 ] && echo "protection $ORG/$name main: reconciled" || { echo "PATCH protection $ORG/$name: HTTP $code $(body)" >&2; fails=$((fails+1)); } ;;
    404)
      code=$(api POST "/repos/$ORG/$name/branch_protections" --data @"$work/create.json")
      [ "$code" = 201 ] && echo "protection $ORG/$name main: created" || { echo "POST protection $ORG/$name: HTTP $code $(body)" >&2; fails=$((fails+1)); } ;;
    *) echo "GET protection $ORG/$name: HTTP $code $(body)" >&2; fails=$((fails+1)) ;;
  esac
done < "$REPOS_FILE"

# ── 5. vendor mirrors: Forgejo pull-mirrors, tags included ─────────────────
# The API cannot change a pull mirror's upstream after creation, so a mirror
# whose original_url differs from the claim is deleted and re-migrated. A
# mirror is derived data; nothing of ours lives in it.
create_mirror() { # $1 = name, $2 = upstream
  jq -n --arg n "$1" --arg u "$2" --arg o "$ORG" '{
    clone_addr: $u, repo_name: $n, repo_owner: $o, mirror: true, service: "git",
    private: false, wiki: false, issues: false, pull_requests: false, releases: true,
    labels: false, milestones: false, lfs: false, description: ("Pull mirror of " + $u)}' > "$work/body.json"
  code=$(api POST /repos/migrate --data @"$work/body.json")
  [ "$code" = 201 ] && echo "mirror $ORG/$1: created from $2" || { echo "migrating $2 as $ORG/$1: HTTP $code $(body)" >&2; return 1; }
}
while read -r name upstream; do
  [ -z "$name" ] && continue
  code=$(api GET "/repos/$ORG/$name")
  case "$code" in
    200)
      is_mirror=$(jq -r '.mirror' "$RESP"); orig=$(jq -r '.original_url // ""' "$RESP")
      if [ "$is_mirror" = true ] && [ -z "$orig" ]; then
        echo "mirror $ORG/$name: present (original_url empty; upstream drift is not detectable on this version)"
      elif [ "$is_mirror" = true ] && [ "$orig" = "$upstream" ]; then
        echo "mirror $ORG/$name: present ($orig)"
      else
        echo "mirror $ORG/$name: mirror=$is_mirror upstream=${orig:-?}, claim says $upstream — recreating"
        code=$(api DELETE "/repos/$ORG/$name")
        [ "$code" = 204 ] || { echo "deleting $ORG/$name: HTTP $code $(body)" >&2; fails=$((fails+1)); continue; }
        create_mirror "$name" "$upstream" || fails=$((fails+1))
      fi ;;
    404) create_mirror "$name" "$upstream" || fails=$((fails+1)) ;;
    *) echo "GET /repos/$ORG/$name: HTTP $code $(body)" >&2; fails=$((fails+1)) ;;
  esac
done < "$MIRRORS_FILE"

# ── 6. break-glass admins, with the passwords ESO delivered ────────────────
for u in $BREAK_GLASS_ADMINS; do
  pwfile="$ADMINS_DIR/$u/password"
  [ -s "$pwfile" ] || { echo "no password mounted for break-glass admin $u at $pwfile (ExternalSecret forgejo-admin-$u not synced?)" >&2; fails=$((fails+1)); continue; }
  code=$(api GET "/users/$u")
  case "$code" in
    200) echo "user $u: present" ;;
    404)
      jq -n --arg u "$u" --arg e "$u@$EMAIL_DOMAIN" --rawfile p "$pwfile" '{
        username: $u, email: $e, password: ($p | rtrimstr("\n")),
        must_change_password: false, send_notify: false, visibility: "private"}' > "$work/body.json"
      code=$(api POST /admin/users --data @"$work/body.json")
      rm -f "$work/body.json"
      [ "$code" = 201 ] && echo "user $u: created" || { echo "creating user $u: HTTP $code $(body)" >&2; fails=$((fails+1)); continue; } ;;
    *) echo "GET /users/$u: HTTP $code $(body)" >&2; fails=$((fails+1)); continue ;;
  esac
  jq -n '{admin: true, must_change_password: false}' > "$work/body.json"
  code=$(api PATCH "/admin/users/$u" --data @"$work/body.json")
  [ "$code" = 200 ] && echo "user $u: admin" || { echo "PATCH /admin/users/$u: HTTP $code $(body)" >&2; fails=$((fails+1)); }
done

[ "$fails" -eq 0 ] || { echo "forgejo configure: $fails step(s) failed" >&2; exit 1; }
echo "forgejo configure: done"
```

  `forgejo/scripts/puller.sh`:

```bash
#!/usr/bin/env bash
# puller.sh — bring GitHub main to Forgejo main for every maintained repository:
# an anonymous fetch from GitHub, an authenticated push to Forgejo with
# --force-with-lease against the tip Forgejo had when this run started (an
# empty expectation when the branch does not exist yet, i.e. "must not exist").
# Only main is written; branches on Forgejo are untouched. One repository
# failing does not stop the others; the exit status is non-zero if any failed,
# which kube-prometheus-stack's KubeJobFailed reports.
#
# Runs as ServiceAccount forgejo-puller: no API token mounted, no OpenBao role.
# The Forgejo token reaches git through GIT_ASKPASS from a mounted Secret and
# never appears in a URL or an argument list. No GitHub credential exists.
set -uo pipefail
: "${FORGEJO_URL:=http://forgejo-http.forgejo.svc.cluster.local:3000}"
: "${ORG:?set ORG}"
: "${PULLER_USERNAME:?set PULLER_USERNAME}"
: "${PULLER_TOKEN_FILE:=/etc/forgejo-puller/token}"
: "${REPOS_FILE:=/etc/forgejo/repos}"
: "${ASKPASS:=/scripts/askpass.sh}"
export GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0 PULLER_USERNAME PULLER_TOKEN_FILE
[ -s "$PULLER_TOKEN_FILE" ] || { echo "no token at $PULLER_TOKEN_FILE" >&2; exit 1; }

fails=0; total=0
while read -r name upstream; do
  [ -z "$name" ] && continue
  total=$((total+1))
  work=$(mktemp -d)
  if (
    set -e
    cd "$work"
    git init -q -b main .
    git remote add github "https://github.com/$upstream.git"
    git remote add forgejo "$FORGEJO_URL/$ORG/$name.git"
    expected=""
    if git fetch -q forgejo main 2>/dev/null; then
      expected=$(git rev-parse -q --verify refs/remotes/forgejo/main)
    fi
    git fetch -q github main
    incoming=$(git rev-parse -q --verify refs/remotes/github/main)
    if [ "$incoming" = "$expected" ]; then
      echo "$name: up to date at ${incoming:0:12}"
      exit 0
    fi
    git push -q forgejo "--force-with-lease=refs/heads/main:$expected" refs/remotes/github/main:refs/heads/main
    echo "$name: ${expected:-<absent>} -> ${incoming:0:12}"
  ); then :; else
    echo "$name: FAILED" >&2
    fails=$((fails+1))
  fi
  rm -rf "$work"
done < "$REPOS_FILE"
echo "puller: $((total-fails))/$total repositories in sync"
[ "$fails" -eq 0 ]
```

  `forgejo/scripts/askpass.sh`:

```bash
#!/usr/bin/env bash
# GIT_ASKPASS helper for puller.sh: git asks "Username for '<url>': " then
# "Password for '<url>': ". The token is read from a file so it is never an
# argument to anything.
case "$1" in
  Username*) printf '%s\n' "$PULLER_USERNAME" ;;
  Password*) cat "$PULLER_TOKEN_FILE" ;;
  *) exit 1 ;;
esac
```

- [ ] **Step 4: The composition.** `forgejo/composition.yaml`. Steps: `load-cluster-identity` (copy of the openbao one), `render-forgejo` (one template, every resource), `auto-ready`.

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: xforgejo-durable
  labels:
    provider: forgejo
spec:
  mode: Pipeline
  compositeTypeRef:
    apiVersion: nidavellir.siliconsaga.org/v1alpha1
    kind: XForgejo
  pipeline:

  # ──────────────────────────────────────────────────────────
  # Step 0: cluster identity → context (environment, domain,
  # storageClass, maturity, optional pullerSchedule).
  # ──────────────────────────────────────────────────────────
  - step: load-cluster-identity
    functionRef:
      name: function-environment-configs
    input:
      apiVersion: environmentconfigs.fn.crossplane.io/v1beta1
      kind: Input
      spec:
        environmentConfigs:
        - type: Reference
          ref:
            name: cluster-identity

  # ──────────────────────────────────────────────────────────
  # Step 1: everything, gated on maturity (realm Forgejo day-2
  # design, Phase 2). Below durable the template renders NOTHING,
  # so the claim can sit on a bootstrap cluster indefinitely. A
  # render that returns nothing while composed resources exist
  # would have Crossplane delete the release, the PVC and the
  # database, so that case fails unless the claim says
  # allowTeardown: true.
  #
  # Ordering is by observed readiness, not sync-waves: the Release
  # is emitted once the admin Secret and the DataService are Ready,
  # the configure Job once the Release is Ready, the puller once the
  # configure Job succeeded. Jobs report Ready through a CEL query
  # on status.succeeded, so a failed Job holds the XR not-Ready.
  #
  # Scripts come from ConfigMap forgejo-scripts (kustomization.yaml).
  # jobGeneration is the manual cache-buster: Jobs are immutable and
  # named by a hash of their inputs, so bump it whenever a script's
  # logic changes, or the old Job keeps its name and never re-runs.
  # ──────────────────────────────────────────────────────────
  - step: render-forgejo
    functionRef:
      name: function-go-templating
    input:
      apiVersion: gotemplating.fn.crossplane.io/v1beta1
      kind: GoTemplate
      source: Inline
      inline:
        template: |
          {{- $identity := index .context "apiextensions.crossplane.io/environment" -}}
          {{- $xr := .observed.composite.resource -}}
          {{- $p := $xr.spec.parameters -}}
          {{- $name := $xr.metadata.name -}}
          {{- $observed := .observed.resources | default dict -}}
          {{- $maturity := $identity.maturity | default "bootstrap" -}}
          {{- if not (has $maturity (list "bootstrap" "durable" "full")) -}}
          {{ fail (printf "cluster-identity maturity %q is not one of bootstrap, durable, full" $maturity) }}
          {{- end -}}
          {{- if not (has $maturity (list "durable" "full")) -}}
          {{- if and (gt (len $observed) 0) (not $p.allowTeardown) -}}
          {{ fail (printf "cluster-identity maturity is %q but %d Forgejo resources are composed; rendering nothing would delete the release, its PVC and the database. Set parameters.allowTeardown: true on the claim to tear down on purpose." $maturity (len $observed)) }}
          {{- end -}}
          {{- else -}}
          {{- if not $p.org -}}{{ fail "parameters.org is required" }}{{- end -}}
          {{- $org := $p.org -}}
          {{- $domain := $p.domain | default $identity.domain -}}
          {{- $storageClass := $identity.storageClass -}}
          {{- $version := $p.chartVersion | default "17.1.7" -}}
          {{- $size := $p.storageSize | default "10Gi" -}}
          {{- $admin := $p.adminUsername | default "forgejo-admin" -}}
          {{- $repos := $p.repos | default list -}}
          {{- $mirrors := $p.vendorMirrors | default list -}}
          {{- $admins := $p.breakGlassAdmins | default list -}}
          {{- $schedule := $identity.pullerSchedule | default ($p.pullerSchedule | default "0 * * * *") -}}
          {{- $ns := "forgejo" -}}
          {{- $image := "alpine/k8s:1.36.4" -}}
          {{- $jobGeneration := "2026-09-30" -}}
          {{- $reposLines := "" -}}
          {{- range $repos -}}{{- $reposLines = printf "%s%s %s\n" $reposLines .name .github -}}{{- end -}}
          {{- $mirrorLines := "" -}}
          {{- range $mirrors -}}{{- $mirrorLines = printf "%s%s %s\n" $mirrorLines .name .upstream -}}{{- end -}}
          {{- $jobSuffix := (printf "%s|%s|%s|%s|%s|%s" $org $admin (join "," $admins) $reposLines $mirrorLines $jobGeneration) | sha256sum | trunc 8 -}}
          {{- /* Ready map: composition-resource-name → its Object/Release Ready condition. */ -}}
          {{- $ready := dict -}}
          {{- range $k, $v := $observed -}}
          {{- $ok := false -}}
          {{- range (dig "status" "conditions" (list) $v.resource) -}}
          {{- if and (eq .type "Ready") (eq .status "True") -}}{{- $ok = true -}}{{- end -}}
          {{- end -}}
          {{- $_ := set $ready $k $ok -}}
          {{- end -}}
          {{- $dbReady := eq (get $ready "dataservice" | toString) "true" -}}
          {{- $adminReady := eq (get $ready "externalsecret-admin" | toString) "true" -}}
          {{- $releaseReady := eq (get $ready "release" | toString) "true" -}}
          {{- $configureReady := eq (get $ready "configure-job" | toString) "true" -}}
          ---
          apiVersion: kubernetes.crossplane.io/v1alpha2
          kind: Object
          metadata:
            name: {{ $name }}-dataservice
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: dataservice
          spec:
            readiness:
              policy: DeriveFromObject
            forProvider:
              manifest:
                apiVersion: mimir.siliconsaga.org/v1alpha1
                kind: DataService
                metadata:
                  name: forgejo
                  namespace: {{ $ns }}
                spec:
                  engine: postgres
                  placement: shared
                  databaseName: forgejo
          ---
          apiVersion: kubernetes.crossplane.io/v1alpha2
          kind: Object
          metadata:
            name: {{ $name }}-sa-init
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: sa-init
          spec:
            forProvider:
              manifest:
                apiVersion: v1
                kind: ServiceAccount
                metadata:
                  name: forgejo-init
                  namespace: {{ $ns }}
          ---
          apiVersion: kubernetes.crossplane.io/v1alpha2
          kind: Object
          metadata:
            name: {{ $name }}-sa-puller
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: sa-puller
          spec:
            forProvider:
              manifest:
                apiVersion: v1
                kind: ServiceAccount
                metadata:
                  name: forgejo-puller
                  namespace: {{ $ns }}
                automountServiceAccountToken: false
          ---
          apiVersion: kubernetes.crossplane.io/v1alpha2
          kind: Object
          metadata:
            name: {{ $name }}-role-init
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: role-init
          spec:
            forProvider:
              manifest:
                apiVersion: rbac.authorization.k8s.io/v1
                kind: Role
                metadata:
                  name: forgejo-init
                  namespace: {{ $ns }}
                rules:
                  # create cannot be name-restricted (the name is unknown at
                  # authorization time); get/update are pinned to the one Secret.
                  - apiGroups: [""]
                    resources: [secrets]
                    verbs: [create]
                  - apiGroups: [""]
                    resources: [secrets]
                    resourceNames: [forgejo-puller]
                    verbs: [get, update]
          ---
          apiVersion: kubernetes.crossplane.io/v1alpha2
          kind: Object
          metadata:
            name: {{ $name }}-rolebinding-init
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: rolebinding-init
          spec:
            forProvider:
              manifest:
                apiVersion: rbac.authorization.k8s.io/v1
                kind: RoleBinding
                metadata:
                  name: forgejo-init
                  namespace: {{ $ns }}
                roleRef:
                  apiGroup: rbac.authorization.k8s.io
                  kind: Role
                  name: forgejo-init
                subjects:
                  - kind: ServiceAccount
                    name: forgejo-init
                    namespace: {{ $ns }}
          ---
          apiVersion: kubernetes.crossplane.io/v1alpha2
          kind: Object
          metadata:
            name: {{ $name }}-repos
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: repos-configmap
          spec:
            forProvider:
              manifest:
                apiVersion: v1
                kind: ConfigMap
                metadata:
                  name: forgejo-repos
                  namespace: {{ $ns }}
                data:
                  # <name> <github owner/repo> — what the puller pulls. Rendered
                  # from the claim, not read from Forgejo: a repository removed
                  # from the claim stops being pulled at the next hydration.
                  repos: |
                    {{- $reposLines | nindent 20 }}
                  # <name> <upstream clone URL> — Forgejo pull-mirrors.
                  mirrors: |
                    {{- $mirrorLines | nindent 20 }}
          ---
          apiVersion: kubernetes.crossplane.io/v1alpha2
          kind: Object
          metadata:
            name: {{ $name }}-externalsecret-admin
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: externalsecret-admin
          spec:
            readiness:
              policy: DeriveFromObject
            forProvider:
              manifest:
                apiVersion: external-secrets.io/v1
                kind: ExternalSecret
                metadata:
                  name: forgejo-admin
                  namespace: {{ $ns }}
                spec:
                  refreshInterval: 1h
                  secretStoreRef:
                    name: openbao-kv
                    kind: ClusterSecretStore
                  target:
                    name: forgejo-admin
                    creationPolicy: Owner
                    deletionPolicy: Retain
                  data:
                    - secretKey: username
                      remoteRef:
                        key: secret/forgejo
                        property: username
                        conversionStrategy: Default
                        decodingStrategy: None
                        metadataPolicy: None
                        nullBytePolicy: Ignore
                    - secretKey: password
                      remoteRef:
                        key: secret/forgejo
                        property: password
                        conversionStrategy: Default
                        decodingStrategy: None
                        metadataPolicy: None
                        nullBytePolicy: Ignore
          {{- range $admins }}
          ---
          apiVersion: kubernetes.crossplane.io/v1alpha2
          kind: Object
          metadata:
            name: {{ $name }}-externalsecret-admin-{{ . }}
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: externalsecret-admin-{{ . }}
          spec:
            readiness:
              policy: DeriveFromObject
            forProvider:
              manifest:
                apiVersion: external-secrets.io/v1
                kind: ExternalSecret
                metadata:
                  name: forgejo-admin-{{ . }}
                  namespace: {{ $ns }}
                spec:
                  refreshInterval: 1h
                  secretStoreRef:
                    name: openbao-kv
                    kind: ClusterSecretStore
                  target:
                    name: forgejo-admin-{{ . }}
                    creationPolicy: Owner
                    deletionPolicy: Retain
                  data:
                    - secretKey: username
                      remoteRef:
                        key: secret/forgejo/admins/{{ . }}
                        property: username
                        conversionStrategy: Default
                        decodingStrategy: None
                        metadataPolicy: None
                        nullBytePolicy: Ignore
                    - secretKey: password
                      remoteRef:
                        key: secret/forgejo/admins/{{ . }}
                        property: password
                        conversionStrategy: Default
                        decodingStrategy: None
                        metadataPolicy: None
                        nullBytePolicy: Ignore
          {{- end }}
          ---
          apiVersion: kubernetes.crossplane.io/v1alpha2
          kind: Object
          metadata:
            name: {{ $name }}-credentials-job
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: credentials-job
          spec:
            readiness:
              policy: DeriveFromCelQuery
              celQuery: has(object.status.succeeded) && object.status.succeeded > 0
            forProvider:
              manifest:
                apiVersion: batch/v1
                kind: Job
                metadata:
                  name: forgejo-credentials-{{ $jobSuffix }}
                  namespace: {{ $ns }}
                spec:
                  backoffLimit: 3
                  template:
                    spec:
                      restartPolicy: Never
                      serviceAccountName: forgejo-init
                      containers:
                        - name: credentials
                          image: {{ $image }}
                          command: ["bash", "/scripts/credentials.sh"]
                          env:
                            - name: OPENBAO_ADDR
                              value: http://openbao.openbao.svc:8200
                            - name: OPENBAO_ROLE
                              value: forgejo-init
                            - name: ADMIN_USERNAME
                              value: {{ $admin | quote }}
                            - name: BREAK_GLASS_ADMINS
                              value: {{ join " " $admins | quote }}
                          resources:
                            requests: {cpu: 25m, memory: 32Mi}
                            limits: {cpu: 250m, memory: 128Mi}
                          volumeMounts:
                            - name: scripts
                              mountPath: /scripts
                      volumes:
                        - name: scripts
                          configMap:
                            name: forgejo-scripts
                            defaultMode: 0555
          {{- if and $dbReady $adminReady }}
          ---
          apiVersion: helm.crossplane.io/v1beta1
          kind: Release
          metadata:
            name: {{ $name }}-release
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: release
          spec:
            forProvider:
              chart:
                name: forgejo
                repository: oci://code.forgejo.org/forgejo-helm
                version: {{ $version | quote }}
              namespace: {{ $ns }}
              wait: true
              values:
                fullnameOverride: forgejo
                replicaCount: 1
                # A PVC-backed single replica cannot roll (the chart default, stated).
                strategy:
                  type: Recreate
                persistence:
                  enabled: true
                  create: true
                  claimName: forgejo-data
                  size: {{ $size }}
                  storageClass: {{ $storageClass }}
                  accessModes: [ReadWriteOnce]
                  # helm.sh/resource-policy: keep stays (chart default): the PVC
                  # survives a teardown and is deleted by hand (docs/forgejo.md).
                service:
                  http:
                    type: ClusterIP
                    port: 3000
                  ssh:
                    type: ClusterIP
                    port: 22
                resources:
                  requests: {cpu: 100m, memory: 256Mi}
                  limits: {cpu: "1", memory: 1Gi}
                gitea:
                  admin:
                    existingSecret: forgejo-admin
                    email: {{ printf "%s@forgejo.%s" $admin $domain | quote }}
                    passwordMode: keepUpdated
                  metrics:
                    enabled: true
                    serviceMonitor:
                      enabled: false
                  # The chart imports only FORGEJO__* variables (README: "external
                  # database"); a GITEA__ name would be silently ignored.
                  additionalConfigFromEnvs:
                    - name: FORGEJO__DATABASE__USER
                      valueFrom:
                        secretKeyRef:
                          name: forgejo-dataservice
                          key: username
                    - name: FORGEJO__DATABASE__PASSWD
                      valueFrom:
                        secretKeyRef:
                          name: forgejo-dataservice
                          key: password
                  config:
                    APP_NAME: {{ printf "Forgejo — %s" $org | quote }}
                    RUN_MODE: prod
                    database:
                      DB_TYPE: postgres
                      # The shared pgBouncer (Mimir DataService, placement: shared).
                      # SSL_MODE stated: the same libpq-versus-JDBC lesson Keycloak
                      # recorded — pgBouncer requires TLS on the client side.
                      HOST: mimir-postgres-pgbouncer.mimir.svc:5432
                      NAME: forgejo
                      SSL_MODE: require
                    server:
                      DOMAIN: forgejo.{{ $domain }}
                      ROOT_URL: https://forgejo.{{ $domain }}/
                      DISABLE_SSH: true
                      START_SSH_SERVER: false
                      OFFLINE_MODE: true
                    service:
                      DISABLE_REGISTRATION: true
                      REQUIRE_SIGNIN_VIEW: false
                    repository:
                      DEFAULT_BRANCH: main
                    metrics:
                      ENABLED: true
                    mirror:
                      ENABLED: true
          {{- end }}
          ---
          apiVersion: kubernetes.crossplane.io/v1alpha2
          kind: Object
          metadata:
            name: {{ $name }}-route
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: route
          spec:
            forProvider:
              manifest:
                apiVersion: gateway.networking.k8s.io/v1
                kind: HTTPRoute
                metadata:
                  name: forgejo
                  namespace: {{ $ns }}
                spec:
                  parentRefs:
                    - name: traefik-gateway
                      namespace: kube-system
                      kind: Gateway
                      sectionName: websecure
                  hostnames:
                    - "forgejo.{{ $domain }}"
                  rules:
                    - matches:
                        - path:
                            type: PathPrefix
                            value: /
                      backendRefs:
                        - name: forgejo-http
                          port: 3000
          {{- if $releaseReady }}
          ---
          apiVersion: kubernetes.crossplane.io/v1alpha2
          kind: Object
          metadata:
            name: {{ $name }}-configure-job
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: configure-job
          spec:
            readiness:
              policy: DeriveFromCelQuery
              celQuery: has(object.status.succeeded) && object.status.succeeded > 0
            forProvider:
              manifest:
                apiVersion: batch/v1
                kind: Job
                metadata:
                  name: forgejo-configure-{{ $jobSuffix }}
                  namespace: {{ $ns }}
                spec:
                  backoffLimit: 2
                  template:
                    spec:
                      restartPolicy: Never
                      serviceAccountName: forgejo-init
                      containers:
                        - name: configure
                          image: {{ $image }}
                          command: ["bash", "/scripts/configure.sh"]
                          env:
                            - name: FORGEJO_URL
                              value: http://forgejo-http.{{ $ns }}.svc.cluster.local:3000
                            - name: ORG
                              value: {{ $org | quote }}
                            - name: ADMIN_USERNAME
                              value: {{ $admin | quote }}
                            - name: BREAK_GLASS_ADMINS
                              value: {{ join " " $admins | quote }}
                            - name: EMAIL_DOMAIN
                              value: forgejo.{{ $domain }}
                            - name: NAMESPACE
                              value: {{ $ns }}
                            - name: PULLER_SECRET
                              value: forgejo-puller
                            - name: ROTATE
                              value: ""
                          resources:
                            requests: {cpu: 25m, memory: 32Mi}
                            limits: {cpu: 250m, memory: 128Mi}
                          volumeMounts:
                            - name: scripts
                              mountPath: /scripts
                            - name: admin
                              mountPath: /etc/forgejo-admin
                              readOnly: true
                            - name: repos
                              mountPath: /etc/forgejo
                              readOnly: true
                            {{- range $admins }}
                            - name: admin-{{ . }}
                              mountPath: /etc/forgejo-admins/{{ . }}
                              readOnly: true
                            {{- end }}
                      volumes:
                        - name: scripts
                          configMap:
                            name: forgejo-scripts
                            defaultMode: 0555
                        - name: admin
                          secret:
                            secretName: forgejo-admin
                        - name: repos
                          configMap:
                            name: forgejo-repos
                        {{- range $admins }}
                        - name: admin-{{ . }}
                          secret:
                            secretName: forgejo-admin-{{ . }}
                        {{- end }}
          {{- end }}
          {{- if $configureReady }}
          ---
          apiVersion: kubernetes.crossplane.io/v1alpha2
          kind: Object
          metadata:
            name: {{ $name }}-puller
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: puller-cronjob
          spec:
            forProvider:
              manifest:
                apiVersion: batch/v1
                kind: CronJob
                metadata:
                  name: forgejo-puller
                  namespace: {{ $ns }}
                spec:
                  schedule: {{ $schedule | quote }}
                  concurrencyPolicy: Forbid
                  # The switch Phase 3's hydration flow flips while it pushes
                  # a working tree to Forgejo main.
                  suspend: false
                  successfulJobsHistoryLimit: 3
                  failedJobsHistoryLimit: 3
                  jobTemplate:
                    spec:
                      backoffLimit: 0
                      template:
                        spec:
                          restartPolicy: Never
                          serviceAccountName: forgejo-puller
                          automountServiceAccountToken: false
                          containers:
                            - name: puller
                              image: {{ $image }}
                              command: ["bash", "/scripts/puller.sh"]
                              env:
                                - name: FORGEJO_URL
                                  value: http://forgejo-http.{{ $ns }}.svc.cluster.local:3000
                                - name: ORG
                                  value: {{ $org | quote }}
                                - name: PULLER_USERNAME
                                  value: {{ $admin | quote }}
                              resources:
                                requests: {cpu: 50m, memory: 64Mi}
                                limits: {cpu: 500m, memory: 512Mi}
                              volumeMounts:
                                - name: scripts
                                  mountPath: /scripts
                                - name: token
                                  mountPath: /etc/forgejo-puller
                                  readOnly: true
                                - name: repos
                                  mountPath: /etc/forgejo
                                  readOnly: true
                                - name: work
                                  mountPath: /tmp
                          volumes:
                            - name: scripts
                              configMap:
                                name: forgejo-scripts
                                defaultMode: 0555
                            - name: token
                              secret:
                                secretName: forgejo-puller
                            - name: repos
                              configMap:
                                name: forgejo-repos
                            - name: work
                              emptyDir: {}
          {{- end }}
          {{- end }}

  # ──────────────────────────────────────────────────────────
  # Step 2: Auto-ready — Ready once every composed resource is.
  # ──────────────────────────────────────────────────────────
  - step: auto-ready
    functionRef:
      name: function-auto-ready
```

- [ ] **Step 5: Render fixtures.** `tests/render/forgejo-xr.yaml` (org `siliconsaga`; repos nordri/nidavellir/mimir/heimdall/realm-siliconsaga under `SiliconSaga/`; vendor mirror `keycloak-k8s-resources` → `https://github.com/keycloak/keycloak-k8s-resources.git`; `breakGlassAdmins: [cervator]`; `storageSize: "10Gi"`), `tests/render/forgejo-xr-teardown.yaml` (the same plus `allowTeardown: true`), `tests/render/cluster-identity-homelab-durable.yaml` (copy of the homelab fixture with `maturity: durable`), `tests/render/cluster-identity-homelab-bad-maturity.yaml` (`maturity: someday`), and `tests/render/forgejo-observed.yaml`, one mocked composed Release:

```yaml
apiVersion: helm.crossplane.io/v1beta1
kind: Release
metadata:
  name: forgejo-release
  annotations:
    crossplane.io/composition-resource-name: release
status:
  conditions:
    - type: Ready
      status: "True"
```

- [ ] **Step 6: The render check.** `tests/render/check-forgejo.sh`, same shape as `check-openbao.sh`:

```bash
#!/usr/bin/env bash
# Offline render check for the Forgejo composition's maturity gate and its
# readiness-driven ordering. Requires Docker and the crossplane CLI. Run from
# the nidavellir repo root: bash tests/render/check-forgejo.sh
set -euo pipefail
command -v crossplane >/dev/null || { echo "crossplane CLI not on PATH" >&2; exit 1; }

render() { # $1=identity-file $2=xr-file [$3=observed-file]
    if [[ -n "${3:-}" ]]; then
        crossplane render "$2" forgejo/composition.yaml tests/render/functions.yaml \
            --extra-resources "tests/render/$1" --observed-resources "$3"
    else
        crossplane render "$2" forgejo/composition.yaml tests/render/functions.yaml \
            --extra-resources "tests/render/$1"
    fi
}
fail=0
check() { # $1=label $2=file $3=want(yes|no) $4=needle
    if grep -Fq -- "$4" "$2"; then found=yes; else found=no; fi
    if [[ "$found" != "$3" ]]; then echo "FAIL [$1]: expected $4 present=$3, got present=$found" >&2; fail=1; fi
}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/forgejo-render.XXXXXX"); trap 'rm -rf "$tmp"' EXIT

# bootstrap: the XR alone, nothing composed.
render cluster-identity-homelab.yaml tests/render/forgejo-xr.yaml > "$tmp/bootstrap"
check bootstrap "$tmp/bootstrap" no 'kind: Object'
check bootstrap "$tmp/bootstrap" no 'kind: Release'

# durable, nothing observed yet: the first wave only.
render cluster-identity-homelab-durable.yaml tests/render/forgejo-xr.yaml > "$tmp/durable"
check durable "$tmp/durable" yes 'kind: DataService'
check durable "$tmp/durable" yes 'name: forgejo-init'
check durable "$tmp/durable" yes 'name: forgejo-puller'
check durable "$tmp/durable" yes 'automountServiceAccountToken: false'
check durable "$tmp/durable" yes 'resourceNames: [forgejo-puller]'
check durable "$tmp/durable" yes 'key: secret/forgejo'
check durable "$tmp/durable" yes 'key: secret/forgejo/admins/cervator'
check durable "$tmp/durable" yes 'name: forgejo-admin-cervator'
check durable "$tmp/durable" yes 'name: forgejo-credentials-'
check durable "$tmp/durable" yes 'celQuery: has(object.status.succeeded) && object.status.succeeded > 0'
check durable "$tmp/durable" yes 'nordri SiliconSaga/nordri'
check durable "$tmp/durable" yes 'keycloak-k8s-resources https://github.com/keycloak/keycloak-k8s-resources.git'
check durable "$tmp/durable" yes 'forgejo.homelab.local'
check durable "$tmp/durable" yes 'image: alpine/k8s:1.36.4'
# Not before the admin Secret and the DataService are Ready:
check durable "$tmp/durable" no  'kind: Release'
check durable "$tmp/durable" no  'name: forgejo-configure-'
check durable "$tmp/durable" no  'kind: CronJob'

# durable with the release observed Ready: the configure Job appears, the puller not yet.
render cluster-identity-homelab-durable.yaml tests/render/forgejo-xr.yaml tests/render/forgejo-observed.yaml > "$tmp/configure"
check configure "$tmp/configure" yes 'name: forgejo-configure-'
check configure "$tmp/configure" yes 'mountPath: /etc/forgejo-admins/cervator'
check configure "$tmp/configure" no  'kind: CronJob'

# invalid maturity fails the render, naming the field.
if render cluster-identity-homelab-bad-maturity.yaml tests/render/forgejo-xr.yaml > "$tmp/bad" 2>&1; then
    echo "FAIL [bad-maturity]: render succeeded" >&2; fail=1
else
    check bad-maturity "$tmp/bad" yes 'maturity "someday" is not one of'
fi

# downgrade with composed resources observed: refused without allowTeardown, empty with it.
if render cluster-identity-homelab.yaml tests/render/forgejo-xr.yaml tests/render/forgejo-observed.yaml > "$tmp/downgrade" 2>&1; then
    echo "FAIL [downgrade]: render succeeded without allowTeardown" >&2; fail=1
else
    check downgrade "$tmp/downgrade" yes 'allowTeardown'
fi
render cluster-identity-homelab.yaml tests/render/forgejo-xr-teardown.yaml tests/render/forgejo-observed.yaml > "$tmp/teardown"
check teardown "$tmp/teardown" no 'kind: Release'
check teardown "$tmp/teardown" no 'kind: Object'

# the scripts ConfigMap builds and carries all four scripts.
kubectl kustomize forgejo > "$tmp/kustomize"
for s in credentials.sh configure.sh puller.sh askpass.sh; do check kustomize "$tmp/kustomize" yes "$s: |"; done
check kustomize "$tmp/kustomize" yes 'name: forgejo-scripts'
for s in forgejo/scripts/*.sh; do bash -n "$s" || { echo "FAIL [syntax]: $s" >&2; fail=1; }; done

[[ $fail -eq 0 ]] && echo "forgejo render checks: PASS"
exit $fail
```

- [ ] **Step 7: Run it.** `ws exec nidavellir bash tests/render/check-forgejo.sh` → `forgejo render checks: PASS`. Fix template errors it surfaces (the first run of a template this size will have some: watch `dig`'s argument order, `nindent` on the repos lines, and the Release only appearing with both readiness flags).

- [ ] **Step 8: Docs.** `docs/forgejo.md` — the runbook: what the app ships at `bootstrap`; what the composition renders at `durable` and in which order; the credential paths and the `forgejo-admin`/`forgejo-admin-<user>` Secrets; how to read a break-glass password (`bao kv get secret/forgejo/admins/<user>` through `openbao_run_with_token`, or `kubectl get secret forgejo-admin-<user>`); the three puller-token states and `PullerTokenInvalid`; **rotating the puller token** (a one-off Job: `kubectl get job -n forgejo -l job-name -o name` to find the current configure Job, `kubectl get job <it> -o yaml`, strip status/uid/selector, set `ROTATE=puller` and a new name, `kubectl create -f`); rotating admin passwords (manual for now: `bao kv put` a new version, wait for ESO, the chart's `keepUpdated` re-applies the admin's; break-glass passwords need a `PATCH /admin/users` by hand — follow-up); re-running a Job (delete it, provider-kubernetes recreates it) and why old Jobs linger after a `jobGeneration` bump; the puller on demand (`kubectl create job --from=cronjob/forgejo-puller -n forgejo puller-manual`) and `suspend`; the Forgejo 15 force-push limitation and what it means for Phase 3; teardown (`allowTeardown: true`, the PVC `forgejo-data` survives and is deleted by hand); troubleshooting (ExternalSecret `SecretSyncedError` until the credentials Job ran; XR not Ready = a Job failed, read its pod log). `docs/README.md`: a `| [Forgejo](forgejo.md) | ... |` row. `docs/platform-gitea.md`: point at `forgejo.md` in its superseded banner. `README.md` line 21: "and the Forgejo runbook".

- [ ] **Step 9: Commit.** Branch `feat/forgejo-composition`. Bodyfile `.commits/nida-forgejo-composition.md`, `message: "feat(forgejo): the Forgejo composition, its init Jobs and the puller, gated on cluster-identity maturity"`, body: "Inert at bootstrap. Repositories are created empty because Forgejo 15 has no force-push allowlist; the puller's first push creates main. Scripts ship as a kustomize-generated ConfigMap.", `add:` `forgejo/`, `apps/forgejo-app.yaml`, `apps/kustomization.yaml`, `tests/render/`, `docs/forgejo.md`, `docs/README.md`, `docs/platform-gitea.md`, `README.md`. `ws commit nidavellir .commits/nida-forgejo-composition.md`, `ws push nidavellir`, `ws cr nidavellir "feat: Forgejo composition, init Jobs and puller (Forgejo Phase 2)" .crs/nida-forgejo-phase2.md`.

### Task 4: ArgoCD ServiceMonitor and the Unknown rule (heimdall)

**Files:**
- Modify: `crossplane/composition.yaml` (new step after `deploy-self-health-rules`; new rule group in `heimdall-self-health`)
- Modify: `README.md` (rules table, line ~115), `docs/architecture.md` (one paragraph beside the `HeimdallWatchedServiceDown` note)

**Interfaces:**
- Consumes: Service `argocd-application-controller-metrics` in `argo` (Task 2), label `app.kubernetes.io/name: argocd-metrics`, port `http-metrics`.
- Produces: series `argocd_app_info{name, namespace, sync_status, health_status, ...}` in Prometheus; rules `ArgoCDApplicationUnknown` (critical, watched) and `ArgoCDMetricsAbsent` (warning).

- [ ] **Step 1: ServiceMonitor step.** After the `deploy-self-health-rules` step:

```yaml
  # ──────────────────────────────────────────────────────────
  # Step 3.6: ArgoCD controller metrics (realm Forgejo day-2 Phase 2
  # design). nordri adopts ArgoCD under GitOps with
  # controller.metrics.enabled, which renders Service
  # argocd-application-controller-metrics in argo. This
  # ServiceMonitor scrapes it for argocd_app_info — the series
  # behind ArgoCDApplicationUnknown below. serviceMonitorSelector
  # is empty (cluster-wide), so the release label documents intent.
  # ──────────────────────────────────────────────────────────
  - step: deploy-argocd-servicemonitor
    functionRef:
      name: function-go-templating
    input:
      apiVersion: gotemplating.fn.crossplane.io/v1beta1
      kind: GoTemplate
      source: Inline
      inline:
        template: |
          {{- $name := .observed.composite.resource.metadata.name -}}
          apiVersion: kubernetes.crossplane.io/v1alpha2
          kind: Object
          metadata:
            name: {{ $name }}-argocd-servicemonitor
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: argocd-servicemonitor
          spec:
            forProvider:
              manifest:
                apiVersion: monitoring.coreos.com/v1
                kind: ServiceMonitor
                metadata:
                  name: argocd-application-controller
                  namespace: heimdall
                  labels:
                    release: {{ $name }}-kube-prometheus
                    app.kubernetes.io/part-of: heimdall
                spec:
                  namespaceSelector:
                    matchNames: [argo]
                  selector:
                    matchLabels:
                      app.kubernetes.io/name: argocd-metrics
                      app.kubernetes.io/component: application-controller
                  endpoints:
                    - port: http-metrics
                      interval: 30s
```

- [ ] **Step 2: The rules.** A new group appended to `heimdall-self-health`'s `groups` (after `heimdall.probes`):

```yaml
                  # ArgoCD sitting in sync status Unknown is the blind spot every
                  # seed wipe exposed: everything reports Healthy while nothing
                  # has reconciled. `watched` puts it in the paging tier.
                  - name: heimdall.argocd
                    interval: 1m
                    rules:
                    - alert: ArgoCDApplicationUnknown
                      expr: argocd_app_info{sync_status="Unknown"} == 1
                      for: 5m
                      labels:
                        severity: critical
                        component: argocd
                        watched: "true"
                      annotations:
                        summary: {{ `ArgoCD Application {{ $labels.name }} has been Unknown for 5 minutes` | quote }}
                        description: {{ `{{ $labels.name }} (project {{ $labels.project }}) reports sync status Unknown: ArgoCD cannot reach or read its source, so nothing has reconciled — and every other Application may still say Healthy. The usual cause is the seed repository being gone or wiped. Check argocd-repo-server logs and the seed Gitea.` | quote }}
                    - alert: ArgoCDMetricsAbsent
                      expr: absent(argocd_app_info)
                      for: 15m
                      labels:
                        severity: warning
                        component: argocd
                      annotations:
                        summary: "ArgoCD application metrics are not being scraped"
                        description: "argocd_app_info has no series for 15 minutes, so ArgoCDApplicationUnknown cannot fire. Check Service argocd-application-controller-metrics in argo (controller.metrics.enabled in nordri's argocd Application) and the argocd-application-controller ServiceMonitor."
```

- [ ] **Step 3: Render both environments.** From the heimdall root: `crossplane render tests/render/heimdall-xr.yaml crossplane/composition.yaml tests/render/functions.yaml --extra-resources tests/render/cluster-identity-homelab.yaml` (and `-gke`), grep for `argocd-application-controller`, `ArgoCDApplicationUnknown`, `ArgoCDMetricsAbsent`. `ws lint heimdall` if wired; otherwise `ws test heimdall` needs a live cluster and is Task 6's job.

- [ ] **Step 4: Docs.** README rules table: `| ArgoCDApplicationUnknown | an Application has sync status Unknown for 5m | **critical** → priority 5 |` and `| ArgoCDMetricsAbsent | argocd_app_info has no series for 15m | warning |`. `docs/architecture.md`: one paragraph after the `HeimdallWatchedServiceDown` note: why Unknown is the signal that Healthy hides, and that the series comes from ArgoCD's own controller metrics, scraped from `argo`.

- [ ] **Step 5: Commit.** Branch `feat/argocd-unknown-alert`. Bodyfile `.commits/heimdall-argocd-unknown.md`, `message: "feat(alerts): ArgoCDApplicationUnknown, scraped from ArgoCD's controller metrics"`. Commit, push, `ws cr heimdall "feat: ArgoCDApplicationUnknown rule and the controller ServiceMonitor (Forgejo Phase 2)" .crs/heimdall-argocd-unknown.md`.

### Task 5: The claim (realm)

**Files:**
- Create: `cluster/forgejo/claim.yaml`, `cluster/forgejo/kustomization.yaml`
- Modify: `cluster/kustomization.yaml`, `cluster/README.md`
- Add: this plan (already on disk)

- [ ] **Step 1: The claim.** `cluster/forgejo/claim.yaml`:

```yaml
# The SiliconSaga Forgejo instance (realm Forgejo day-2 design; Phase 2).
#
# Delivered by nordri's realm root-app exactly as the Keycloak realm import
# is. The XRD and composition are nidavellir's (forgejo/); this file is the
# only place the org name, the repository list, the vendor mirrors and the
# break-glass accounts are written down. It is hydrated unchanged into every
# cluster and renders NOTHING until that cluster's identity says
# maturity: durable — so it can sit on GKE and on a Docker Desktop cluster
# alike, inert, until an operator graduates one.
#
# Credentials are not seeded here (openbao-seeds is not used for Forgejo):
# the composition's credentials Job mints them in-cluster and writes them to
# OpenBao create-only, at secret/forgejo and secret/forgejo/admins/<user>.
apiVersion: nidavellir.siliconsaga.org/v1alpha1
kind: ForgejoInstance
metadata:
  name: forgejo
  namespace: forgejo
spec:
  parameters:
    chartVersion: "17.1.7"
    org: siliconsaga
    # main is written only by the puller, from these GitHub upstreams.
    repos:
      - {name: nordri, github: SiliconSaga/nordri}
      - {name: nidavellir, github: SiliconSaga/nidavellir}
      - {name: mimir, github: SiliconSaga/mimir}
      - {name: heimdall, github: SiliconSaga/heimdall}
      - {name: realm-siliconsaga, github: SiliconSaga/realm-siliconsaga}
    # Forgejo pull-mirrors, tags included (the keycloak-operator app pins tag 26.6.3).
    vendorMirrors:
      - {name: keycloak-k8s-resources, upstream: https://github.com/keycloak/keycloak-k8s-resources.git}
    breakGlassAdmins:
      - cervator
    storageSize: "10Gi"
    # pullerSchedule: hourly by default; a per-cluster cadence belongs on
    # cluster-identity (pullerSchedule), not here.
    # allowTeardown: never set on GKE. See nidavellir docs/forgejo.md.
```

  `cluster/forgejo/kustomization.yaml` with `resources: [claim.yaml]`; add `- forgejo` to `cluster/kustomization.yaml`.

- [ ] **Step 2: README.** Under Layout: "- `forgejo/` — the `ForgejoInstance` claim: org, maintained repositories, vendor mirrors, break-glass admins. Inert until the cluster's identity says `maturity: durable` (nidavellir `docs/forgejo.md`)." Under Ordering: "The `ForgejoInstance` claim retries until nidavellir's XRD exists (sync-wave 11)."

- [ ] **Step 3: Commit.** Branch `feat/forgejo-claim`. Bodyfile `.commits/realm-forgejo-claim.md`, `message: "feat(cluster): the ForgejoInstance claim, plus the Phase 2 implementation plan"`, `add:` `cluster/forgejo/`, `cluster/kustomization.yaml`, `cluster/README.md`, `docs/plans/2026-09-19-forgejo-day2-phase2-plan.md`. Commit, push, `ws cr realm-siliconsaga "feat: Forgejo claim and Phase 2 plan" .crs/realm-forgejo-claim.md`.

### Task 6: Validation on the Docker Desktop cluster (the proof list)

All from the topic branches, before merge; `kubectl config current-context` must be `docker-desktop`. Raw `kubectl` against the local cluster passed the hook in the planning session; if it does not, `ws hook-bypass k8s`.

- [ ] **Step 1: Role on the live vault.** `ws exec nordri ./openbao-configure.sh homelab realm-siliconsaga` → prints `forgejo-init policy and role`. Verify: `kubectl exec -n openbao openbao-0 -- bao read auth/kubernetes/role/forgejo-init` needs a token; instead the credentials Job's login in Step 4 is the test.
- [ ] **Step 2: Hydrate at bootstrap first.** `ws exec nordri ./update-embedded-git.sh homelab realm-siliconsaga`. Expect: `forgejo` Application Synced/Healthy with Namespace + ConfigMap + XRD + Composition; `realm-siliconsaga` Synced with the claim; XR `forgejo-*` Ready with zero composed resources (`kubectl get xforgejo`); `argocd` Application Synced/Healthy **with no diff** after adoption; Service `argocd-application-controller-metrics` present; `argocd_app_info` in Prometheus (`kubectl port-forward -n heimdall svc/prometheus-operated 9090` then `curl 'localhost:9090/api/v1/query?query=argocd_app_info'`); both rules loaded (`/api/v1/rules`), inactive.
- [ ] **Step 3: Bump to durable, locally.** Edit `nordri/platform/fundamentals/manifests/cluster-identity-homelab.yaml` to `maturity: durable` (do not commit), rehydrate. Watch: `kubectl get dataservice,externalsecret,job,release,cronjob -n forgejo -w`. Expect in order: DataService Ready; ExternalSecrets `SecretSyncedError` (the gate); credentials Job Complete; ExternalSecrets `SecretSynced`; Release Ready (`forgejo-0`… pod `forgejo-<hash>` Ready); configure Job Complete; CronJob `forgejo-puller`. `curl -k https://forgejo.homelab.local/api/healthz` → 200 (confirm it is unauthenticated). XR Ready/Synced.
- [ ] **Step 4: Configure Job proof.** Its log lists: org created, five repos created (empty), token minted, protection created ×5, mirror created, user `cervator` created + admin. In the UI (`https://forgejo.homelab.local`): log in as `cervator` with the password from the Secret — into a fresh private file, not the terminal: `d=$(mktemp -d); umask 077; kubectl get secret -n forgejo forgejo-admin-cervator -o jsonpath='{.data.password}' | base64 -d > "$d/cervator"` (`mktemp -d` creates a new 0700 directory, so nothing pre-existing or symlinked can be followed), paste it from there into the UI, then `rm -r "$d"`; the vendor mirror shows tag `26.6.3`. Record what `GET /repos/siliconsaga/keycloak-k8s-resources` returns in `original_url` (Task 3's drift note) and fix the script's comment if it is populated.
- [ ] **Step 5: Puller proof.** `kubectl create job -n forgejo --from=cronjob/forgejo-puller puller-manual-1`; log shows `<name>: <absent> -> <sha>` ×5 and `5/5`; `git ls-remote https://github.com/SiliconSaga/nordri main` equals Forgejo's `main` (`kubectl exec` a `git ls-remote` or the API `GET /repos/siliconsaga/nordri/branches/main`). A second run says `up to date` ×5. Add a bogus line to ConfigMap `forgejo-repos` by hand (`nope SiliconSaga/does-not-exist`), run again: that entry FAILED, the other five in sync, Job Failed; remove the line (or rehydrate; selfHeal restores it).
- [ ] **Step 6: Pod delete.** `kubectl delete pod -n forgejo -l app.kubernetes.io/name=forgejo`; PVC `forgejo-data` Bound throughout; after the pod is Ready, `GET /repos/siliconsaga/nordri/branches/main` still matches GitHub.
- [ ] **Step 7: Alert fires.** Point an Application at a missing path (`kubectl patch application -n argo ntfy --type merge -p '{"spec":{"source":{"path":"does-not-exist"}}}'`); within ~5 minutes `argocd_app_info{name="ntfy",sync_status="Unknown"} == 1` and `ArgoCDApplicationUnknown` is Pending then Firing; revert (the nidavellir app's selfHeal will not revert it — patch back by hand).
- [ ] **Step 8: Fail-closed downgrade.** Set the local identity back to `bootstrap`, rehydrate. The XR reports the render failure (`kubectl describe xforgejo` → the message naming `allowTeardown`); every composed resource, PVC included, is still there.
- [ ] **Step 9: Deliberate teardown.** Add `allowTeardown: true` to the realm claim locally (do not commit), rehydrate. Everything in `forgejo` goes except the PVC and the Namespace/ConfigMap the app ships; the DataService deletion drops the database. Delete the PVC by hand. Remove `allowTeardown` from the local claim.
- [ ] **Step 10: Fresh bootstrap.** Reset the local cluster (Docker Desktop: reset Kubernetes), `ws exec nordri ./bootstrap.sh homelab realm-siliconsaga`; everything green at `bootstrap` with the Forgejo pieces present and inert, ArgoCD adopted with no diff, rules loaded.
- [ ] **Step 11: Record.** Tick the design's proof list in `2026-09-19-forgejo-day2-phase2-design.md` (Status line: "Implemented; validated locally <date>"). Loki thalamus `forgejo-day2`: a dated section with what the validation found, the Forgejo 15 force-push finding for Phase 3, and `next:` → Phase 3. Then merge in land order (nordri → nidavellir + heimdall → realm), rebasing as needed.
