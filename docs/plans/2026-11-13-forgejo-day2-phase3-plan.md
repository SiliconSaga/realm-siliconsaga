# Forgejo Day-2 Phase 3 Implementation Plan (3a generic Git, 3b graduation and promotion)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status (2026-11-13):** written from the [Phase 3 design](2026-11-06-forgejo-day2-phase3-design.md) (decisions 1–5 settled 2026-11-10, review items settled 2026-11-12 and 2026-11-13) after surveying nordri, nidavellir, mimir, heimdall and this realm as they stand today. The author does not review plans separately; the CRs are the review surface. Plan docs are not maintained past implementation. One plan covers 3a then 3b, as settled; 3a is Tasks 1–12 and must merge before any 3b task starts.

**Goal:** Every per-cluster value leaves Git for a cluster-local identity written at bootstrap, ArgoCD reads one stable in-cluster Git address, and clusters climb a ladder: lab and test from the seed, `homelab-prod` from GitHub `main` through its Forgejo, `gke-prod` from a `live` branch promoted after the homelab soak, with `graduate.sh` repointing a cluster from seed to Forgejo and `promote.sh` moving `live`.

**Architecture:** nordri gains `identity.sh` (ConfigMap `nordri/cluster-identity`, projected onto the `cluster-identity` EnvironmentConfig and onto ArgoCD's `in-cluster` cluster Secret as labels and annotations), `lib/gitops.sh` (seed orgs, the `git` ExternalName Service in `gitops`, the two bootstrap-owned root Applications), and the four operator scripts `identity.sh`, `migrate.sh`, `graduate.sh`, `promote.sh`. The five Applications that carried stamped values become ApplicationSets with a cluster generator reading the identity. The hydration patch libraries, the overlay `sed` and `envs/` are deleted; 18 repoURLs become `http://git.gitops.svc.cluster.local:3000/siliconsaga/<repo>.git`. The Forgejo composition learns `orgs` with classes, `role` and `sourceRef`; its puller records `forgejo-puller-state` and, on `live`, syncs to the newest complete `live-<n>` tag set.

**Tech Stack:** bash + jq + curl + git + kubectl (nordri scripts and the puller on `alpine/k8s:1.36.4`), ArgoCD chart 10.9.1 with the ApplicationSet controller (cluster generator, `goTemplate: true`, Sprig), Crossplane 2.x `function-go-templating` v0.4.0 and `function-environment-configs` v0.4.0, Gitea seed (chart from `https://dl.gitea.io/charts/`) and forgejo-helm 17.1.7 (Forgejo 15.0.9, same `/api/v1` shapes for orgs, repos and branch protection), `gh` CLI for GitHub refs and rulesets, kube-prometheus-stack in heimdall, Tailscale API v2 with the operator's OAuth client.

## Global Constraints

- Every GDD convention: `ws orient` at session start, `ws checkout <comp> <branch>` for topic branches, `ws commit <comp> <bodyfile>` (terse style: subject plus at most ~50 words, bodyfile frontmatter `message:` and `add:`), `ws push`, `ws cr <comp> <title> <bodyfile>`. Rebase, never merge; hand force pushes to the author; after fixing bot findings push and stop. The author merges.
- The kube context is a human act. No script in this plan takes a `--context` flag; every one follows kubectl's current context and refuses when the live identity's `cluster` does not match the name it was given. `kubectl config use-context` stays the operator's step, and the Claude hook asks for it.
- No credential in argv, a URL or a shell variable outside the pod: tokens and passwords rest in 0600 files under a 0700 scratch dir and reach curl through `-K` config files or `--data @file`, and git through `GIT_ASKPASS`. The seed's push URL keeps today's `user:pass@host` form only inside `GITEA_GIT_BASE`, which is never printed.
- Names are contracts across repos and must match exactly: ConfigMap `cluster-identity` in namespace `nordri`; EnvironmentConfig `cluster-identity` (unchanged name); cluster Secret `in-cluster` in `argo` with label `argocd.argoproj.io/secret-type: cluster`; labels `nordri.siliconsaga.org/cluster`, `nordri.siliconsaga.org/environment`, `nordri.siliconsaga.org/role`, `nordri.siliconsaga.org/tailnet` (`"true"`/`"false"`); annotations `nordri.siliconsaga.org/tailnet-node`, `nordri.siliconsaga.org/gcp-project`, `nordri.siliconsaga.org/maturity`; Service `git` in namespace `gitops`, port 3000; orgs `siliconsaga` (canonical) and `siliconsaga-vendor` (vendor) on every Git server; stable address `http://git.gitops.svc.cluster.local:3000/<org>/<repo>.git`; ConfigMap `forgejo-puller-state` in namespace `forgejo`; GitHub branch `live` and tags `live-<n>`; identity keys exactly as the design's table: `cluster`, `environment`, `role`, `maturity`, `sourceRef`, `tailnetNode`, `storageClass`, `domain`, `harborRole`, `harborCentral`, `gcpProject`, `gcpRegion`, `pullerSchedule`.
- Identity files are flat `key: value` YAML (one scalar per line, `#` comments, no nesting), because nordri's scripts have jq and not yq. `identity_read_flat` refuses anything else.
- Chart and image pins are unchanged by this plan: argo-cd `10.9.1` in both install places, forgejo-helm `17.1.7`, `alpine/k8s:1.36.4`, tailscale-operator `1.98.3`, velero `11.3.1`.
- Land order: 3a as one coordinated change set, climbing the ladder before merge: nordri (Tasks 1–5, 11) first, then nidavellir (6–8) and mimir (9) in parallel, then the realm (10). Task 12's gates run from the topic branches on a fresh lab cluster and on the Nano76 cluster, since `update-embedded-git.sh` hydrates from local checkouts. Merge order: nordri, nidavellir, mimir, realm. 3b tasks (13–21) start only after 3a has merged and GKE has migrated (Task 20 step 2).
- Nothing in this plan deletes data: Velero's originals are deleted only in Task 20 after the two checks pass; the seed is retired only by `graduate.sh --retire-seed` with its gates; `shared-clusters` keeps `prune: false`.

## Facts checked, and what they changed

| Question | Answer | Consequence |
|---|---|---|
| Does the realm's `ecosystem.yaml` carry `defaults.gitea.internalUrl`? | No. It was added in `9a674ca` and removed in `5c58420` (2026-09-30, "major realm cleanup"); nothing in `scripts/`, `.agent/` or any component reads an `internalUrl`. | 3a-4's rename is dropped. The stable address is a constant in nordri `lib/gitops.sh`; the realm declares nothing about it. |
| Where does the realm root Application's `path: .` live? | nordri `platform/argocd/realm-root-app.template.yaml:19`, rendered by `bootstrap.sh:692-695`; the realm has no Application manifest. Hydration pushes only `cluster/` (`bootstrap.sh:504`, `update-embedded-git.sh:313`). | Task 3 changes the template to `path: cluster` and Task 4 hydrates the whole realm checkout, so the seed's realm repo matches Forgejo's mirror. |
| What does the puller have access to? | ServiceAccount `forgejo-puller` has no Role, `automountServiceAccountToken: false` on SA and pod; no GitHub token exists; the Forgejo token reaches git through `GIT_ASKPASS` only. | Task 14 adds a Role in `forgejo` (ConfigMap `forgejo-puller-state` get/create/update) and a Role in `argo` (applications get/list), and mounts the token. GitHub stays anonymous. |
| Is there any Prometheus series for the puller? | None; "puller" appears nowhere in heimdall. kube-state-metrics in kube-prometheus-stack exports `kube_cronjob_status_last_successful_time` and `kube_job_status_failed`. | The 3b-6 alert fires on the CronJob's last success age (Task 17). A per-repository series needs an exporter the stack does not have, so the per-repository panel and metric slip to Phase 4, as the design allowed; `promote.sh` reads `forgejo-puller-state` directly. |
| Any ApplicationSet today? | None in nordri, nidavellir or mimir. `applicationsSync` is ignored unless the controller runs with policy override. | Task 4 sets `configs.params."applicationsetcontroller.enable.policy.override": true` in both ArgoCD install places; `migrate.sh` step 1 reads it back from `argocd-cmd-params-cm`. |
| Can an ApplicationSet be rendered offline with a missing identity value? | The cluster generator needs the controller and a cluster Secret; `argocd appset generate` cannot stand in for it. | The design's missing-value test runs live on the lab cluster in Task 12 (Secret with one label removed at a time; the ApplicationSet reports a render error and the Application is left alone). Offline, `tests/unit/appset-guards-test.sh` asserts every `index` lookup has a `fail` guard. |
| Who reads `envs/<target>/values.yaml`? | Only the two `cp` lines in the scripts; no manifest references it. | Deleted in Task 4. |
| How does the ntfy composition decide tailnet exposure? | `{{- if eq $env "gke" }}` adds `tailscale.com/expose`, hostname `$params.tailscaleHostname \| default "ntfy-<env>"`; replicas are 1 everywhere since 2026-11-03 because Alertmanager posts to ntfy in every realm. | Exposure follows `tailnetNode` (non-empty), not the environment; ntfy itself runs everywhere. The design's 2026-11-13 wording was corrected to say so. |
| Where is `teralivekubernetes` hardcoded? | mimir `shared/overlays/gke/kustomization.yaml` (pgBackRest GSA, repo2 bucket, PXC bucket); nidavellir `vegvisir/manifests/base/cert-manager-app.yaml:31` (SA annotation, in **base**) and `overlays/gke/letsencrypt-dns01.yaml:42`; nordri `velero-gke.yaml` as `__GCP_PROJECT__`. No backup path prefix exists anywhere. | Tasks 5, 6 and 9 inject `gcpProject` from the identity through the ApplicationSets (`kustomize.patches`, a helm parameter) and add the cluster prefix: Velero `prefix`, pgBackRest `repo2-path`, PXC `bucket: <bucket>/<cluster>`. The cert-manager annotation leaves base. |
| How are the seed's repos owned? | `gitea_ensure_repo` posts to `/user/repos` as `nordri-admin`; no org exists. Gitea's API has the same `POST /orgs` and `POST /orgs/{org}/repos` as Forgejo. | Task 3 gives `gitea_ensure_repo` an owner argument and adds `gitops_ensure_org`. The old `nordri-admin` repos stay, unreferenced. |
| Does a cluster generator see the in-cluster cluster without a Secret? | No. The implicit in-cluster has no Secret, so the generator matches nothing until one exists. Creating Secret `in-cluster` (`name: in-cluster`, `server: https://kubernetes.default.svc`) is the documented way to label it. | `identity.sh apply` owns that Secret (Task 2). |
| Git over an ExternalName Service | ArgoCD's repo-server resolves `git.gitops.svc.cluster.local` to a CNAME for `gitea-http.gitea.svc.cluster.local`; Gitea serves smart-HTTP on `/<org>/<repo>.git/info/refs` regardless of Host. | Task 12's lab gate is the live check; nothing else assumes it. |
| GitHub protection for `live` | Repository rulesets: `target: branch`, `ref_name.include: ["refs/heads/live"]`, rules `deletion`, `non_fast_forward`, `update`; bypass actor `{actor_id: 5, actor_type: RepositoryRole}` (admin). Tags: `target: tag`, `refs/tags/live-*`, rules `deletion`, `update`, `creation`. | `scripts/protect-live.sh` (Task 15). The admin role id is confirmed in Task 15 step 1 against `GET /repos/{o}/{r}/rulesets` after the first create, before the other four. |
| Tailscale API for the device list | `POST https://api.tailscale.com/api/v2/oauth/token` (client credentials) then `GET /api/v2/tailnet/-/devices`; a device has `id`, `hostname`, `name`, `tags`, `lastSeen`; delete is `DELETE /api/v2/device/{id}`. The operator's OAuth client already holds the device-write scope. | `scripts/tailnet-devices.sh` (Task 19) lists and prints delete commands; it never deletes. |
| Fast-forward on GitHub without a clone | `PATCH /repos/{o}/{r}/git/refs/heads/live` with `{sha, force: false}` is refused unless it is a fast-forward; `POST /repos/{o}/{r}/git/refs` creates `refs/heads/live` or `refs/tags/live-<n>`; `GET /repos/{o}/{r}/git/matching-refs/tags/live-` lists the tag set. | `promote.sh` is API-only (Task 15). |

---

## Phase 3a — generic Git

### Task 1: identity library and defaults (nordri)

**Files:**
- Create: `lib/identity.sh`
- Create: `identity/defaults-homelab.yaml`, `identity/defaults-gke.yaml`
- Create: `tests/unit/identity-resolve-test.sh`

**Interfaces:**
- Consumes: nothing from nordri; `date -u`, `kubectl` (only in `identity_live_value`).
- Produces: `identity_read_flat <file>` (prints `key=value` lines, exit 1 on a nested or malformed line); `identity_resolve <realm_dir> <cluster>` (prints the merged `key=value` lines, sorted, every required key present); `identity_live_value <key>` (prints the live ConfigMap's value or nothing); `identity_tailnet_default <cluster> <role> <live_tailnet>` (prints the tailnet node to use); constants `IDENTITY_NAMESPACE=nordri`, `IDENTITY_CONFIGMAP=cluster-identity`, `IDENTITY_REQUIRED="cluster environment role maturity"`.

- [ ] **Step 1: Write the defaults.** `identity/defaults-homelab.yaml`:

```yaml
# Environment defaults for homelab clusters. Layer 1 of the identity: the realm's
# clusters/<cluster>.yaml overrides, then NORDRI_IDENTITY_<KEY> env vars. Flat
# key: value only — lib/identity.sh refuses nesting. No maturity here: a cluster
# with no realm file is a lab at bootstrap, by design.
environment: homelab
storageClass: local-path
domain: homelab.local
harborRole: local
harborCentral: harbor.cmdbee.org
```

`identity/defaults-gke.yaml`:

```yaml
# Environment defaults for GKE clusters. gcpProject is NOT here: the realm's
# clusters/<cluster>.yaml declares it, and identity_resolve refuses a gke
# cluster without one. gcpRegion is the KMS key ring's region, static.
environment: gke
storageClass: standard-rwo
domain: cmdbee.org
harborRole: central
gcpRegion: us-east1
```

- [ ] **Step 2: Write the failing test** `tests/unit/identity-resolve-test.sh`:

```bash
#!/usr/bin/env bash
# Unit test for lib/identity.sh: flat-file parsing, the three layers, the lab
# default for an undeclared cluster, the gke gcpProject requirement, and the
# tailnet default (realm Phase 3 design, Decision 3 and the 2026-11-13 review).
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/lib/identity.sh"

fails=0
check() { if eval "$2"; then echo "ok - $1"; else echo "NOT OK - $1"; fails=$((fails+1)); fi; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/realm/clusters"
cat > "$work/realm/clusters/homelab-prod.yaml" <<'EOF'
# a declared prod cluster
role: prod
maturity: durable
sourceRef: main
environment: homelab
EOF
cat > "$work/realm/clusters/gke-prod.yaml" <<'EOF'
environment: gke
role: prod
maturity: bootstrap
sourceRef: live
tailnetNode: gke
gcpProject: example-project
EOF
cat > "$work/realm/clusters/gke-bad.yaml" <<'EOF'
environment: gke
role: test
maturity: bootstrap
EOF
cat > "$work/realm/clusters/homelab-test.yaml" <<'EOF'
environment: homelab
role: test
maturity: bootstrap
tailnetNode: stamped
EOF
cat > "$work/nested.yaml" <<'EOF'
role: prod
backups:
  enabled: true
EOF

# Parsing
out=$(identity_read_flat "$work/realm/clusters/homelab-prod.yaml")
check "comments and blanks skipped, four keys" "[[ \$(printf '%s\n' \"\$out\" | wc -l) -eq 4 ]]"
check "key=value form" "[[ \"\$out\" == *'maturity=durable'* ]]"
identity_read_flat "$work/nested.yaml" >/dev/null 2>&1; rc=$?
check "a nested file is refused" "[[ $rc -eq 1 ]]"

# Layer 1 + 2: realm file over environment defaults
out=$(identity_resolve "$work/realm" homelab-prod)
check "cluster name recorded" "[[ \"\$out\" == *'cluster=homelab-prod'* ]]"
check "defaults supply storageClass" "[[ \"\$out\" == *'storageClass=local-path'* ]]"
check "realm file supplies maturity" "[[ \"\$out\" == *'maturity=durable'* ]]"
check "prod tailnet defaults to the cluster name" "[[ \"\$out\" == *'tailnetNode=homelab-prod'* ]]"

# Layer 3: env override wins
out=$(NORDRI_IDENTITY_DOMAIN=lab.example identity_resolve "$work/realm" homelab-prod)
check "env var overrides the merged value" "[[ \"\$out\" == *'domain=lab.example'* ]]"

# An undeclared cluster is a lab at bootstrap on homelab, with no tailnet node
out=$(identity_resolve "$work/realm" homelab-spare)
check "lab default role" "[[ \"\$out\" == *'role=lab'* ]]"
check "lab default maturity" "[[ \"\$out\" == *'maturity=bootstrap'* ]]"
check "lab default environment" "[[ \"\$out\" == *'environment=homelab'* ]]"
check "lab has no tailnet node" "[[ \"\$out\" == *'tailnetNode='$'\n'* ]]"

# gke needs a project
out=$(identity_resolve "$work/realm" gke-prod)
check "gke project carried" "[[ \"\$out\" == *'gcpProject=example-project'* ]]"
identity_resolve "$work/realm" gke-bad >/dev/null 2>&1; rc=$?
check "gke without gcpProject is refused" "[[ $rc -eq 1 ]]"

# A stamped test cluster: fresh stamp when none is live, kept when one is
date() { echo "20261113-1430"; }
out=$(identity_resolve "$work/realm" homelab-test)
check "stamped tailnet node" "[[ \"\$out\" == *'tailnetNode=homelab-test-20261113-1430'* ]]"
unset -f date
out=$(IDENTITY_LIVE_TAILNET=homelab-test-20261101-0900 identity_resolve "$work/realm" homelab-test)
check "an existing stamp is kept across re-applies" "[[ \"\$out\" == *'tailnetNode=homelab-test-20261101-0900'* ]]"

echo "---"; [ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
```

- [ ] **Step 3: Run it to see it fail.** `bash tests/unit/identity-resolve-test.sh` → `lib/identity.sh: No such file or directory`.

- [ ] **Step 4: Write `lib/identity.sh`:**

```bash
#!/usr/bin/env bash
# lib/identity.sh — resolve a cluster's identity from three layers and read the
# live one. Sourced by scripts/identity.sh, bootstrap.sh, migrate.sh,
# graduate.sh and update-embedded-git.sh. Realm Phase 3 design, Decision 3.
#
# Layers, later winning: identity/defaults-<environment>.yaml, the realm's
# clusters/<cluster>.yaml, then NORDRI_IDENTITY_<KEY> environment variables
# (the layer for values that must never be committed; none exist today).
# A cluster with no realm file is a homelab lab at bootstrap maturity.

IDENTITY_NAMESPACE="nordri"
IDENTITY_CONFIGMAP="cluster-identity"
IDENTITY_REQUIRED="cluster environment role maturity"
IDENTITY_KEYS="cluster environment role maturity sourceRef tailnetNode storageClass domain harborRole harborCentral gcpProject gcpRegion pullerSchedule"
NORDRI_LIB_DIR="${NORDRI_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Print key=value per line. Flat scalars only: a line that ends in ':' or
# starts with '-' is nesting, and nesting is refused because the readers of
# these files have jq, not yq, and a silently dropped subtree is worse than a
# refusal.
identity_read_flat() {
    local file="$1" line key value n=0
    [[ -f "$file" ]] || { echo "identity: no such file: $file" >&2; return 1; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n+1))
        line="${line%$'\r'}"
        [[ -z "${line// }" || "${line#"${line%%[![:space:]]*}"}" == \#* ]] && continue
        if [[ "$line" =~ ^[[:space:]]*-|:[[:space:]]*(#.*)?$ ]]; then
            echo "identity: $file:$n is nested, and identity files are flat key: value only" >&2; return 1
        fi
        if [[ ! "$line" =~ ^([A-Za-z][A-Za-z0-9_]*):[[:space:]]*(.*)$ ]]; then
            echo "identity: $file:$n is not 'key: value': $line" >&2; return 1
        fi
        key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
        value="${value%%[[:space:]]#*}"              # trailing comment
        value="${value%"${value##*[![:space:]]}"}"    # trailing space
        value="${value#\"}"; value="${value%\"}"      # optional quotes
        value="${value#\'}"; value="${value%\'}"
        printf '%s=%s\n' "$key" "$value"
    done < "$file"
}

# The tailnet node a cluster registers under. prod: the cluster name, unique in
# the realm. "stamped": <cluster>-<yyyymmdd-HHMM>, kept once set so a re-apply
# never renames a live device (2026-11-13 review). Empty means no operator.
identity_tailnet_default() {
    local cluster="$1" role="$2" live="${3:-}"
    case "$role" in
        prod) printf '%s' "$cluster" ;;
        *) printf '' ;;
    esac
}
identity_tailnet_stamp() {
    local cluster="$1" live="${2:-}"
    if [[ -n "$live" && "$live" == "$cluster"-* ]]; then printf '%s' "$live"; return 0; fi
    printf '%s-%s' "$cluster" "$(date -u +%Y%m%d-%H%M)"
}

# Merge the layers for <cluster> and print sorted key=value lines. Every key in
# IDENTITY_KEYS is printed (empty when unset) so readers can rely on the shape.
# IDENTITY_LIVE_TAILNET carries the live tailnetNode for the stamp rule; the
# CLI sets it from the cluster before calling this.
identity_resolve() {
    local realm_dir="$1" cluster="$2" realm_file env_file line key value
    declare -A id=()
    [[ "$cluster" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ && ${#cluster} -le 63 ]] \
        || { echo "identity: cluster '$cluster' must be a DNS-1123 label" >&2; return 1; }
    realm_file="$realm_dir/clusters/$cluster.yaml"
    if [[ -f "$realm_file" ]]; then
        while IFS='=' read -r key value; do id["$key"]="$value"; done < <(identity_read_flat "$realm_file") || return 1
        for key in environment role maturity; do
            [[ -n "${id[$key]:-}" ]] || { echo "identity: $realm_file must set $key" >&2; return 1; }
        done
    else
        echo "identity: no clusters/$cluster.yaml in $realm_dir — lab defaults (homelab, lab, bootstrap)" >&2
        id[environment]=homelab; id[role]=lab; id[maturity]=bootstrap
    fi
    env_file="$NORDRI_LIB_DIR/../identity/defaults-${id[environment]}.yaml"
    [[ -f "$env_file" ]] || { echo "identity: unknown environment '${id[environment]}' (no $env_file)" >&2; return 1; }
    declare -A merged=()
    while IFS='=' read -r key value; do merged["$key"]="$value"; done < <(identity_read_flat "$env_file") || return 1
    for key in "${!id[@]}"; do merged["$key"]="${id[$key]}"; done
    for key in $IDENTITY_KEYS; do
        value="$(printenv "NORDRI_IDENTITY_$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')" 2>/dev/null || true)"
        [[ -n "$value" ]] && merged["$key"]="$value"
    done
    merged[cluster]="$cluster"
    case "${merged[role]}" in lab|test|prod) ;; *) echo "identity: role '${merged[role]}' is not lab, test or prod" >&2; return 1 ;; esac
    case "${merged[maturity]}" in bootstrap|durable|full) ;; *) echo "identity: maturity '${merged[maturity]}' is not bootstrap, durable or full" >&2; return 1 ;; esac
    if [[ "${merged[role]}" == "prod" ]]; then
        merged[sourceRef]="${merged[sourceRef]:-main}"
        case "${merged[sourceRef]}" in main|live) ;; *) echo "identity: sourceRef '${merged[sourceRef]}' is not main or live" >&2; return 1 ;; esac
    else
        merged[sourceRef]=""
    fi
    if [[ "${merged[environment]}" == "gke" ]]; then
        [[ "${merged[gcpProject]:-}" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] \
            || { echo "identity: a gke cluster must declare gcpProject in clusters/$cluster.yaml (got '${merged[gcpProject]:-}')" >&2; return 1; }
    fi
    case "${merged[tailnetNode]:-}" in
        "") merged[tailnetNode]="$(identity_tailnet_default "$cluster" "${merged[role]}")" ;;
        stamped) merged[tailnetNode]="$(identity_tailnet_stamp "$cluster" "${IDENTITY_LIVE_TAILNET:-}")" ;;
    esac
    for key in $IDENTITY_KEYS; do printf '%s=%s\n' "$key" "${merged[$key]:-}"; done | sort
}

# The live ConfigMap's value for <key>, or nothing (no ConfigMap, no key).
identity_live_value() {
    kubectl get configmap -n "$IDENTITY_NAMESPACE" "$IDENTITY_CONFIGMAP" \
        -o "jsonpath={.data.$1}" 2>/dev/null | tr -d '\r'
}
```

- [ ] **Step 5: Run the test.** `bash tests/unit/identity-resolve-test.sh` → `ALL PASS`. Then `bash tests/run.sh test` (the glob picks the new test up; `lib/*.sh` is already in the lint list).

- [ ] **Step 6: Commit.** Bodyfile message `feat(identity): resolve a cluster's identity from three flat layers`, add `lib/identity.sh identity/ tests/unit/identity-resolve-test.sh`.

---

### Task 2: `scripts/identity.sh` — apply, show, diff, and the three projections (nordri)

**Files:**
- Create: `scripts/identity.sh`
- Create: `tests/unit/identity-apply-test.sh`
- Modify: `tests/run.sh:7` (add `scripts/identity.sh` to `shell_files`)

**Interfaces:**
- Consumes: `identity_resolve`, `identity_live_value`, `IDENTITY_*` from `lib/identity.sh`.
- Produces: `scripts/identity.sh apply <realm> <cluster>` (writes ConfigMap, cluster Secret, EnvironmentConfig handover; exit 1 on a cluster-name mismatch with the live ConfigMap), `scripts/identity.sh show` (live ConfigMap as `key=value`), `scripts/identity.sh diff <realm> <cluster>` (resolved vs live, exit 2 when different). `REALM_DIR` overrides the realm checkout path, as bootstrap already allows. Environment variable `IDENTITY_SKIP_ENVCONFIG=1` skips the EnvironmentConfig projection (bootstrap's first call, before Crossplane's CRDs exist).

- [ ] **Step 1: Write the failing test** `tests/unit/identity-apply-test.sh`. A `kubectl` stub records every call in a file and answers `get configmap` from a variable, so the test can assert the ConfigMap, the Secret's labels, the two EnvironmentConfig modes and the name guard:

```bash
#!/usr/bin/env bash
# Unit test for scripts/identity.sh apply: the ConfigMap, the in-cluster
# Secret's labels and annotations, the EnvironmentConfig handover (annotate
# only while ArgoCD still tracks it; take over once it does not), and the
# cluster-name guard. kubectl is a recording stub.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
fails=0
check() { if eval "$2"; then echo "ok - $1"; else echo "NOT OK - $1"; fails=$((fails+1)); fi; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/realm/clusters" "$work/bin"
printf 'environment: homelab\nrole: prod\nmaturity: durable\n' > "$work/realm/clusters/homelab-prod.yaml"
export STUB_LOG="$work/calls" STUB_LIVE_CLUSTER="" STUB_EC_TRACKED="" STUB_EC_PRESENT=""
cat > "$work/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$*" in
  *"get configmap -n nordri cluster-identity -o jsonpath={.data.cluster}"*) printf '%s' "$STUB_LIVE_CLUSTER" ;;
  *"get configmap -n nordri cluster-identity -o jsonpath={.data.tailnetNode}"*) printf '' ;;
  *"get crd environmentconfigs.apiextensions.crossplane.io"*) exit 0 ;;
  *"get environmentconfig cluster-identity -o jsonpath={.metadata.labels.app\.kubernetes\.io/instance}"*)
      [[ -n "$STUB_EC_PRESENT" ]] || exit 1; printf '%s' "$STUB_EC_TRACKED" ;;
  "apply -f -"|"apply -f - -n nordri"|*"apply -f -"*) cat >> "$STUB_LOG.applied" ;;
esac
exit 0
STUB
chmod +x "$work/bin/kubectl"
export PATH="$work/bin:$PATH"

run() { : > "$STUB_LOG"; : > "$STUB_LOG.applied"; REALM_DIR="$work/realm" bash "$root/scripts/identity.sh" "$@"; }

# Fresh cluster, EnvironmentConfig absent: ConfigMap, Secret and a new EC.
STUB_LIVE_CLUSTER="" STUB_EC_PRESENT="" run apply realm-x homelab-prod >/dev/null 2>&1; rc=$?
check "apply succeeds on a fresh cluster" "[[ $rc -eq 0 ]]"
check "namespace nordri ensured" "grep -q 'create namespace nordri' \"\$STUB_LOG\""
check "ConfigMap carries the cluster" "grep -q 'cluster: homelab-prod' \"\$STUB_LOG.applied\""
check "ConfigMap carries the merged storageClass" "grep -q 'storageClass: local-path' \"\$STUB_LOG.applied\""
check "cluster Secret has the type label" "grep -q 'argocd.argoproj.io/secret-type: cluster' \"\$STUB_LOG.applied\""
check "cluster Secret has the cluster label" "grep -q 'nordri.siliconsaga.org/cluster: homelab-prod' \"\$STUB_LOG.applied\""
check "cluster Secret has the environment label" "grep -q 'nordri.siliconsaga.org/environment: homelab' \"\$STUB_LOG.applied\""
check "prod has a tailnet node, so tailnet=true" "grep -q 'nordri.siliconsaga.org/tailnet: \"true\"' \"\$STUB_LOG.applied\""
check "tailnet-node annotation" "grep -q 'nordri.siliconsaga.org/tailnet-node: homelab-prod' \"\$STUB_LOG.applied\""
check "in-cluster server" "grep -q 'server: https://kubernetes.default.svc' \"\$STUB_LOG.applied\""
check "EnvironmentConfig written" "grep -q 'kind: EnvironmentConfig' \"\$STUB_LOG.applied\""

# EC present and still tracked by ArgoCD: annotate Prune=false, do not write it.
STUB_LIVE_CLUSTER="homelab-prod" STUB_EC_PRESENT=1 STUB_EC_TRACKED="layer4-fundamentals" run apply realm-x homelab-prod >/dev/null 2>&1
check "tracked EC gets Prune=false" "grep -q 'annotate environmentconfig cluster-identity argocd.argoproj.io/sync-options=Prune=false --overwrite' \"\$STUB_LOG\""
check "tracked EC is not rewritten" "! grep -q 'kind: EnvironmentConfig' \"\$STUB_LOG.applied\""

# EC present and untracked: take it over, strip tracking metadata.
STUB_LIVE_CLUSTER="homelab-prod" STUB_EC_PRESENT=1 STUB_EC_TRACKED="" run apply realm-x homelab-prod >/dev/null 2>&1
check "untracked EC is rewritten" "grep -q 'kind: EnvironmentConfig' \"\$STUB_LOG.applied\""
check "tracking label removed" "grep -q 'label environmentconfig cluster-identity app.kubernetes.io/instance-' \"\$STUB_LOG\""
check "prune annotation removed" "grep -q 'annotate environmentconfig cluster-identity argocd.argoproj.io/sync-options-' \"\$STUB_LOG\""

# The name guard
STUB_LIVE_CLUSTER="homelab-test" run apply realm-x homelab-prod >/dev/null 2>"$work/err"; rc=$?
check "a different live cluster name is refused" "[[ $rc -eq 1 ]]"
check "the refusal names both" "grep -q 'homelab-test' \"\$work/err\" && grep -q 'homelab-prod' \"\$work/err\""

# Skip the EC projection on request
STUB_LIVE_CLUSTER="" STUB_EC_PRESENT="" IDENTITY_SKIP_ENVCONFIG=1 run apply realm-x homelab-prod >/dev/null 2>&1
check "IDENTITY_SKIP_ENVCONFIG skips the EC" "! grep -q 'kind: EnvironmentConfig' \"\$STUB_LOG.applied\""

echo "---"; [ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
```

- [ ] **Step 2: Run it to see it fail.** `bash tests/unit/identity-apply-test.sh` → every check NOT OK (no script).

- [ ] **Step 3: Write `scripts/identity.sh`:**

```bash
#!/usr/bin/env bash
# identity.sh — the cluster's single source of per-cluster facts, written once at
# bootstrap and re-applied on graduation. Realm Phase 3 design, Decision 3.
#
#   scripts/identity.sh apply <realm> <cluster>   write ConfigMap nordri/cluster-identity,
#                                                  project it onto the in-cluster ArgoCD
#                                                  cluster Secret and the cluster-identity
#                                                  EnvironmentConfig; prints a diff first
#   scripts/identity.sh show                       the live ConfigMap as key=value
#   scripts/identity.sh diff <realm> <cluster>     resolved vs live; exit 2 when they differ
#
# Follows kubectl's current context. Refuses to apply when the live ConfigMap
# names a different cluster: identity-changing scripts never rename a cluster.
# REALM_DIR overrides where the realm checkout is (default: ../../realms/<realm>
# from this repo, as bootstrap.sh). IDENTITY_SKIP_ENVCONFIG=1 skips the
# EnvironmentConfig, for bootstrap's first call before Crossplane's CRDs exist.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$SCRIPT_DIR/lib/identity.sh"

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }
cmd="${1:-}"; shift || true
case "$cmd" in apply|diff) [[ $# -eq 2 ]] || usage ;; show) ;; *) usage ;; esac

realm_dir_for() {
    local realm="$1"
    [[ "$realm" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { echo "❌ realm '$realm' must be a DNS-1123 label" >&2; exit 1; }
    printf '%s' "${REALM_DIR:-$(dirname "$(dirname "$SCRIPT_DIR")")/realms/$realm}"
}

resolve() { # $1 realm $2 cluster → RESOLVED (key=value lines)
    local dir; dir="$(realm_dir_for "$1")"
    [[ -d "$dir" ]] || { echo "❌ realm checkout not found at $dir (set REALM_DIR)" >&2; exit 1; }
    IDENTITY_LIVE_TAILNET="$(identity_live_value tailnetNode)" RESOLVED="$(identity_resolve "$dir" "$2")" || exit 1
}
value_of() { printf '%s\n' "$RESOLVED" | sed -n "s/^$1=//p"; }

live_lines() {
    kubectl get configmap -n "$IDENTITY_NAMESPACE" "$IDENTITY_CONFIGMAP" -o json 2>/dev/null \
        | jq -r '.data // {} | to_entries[] | "\(.key)=\(.value)"' | sort
}

show_diff() { # prints the diff, returns 0 same / 2 different
    local live; live="$(live_lines)"
    if [[ -z "$live" ]]; then echo "   (no live ConfigMap $IDENTITY_NAMESPACE/$IDENTITY_CONFIGMAP)"; printf '%s\n' "$RESOLVED" | sed 's/^/ + /'; return 2; fi
    if diff <(printf '%s\n' "$live") <(printf '%s\n' "$RESOLVED") >/dev/null; then echo "   identity unchanged"; return 0; fi
    diff <(printf '%s\n' "$live") <(printf '%s\n' "$RESOLVED") | sed -n 's/^</ - /p; s/^>/ + /p'; return 2
}

apply_configmap() {
    local cluster="$1" live
    live="$(identity_live_value cluster)"
    if [[ -n "$live" && "$live" != "$cluster" ]]; then
        echo "❌ the live identity is cluster '$live', not '$cluster'. This script never renames a cluster; re-bootstrap instead." >&2; exit 1
    fi
    kubectl create namespace "$IDENTITY_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    {
        echo "apiVersion: v1"; echo "kind: ConfigMap"
        echo "metadata:"; echo "  name: $IDENTITY_CONFIGMAP"; echo "  namespace: $IDENTITY_NAMESPACE"
        echo "  labels:"; echo "    app.kubernetes.io/part-of: nordri"
        echo "data:"
        printf '%s\n' "$RESOLVED" | while IFS='=' read -r k v; do printf '  %s: %s\n' "$k" "$(jq -nr --arg v "$v" '$v|@json')"; done
    } | kubectl apply -f - >/dev/null || exit 1
    echo "✅ ConfigMap $IDENTITY_NAMESPACE/$IDENTITY_CONFIGMAP applied"
}

apply_cluster_secret() {
    local cluster env role maturity tailnet project tailnet_flag
    cluster="$(value_of cluster)"; env="$(value_of environment)"; role="$(value_of role)"
    maturity="$(value_of maturity)"; tailnet="$(value_of tailnetNode)"; project="$(value_of gcpProject)"
    tailnet_flag=false; [[ -n "$tailnet" ]] && tailnet_flag=true
    kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    cat <<EOF | kubectl apply -f - >/dev/null || exit 1
apiVersion: v1
kind: Secret
metadata:
  name: in-cluster
  namespace: argo
  labels:
    argocd.argoproj.io/secret-type: cluster
    nordri.siliconsaga.org/cluster: $cluster
    nordri.siliconsaga.org/environment: $env
    nordri.siliconsaga.org/role: $role
    nordri.siliconsaga.org/tailnet: "$tailnet_flag"
  annotations:
    nordri.siliconsaga.org/tailnet-node: "$tailnet"
    nordri.siliconsaga.org/gcp-project: "$project"
    nordri.siliconsaga.org/maturity: "$maturity"
type: Opaque
stringData:
  name: in-cluster
  server: https://kubernetes.default.svc
EOF
    echo "✅ ArgoCD cluster Secret argo/in-cluster labelled for $cluster"
}

# The EnvironmentConfig handover (design, Decision 4 step 2). While ArgoCD still
# tracks the object (label app.kubernetes.io/instance), only annotate it
# Prune=false so the Git removal leaves it in place. Once untracked, strip the
# tracking metadata and write the identity's values.
apply_envconfig() {
    local tracked
    if ! kubectl get crd environmentconfigs.apiextensions.crossplane.io >/dev/null 2>&1; then
        echo "   EnvironmentConfig CRD not installed yet — skipped (re-run apply after Crossplane is up)"; return 0
    fi
    if tracked="$(kubectl get environmentconfig "$IDENTITY_CONFIGMAP" -o 'jsonpath={.metadata.labels.app\.kubernetes\.io/instance}' 2>/dev/null)"; then
        if [[ -n "$tracked" ]]; then
            kubectl annotate environmentconfig "$IDENTITY_CONFIGMAP" argocd.argoproj.io/sync-options=Prune=false --overwrite >/dev/null || exit 1
            echo "   EnvironmentConfig is still tracked by Application '$tracked': marked Prune=false, values untouched. Re-run apply after Git stops carrying it."
            return 0
        fi
        kubectl label environmentconfig "$IDENTITY_CONFIGMAP" app.kubernetes.io/instance- >/dev/null 2>&1 || true
        kubectl annotate environmentconfig "$IDENTITY_CONFIGMAP" argocd.argoproj.io/sync-options- >/dev/null 2>&1 || true
    fi
    {
        echo "apiVersion: apiextensions.crossplane.io/v1beta1"; echo "kind: EnvironmentConfig"
        echo "metadata:"; echo "  name: $IDENTITY_CONFIGMAP"
        echo "  labels:"; echo "    app.kubernetes.io/part-of: nordri"
        echo "data:"
        printf '%s\n' "$RESOLVED" | while IFS='=' read -r k v; do [[ -n "$v" ]] && printf '  %s: %s\n' "$k" "$(jq -nr --arg v "$v" '$v|@json')"; done
    } | kubectl apply -f - >/dev/null || exit 1
    echo "✅ EnvironmentConfig $IDENTITY_CONFIGMAP written from the identity"
}

case "$cmd" in
    show) live_lines ;;
    diff) resolve "$1" "$2"; show_diff ;;
    apply)
        resolve "$1" "$2"
        echo "🪪 identity for cluster '$2' (realm $1):"; show_diff || true
        apply_configmap "$2"
        apply_cluster_secret
        [[ "${IDENTITY_SKIP_ENVCONFIG:-0}" == "1" ]] || apply_envconfig
        ;;
esac
```

- [ ] **Step 4: Run the test.** `bash tests/unit/identity-apply-test.sh` → `ALL PASS`. Add `scripts/identity.sh` to `shell_files` in `tests/run.sh` and run `bash tests/run.sh test` and `bash tests/run.sh lint`.

- [ ] **Step 5: Commit.** Message `feat(identity): identity.sh apply/show/diff with the three projections`, add `scripts/identity.sh tests/unit/identity-apply-test.sh tests/run.sh`.

---

### Task 3: `lib/gitops.sh`, org-aware seed repos, the stable address in nordri (nordri)

**Files:**
- Create: `lib/gitops.sh`
- Modify: `lib/gitea.sh:93-128` (`gitea_ensure_repo` gains an owner)
- Modify: `lib/hydrate.sh:26-39, 44-76, 88-128` (push URLs use the org; vendor mirrors go to the vendor org)
- Modify: `platform/root-app.yaml:11`, `platform/argocd/realm-root-app.template.yaml:5-6,17,19`, `platform/argocd/app-of-apps.yaml:9` (replaced in Task 5), `platform/argocd/nidavellir-apps.yaml:24`, `platform/fundamentals/apps/garage.yaml:11`
- Create: `tests/unit/gitops-test.sh`
- Modify: `tests/unit/gitea-urls-test.sh`, `tests/unit/gitea-install-test.sh` (owner argument)

**Interfaces:**
- Consumes: `GITEA_API_URL`, `GITEA_GIT_BASE`, `GITEA_USER`, `GITEA_PASS` from `lib/gitea.sh`.
- Produces: constants `GIT_STABLE_HOST="git.gitops.svc.cluster.local:3000"`, `GIT_STABLE_BASE="http://$GIT_STABLE_HOST"`, `GIT_SEED_SERVICE="gitea-http.gitea.svc.cluster.local"`, `GIT_FORGEJO_SERVICE="forgejo-http.forgejo.svc.cluster.local"`; functions `gitops_canonical_org <realm>` (prints `${realm#realm-}`), `gitops_vendor_org <realm>` (`<canonical>-vendor`), `gitops_ensure_org <org>` (Gitea/Forgejo `GET/POST /orgs`, idempotent), `gitops_ensure_git_service [externalName]` (ExternalName Service `git` in `gitops`; default target the seed; never changes an existing target unless one is given), `gitops_git_service_target` (prints the current externalName or nothing), `gitops_apply_root_apps <realm>` (renders and applies `nordri-root` and the realm root with the stable address, realm `path: cluster`), `gitops_repo_url <org> <repo>` (`$GIT_STABLE_BASE/<org>/<repo>.git`). `gitea_ensure_repo <owner> <repo> [auto_init]` creates under `/orgs/<owner>/repos`.

- [ ] **Step 1: Write the failing test** `tests/unit/gitops-test.sh`:

```bash
#!/usr/bin/env bash
# Unit test for lib/gitops.sh and the org-aware gitea_ensure_repo: org names,
# the stable address, the idempotent org and Service creation, the root
# Applications rendered with the stable URL and path cluster. curl and kubectl
# are recording stubs.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/lib/gitea.sh"; . "$root/lib/gitops.sh"
fails=0
check() { if eval "$2"; then echo "ok - $1"; else echo "NOT OK - $1"; fails=$((fails+1)); fi; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
LOG="$work/log"; : > "$LOG"; APPLIED="$work/applied"; : > "$APPLIED"

check "canonical org drops the realm- prefix" "[[ \$(gitops_canonical_org realm-siliconsaga) == siliconsaga ]]"
check "vendor org" "[[ \$(gitops_vendor_org realm-siliconsaga) == siliconsaga-vendor ]]"
check "stable repo url" "[[ \$(gitops_repo_url siliconsaga nordri) == http://git.gitops.svc.cluster.local:3000/siliconsaga/nordri.git ]]"

# curl stub: GET /orgs/<x> → 404 the first time, 200 after a POST; POST → 201.
# Prints the status like the real -w '%{http_code}' call does.
declare -A ORGS=()
curl() {
    local method="GET" url="" a
    for a in "$@"; do case "$a" in -X) method=next ;; GET|POST|PATCH|DELETE) [[ $method == next ]] && method=$a ;; http*) url=$a ;; esac; done
    printf '%s %s\n' "$method" "$url" >> "$LOG"
    case "$method $url" in
        "GET "*/api/v1/orgs/*) [[ -n "${ORGS[${url##*/}]:-}" ]] && printf 200 || printf 404 ;;
        "POST "*/api/v1/orgs) ORGS[siliconsaga]=1; ORGS[siliconsaga-vendor]=1; printf 201 ;;
        "POST "*/api/v1/orgs/*/repos) printf 201 ;;
        *) printf 500 ;;
    esac
}
kubectl() {
    printf '%s\n' "$*" >> "$LOG"
    case "$*" in
        *"get service git -n gitops -o jsonpath={.spec.externalName}"*) printf '%s' "${GIT_TARGET:-}" ;;
        *"apply -f -"*) cat >> "$APPLIED" ;;
    esac
    return 0
}
GITEA_USER=nordri-admin GITEA_PASS=pw GITEA_HOST=localhost:3000 GITEA_SCHEME=http; gitea_build_urls

gitops_ensure_org siliconsaga >/dev/null; gitops_ensure_org siliconsaga >/dev/null
check "org created once, then found" "[[ \$(grep -c 'POST .*/api/v1/orgs$' \"\$LOG\") -eq 1 ]]"
gitea_ensure_repo siliconsaga nordri true >/dev/null
check "repo created under the org" "grep -q 'POST .*/api/v1/orgs/siliconsaga/repos' \"\$LOG\""

GIT_TARGET="" gitops_ensure_git_service >/dev/null
check "Service git created pointing at the seed" "grep -q 'externalName: gitea-http.gitea.svc.cluster.local' \"\$APPLIED\""
: > "$APPLIED"; GIT_TARGET="forgejo-http.forgejo.svc.cluster.local" gitops_ensure_git_service >/dev/null
check "an existing target is left alone" "[[ ! -s \"\$APPLIED\" ]]"
: > "$APPLIED"; GIT_TARGET="gitea-http.gitea.svc.cluster.local" gitops_ensure_git_service forgejo-http.forgejo.svc.cluster.local >/dev/null
check "an explicit target repoints" "grep -q 'externalName: forgejo-http.forgejo.svc.cluster.local' \"\$APPLIED\""

: > "$APPLIED"; SCRIPT_DIR="$root" gitops_apply_root_apps realm-siliconsaga >/dev/null
check "nordri root uses the stable address" "grep -q 'repoURL: .http://git.gitops.svc.cluster.local:3000/siliconsaga/nordri.git' \"\$APPLIED\""
check "realm root uses the stable address" "grep -q 'repoURL: .http://git.gitops.svc.cluster.local:3000/siliconsaga/realm-siliconsaga.git' \"\$APPLIED\""
check "realm root path is cluster" "grep -q 'path: cluster' \"\$APPLIED\""
check "no placeholder survives" "! grep -q '__REALM_REPO__' \"\$APPLIED\""
check "no seed URL survives in the applied roots" "! grep -q 'gitea-http' \"\$APPLIED\""
echo "---"; [ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
```

- [ ] **Step 2: Run it to see it fail.** `bash tests/unit/gitops-test.sh` → `lib/gitops.sh: No such file`.

- [ ] **Step 3: Write `lib/gitops.sh`:**

```bash
#!/usr/bin/env bash
# lib/gitops.sh — the pieces of a cluster's GitOps wiring that Git never carries:
# the seed's orgs, the stable in-cluster Git address, and the two bootstrap-owned
# root Applications. Idempotent, so bootstrap.sh, migrate.sh and graduate.sh all
# call it. Realm Phase 3 design, Decisions 2 and 5.
#
# Requires lib/gitea.sh sourced first (GITEA_API_URL, GITEA_USER, GITEA_PASS).

GIT_STABLE_HOST="git.gitops.svc.cluster.local:3000"
GIT_STABLE_BASE="http://$GIT_STABLE_HOST"
GIT_SEED_SERVICE="gitea-http.gitea.svc.cluster.local"
GIT_FORGEJO_SERVICE="forgejo-http.forgejo.svc.cluster.local"
GITOPS_NAMESPACE="gitops"

# Decision 2, rule 5: the canonical org keeps the realm's bare name; every other
# class is <realm>-<class>. "realm-siliconsaga" → "siliconsaga".
gitops_canonical_org() { printf '%s' "${1#realm-}"; }
gitops_vendor_org() { printf '%s-vendor' "$(gitops_canonical_org "$1")"; }
gitops_repo_url() { printf '%s/%s/%s.git' "$GIT_STABLE_BASE" "$1" "$2"; }

# Same API on Gitea and Forgejo. Credentials go through -u, never the URL.
gitops_ensure_org() {
    local org="$1" status body
    status=$(curl -sS -o /dev/null -w '%{http_code}' -u "$GITEA_USER:$GITEA_PASS" -X GET "$GITEA_API_URL/api/v1/orgs/$org") || status=000
    case "$status" in
        200) echo "   org $org: present"; return 0 ;;
        404) ;;
        *) echo "❌ GET /orgs/$org returned HTTP $status" >&2; return 1 ;;
    esac
    body=$(jq -n --arg u "$org" '{username: $u, visibility: "public", repo_admin_change_team_access: false}')
    status=$(curl -sS -o /dev/null -w '%{http_code}' -u "$GITEA_USER:$GITEA_PASS" -X POST "$GITEA_API_URL/api/v1/orgs" \
        -H 'Content-Type: application/json' -d "$body") || status=000
    [[ "$status" == 201 ]] && { echo "   org $org: created"; return 0; }
    echo "❌ creating org $org returned HTTP $status" >&2; return 1
}

gitops_git_service_target() {
    kubectl get service git -n "$GITOPS_NAMESPACE" -o 'jsonpath={.spec.externalName}' 2>/dev/null | tr -d '\r'
}

# Create the Service pointing at the seed when it does not exist. With an
# argument, (re)point it there — graduate.sh's repoint and rollback. Never
# synced by ArgoCD, so nothing self-heals it back.
gitops_ensure_git_service() {
    local target="${1:-}" current
    current="$(gitops_git_service_target)"
    if [[ -z "$target" ]]; then
        if [[ -n "$current" ]]; then echo "   Service $GITOPS_NAMESPACE/git → $current (unchanged)"; return 0; fi
        target="$GIT_SEED_SERVICE"
    elif [[ "$current" == "$target" ]]; then
        echo "   Service $GITOPS_NAMESPACE/git already → $target"; return 0
    fi
    kubectl create namespace "$GITOPS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    cat <<EOF | kubectl apply -f - >/dev/null || return 1
apiVersion: v1
kind: Service
metadata:
  name: git
  namespace: $GITOPS_NAMESPACE
  labels:
    app.kubernetes.io/part-of: nordri
  annotations:
    nordri.siliconsaga.org/repointed-at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
spec:
  type: ExternalName
  externalName: $target
  ports:
    - name: http
      port: 3000
      targetPort: 3000
EOF
    echo "   Service $GITOPS_NAMESPACE/git → $target"
}

# The two Applications bootstrap owns. Git never updates them, so every script
# that changes what they should say re-applies them through here.
gitops_apply_root_apps() {
    local realm="$1" org dir
    org="$(gitops_canonical_org "$realm")"
    dir="$(mktemp -d)"
    sed "s|__NORDRI_REPO_URL__|$(gitops_repo_url "$org" nordri)|g" "$SCRIPT_DIR/platform/root-app.yaml" > "$dir/root-app.yaml"
    sed -e "s|__REALM_REPO__|$realm|g" -e "s|__REALM_REPO_URL__|$(gitops_repo_url "$org" "$realm")|g" \
        "$SCRIPT_DIR/platform/argocd/realm-root-app.template.yaml" > "$dir/realm-root-app.yaml"
    if grep -q '__[A-Z_]*__' "$dir/root-app.yaml" "$dir/realm-root-app.yaml"; then
        echo "❌ a placeholder survived in the root Applications" >&2; rm -rf "$dir"; return 1
    fi
    kubectl apply -n argo -f "$dir/root-app.yaml" >/dev/null || { rm -rf "$dir"; return 1; }
    kubectl apply -n argo -f "$dir/realm-root-app.yaml" >/dev/null || { rm -rf "$dir"; return 1; }
    rm -rf "$dir"
    echo "   root Applications nordri-root and $realm applied (stable address, realm path cluster)"
}
```

- [ ] **Step 4: Make `gitea_ensure_repo` org-aware.** In `lib/gitea.sh` replace the function's first line and the POST target:

```bash
gitea_ensure_repo() {
    local owner=$1 repo_name=$2 auto_init=${3:-false}
    ...
            -X POST "$GITEA_API_URL/api/v1/orgs/$owner/repos" \
```

and the error text to name `$owner/$repo_name`. In `lib/hydrate.sh`: `hydrate_push_tree dir owner repo msg` uses `"$GITEA_GIT_BASE/$owner/$gitea_repo.git"`; `hydrate_working_tree_repo src_dir owner repo msg` drops the `patch_fn` argument and the `patch_repo_urls_tree` call entirely (the Task 4 deletions), and calls `gitea_ensure_repo "$owner" "$gitea_repo" "${HYDRATE_AUTO_INIT:-false}"`; `hydrate_vendor_mirrors owner mirrors` pushes to `"$GITEA_GIT_BASE/$owner/$vendor.git"`. Every call site is rewritten in Task 4.

- [ ] **Step 5: The root manifests carry placeholders, not seed URLs.** `platform/root-app.yaml:11` becomes `repoURL: '__NORDRI_REPO_URL__'`; `platform/argocd/realm-root-app.template.yaml`: lines 5–6 become `# The seed's realm repository holds the WHOLE realm checkout, as Forgejo's mirror does, so path is "cluster" (Phase 3 design, Decision 5).`, line 17 `repoURL: '__REALM_REPO_URL__'`, line 19 `path: cluster`. The `nordri-root` Application already excludes `*.template.yaml`; `root-app.yaml` is never synced by Git either (it is applied by bootstrap), but the nordri repo is hydrated whole, so keep `root-app.yaml` outside `platform/argocd/` as it is today. Rename the three plain in-cluster URLs: `platform/argocd/nidavellir-apps.yaml:24` and `platform/fundamentals/apps/garage.yaml:11` to `'http://git.gitops.svc.cluster.local:3000/siliconsaga/<repo>.git'` (`nidavellir`, `nordri`); `app-of-apps.yaml` is rewritten in Task 5.

- [ ] **Step 6: Update the two existing tests.** `tests/unit/gitea-urls-test.sh` and `gitea-install-test.sh` call `gitea_ensure_repo` nowhere, but assert `nordri-admin` as the admin user, which stays (the seed's admin account is unchanged; only repo ownership moves to orgs). Add to `gitea-urls-test.sh` one assertion that a push base plus org renders `…@localhost:3000/siliconsaga/nordri.git` when composed as `hydrate_push_tree` does.

- [ ] **Step 7: Run.** `bash tests/unit/gitops-test.sh` → `ALL PASS`; `bash tests/run.sh test`.

- [ ] **Step 8: Commit.** Message `feat(gitops): seed orgs, the stable git Service, root apps with the stable address`, add `lib/gitops.sh lib/gitea.sh lib/hydrate.sh platform/root-app.yaml platform/argocd/realm-root-app.template.yaml platform/argocd/nidavellir-apps.yaml platform/fundamentals/apps/garage.yaml tests/unit/gitops-test.sh tests/unit/gitea-urls-test.sh`.

---

### Task 4: `bootstrap.sh <realm> <cluster>`, `update-embedded-git.sh <realm>`, the deletions (nordri)

**Files:**
- Modify: `bootstrap.sh` (header 4–74; sources 90–98; args and guard 99–167; identity before Layer 0; seed section 281–388; hydration 391–505; ArgoCD install 624–636; root apps 675–696)
- Modify: `update-embedded-git.sh` (56–62, 63–99, 246–314)
- Modify: `scripts/reseed-gitea.sh:1-45` (argument becomes `<realm> <cluster>`; context guard from the resolved environment)
- Delete: `lib/patch-urls.sh`, `lib/patch-velero.sh`, `lib/patch-nidavellir.sh`, `lib/patch-mimir.sh`, `envs/`, `tests/unit/patch-urls-test.sh`, `tests/unit/patch-velero-test.sh`, `tests/unit/patch-nidavellir-test.sh`, `tests/unit/patch-mimir-test.sh`
- Modify: `lib/kube-context.sh` (no contract change; the comment says the argument is the resolved environment)
- Modify: `platform/fundamentals/apps/argocd.yaml:36-48` (policy override), `tests/run.sh:7`, `CLAUDE.md`, `README.md`, `docs/bootstrap.md`, `.agent/skills/nordri/SKILL.md` (usage strings)
- Create: `tests/unit/bootstrap-args-test.sh`

**Interfaces:**
- Consumes: Task 1–3 functions.
- Produces: `./bootstrap.sh <realm> <cluster>`; `./update-embedded-git.sh <realm> [--target forgejo]` (target defaults to whatever the `git` Service points at; refused on a graduated `prod` cluster; `--target forgejo` refused on `prod`); `scripts/reseed-gitea.sh <realm> <cluster>`; environment variables `GITEA_HOST`, `GITEA_SCHEME`, `GITEA_PASS`, `KUBE_CONTEXT`, `REALM_DIR`, `NIDAVELLIR_DIR`, `MIMIR_DIR`, `HEIMDALL_DIR`, `VENDOR_MIRRORS` unchanged; `HYDRATE_URL_MODE`, `GCP_PROJECT` gone. Every hydration commit carries a `Source-Commit: <sha>` trailer (read by `graduate.sh` in Task 16).

- [ ] **Step 1: Write the failing test** `tests/unit/bootstrap-args-test.sh`. Bootstrap cannot run under test, so this tests the shape: usage, the argument order, the absence of the deleted libraries and placeholders, and that the hydration scripts no longer carry a `sed` on manifests:

```bash
#!/usr/bin/env bash
# Shape test for Phase 3a's bootstrap and update scripts: the <realm> <cluster>
# contract, no patch libraries, no overlay sed, no envs copy, the identity
# written first, the policy override in both ArgoCD install places.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
fails=0
check() { if eval "$2"; then echo "ok - $1"; else echo "NOT OK - $1"; fails=$((fails+1)); fi; }
out=$(bash "$root/bootstrap.sh" 2>&1); rc=$?
check "bootstrap without args exits 1" "[[ $rc -eq 1 ]]"
check "bootstrap usage names realm and cluster" "[[ \"\$out\" == *'bootstrap.sh <realm> <cluster>'* ]]"
out=$(bash "$root/update-embedded-git.sh" 2>&1); rc=$?
check "update without args exits 1" "[[ $rc -eq 1 ]]"
check "update usage names the realm and --target" "[[ \"\$out\" == *'update-embedded-git.sh <realm> [--target forgejo]'* ]]"
for lib in patch-urls patch-velero patch-nidavellir patch-mimir; do
    check "lib/$lib.sh is gone" "[[ ! -e \"$root/lib/$lib.sh\" ]]"
done
check "envs/ is gone" "[[ ! -d \"$root/envs\" ]]"
for f in bootstrap.sh update-embedded-git.sh lib/hydrate.sh; do
    check "$f has no manifest sed" "! grep -q 'sed -i' \"$root/$f\""
    check "$f sources no patch lib" "! grep -q 'lib/patch-' \"$root/$f\""
done
check "bootstrap writes the identity first" "[[ \$(grep -n 'scripts/identity.sh apply' \"$root/bootstrap.sh\" | head -1 | cut -d: -f1) -lt \$(grep -n 'gitea_install_seed' \"$root/bootstrap.sh\" | head -1 | cut -d: -f1) ]]"
check "bootstrap enables the ApplicationSet policy override" "grep -q 'applicationsetcontroller\\\\.enable\\\\.policy\\\\.override' \"$root/bootstrap.sh\""
check "the argocd Application enables it too" "grep -q 'applicationsetcontroller.enable.policy.override: \"true\"' \"$root/platform/fundamentals/apps/argocd.yaml\""
check "no __GCP_PROJECT__ anywhere in platform/" "! grep -rq '__GCP_PROJECT__' \"$root/platform\""
check "hydration commits carry a Source-Commit trailer" "grep -q 'Source-Commit:' \"$root/lib/hydrate.sh\""
echo "---"; [ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
```

- [ ] **Step 2: Run it to see it fail** (`bash tests/unit/bootstrap-args-test.sh`): usage, libs and sed checks all NOT OK.

- [ ] **Step 3: Rewrite the argument block of `bootstrap.sh`** (replaces lines 99–167). Keep every variable the rest of the script reads; `TARGET` survives as the resolved **environment**, so the environment-specific layers (0b, 2.9, 5) keep working unchanged:

```bash
REALM="${1:-}"; CLUSTER="${2:-}"
if [[ -z "$REALM" || -z "$CLUSTER" ]]; then
    echo "Usage: ./bootstrap.sh <realm> <cluster>"
    echo "  <realm>   the owning realm (its checkout at ../../realms/<realm>, or REALM_DIR)"
    echo "  <cluster> this cluster's name, e.g. homelab-prod, homelab-test, gke-prod, homelab-<hostname>"
    echo "  A cluster with no clusters/<cluster>.yaml in the realm is a homelab lab at bootstrap maturity."
    exit 1
fi
for v in "$REALM" "$CLUSTER"; do
    if [[ ! "$v" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || [[ ${#v} -gt 63 ]]; then
        echo "❌ '$v' must be a DNS-1123 label (lowercase alphanumeric and '-', max 63 chars)." >&2; exit 1
    fi
done
REALM_DIR="${REALM_DIR:-$(dirname "$(dirname "$SCRIPT_DIR")")/realms/$REALM}"
if [[ ! -d "$REALM_DIR/cluster" ]]; then
    echo "❌ Realm '$REALM' has no cluster/ config at: $REALM_DIR/cluster (set REALM_DIR or clone the realm)." >&2; exit 1
fi
# Resolve the identity now: the environment it yields drives the context guard
# and every environment-specific layer below. Nothing is written yet.
IDENTITY="$(IDENTITY_LIVE_TAILNET="$(identity_live_value tailnetNode)" identity_resolve "$REALM_DIR" "$CLUSTER")" || exit 1
TARGET="$(printf '%s\n' "$IDENTITY" | sed -n 's/^environment=//p')"
MATURITY="$(printf '%s\n' "$IDENTITY" | sed -n 's/^maturity=//p')"
ROLE="$(printf '%s\n' "$IDENTITY" | sed -n 's/^role=//p')"
GITOPS_ORG="$(gitops_canonical_org "$REALM")"
GITOPS_VENDOR_ORG="$(gitops_vendor_org "$REALM")"
echo "🪪 cluster $CLUSTER: environment=$TARGET role=$ROLE maturity=$MATURITY (realm $REALM)"

# Every kubectl below follows the kubeconfig's current context, not the ws k8s
# guard scope — refuse now if that context does not fit the environment.
require_kube_context "$TARGET" || exit 1
```

Sources (lines 90–98) become `gitea.sh hydrate.sh identity.sh gitops.sh openbao.sh kube-context.sh garage.sh`. Delete `HYDRATE_URL_MODE` and `GCP_PROJECT` from the header comment; document `<realm> <cluster>`.

- [ ] **Step 4: Write the identity before Layer 0.** Immediately after the `jq` check (old line 173) add:

```bash
echo "🪪 [Layer -1] Writing the cluster identity..."
IDENTITY_SKIP_ENVCONFIG=1 REALM_DIR="$REALM_DIR" bash "$SCRIPT_DIR/scripts/identity.sh" apply "$REALM" "$CLUSTER" || exit 1
```

and after Crossplane's readiness loop (after old line ~555, Layer 2.5) add the second call without the skip, so the EnvironmentConfig exists before the providers' configs reference it:

```bash
REALM_DIR="$REALM_DIR" bash "$SCRIPT_DIR/scripts/identity.sh" apply "$REALM" "$CLUSTER" || exit 1
```

- [ ] **Step 5: Seed orgs and the hydration without stamping.** After `gitea_wait_ready 300 || exit 1` and the port-forward block, replace lines 433–505 with:

```bash
gitops_ensure_org "$GITOPS_ORG" || exit 1
gitops_ensure_org "$GITOPS_VENDOR_ORG" || exit 1
gitops_ensure_git_service || exit 1

# nordri itself: the platform/ tree and root-app.yaml, verbatim. No overlay
# sed, no project stamp, no envs/ — every per-cluster value is in the identity.
hydrate_working_tree_repo "$SCRIPT_DIR" "$GITOPS_ORG" "$GITEA_REPO_NAME" "Hydration of nordri"
hydrate_working_tree_repo "$NIDAVELLIR_DIR" "$GITOPS_ORG" "$NIDAVELLIR_GITEA_REPO" "Hydration of nidavellir"
hydrate_working_tree_repo "$MIMIR_DIR" "$GITOPS_ORG" "$MIMIR_GITEA_REPO" "Hydration of mimir"
hydrate_working_tree_repo "$HEIMDALL_DIR" "$GITOPS_ORG" "$HEIMDALL_GITEA_REPO" "Hydration of heimdall"
hydrate_vendor_mirrors "$GITOPS_VENDOR_ORG" "$VENDOR_MIRRORS"
# The whole realm checkout, so the seed's realm repository has the same shape
# as Forgejo's mirror and the realm root Application reads path cluster.
hydrate_working_tree_repo "$REALM_DIR" "$GITOPS_ORG" "$REALM" "Hydration of $REALM"
```

`hydrate_working_tree_repo` (Task 3) now copies the whole source tree minus `.git`, so nordri's own hydrate is the same call as the others and the special-cased copy (old 439–478) is deleted. In `hydrate_push_tree`, the commit records its source: before `git commit`, compute `src_sha="$(git -C "$src_dir" rev-parse HEAD 2>/dev/null || echo unknown)"` in the caller and pass it; commit with `git commit -q -m "$commit_msg" -m "Source-Commit: $src_sha"`.

- [ ] **Step 6: ArgoCD policy override, both places.** Add to the helm install (after `--set controller.metrics.enabled=true`):

```bash
  --set configs.params."applicationsetcontroller\.enable\.policy\.override"=true \
```

and in `platform/fundamentals/apps/argocd.yaml` values, after `controller:` block:

```yaml
        configs:
          cm:
            kustomize.buildOptions: --load-restrictor LoadRestrictionsNone --enable-helm
          params:
            # ApplicationSets set applicationsSync: create-update so a generator
            # that matches nothing cannot delete an Application (Phase 3 design,
            # Decision 4). The controller ignores that field unless this is on.
            applicationsetcontroller.enable.policy.override: "true"
```

(merge into the existing `configs:` map; keep the header comment's "keep the two in step" rule.)

- [ ] **Step 7: Root Applications through the library.** Replace lines 675–696 with:

```bash
echo "🌱 [Layer 4] Applying the root Applications..."
gitops_apply_root_apps "$REALM" || exit 1
```

The realm is no longer optional anywhere in the script; delete every `if [[ -n "$REALM" ]]` guard.

- [ ] **Step 8: `update-embedded-git.sh`.** Arguments: `<realm> [--target forgejo]`. After sourcing `gitea.sh hydrate.sh identity.sh gitops.sh kube-context.sh`:

```bash
REALM="${1:-}"; TARGET_SERVER="service"
[[ -n "$REALM" ]] || { echo "Usage: ./update-embedded-git.sh <realm> [--target forgejo]"; exit 1; }
shift
while [[ $# -gt 0 ]]; do case "$1" in
    --target) TARGET_SERVER="${2:-}"; shift 2 ;;
    *) echo "❌ unknown argument '$1'" >&2; exit 1 ;;
esac; done
CLUSTER="$(identity_live_value cluster)"; ROLE="$(identity_live_value role)"; TARGET="$(identity_live_value environment)"
[[ -n "$CLUSTER" && -n "$TARGET" ]] || { echo "❌ no cluster identity on this cluster (ConfigMap nordri/cluster-identity). Bootstrap or migrate it first." >&2; exit 1; }
require_kube_context "$TARGET" || exit 1
GITOPS_ORG="$(gitops_canonical_org "$REALM")"; GITOPS_VENDOR_ORG="$(gitops_vendor_org "$REALM")"
git_target="$(gitops_git_service_target)"
case "$TARGET_SERVER" in
    service)
        if [[ "$git_target" == "$GIT_FORGEJO_SERVICE" ]]; then
            if [[ "$ROLE" == "prod" ]]; then
                echo "❌ cluster $CLUSTER has graduated: its Forgejo is written only by its puller. Change GitHub instead." >&2; exit 1
            fi
            TARGET_SERVER=forgejo
        else
            TARGET_SERVER=seed
        fi ;;
    forgejo)
        [[ "$ROLE" != "prod" ]] || { echo "❌ --target forgejo is refused on a prod cluster ($CLUSTER)." >&2; exit 1; } ;;
    seed) ;;
    *) echo "❌ --target must be forgejo (or omitted)" >&2; exit 1 ;;
esac
echo "🎯 pushing to the $TARGET_SERVER on cluster $CLUSTER (git Service → ${git_target:-unset})"
```

For `TARGET_SERVER=forgejo` the push goes to Forgejo's HTTP Service: port-forward `svc/forgejo-http -n forgejo 3000:3000` instead of the seed's, with `GITEA_USER="$(kubectl get secret -n forgejo forgejo-admin -o jsonpath='{.data.username}' | base64 -d)"` and `GITEA_PASS` from the same Secret's `password`; the existing seed-credential block runs only for `seed`. The push section (old 246–314) becomes the same seven `hydrate_*` calls as bootstrap step 5 with messages `"Update of <repo>"`, and the trailing hard refresh stays. Delete the inline nordri push and the `envs` copy.

- [ ] **Step 9: `scripts/reseed-gitea.sh <realm> <cluster>`:** replace the `TARGET` parsing with the Task 3 resolve (`identity_resolve` to get the environment, since the seed may be gone), keep the rest. Its closing hint becomes `./update-embedded-git.sh <realm>`.

- [ ] **Step 10: Delete** the four `lib/patch-*.sh`, the four `tests/unit/patch-*-test.sh`, and `envs/`. Update `tests/run.sh` `shell_files` (add `scripts/identity.sh`; nothing else changes since `lib/*.sh` is a glob). Update the usage strings in `CLAUDE.md` (`./update-embedded-git.sh realm-siliconsaga`, `scripts/reseed-gitea.sh realm-siliconsaga <cluster>`), `README.md`, `docs/bootstrap.md`, `.agent/skills/nordri/SKILL.md`; the GKE pin sentence in `CLAUDE.md` loses `GITEA_SCHEME`-irrelevant `gke` arguments: `KUBE_CONTEXT=gke_<project>_<zone>_<cluster> GITEA_HOST=gitea.cmdbee.org GITEA_SCHEME=https ./update-embedded-git.sh realm-siliconsaga`.

- [ ] **Step 11: Run.** `bash tests/unit/bootstrap-args-test.sh` → `ALL PASS`; `bash tests/run.sh test`; `bash tests/run.sh lint` (shellcheck must be clean on the rewritten scripts).

- [ ] **Step 12: Commit.** Message `feat(bootstrap): <realm> <cluster>, identity first, generic hydration, no stamping`, add every file above (deletions included via `git rm`, which `ws commit`'s `add:` list stages when the paths are listed).

---

### Task 5: nordri's two ApplicationSets, the identity manifests leave Git, `docs/cluster-identity.md` (nordri)

**Files:**
- Modify: `platform/argocd/app-of-apps.yaml` (becomes an ApplicationSet)
- Modify: `platform/fundamentals/apps/velero-gke.yaml` (becomes an ApplicationSet; prefix; project from the identity)
- Delete: `platform/fundamentals/manifests/cluster-identity-gke.yaml`, `platform/fundamentals/manifests/cluster-identity-homelab.yaml`
- Modify: `platform/fundamentals/overlays/gke/kustomization.yaml:17`, `platform/fundamentals/overlays/homelab/kustomization.yaml:22` (drop the identity manifests)
- Create: `tests/unit/appset-guards-test.sh`
- Rewrite: `docs/cluster-identity.md`

**Interfaces:**
- Consumes: cluster Secret labels/annotations from Task 2.
- Produces: ApplicationSet `layer4-fundamentals` generating Application `layer4-fundamentals` with `path: platform/fundamentals/overlays/<environment>`; ApplicationSet `velero` generating Application `velero` on gke only (selector `nordri.siliconsaga.org/environment: gke`), with `backupStorageLocation[0].prefix: <cluster>` and every `__GCP_PROJECT__` replaced by the `gcp-project` annotation. Both: `goTemplate: true`, `goTemplateOptions: ["missingkey=error"]`, `syncPolicy.preserveResourcesOnDeletion: true`, `syncPolicy.applicationsSync: create-update`.

- [ ] **Step 1: Write the failing test** `tests/unit/appset-guards-test.sh` — every `index .metadata.(labels|annotations) "<key>"` in any ApplicationSet of this repo must be preceded in the same template by a `fail` guard on the same key, and every ApplicationSet carries the two safety settings:

```bash
#!/usr/bin/env bash
# Every identity lookup in an ApplicationSet template is guarded (index on a
# missing key yields "", which would render a path like overlays/), and every
# ApplicationSet carries the two settings that keep an empty generator from
# deleting anything. Realm Phase 3 design, Decision 4.
set -uo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
fails=0
check() { if eval "$2"; then echo "ok - $1"; else echo "NOT OK - $1"; fails=$((fails+1)); fi; }
files=$(grep -rl '^kind: ApplicationSet' "$root/platform")
check "there are ApplicationSets" "[[ -n \"\$files\" ]]"
for f in $files; do
    rel="${f#"$root"/}"
    check "$rel: goTemplate" "grep -q 'goTemplate: true' \"$f\""
    check "$rel: missingkey=error" "grep -q 'missingkey=error' \"$f\""
    check "$rel: preserveResourcesOnDeletion" "grep -q 'preserveResourcesOnDeletion: true' \"$f\""
    check "$rel: applicationsSync create-update" "grep -q 'applicationsSync: create-update' \"$f\""
    for key in $(grep -o 'index .metadata.[a-z]* "nordri.siliconsaga.org/[a-z-]*"' "$f" | grep -o '"nordri[^"]*"' | sort -u); do
        check "$rel: $key is guarded" "grep -q \"if not (index .metadata.[a-z]* $key)\" \"$f\""
    done
done
check "no identity manifest left in platform/" "! ls \"$root\"/platform/fundamentals/manifests/cluster-identity-*.yaml 2>/dev/null | grep -q ."
echo "---"; [ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
```

- [ ] **Step 2: Run it to see it fail:** "there are ApplicationSets" NOT OK.

- [ ] **Step 3: Replace `platform/argocd/app-of-apps.yaml`:**

```yaml
# Layer 4 fundamentals, as an ApplicationSet (realm Phase 3 design, Decision 4).
# One cluster, one Application — the cluster generator reads the identity that
# scripts/identity.sh projects onto ArgoCD's in-cluster Secret, so the overlay
# is chosen by the cluster, not stamped into Git at hydration.
#
# Every identity lookup is guarded with fail: index on a missing key renders ""
# (missingkey=error does not cover it), and "overlays/" would deploy nothing.
# preserveResourcesOnDeletion + applicationsSync create-update: a generator
# that matches nothing (a deleted label, a typo) cannot delete the Application
# or what it deployed. The controller honours applicationsSync only with
# applicationsetcontroller.enable.policy.override on, set in bootstrap.sh and
# apps/argocd.yaml.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: layer4-fundamentals
  namespace: argo
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  syncPolicy:
    preserveResourcesOnDeletion: true
    applicationsSync: create-update
  generators:
    - clusters:
        selector:
          matchExpressions:
            - {key: nordri.siliconsaga.org/cluster, operator: Exists}
  template:
    metadata:
      name: layer4-fundamentals
      namespace: argo
    spec:
      project: default
      source:
        repoURL: 'http://git.gitops.svc.cluster.local:3000/siliconsaga/nordri.git'
        targetRevision: HEAD
        path: '{{ if not (index .metadata.labels "nordri.siliconsaga.org/environment") }}{{ fail "identity: environment label missing on the in-cluster Secret" }}{{ end }}platform/fundamentals/overlays/{{ index .metadata.labels "nordri.siliconsaga.org/environment" }}'
      destination:
        server: https://kubernetes.default.svc
        namespace: argo
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - SkipDryRunOnMissingResource=true
          - ServerSideApply=true
```

- [ ] **Step 4: Replace `platform/fundamentals/apps/velero-gke.yaml`.** Keep the whole Helm values block as it is today, with these changes inside the template: wrap it as an ApplicationSet whose generator selects `nordri.siliconsaga.org/environment: gke`; open the values with the guard; replace the four `__GCP_PROJECT__` with `{{ $project }}`; add `prefix`. The head of the file:

```yaml
# Velero for GKE as an ApplicationSet: rendered only on a cluster whose identity
# says environment gke, with the project and the per-cluster prefix read from the
# identity (realm Phase 3 design, Decision 4). Nothing project-specific is
# committed, and two clusters in one project never share a backup path.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: velero
  namespace: argo
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  syncPolicy:
    preserveResourcesOnDeletion: true
    applicationsSync: create-update
  generators:
    - clusters:
        selector:
          matchLabels:
            nordri.siliconsaga.org/environment: gke
  template:
    metadata:
      name: velero
      namespace: argo
    spec:
      project: default
      source:
        repoURL: 'https://vmware-tanzu.github.io/helm-charts'
        chart: velero
        targetRevision: 11.3.1 # Corresponds to Velero v1.17.1
        helm:
          values: |
            {{- if not (index .metadata.annotations "nordri.siliconsaga.org/gcp-project") }}{{ fail "identity: gcp-project annotation missing on the in-cluster Secret" }}{{ end }}
            {{- if not (index .metadata.labels "nordri.siliconsaga.org/cluster") }}{{ fail "identity: cluster label missing on the in-cluster Secret" }}{{ end }}
            {{- $project := index .metadata.annotations "nordri.siliconsaga.org/gcp-project" }}
            {{- $cluster := index .metadata.labels "nordri.siliconsaga.org/cluster" }}
            upgradeCRDs: false
            ...
            serviceAccount:
              server:
                annotations:
                  iam.gke.io/gcp-service-account: velero@{{ $project }}.iam.gserviceaccount.com
            configuration:
              backupStorageLocation:
                - name: default
                  provider: gcp
                  bucket: {{ $project }}-velero
                  # Per-cluster prefix: gke-prod/ holds this cluster's backups,
                  # a gke-test never writes beside them. The 3b-4 sequence
                  # copies the pre-existing root-level backups under it first.
                  prefix: {{ $cluster }}
                  config:
                    serviceAccount: velero@{{ $project }}.iam.gserviceaccount.com
              volumeSnapshotLocation:
                - name: default
                  provider: gcp
                  config:
                    project: {{ $project }}
            ...
```

The `finalizers:` block is dropped (Decision 4: the generated Application carries none; migration step 1 removes it from the live object). Everything after `credentials:` is unchanged. Indent the whole values body by the extra template nesting.

- [ ] **Step 5: Delete the identity manifests** and their two overlay lines (`overlays/gke/kustomization.yaml:17` `../../manifests/cluster-identity-gke.yaml`; `overlays/homelab/kustomization.yaml:22` `../../manifests/cluster-identity-homelab.yaml`). `kubectl kustomize platform/fundamentals/overlays/gke` and `.../homelab` must both still build (run them).

- [ ] **Step 6: Rewrite `docs/cluster-identity.md`** for the cluster-local model: the ConfigMap, the three layers with a worked example (`clusters/homelab-prod.yaml`), the two projections and what reads each (compositions read the EnvironmentConfig; ApplicationSets read the Secret's labels/annotations), the lab default, the name guard, `tailnetNode` rules (prod = cluster name; `stamped` for lab/test; empty = no operator), graduation as "edit the realm file, merge, `identity.sh apply`", and the removal of the old "bootstrap.sh always produces a bootstrap cluster" claim, replaced by "a cluster with no realm file is a bootstrap lab".

- [ ] **Step 7: Run** `bash tests/unit/appset-guards-test.sh` → `ALL PASS`; `bash tests/run.sh test`.

- [ ] **Step 8: Commit.** Message `feat(argocd): layer4 and velero as ApplicationSets reading the cluster identity`, add the files above.

---

### Task 6: nidavellir ApplicationSets, finalizers, the GCP values, URL renames (nidavellir)

**Files:**
- Modify: `apps/vegvisir-app.yaml`, `apps/tailscale-operator-app.yaml` (become ApplicationSets)
- Modify: `apps/ntfy-app.yaml:32`, `apps/forgejo-app.yaml:30`, `apps/keycloak-app.yaml:26`, `apps/openbao-app.yaml:27`, `apps/harbor-app.yaml:36`, `apps/mimir-app.yaml:24`, `apps/heimdall-app.yaml:26`, `apps/demicracy-apps.yaml:28` (URL rename), `apps/keycloak-operator-app.yaml:28` (vendor org)
- Modify: `apps/kustomization.yaml:8-14` (comment)
- Modify: `vegvisir/manifests/base/cert-manager-app.yaml:26-31` (annotation leaves base), `vegvisir/manifests/overlays/gke/letsencrypt-dns01.yaml:42` (placeholder value replaced by the patch)
- Create: `tests/render/check-appsets.sh`

**Interfaces:**
- Consumes: the cluster Secret labels/annotations (Task 2).
- Produces: ApplicationSet `vegvisir` → Application `vegvisir` with `path: vegvisir/manifests/overlays/<environment>` and, on gke, `kustomize.patches` setting the ClusterIssuer's `cloudDNS.project` and the cert-manager Application's SA annotation to `<gcp-project>`; ApplicationSet `tailscale-operator` → Application `tailscale-operator` only where label `nordri.siliconsaga.org/tailnet: "true"`, `operatorConfig.hostname: tailscale-operator-<tailnet-node>`.

- [ ] **Step 1: Write the failing render check** `tests/render/check-appsets.sh` (same style as the other checks; this one needs no Docker): it `kubectl kustomize apps` and asserts shape:

```bash
#!/usr/bin/env bash
# Shape check for the apps/ directory after the Phase 3a conversion: two
# ApplicationSets with guarded identity lookups and the two safety settings, no
# seed URL, no MACHINE placeholder, the vendor pin in the vendor org, and the
# finalizer gone from the two converted apps. Run from the nidavellir root.
set -euo pipefail
fail=0
check() { if grep -Fq -- "$3" "$2"; then found=yes; else found=no; fi; [[ "$found" == "$1" ]] || { echo "FAIL: expected $3 present=$1" >&2; fail=1; }; }
tmp=$(mktemp "${TMPDIR:-/tmp}/apps.XXXXXX"); trap 'rm -f "$tmp"' EXIT
kubectl kustomize apps > "$tmp"
check yes "$tmp" 'kind: ApplicationSet'
check no  "$tmp" 'gitea-http.gitea.svc.cluster.local'
check no  "$tmp" 'nordri-admin'
check no  "$tmp" 'MACHINE'
check no  "$tmp" 'teralivekubernetes'
check yes "$tmp" 'http://git.gitops.svc.cluster.local:3000/siliconsaga-vendor/keycloak-k8s-resources.git'
check yes "$tmp" 'applicationsSync: create-update'
check yes "$tmp" 'preserveResourcesOnDeletion: true'
check yes "$tmp" 'nordri.siliconsaga.org/tailnet: "true"'
check yes "$tmp" 'fail "identity: environment label missing'
check yes "$tmp" 'fail "identity: tailnet-node annotation missing'
check yes "$tmp" 'fail "identity: gcp-project annotation missing'
for f in apps/vegvisir-app.yaml apps/tailscale-operator-app.yaml; do
    grep -q 'resources-finalizer' "$f" && { echo "FAIL: $f still carries the finalizer" >&2; fail=1; }
done
grep -q 'teralivekubernetes' vegvisir/manifests/base/cert-manager-app.yaml && { echo "FAIL: project still in base" >&2; fail=1; }
[[ $fail -eq 0 ]] && echo "appset shape checks: PASS"; exit $fail
```

- [ ] **Step 2: Run it to see it fail** (`bash tests/render/check-appsets.sh`): ApplicationSet absent, seed URLs present.

- [ ] **Step 3: `apps/vegvisir-app.yaml` as an ApplicationSet** (keep the header comment's substance, drop the hydration sentences):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: vegvisir
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  syncPolicy:
    preserveResourcesOnDeletion: true
    applicationsSync: create-update
  generators:
    - clusters:
        selector:
          matchExpressions:
            - {key: nordri.siliconsaga.org/cluster, operator: Exists}
  template:
    metadata:
      name: vegvisir
      namespace: argo
      annotations:
        argocd.argoproj.io/sync-wave: "5"
    spec:
      project: default
      source:
        repoURL: 'http://git.gitops.svc.cluster.local:3000/siliconsaga/nidavellir.git'
        targetRevision: HEAD
        path: '{{ if not (index .metadata.labels "nordri.siliconsaga.org/environment") }}{{ fail "identity: environment label missing on the in-cluster Secret" }}{{ end }}vegvisir/manifests/overlays/{{ index .metadata.labels "nordri.siliconsaga.org/environment" }}'
      destination:
        server: https://kubernetes.default.svc
        namespace: kube-system
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - SkipDryRunOnMissingResource=true
          - ServerSideApply=true
  templatePatch: |
    {{- if eq (index .metadata.labels "nordri.siliconsaga.org/environment") "gke" }}
    {{- if not (index .metadata.annotations "nordri.siliconsaga.org/gcp-project") }}{{ fail "identity: gcp-project annotation missing on the in-cluster Secret" }}{{ end }}
    spec:
      source:
        kustomize:
          patches:
            - target: {group: cert-manager.io, version: v1, kind: ClusterIssuer, name: letsencrypt-dns01}
              patch: |-
                - op: replace
                  path: /spec/acme/solvers/0/dns01/cloudDNS/project
                  value: {{ index .metadata.annotations "nordri.siliconsaga.org/gcp-project" }}
            - target: {group: argoproj.io, version: v1alpha1, kind: Application, name: cert-manager}
              patch: |-
                - op: add
                  path: /spec/source/helm/parameters
                  value:
                    - name: serviceAccount.annotations.iam\.gke\.io/gcp-service-account
                      value: cert-manager-dns01@{{ index .metadata.annotations "nordri.siliconsaga.org/gcp-project" }}.iam.gserviceaccount.com
    {{- end }}
```

`templatePatch` is the ApplicationSet field for conditional spec fragments (ArgoCD ≥ 2.10; chart 10.9.1 ships 3.x). In `vegvisir/manifests/base/cert-manager-app.yaml` delete lines 26–31 (the `serviceAccount:` annotation block and its comment) and add above `installCRDs` the comment `# On gke the vegvisir ApplicationSet adds the Workload Identity SA annotation as a helm parameter from the identity's gcp-project; nothing project-specific is committed.` In `overlays/gke/letsencrypt-dns01.yaml:42` set `project: __GCP_PROJECT__` is **not** used (no placeholders survive in Git): set `project: set-by-the-vegvisir-applicationset` and a comment saying the ApplicationSet's kustomize patch replaces it; the gke render check in Step 1 asserts the literal is replaced when the patch applies (Step 6).

- [ ] **Step 4: `apps/tailscale-operator-app.yaml` as an ApplicationSet:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tailscale-operator
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "4"
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  syncPolicy:
    preserveResourcesOnDeletion: true
    applicationsSync: create-update
  generators:
    # Only clusters whose identity names a tailnet node run the operator
    # (2026-11-13 review): prod clusters by name, test clusters by stamp, labs
    # not at all unless a test asks for it.
    - clusters:
        selector:
          matchLabels:
            nordri.siliconsaga.org/tailnet: "true"
  template:
    metadata:
      name: tailscale-operator
      namespace: argo
      annotations:
        argocd.argoproj.io/sync-wave: "4"
    spec:
      project: default
      source:
        repoURL: https://pkgs.tailscale.com/helmcharts
        chart: tailscale-operator
        targetRevision: "1.98.3"
        helm:
          values: |-
            {{- if not (index .metadata.annotations "nordri.siliconsaga.org/tailnet-node") }}{{ fail "identity: tailnet-node annotation missing on the in-cluster Secret" }}{{ end }}
            operatorConfig:
              hostname: tailscale-operator-{{ index .metadata.annotations "nordri.siliconsaga.org/tailnet-node" }}
      destination:
        server: https://kubernetes.default.svc
        namespace: tailscale
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
```

- [ ] **Step 5: URL renames.** The nine plain URLs become `'http://git.gitops.svc.cluster.local:3000/siliconsaga/<repo>.git'` (`nidavellir` ×6 incl. harbor and demicracy, `mimir`, `heimdall`); `apps/keycloak-operator-app.yaml:28` becomes `'http://git.gitops.svc.cluster.local:3000/siliconsaga-vendor/keycloak-k8s-resources.git'` and its header's "SiliconSaga VENDOR MIRROR … pushes its real history + tags into the seed Gitea" gains "under the `siliconsaga-vendor` org". `apps/kustomization.yaml:8-14`: "Each Application uses the stable in-cluster address `git.gitops.svc.cluster.local`, which the `git` Service points at the seed until `graduate.sh` repoints it at Forgejo (realm Forgejo day-2 Phase 3)."

- [ ] **Step 6: Verify the gke patch set applies.** Build a scratch kustomization that reproduces what ArgoCD will do: `mkdir -p /tmp/vg && cat > /tmp/vg/kustomization.yaml` with `resources: [../../<abs path>/vegvisir/manifests/overlays/gke]` and the two patches with `example-project` substituted, then `kubectl kustomize --load-restrictor LoadRestrictionsNone /tmp/vg | grep -c example-project` → `2` (issuer project and the helm parameter). Record the command in the task's commit body.

- [ ] **Step 7: Run** `bash tests/render/check-appsets.sh` → PASS; `bash tests/platform/...` unchanged (kuttl asserts still name Application `vegvisir`, which the ApplicationSet generates).

- [ ] **Step 8: Commit.** Message `feat(apps): vegvisir and tailscale-operator as ApplicationSets; stable git address`, add the files above.

---

### Task 7: ntfy derives its tailnet name from the identity (nidavellir)

**Files:**
- Modify: `ntfy/xrd.yaml:26-42` (drop `tailscaleHostname`, `baseUrl`, `environment`; add `tailnet`)
- Modify: `ntfy/composition.yaml:43-46, 87-89, 214-219`
- Modify: `ntfy/claim.yaml` (drops the placeholders; sets `tailnet`)
- Modify: `tests/render/check-ntfy.sh`, `tests/render/ntfy-xr.yaml`; create `tests/render/cluster-identity-homelab-tailnet.yaml`
- Modify: `ntfy/README.md` "Device naming"

**Interfaces:**
- Consumes: EnvironmentConfig keys `tailnetNode` (may be absent) from Task 2.
- Produces: Service `ntfy` annotated `tailscale.com/expose`, `tailscale.com/hostname: ntfy-<tailnetNode>`, `tailscale.com/tags: tag:ntfy` only when `tailnetNode` is non-empty; `server.yml` `base-url: http://ntfy-<tailnetNode>.<tailnet>` when both `tailnetNode` and the claim's `tailnet` are set. Claim parameter `tailnet` (string, the tailnet's MagicDNS suffix, e.g. `tailf5b47a.ts.net`).

- [ ] **Step 1: Update the render test first.** In `tests/render/check-ntfy.sh` replace the last two blocks: the placeholder loop asserts `no 'ntfy-MACHINE'` and `no 'ntfy-loki'`; add a render against a new identity `cluster-identity-homelab-tailnet.yaml` (the homelab identity plus `tailnetNode: homelab-test-20261113-1430`) asserting `yes 'tailscale.com/hostname: ntfy-homelab-test-20261113-1430'` and `yes 'base-url: "http://ntfy-homelab-test-20261113-1430.tailf5b47a.ts.net"'`; the plain homelab and the gke fixture (whose identity has no `tailnetNode`) assert `no 'tailscale.com/hostname'`. `ntfy-xr.yaml` loses `tailscaleHostname`/`baseUrl` and gains `tailnet: tailf5b47a.ts.net`. Run it: FAIL (hostname still env-driven).

- [ ] **Step 2: XRD.** Remove `tailscaleHostname`, `baseUrl`, `environment`; add:

```yaml
                    tailnet:
                      type: string
                      description: "The tailnet's MagicDNS suffix (e.g. tailf5b47a.ts.net). With cluster-identity tailnetNode set, the Service is exposed as ntfy-<tailnetNode> and base-url is http://ntfy-<tailnetNode>.<tailnet>. Without tailnetNode the Service is not exposed and base-url is unset."
```

- [ ] **Step 3: Composition.** Lines 43–46 become:

```
          {{- $identity := index .context "apiextensions.crossplane.io/environment" -}}
          {{- $params := .observed.composite.resource.spec.parameters | default dict -}}
          {{- $tailnetNode := $identity.tailnetNode | default "" -}}
          {{- $tailnet := $params.tailnet | default "" -}}
          {{- $storageClass := $identity.storageClass -}}
```

Lines 87–89: `{{ if and $tailnetNode $tailnet -}}` / `base-url: "http://ntfy-{{ $tailnetNode }}.{{ $tailnet }}"` / `{{ end -}}`. Lines 214–219: `{{- if $tailnetNode }}` … `tailscale.com/hostname: ntfy-{{ $tailnetNode }}` … `{{- end }}`. Delete the stale comment at 31–32 about `$env` driving replicas, and every other `$env` use (grep `\$env` must return nothing).

- [ ] **Step 4: Claim.** `ntfy/claim.yaml`: delete lines 8–27 (the placeholder comment, `tailscaleHostname`, `baseUrl`); add `tailnet: tailf5b47a.ts.net` with the comment `# The tailnet suffix is realm-wide and not secret; the device name comes from cluster-identity tailnetNode, so this file is identical on every cluster.`

- [ ] **Step 5: Run** `bash tests/render/check-ntfy.sh` → PASS. Update `ntfy/README.md` "Device naming": per-cluster names come from `tailnetNode`; GKE keeps `ntfy-gke`; lab/test get the stamp; the operator's own device lingers after a cluster is destroyed and is pruned by hand (Task 19's script).

- [ ] **Step 6: Commit.** Message `feat(ntfy): tailnet exposure and base-url from cluster-identity tailnetNode`.

---

### Task 8: Forgejo composition — `orgs` with classes, `role` (nidavellir)

**Files:**
- Modify: `forgejo/xrd.yaml` (`org` → `orgs`; `vendorMirrors` unchanged but owned by the vendor org)
- Modify: `forgejo/composition.yaml:73-74, 87-91, 207-229, 489-568, 569` (orgs, role, configure env, puller gate)
- Modify: `forgejo/scripts/configure.sh` (org loop, protection by role, mirrors in the vendor org)
- Modify: `tests/render/forgejo-xr.yaml`, `tests/render/forgejo-xr-teardown.yaml`, `tests/render/check-forgejo.sh`; create `tests/render/cluster-identity-homelab-test-durable.yaml`, `tests/render/forgejo-observed-configured.yaml`
- Modify: `docs/forgejo.md` ("What renders at durable", "The puller", a new "Roles" section)

**Interfaces:**
- Consumes: EnvironmentConfig keys `role` (default `prod` when absent, so an un-migrated cluster behaves as today), `sourceRef`, `maturity`, `pullerSchedule`.
- Produces: claim `spec.parameters.orgs: [{name, class}]` with `class` in `canonical|vendor`, exactly one of each required; `$org` = the canonical org, `$vendorOrg` = the vendor org; env `VENDOR_ORG` and `ROLE` on the configure Job; env `ROLE`, `SOURCE_REF` on the puller (consumed in Task 14); the puller CronJob renders only when `role != test`; `configure.sh` on `role: test` deletes any `main` protection rule and creates none.

- [ ] **Step 1: Fixtures and the failing render checks.** `tests/render/forgejo-xr.yaml` and `-teardown.yaml`: replace `org: siliconsaga` with

```yaml
    orgs:
      - {name: siliconsaga, class: canonical}
      - {name: siliconsaga-vendor, class: vendor}
```

New identity `cluster-identity-homelab-test-durable.yaml` = the durable homelab identity plus `role: test`. New observed fixture `forgejo-observed-configured.yaml` = `forgejo-observed.yaml` plus a Ready Object with annotation `crossplane.io/composition-resource-name: configure-job`. In `check-forgejo.sh` add: durable + observed-configured → `yes 'kind: CronJob'`, `yes 'value: "main"'` (SOURCE_REF), `yes 'name: VENDOR_ORG'`, `yes 'value: "siliconsaga-vendor"'`; test-durable + observed-configured → `no 'kind: CronJob'`, `yes 'name: ROLE'` and `yes 'value: "test"'`; a fixture with a single `orgs` entry must fail with `orgs needs one canonical and one vendor entry`. Run: FAIL.

- [ ] **Step 2: XRD.** Replace `org` (and `required: [org]`) with:

```yaml
                  required: [orgs]
                  properties:
                    orgs:
                      type: array
                      description: "Decision 2 of the Phase 3 design: an org is a trust class. Exactly one canonical (maintained repositories, main protected and puller-written) and one vendor (pull-mirrors, read-only)."
                      minItems: 2
                      items:
                        type: object
                        required: [name, class]
                        properties:
                          name: {type: string}
                          class: {type: string, enum: [canonical, vendor]}
```

- [ ] **Step 3: Composition header.** Replace lines 73–74 with:

```
          {{- $orgs := $p.orgs | default list -}}
          {{- $org := "" -}}{{- $vendorOrg := "" -}}
          {{- range $orgs -}}{{- if eq .class "canonical" -}}{{- $org = .name -}}{{- else if eq .class "vendor" -}}{{- $vendorOrg = .name -}}{{- end -}}{{- end -}}
          {{- if or (not $org) (not $vendorOrg) -}}{{ fail "parameters.orgs needs one canonical and one vendor entry" }}{{- end -}}
          {{- $role := $identity.role | default "prod" -}}
          {{- $sourceRef := $identity.sourceRef | default "main" -}}
```

Add `$vendorOrg $role $sourceRef` to the `$jobSuffix` printf (line 91). In the configure Job env add `- name: VENDOR_ORG` / `value: {{ $vendorOrg | quote }}` and `- name: ROLE` / `value: {{ $role | quote }}`. In the puller: change line 569's gate to `{{- if and $configureReady (ne $role "test") }}` and add env `ROLE`, `SOURCE_REF` (`{{ $sourceRef | quote }}`). The `forgejo-repos` ConfigMap is unchanged.

- [ ] **Step 4: `configure.sh`.** Add `: "${VENDOR_ORG:?set VENDOR_ORG}"` and `: "${ROLE:=prod}"`. Section 1 loops over both orgs:

```bash
for o in "$ORG" "$VENDOR_ORG"; do
  code=$(api GET "/orgs/$o")
  case "$code" in
    200) echo "org $o: present" ;;
    404)
      jq -n --arg u "$o" '{username: $u, visibility: "public"}' > "$work/body.json"
      code=$(api POST /orgs --data @"$work/body.json")
      [ "$code" = 201 ] && echo "org $o: created" || { echo "creating org $o: HTTP $code $(body)" >&2; exit 1; } ;;
    *) echo "GET /orgs/$o: HTTP $code $(body)" >&2; exit 1 ;;
  esac
done
```

Section 5 reconciles to the role:

```bash
while read -r name _; do
  [ -z "$name" ] && continue
  code=$(api GET "/repos/$ORG/$name/branch_protections/main")
  if [ "$ROLE" = test ]; then
    # A test cluster's Forgejo is scratch space: hydration writes main, no rule.
    case "$code" in
      200) code=$(api DELETE "/repos/$ORG/$name/branch_protections/main")
           [ "$code" = 204 ] && echo "protection $ORG/$name main: removed (role test)" || { echo "DELETE protection $ORG/$name: HTTP $code $(body)" >&2; fails=$((fails+1)); } ;;
      404) echo "protection $ORG/$name main: none (role test)" ;;
      *) echo "GET protection $ORG/$name: HTTP $code $(body)" >&2; fails=$((fails+1)) ;;
    esac
    continue
  fi
  case "$code" in
    ... (today's 200/404/* arms unchanged)
  esac
done < "$REPOS_FILE"
```

Section 6 uses `$VENDOR_ORG` everywhere `$ORG` appeared (`create_mirror` and the loop).

- [ ] **Step 5: Run** `bash tests/render/check-forgejo.sh` → PASS (it also runs `bash -n` on the scripts). Document in `docs/forgejo.md`: a "Roles" section (prod: protected, puller; test: unprotected, no puller, filled by hydration or `graduate.sh`), and that the vendor mirrors live in the vendor org.

- [ ] **Step 6: Commit.** Message `feat(forgejo): orgs with classes; role test renders no puller and no protection`.

---

### Task 9: mimir ApplicationSet and parameterised GKE overlay (mimir)

**Files:**
- Modify: `argocd/apps/shared-clusters.yaml` (becomes an ApplicationSet)
- Modify: `argocd/apps/dataservice-operator.yaml:20`, `argocd/apps/percona-pg-operator.yaml:11` (URL rename)
- Modify: `shared/overlays/gke/kustomization.yaml` (project and bucket values become patch targets; `repo2-path`; PXC bucket prefix)
- Create: `scripts/render-check.sh`; modify `scripts/test.sh` to call it in unit mode
- Modify: `docs/offsite-backups.md` ("What is NOT in Git" names the identity as the source of the project; the restore-source note for the old paths)

**Interfaces:**
- Consumes: cluster Secret labels/annotations.
- Produces: ApplicationSet `mimir-shared-clusters` → Application `mimir-shared-clusters`, `path: shared/overlays/<environment>`, `prune: false`, no finalizer; on gke `kustomize.patches` replace the pgBackRest GSA, the repo2 bucket, add `repo2-path: /<cluster>/pgbackrest`, and set the PXC bucket to `<project>-mysql-backups/<cluster>`.

- [ ] **Step 1: Write the failing render check** `scripts/render-check.sh`: builds both overlays with `kustomize build --load-restrictor LoadRestrictionsNone`, asserts the homelab build has no `gcs:` and the gke build has `repo2-gcs-key-type: auto`; then builds a scratch kustomization layering the gke overlay plus the ApplicationSet's gke patches with `example-project` and `gke-prod` substituted, and asserts the pgBackRest service account ends in `example-project.iam.gserviceaccount.com`, `bucket: example-project-pgbackrest`, `repo2-path: /gke-prod/pgbackrest`, `bucket: example-project-mysql-backups/gke-prod`, and no `teralivekubernetes`. `scripts/test.sh` unit mode runs it after `go test` when `kustomize` is on PATH (skips with a note otherwise). Run: FAIL.

- [ ] **Step 2: ApplicationSet.** Replace `argocd/apps/shared-clusters.yaml` (keep the two header comments on prune and the finalizer):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: mimir-shared-clusters
  namespace: argo
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  syncPolicy:
    preserveResourcesOnDeletion: true
    applicationsSync: create-update
  generators:
    - clusters:
        selector:
          matchExpressions:
            - {key: nordri.siliconsaga.org/cluster, operator: Exists}
  template:
    metadata:
      name: mimir-shared-clusters
      namespace: argo
    spec:
      project: default
      source:
        repoURL: 'http://git.gitops.svc.cluster.local:3000/siliconsaga/mimir.git'
        targetRevision: HEAD
        path: '{{ if not (index .metadata.labels "nordri.siliconsaga.org/environment") }}{{ fail "identity: environment label missing on the in-cluster Secret" }}{{ end }}shared/overlays/{{ index .metadata.labels "nordri.siliconsaga.org/environment" }}'
      destination:
        server: https://kubernetes.default.svc
        namespace: mimir
      syncPolicy:
        automated:
          prune: false
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
          - SkipDryRunOnMissingResource=true
  templatePatch: |
    {{- if eq (index .metadata.labels "nordri.siliconsaga.org/environment") "gke" }}
    {{- if not (index .metadata.annotations "nordri.siliconsaga.org/gcp-project") }}{{ fail "identity: gcp-project annotation missing on the in-cluster Secret" }}{{ end }}
    {{- if not (index .metadata.labels "nordri.siliconsaga.org/cluster") }}{{ fail "identity: cluster label missing on the in-cluster Secret" }}{{ end }}
    {{- $project := index .metadata.annotations "nordri.siliconsaga.org/gcp-project" }}
    {{- $cluster := index .metadata.labels "nordri.siliconsaga.org/cluster" }}
    spec:
      source:
        kustomize:
          patches:
            - target: {group: pgv2.percona.com, version: v2, kind: PerconaPGCluster, name: mimir-postgres}
              patch: |-
                - op: replace
                  path: /spec/metadata/annotations/iam.gke.io~1gcp-service-account
                  value: pgbackrest@{{ $project }}.iam.gserviceaccount.com
                - op: replace
                  path: /spec/backups/pgbackrest/repos/1/gcs/bucket
                  value: {{ $project }}-pgbackrest
                - op: add
                  path: /spec/backups/pgbackrest/global/repo2-path
                  value: /{{ $cluster }}/pgbackrest
            - target: {group: pxc.percona.com, version: v1, kind: PerconaXtraDBCluster, name: mimir-mysql}
              patch: |-
                - op: replace
                  path: /spec/backup/storages/gcs/s3/bucket
                  value: {{ $project }}-mysql-backups/{{ $cluster }}
    {{- end }}
```

In `shared/overlays/gke/kustomization.yaml` the three hardcoded values become `set-by-the-shared-clusters-applicationset` with a comment above each pointing here; the structure (repo2 appended as index 1, the `gcs` storage name) is what the patch paths depend on, so add a comment at the top: `# The mimir-shared-clusters ApplicationSet patches three values below by JSON path; keep repo2 as the second repo and the storage named gcs.`

- [ ] **Step 3: URL renames** in `dataservice-operator.yaml:20` and `percona-pg-operator.yaml:11`.

- [ ] **Step 4: Run** `bash scripts/render-check.sh` → PASS; `bash scripts/test.sh`.

- [ ] **Step 5: Docs.** `docs/offsite-backups.md`: the project and buckets come from the identity's `gcpProject`; the paths are `/<cluster>/pgbackrest` and `<bucket>/<cluster>`; add under "Still owed" the restore note from the design: `gke-prod`'s pre-3a repository at the default path and its MySQL folders at the bucket root stay as named restore sources until retention lapses.

- [ ] **Step 6: Commit.** Message `feat(argocd): shared-clusters as an ApplicationSet; GKE project and paths from the identity`.

---

### Task 10: the realm — `clusters/`, the claim's orgs, stale text (realm-siliconsaga)

**Files:**
- Create: `clusters/README.md`, `clusters/homelab-prod.yaml`, `clusters/homelab-test.yaml`, `clusters/gke-prod.yaml`, `clusters/homelab-nano76win11.yaml`
- Modify: `cluster/forgejo/claim.yaml:22` (orgs)
- Modify: `cluster/README.md:7,12`, `cluster/kustomization.yaml:3-5`, `ecosystem.yaml:229-237`, `docs/forgejo.md`, `docs/stack.md:95`, `docs/dev-setup.md:305,325`, `.agent/skills/siliconsaga-stack/SKILL.md:81`

**Interfaces:**
- Produces: the four cluster files Task 1's `identity_resolve` reads.

- [ ] **Step 1: The cluster files.**

`clusters/README.md`: one paragraph: one flat file per declared cluster, keys from the design's table, read by nordri `identity.sh`; a cluster with no file is a lab; GKE clusters must be declared; `tailnetNode: stamped` for a test cluster that needs the tailnet.

```yaml
# clusters/homelab-prod.yaml — the homelab production cluster on the new server.
environment: homelab
role: prod
maturity: bootstrap   # raised to durable in 3b-1, then graduated
sourceRef: main
```

```yaml
# clusters/homelab-test.yaml — recycled at will; durable when the durable layer is under test.
environment: homelab
role: test
maturity: bootstrap
tailnetNode: stamped   # <cluster>-<yyyymmdd-HHMM> at bootstrap; devices pruned by hand
```

```yaml
# clusters/gke-prod.yaml — GKE production. Stays bootstrap until 3b-4 step 3.
environment: gke
role: prod
maturity: bootstrap
sourceRef: live
tailnetNode: gke       # keeps today's device names and the phone's ntfy subscription
gcpProject: teralivekubernetes
```

```yaml
# clusters/homelab-nano76win11.yaml — today's Docker Desktop cluster: a durable
# test cluster until it is recycled into a generic lab, when this file is deleted.
environment: homelab
role: test
maturity: durable
tailnetNode: stamped
```

- [ ] **Step 2: The claim.** `cluster/forgejo/claim.yaml:22` becomes the `orgs` list from Task 8 step 1, with the comment `# Decision 2: the canonical org and the vendor org; the puller writes the first, pull-mirrors fill the second.` Line 30's comment stays.

- [ ] **Step 3: Stale text.** `cluster/README.md:7`: `nordri/bootstrap.sh <realm> <cluster>` hydrates the whole realm checkout into the seed repo `realm-siliconsaga` and the realm root Application reads `cluster/`; day-2 changes: `nordri/update-embedded-git.sh realm-siliconsaga`. Line 12: "the two orgs". `cluster/kustomization.yaml:3-5` likewise. `ecosystem.yaml:229-237`: "under the realm's vendor org `siliconsaga-vendor`". `docs/stack.md:95`, `docs/dev-setup.md:305,325`, `.agent/skills/siliconsaga-stack/SKILL.md:81`: the new argument shapes. `docs/forgejo.md` phase table: Phase 3 "in progress".

- [ ] **Step 4: Check** `bash <nordri>/tests/unit/identity-resolve-test.sh` style resolve against the real files: from the nordri checkout, `REALM_DIR=../../realms/realm-siliconsaga bash -c '. lib/identity.sh; identity_resolve "$REALM_DIR" gke-prod; identity_resolve "$REALM_DIR" homelab-nano76win11'` prints both identities with `gcpProject=teralivekubernetes` and a stamped `tailnetNode`.

- [ ] **Step 5: Commit** on a realm topic branch. Message `feat(clusters): declare the four clusters; the claim's two orgs`.

---

### Task 11: `migrate.sh` and the shared Argo wait (nordri)

**Files:**
- Create: `scripts/migrate.sh`, `lib/argo.sh`
- Modify: `scripts/argo-settle.sh` (uses `lib/argo.sh`)
- Create: `tests/unit/migrate-order-test.sh`
- Modify: `tests/run.sh:7`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: `lib/argo.sh`: `argo_wait_settled <timeout>` (today's loop: no `Unknown`), `argo_wait_synced_healthy <timeout>` (every Application `Synced` and `Healthy`), `argo_wait_operations_done <timeout>` (no Application with `status.operationState.phase` in `Running`), `argo_hard_refresh_all`, `argo_remove_finalizer <app>` (patch `metadata.finalizers` to `[]` when it is only the resources finalizer). `scripts/migrate.sh <realm> <cluster>`: the eight steps of 3a-5, re-runnable.

- [ ] **Step 1: Write the failing test** `tests/unit/migrate-order-test.sh`: a `kubectl` stub records calls; stubs for `argo_wait_*` record order; the test asserts the sequence: policy-override check reads `argocd-cmd-params-cm`; refusal when it is not `true`; `identity.sh apply` runs before the finalizer patches; the three finalizer patches name `tailscale-operator`, `vegvisir`, `velero`; `gitops_ensure_org` ×2 and `gitops_ensure_git_service` run before the hydrate; root apps are applied before the hard refresh; `identity.sh apply` runs a second time after `argo_wait_operations_done`; `argo_wait_synced_healthy` is last. Implement with `MIGRATE_DRY_RUN=1` making the hydrate call print instead of push.

- [ ] **Step 2: `lib/argo.sh`** — extract the loop from `argo-settle.sh` into `argo_wait_settled`, generalised by a predicate; add the two other waits and the two helpers:

```bash
#!/usr/bin/env bash
# lib/argo.sh — read-mostly helpers over ArgoCD Applications in namespace argo.
ARGO_NS="${ARGO_NS:-argo}"
ARGO_REQUEST_TIMEOUT=30

_argo_rows() { # name<TAB>sync<TAB>health<TAB>opphase
    kubectl get applications -n "$ARGO_NS" --request-timeout="${1:-30}s" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\t"}{.status.operationState.phase}{"\n"}{end}' | tr -d '\r'
}
# argo_wait <timeout> <label> <predicate-fn>: predicate gets the rows, prints
# the unsettled count, returns 0 when settled.
argo_wait() {
    local timeout="$1" label="$2" pred="$3" start elapsed remaining bounded rows n
    start=$(date +%s)
    while true; do
        elapsed=$(( $(date +%s) - start )); remaining=$(( timeout - elapsed ))
        bounded=$(( remaining > 0 && remaining < ARGO_REQUEST_TIMEOUT ? remaining : ARGO_REQUEST_TIMEOUT ))
        if rows=$(_argo_rows "$bounded" 2>/dev/null); then
            n=$("$pred" <<< "$rows")
            echo "   ${elapsed}s: $n not yet $label"
            [[ -n "$rows" && "$n" -eq 0 ]] && return 0
        else
            echo "   ${elapsed}s: query failed" >&2
        fi
        [[ "$elapsed" -ge "$timeout" ]] && { echo "❌ Timeout after ${timeout}s waiting for Applications to be $label." >&2; return 1; }
        sleep 20
    done
}
_pred_settled() { awk -F'\t' '$2=="" || $2=="Unknown" {n++} END {print n+0}'; }
_pred_synced_healthy() { awk -F'\t' '$2!="Synced" || $3!="Healthy" {n++} END {print n+0}'; }
_pred_ops_done() { awk -F'\t' '$4=="Running" || $4=="Terminating" {n++} END {print n+0}'; }
argo_wait_settled() { argo_wait "${1:-900}" "settled (not Unknown)" _pred_settled; }
argo_wait_synced_healthy() { argo_wait "${1:-900}" "Synced and Healthy" _pred_synced_healthy; }
argo_wait_operations_done() { argo_wait "${1:-900}" "done syncing" _pred_ops_done; }
argo_hard_refresh_all() { kubectl annotate applications.argoproj.io -n "$ARGO_NS" --all argocd.argoproj.io/refresh=hard --overwrite >/dev/null; }
# Drop the resources finalizer so a later prune orphans the resources instead of
# deleting them (design, Decision 4 step 1). Only that finalizer is touched.
argo_remove_finalizer() {
    local app="$1" fins
    fins=$(kubectl get application -n "$ARGO_NS" "$app" -o jsonpath='{.metadata.finalizers}' 2>/dev/null | tr -d '\r')
    [[ -z "$fins" || "$fins" == "[]" ]] && { echo "   $app: no finalizer"; return 0; }
    kubectl patch application -n "$ARGO_NS" "$app" --type=json -p '[{"op":"remove","path":"/metadata/finalizers"}]' >/dev/null \
        && echo "   $app: resources finalizer removed"
}
```

`scripts/argo-settle.sh` keeps its argument parsing and context echo and calls `argo_wait_settled "$timeout"` then prints the table.

- [ ] **Step 3: `scripts/migrate.sh`:**

```bash
#!/usr/bin/env bash
# migrate.sh — move a running cluster onto generic Git (realm Phase 3 design,
# 3a-5), safe to re-run. Usage: scripts/migrate.sh <realm> <cluster>
# Follows kubectl's current context; refuses when the live identity (if any)
# names another cluster. Hydrates from the local checkouts like
# update-embedded-git.sh, so run it from the branches you mean to migrate to.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$SCRIPT_DIR/lib/gitea.sh"; . "$SCRIPT_DIR/lib/hydrate.sh"; . "$SCRIPT_DIR/lib/identity.sh"
. "$SCRIPT_DIR/lib/gitops.sh"; . "$SCRIPT_DIR/lib/kube-context.sh"; . "$SCRIPT_DIR/lib/argo.sh"
REALM="${1:-}"; CLUSTER="${2:-}"
[[ -n "$REALM" && -n "$CLUSTER" ]] || { echo "Usage: scripts/migrate.sh <realm> <cluster>"; exit 1; }
REALM_DIR="${REALM_DIR:-$(dirname "$(dirname "$SCRIPT_DIR")")/realms/$REALM}"
NIDAVELLIR_DIR="${NIDAVELLIR_DIR:-$(dirname "$SCRIPT_DIR")/nidavellir}"; MIMIR_DIR="${MIMIR_DIR:-$(dirname "$SCRIPT_DIR")/mimir}"; HEIMDALL_DIR="${HEIMDALL_DIR:-$(dirname "$SCRIPT_DIR")/heimdall}"
VENDOR_MIRRORS="${VENDOR_MIRRORS:-keycloak-k8s-resources}"; HYDRATE_AUTO_INIT=true; HYDRATE_COMMITTER="Nordri Migrate"
TEMP_DIRS=(); trap 'rm -rf "${TEMP_DIRS[@]}"' EXIT

IDENTITY="$(IDENTITY_LIVE_TAILNET="$(identity_live_value tailnetNode)" identity_resolve "$REALM_DIR" "$CLUSTER")" || exit 1
TARGET="$(printf '%s\n' "$IDENTITY" | sed -n 's/^environment=//p')"
require_kube_context "$TARGET" || exit 1
GITOPS_ORG="$(gitops_canonical_org "$REALM")"; GITOPS_VENDOR_ORG="$(gitops_vendor_org "$REALM")"

echo "1/8 ApplicationSet policy override"
override=$(kubectl get configmap -n argo argocd-cmd-params-cm -o 'jsonpath={.data.applicationsetcontroller\.enable\.policy\.override}' 2>/dev/null | tr -d '\r')
[[ "$override" == "true" ]] || { echo "❌ ArgoCD does not allow ApplicationSet policy overrides (argocd-cmd-params-cm). Sync the argocd Application from a nordri main that carries it, then re-run." >&2; exit 1; }

echo "2/8 identity (ConfigMap, cluster Secret; EnvironmentConfig marked Prune=false while tracked)"
REALM_DIR="$REALM_DIR" bash "$SCRIPT_DIR/scripts/identity.sh" apply "$REALM" "$CLUSTER" || exit 1

echo "3/8 finalizers off the three Applications that carry one"
for app in tailscale-operator vegvisir velero; do argo_remove_finalizer "$app"; done

echo "4/8 seed orgs and the git Service"
# Seed credentials and port-forward exactly as update-embedded-git.sh (shared block)
. "$SCRIPT_DIR/lib/seed-access.sh"; seed_access_open || exit 1
gitops_ensure_org "$GITOPS_ORG" || exit 1; gitops_ensure_org "$GITOPS_VENDOR_ORG" || exit 1
gitops_ensure_git_service || exit 1

echo "5/8 hydrate the change into the new orgs"
if [[ "${MIGRATE_DRY_RUN:-0}" == "1" ]]; then echo "   (dry run) hydrate skipped"; else
hydrate_working_tree_repo "$SCRIPT_DIR" "$GITOPS_ORG" nordri "Migration of nordri" || exit 1
hydrate_working_tree_repo "$NIDAVELLIR_DIR" "$GITOPS_ORG" nidavellir "Migration of nidavellir" || exit 1
hydrate_working_tree_repo "$MIMIR_DIR" "$GITOPS_ORG" mimir "Migration of mimir" || exit 1
hydrate_working_tree_repo "$HEIMDALL_DIR" "$GITOPS_ORG" heimdall "Migration of heimdall" || exit 1
hydrate_vendor_mirrors "$GITOPS_VENDOR_ORG" "$VENDOR_MIRRORS" || exit 1
hydrate_working_tree_repo "$REALM_DIR" "$GITOPS_ORG" "$REALM" "Migration of $REALM" || exit 1
fi

echo "6/8 root Applications at the stable address; hard refresh; wait for operations"
gitops_apply_root_apps "$REALM" || exit 1
argo_hard_refresh_all
argo_wait_operations_done 900 || exit 1

echo "7/8 identity again: take over the EnvironmentConfig"
REALM_DIR="$REALM_DIR" bash "$SCRIPT_DIR/scripts/identity.sh" apply "$REALM" "$CLUSTER" || exit 1

echo "8/8 wait for Synced and Healthy"
argo_hard_refresh_all
argo_wait_synced_healthy 1200 || exit 1
echo "✅ $CLUSTER runs generic Git from its seed. Old nordri-admin repositories remain in the seed, unreferenced."
```

`lib/seed-access.sh` is the seed credential resolution and port-forward block factored out of `update-embedded-git.sh` (Task 4 step 8) into `seed_access_open` (sets `GITEA_USER`, `GITEA_PASS`, builds URLs, port-forwards or probes, appends to `TEMP_DIRS`/`PF_PID`), used by `update-embedded-git.sh`, `migrate.sh` and `graduate.sh`. Do that extraction in this task and point `update-embedded-git.sh` at it.

- [ ] **Step 4: Run** `bash tests/unit/migrate-order-test.sh` → `ALL PASS`; add `scripts/migrate.sh` and `lib/seed-access.sh` coverage to `tests/run.sh` (`scripts/migrate.sh` in the list; libs are globbed); `bash tests/run.sh test && bash tests/run.sh lint`.

- [ ] **Step 5: Commit.** Message `feat(migrate): migrate.sh runs the eight 3a-5 steps; shared Argo waits`.

---

### Task 12: 3a gates — lab from nothing, Nano76 in place, repo-wide checks (all four repos)

This task runs on clusters from the topic branches, before any 3a merge. It changes no code unless a gate fails; a failure is fixed in the owning task and the gate re-run.

- [ ] **Step 1: Lab from nothing.** On the driving machine create a kind cluster (`kind create cluster --name lab-3a`), `kubectl config use-context kind-lab-3a` (the operator's act), then from nordri `./bootstrap.sh realm-siliconsaga homelab-lab-3a`. Expect: identity written with `role=lab maturity=bootstrap tailnetNode=` (empty), `kubectl get secret in-cluster -n argo -o jsonpath='{.metadata.labels}'` shows `tailnet: "false"`, `kubectl get svc git -n gitops -o jsonpath='{.spec.externalName}'` = `gitea-http.gitea.svc.cluster.local`, every Application `Synced`/`Healthy` (`scripts/argo-settle.sh` then `kubectl get applications -n argo`), **no** `tailscale-operator` Application, ntfy Service without `tailscale.com/*` annotations, `layer4-fundamentals` path `platform/fundamentals/overlays/homelab`. Then the missing-value check: `kubectl label secret in-cluster -n argo nordri.siliconsaga.org/environment-`; within a minute `kubectl get applicationset layer4-fundamentals -n argo -o jsonpath='{.status.conditions}'` reports the render error containing `identity: environment label missing`, and `kubectl get application layer4-fundamentals -n argo` still exists unchanged; restore the label with `scripts/identity.sh apply realm-siliconsaga homelab-lab-3a`. Repeat for the gcp-project annotation on a gke-labelled scratch Secret only if a gke-test exists; otherwise record "not exercised" in the CR.

- [ ] **Step 2: Nano76 in place.** `kubectl config use-context docker-desktop`; record UIDs first: `kubectl get deploy -n tailscale operator -o jsonpath='{.metadata.uid}'`, `kubectl get gateway -n kube-system traefik-gateway -o jsonpath='{.metadata.uid}'`, `kubectl get perconapgcluster -n mimir mimir-postgres -o jsonpath='{.metadata.uid}'`, `kubectl get environmentconfig cluster-identity -o jsonpath='{.metadata.uid}'`, and Forgejo's `kubectl get pvc -n forgejo forgejo-data -o jsonpath='{.metadata.uid}'`. Run `scripts/migrate.sh realm-siliconsaga homelab-nano76win11`. Expect: exit 0, every Application `Synced`/`Healthy`, the five UIDs unchanged, `kubectl get applicationset -n argo` lists `layer4-fundamentals vegvisir tailscale-operator mimir-shared-clusters` (no `velero` on homelab), the generated Applications carry `ownerReferences` to their ApplicationSets, the tailscale operator's hostname is `tailscale-operator-homelab-nano76win11-<stamp>` (a new device; the old machine-named one is now a prune candidate), and the Forgejo configure Job re-ran (new `jobSuffix`) with `role test`: `main` protection rules deleted, no `forgejo-puller` CronJob. Record whether the ApplicationSet adopted the pre-existing same-named Application or waited for the prune (the design's open check) in the nordri CR body.

- [ ] **Step 3: Repo-wide greps**, each must print nothing: `grep -rn 'MACHINE\|__GCP_PROJECT__' <nordri>/platform <nidavellir>/apps <nidavellir>/ntfy <mimir>/argocd <mimir>/shared`; `grep -rn 'repoURL:.*gitea-http\|repoURL:.*nordri-admin' <nordri> <nidavellir> <mimir> <realm>/cluster`; `grep -rln 'kind: Application$' <nordri>/platform <nidavellir>/apps <mimir>/argocd | xargs grep -l 'repoURL:.*svc.cluster.local' | xargs grep -L 'git.gitops.svc.cluster.local'` (every in-cluster repoURL is the stable one). `grep -rn forgejo-http <nidavellir>/forgejo` still matches the HTTPRoute backend and the Jobs' `FORGEJO_URL`, as it must.

- [ ] **Step 4: Suites.** nordri `bash tests/run.sh test && bash tests/run.sh lint`; nidavellir `bash tests/render/check-forgejo.sh && bash tests/render/check-ntfy.sh && bash tests/render/check-appsets.sh`; mimir `bash scripts/test.sh`.

- [ ] **Step 5: CRs**, in land order: nordri (`feat: generic Git — cluster identity, stable address, ApplicationSets`), nidavellir, mimir, realm. Each body records the gate evidence from steps 1–4. The author merges, in that order; after each merge `ws checkout <comp> main && ws pull <comp>`.

---

## Phase 3b — graduation and promotion

Starts after 3a has merged in all four repos and GKE has migrated (Task 20, step 2). Tasks 14–17 and 19 are code; 13, 18, 20 and 21 are operations with checks.

### Task 13: `homelab-prod` (operations, nordri unchanged)

- [ ] **Step 1:** On the new server's cluster, `kubectl config use-context <homelab-prod context>` (operator), then from nordri `./bootstrap.sh realm-siliconsaga homelab-prod`. Expect identity `role=prod maturity=bootstrap sourceRef=main tailnetNode=homelab-prod`, every Application green, `tailscale-operator-homelab-prod` on the tailnet.
- [ ] **Step 2:** Edit `clusters/homelab-prod.yaml` `maturity: durable`, merge on GitHub, pull, `scripts/identity.sh apply realm-siliconsaga homelab-prod`. Forgejo comes up (DataService, Release, configure Job, puller with `SOURCE_REF=main`); `kubectl get cronjob -n forgejo forgejo-puller` exists; one on-demand run (`kubectl create job -n forgejo --from=cronjob/forgejo-puller puller-manual-$(date +%s)`) fills the five repositories.
- [ ] **Step 3:** Graduation itself is Task 16 step 6, after `graduate.sh` exists.

### Task 14: the puller — state, soak, `incoming`, `live` tag sets (nidavellir)

**Files:**
- Modify: `forgejo/scripts/puller.sh` (rewrite)
- Modify: `forgejo/composition.yaml` (puller RBAC: Role `forgejo-puller-state` in `forgejo`, Role `forgejo-puller-apps` in `argo` with RoleBindings; `automountServiceAccountToken: true` on the puller pod; env `STATE_CONFIGMAP`, `ARGO_NAMESPACE`; `$jobGeneration` bump)
- Modify: `forgejo/scripts/configure.sh` (nothing) ; `docs/forgejo.md` ("The puller", "Promotion", "Recovering a diverged main" runbook)
- Create: `tests/scripts/forgejo-puller-test.sh`
- Modify: `tests/render/check-forgejo.sh` (RBAC and env assertions)

**Interfaces:**
- Consumes: env `ROLE`, `SOURCE_REF` (Task 8), `REPOS_FILE`, the Forgejo token.
- Produces: ConfigMap `forgejo-puller-state` in `forgejo`, key `state.json`: `{"sourceRef": "main|live", "promotion": <n or null>, "pending": ["<repo>", ...], "repos": {"<name>": {"commit": "<sha>", "healthySince": "<RFC3339>|null", "lastRun": "<RFC3339>", "lastResult": "ok|failed|behind"}}}`. On `main`: today's fast-forward, plus the state. On `live`: the highest `n` whose tag `live-<n>` exists in all five repositories is the target; each repository is pushed to `refs/heads/incoming` first, verified, then `main` is fast-forwarded; a failed move is recorded in `pending` and resumed next run. Health is read from Applications in `argo` (see below). Exit non-zero if any repository failed.

- [ ] **Step 1: Write the failing test** `tests/scripts/forgejo-puller-test.sh`. It runs `puller.sh` against two local bare repositories standing in for GitHub and Forgejo (file URLs; `GITHUB_BASE` and `FORGEJO_URL` are overridable for exactly this), a `kubectl` stub that stores the state ConfigMap in a file and answers `get applications -o json` from a fixture, and asserts: (a) `main` mode fast-forwards and writes `repos.nordri.commit`; (b) `healthySince` is set when the fixture shows every dependent Application `Synced` at that commit and `Healthy`, cleared when one is `Degraded`, and kept across a later healthy run; (c) `live` mode with tags `live-1` on all repos and `live-2` on four of five moves `main` to `live-1`'s commits and records `promotion: 1`; (d) a refused `main` move (make the bare repo's `main` diverge) leaves that repo in `pending` and exit 1, and the next run with the divergence removed completes it. Use the test style of `tests/scripts/forgejo-askpass-test.sh`.

- [ ] **Step 2: Rewrite `puller.sh`.** Keep the header's rules (every step checks its status; `GIT_ASKPASS`; anonymous GitHub). The body:

```bash
set -uo pipefail
: "${FORGEJO_URL:=http://forgejo-http.forgejo.svc.cluster.local:3000}"
: "${GITHUB_BASE:=https://github.com}"
: "${ORG:?set ORG}"; : "${PULLER_USERNAME:?set PULLER_USERNAME}"
: "${PULLER_TOKEN_FILE:=/etc/forgejo-puller/token}"; : "${REPOS_FILE:=/etc/forgejo/repos}"; : "${ASKPASS:=/scripts/askpass.sh}"
: "${ROLE:=prod}"; : "${SOURCE_REF:=main}"
: "${STATE_CONFIGMAP:=forgejo-puller-state}"; : "${NAMESPACE:=forgejo}"; : "${ARGO_NAMESPACE:=argo}"
export GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0 FORGEJO_URL PULLER_USERNAME PULLER_TOKEN_FILE
[ -s "$PULLER_TOKEN_FILE" ] || { echo "no token at $PULLER_TOKEN_FILE" >&2; exit 1; }
[ "$ROLE" = test ] && { echo "role test: the puller does nothing"; exit 0; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# ── state ────────────────────────────────────────────────────────────────────
state_load() {
  kubectl get configmap -n "$NAMESPACE" "$STATE_CONFIGMAP" -o jsonpath='{.data.state\.json}' 2>/dev/null > "$work/state.json" || true
  [ -s "$work/state.json" ] || printf '{"sourceRef":"%s","promotion":null,"pending":[],"repos":{}}' "$SOURCE_REF" > "$work/state.json"
}
state_save() {
  kubectl create configmap -n "$NAMESPACE" "$STATE_CONFIGMAP" --from-file=state.json="$work/state.json" --dry-run=client -o yaml \
    | kubectl apply -f - >/dev/null || echo "warning: could not write $STATE_CONFIGMAP" >&2
}
state_set() { # $1 jq filter with $now bound
  jq --arg now "$(now)" "$1" "$work/state.json" > "$work/state.next" && mv "$work/state.next" "$work/state.json"
}

# ── health: every Application that depends on <repo> at <commit> ─────────────
# Dependents: Applications whose source is the repository, plus everything they
# render — Applications and ApplicationSets labelled app.kubernetes.io/instance
# = parent (ArgoCD's default tracking), and Applications owned by those
# ApplicationSets — recursively. A dependent sourced from the repository must be
# Synced AT the commit; one sourced elsewhere (a Helm chart) must be Synced and
# Healthy, and its parent carries the commit check.
apps_json() { kubectl get applications,applicationsets -n "$ARGO_NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}'; }
repo_healthy() { # $1 repo $2 commit → 0 healthy, 1 not, 2 no dependents
  local repo="$1" commit="$2" url="$FORGEJO_URL/$ORG/$repo.git"
  jq -e --arg url "$url" --arg sha "$commit" '
    .items as $all
    | [ $all[] | select(.kind=="Application" and (.spec.source.repoURL|rtrimstr(".git")) == ($url|rtrimstr(".git"))) ] as $roots
    | def kids($names): [ $all[] | select(((.metadata.labels["app.kubernetes.io/instance"] // "") as $p | $names | index($p)) or
          ((.metadata.ownerReferences // [])[] | select(.kind=="ApplicationSet") | .name) as $o | ($all[] | select(.kind=="ApplicationSet" and .metadata.name==$o) | .metadata.labels["app.kubernetes.io/instance"] // "") as $p | $names | index($p)) ];
    def closure($set): ($set | map(.metadata.name)) as $n | (kids($n) | map(select(.kind=="Application"))) as $k
        | if ($k | map(.metadata.name) - $n | length) == 0 then $set else closure(($set + $k) | unique_by(.metadata.name)) end;
    closure($roots) as $deps
    | if ($deps|length)==0 then "none" else
      ( [ $deps[] | select(.status.sync.status != "Synced" or .status.health.status != "Healthy"
            or ((.spec.source.repoURL|rtrimstr(".git")) == ($url|rtrimstr(".git")) and .status.sync.revision != $sha)) ] | length ) == 0 end
    | if . == "none" then error("none") else . end' <<< "$(apps_json)" >/dev/null 2>"$work/herr"
  local rc=$?
  grep -q '"none"' "$work/herr" 2>/dev/null && return 2
  return $rc
}

# ── git ──────────────────────────────────────────────────────────────────────
forgejo_tip() { # $1 repo $2 ref → sha or "" ; exit 1 on transport failure
  local out rc=0
  out=$(git ls-remote --exit-code "$FORGEJO_URL/$ORG/$1.git" "refs/heads/$2" 2>/dev/null) || rc=$?
  case "$rc" in 0) printf '%s' "${out%%[[:space:]]*}" ;; 2) printf '' ;; *) echo "$1: forgejo unreachable (ls-remote exit $rc)" >&2; return 1 ;; esac
}
github_sha() { # $1 owner/repo $2 ref (branch or tag) → sha or ""
  local out; out=$(git ls-remote "$GITHUB_BASE/$1.git" "$2" 2>/dev/null) || { echo "$1: github ls-remote failed" >&2; return 1; }
  printf '%s' "${out%%[[:space:]]*}"
}
# Stage into refs/heads/incoming (any state, it is scratch), verify, then
# fast-forward main with a lease on the tip we saw. Protection refuses a
# non-fast-forward for everyone, so a refusal here is a divergence (3b-7).
move_main() { # $1 repo $2 github owner/repo $3 target sha → 0 moved/up-to-date, 1 refused/failed
  local repo="$1" upstream="$2" sha="$3" expected d="$work/$repo"
  expected=$(forgejo_tip "$repo" main) || return 1
  [ "$expected" = "$sha" ] && { echo "$repo: up to date at ${sha:0:12}"; return 0; }
  rm -rf "$d"; git init -q -b main "$d" || return 1
  git -C "$d" fetch -q "$GITHUB_BASE/$upstream.git" "$sha" || { echo "$repo: fetch $sha from github failed" >&2; return 1; }
  git -C "$d" push -q --force "$FORGEJO_URL/$ORG/$repo.git" "$sha:refs/heads/incoming" || { echo "$repo: staging push failed" >&2; return 1; }
  [ "$(forgejo_tip "$repo" incoming)" = "$sha" ] || { echo "$repo: incoming did not land at $sha" >&2; return 1; }
  git -C "$d" push -q "$FORGEJO_URL/$ORG/$repo.git" "--force-with-lease=refs/heads/main:$expected" "$sha:refs/heads/main" \
    || { echo "$repo: main move refused (lease ${expected:-<absent>} → ${sha:0:12}); protection rejects non-fast-forward: see docs/forgejo.md 'Recovering a diverged main'" >&2; return 1; }
  echo "$repo: ${expected:-<absent>} -> ${sha:0:12}"
}

# ── targets: main follows GitHub main; live follows the newest complete tag set ─
declare -A TARGET=()
mapfile -t LINES < <(grep -v '^[[:space:]]*$' "$REPOS_FILE")
state_load
promotion=null
if [ "$SOURCE_REF" = main ]; then
  for l in "${LINES[@]}"; do set -- $l; TARGET[$1]=$(github_sha "$2" refs/heads/main) || exit 1; done
else
  # live-<n> present in ALL repositories; the highest such n is the target.
  declare -A TAGS=()
  for l in "${LINES[@]}"; do set -- $l
    TAGS[$1]=$(git ls-remote --tags "$GITHUB_BASE/$2.git" 'refs/tags/live-*' 2>/dev/null | awk '{print $2}' | sed 's|refs/tags/live-||; /\^{}$/d' | sort -n | tr '\n' ' ') || exit 1
  done
  best=""
  for n in $(printf '%s\n' "${TAGS[@]}" | tr ' ' '\n' | sort -nu); do
    ok=1; for l in "${LINES[@]}"; do set -- $l; [[ " ${TAGS[$1]} " == *" $n "* ]] || ok=0; done
    [ $ok = 1 ] && best=$n
  done
  [ -n "$best" ] || { echo "live: no complete tag set yet; nothing to do"; state_set '.sourceRef="live" | .repos |= with_entries(.value.lastRun=$now)'; state_save; exit 0; }
  promotion=$best
  for l in "${LINES[@]}"; do set -- $l; TARGET[$1]=$(github_sha "$2" "refs/tags/live-$best^{}") ; [ -n "${TARGET[$1]}" ] || TARGET[$1]=$(github_sha "$2" "refs/tags/live-$best") || exit 1; done
fi

# ── move, then record health ─────────────────────────────────────────────────
fails=0
state_set --arg p "$promotion" '.sourceRef=$ENV.SOURCE_REF' 2>/dev/null || true
jq --argjson p "$promotion" '.promotion=$p' "$work/state.json" > "$work/s" && mv "$work/s" "$work/state.json"
for l in "${LINES[@]}"; do set -- $l; name=$1 upstream=$2 sha=${TARGET[$1]}
  if move_main "$name" "$upstream" "$sha"; then
    jq --arg n "$name" --arg sha "$sha" --arg now "$(now)" '.pending -= [$n] | .repos[$n] = ((.repos[$n] // {}) + {commit:$sha,lastRun:$now,lastResult:"ok"})' "$work/state.json" > "$work/s" && mv "$work/s" "$work/state.json"
  else
    fails=$((fails+1))
    jq --arg n "$name" --arg now "$(now)" '.pending = ((.pending + [$n]) | unique) | .repos[$n] = ((.repos[$n] // {}) + {lastRun:$now,lastResult:"failed"})' "$work/state.json" > "$work/s" && mv "$work/s" "$work/state.json"
  fi
done
for l in "${LINES[@]}"; do set -- $l; name=$1; sha=$(jq -r --arg n "$name" '.repos[$n].commit // ""' "$work/state.json"); [ -n "$sha" ] || continue
  repo_healthy "$name" "$sha"; hrc=$?
  case $hrc in
    0) jq --arg n "$name" --arg now "$(now)" '.repos[$n].healthySince = (.repos[$n].healthySince // $now)' "$work/state.json" > "$work/s" && mv "$work/s" "$work/state.json" ;;
    2) echo "$name: no dependent Application found; healthySince not tracked" ;;
    *) jq --arg n "$name" '.repos[$n].healthySince = null' "$work/state.json" > "$work/s" && mv "$work/s" "$work/state.json" ;;
  esac
done
state_save
echo "puller[$SOURCE_REF${promotion:+ live-$promotion}]: $(( ${#LINES[@]} - fails ))/${#LINES[@]} repositories in sync; pending: $(jq -c .pending "$work/state.json")"
[ "$fails" -eq 0 ]
```

(The stray `state_set --arg …` line is a no-op guard and must be deleted before commit; the `jq --argjson p` line is what sets `promotion`. Keep the script shellcheck-clean.)

- [ ] **Step 3: Composition.** Add after `rolebinding-init`: Role `forgejo-puller-state` (`configmaps`, `create` unrestricted; `get`, `update`, `patch` with `resourceNames: [forgejo-puller-state]`) and RoleBinding in `forgejo`; Role `forgejo-puller-apps` in namespace `argo` (`argoproj.io` `applications`, `applicationsets`: `get`, `list`) and RoleBinding to SA `forgejo-puller` of namespace `forgejo`. On the puller pod spec set `automountServiceAccountToken: true` (and remove the `false` on the ServiceAccount). Env: `STATE_CONFIGMAP=forgejo-puller-state`, `NAMESPACE={{ $ns }}`, `ARGO_NAMESPACE=argo`. Bump `$jobGeneration` to `"2026-11-13.1"`. Render test: durable + observed-configured renders `name: forgejo-puller-apps`, `namespace: argo`, `resourceNames:` … `- forgejo-puller-state`, `name: SOURCE_REF`.

- [ ] **Step 4: Docs.** `docs/forgejo.md` "The puller": the state ConfigMap and its keys; `live` mode and the tag set; `incoming`; `pending` and resume. New section **"Recovering a diverged `main`"** (3b-7), the runbook: (1) confirm with `git ls-remote` on Forgejo and GitHub that Forgejo's `main` is not an ancestor of the target; (2) delete the rule: `curl -K <auth> -X DELETE $FORGEJO_URL/api/v1/repos/siliconsaga/<repo>/branch_protections/main` from a one-off Job using the `forgejo-admin` Secret, or the break-glass account in the UI; (3) `kubectl create job -n forgejo --from=cronjob/forgejo-puller puller-recover-$(date +%s)` — the lease push now succeeds as a forced move is not needed (the puller pushes `--force-with-lease`, which protection no longer blocks); (4) re-create the rule by re-running the configure Job: `kubectl delete job -n forgejo -l app=forgejo-configure` is wrong (names are hashed) — instead `kubectl get jobs -n forgejo | grep forgejo-configure`, delete the current one, provider-kubernetes recreates it and section 5 reconciles the rule. State that this is the only sanctioned non-fast-forward path.

- [ ] **Step 5: Run** `bash tests/scripts/forgejo-puller-test.sh` → PASS; `bash tests/render/check-forgejo.sh` → PASS.

- [ ] **Step 6: Commit.** Message `feat(forgejo): puller records state and soak health; live follows complete tag sets; incoming staging`.

---

### Task 15: `promote.sh` and `protect-live.sh` (nordri)

**Files:**
- Create: `scripts/promote.sh`, `scripts/protect-live.sh`, `tests/unit/promote-test.sh`
- Modify: `tests/run.sh:7`

**Interfaces:**
- Consumes: ConfigMap `forgejo-puller-state` on `homelab-prod` (current context), Prometheus in `heimdall`, `gh` authenticated as the owner, the realm's Forgejo claim for the repo list (`cluster/forgejo/claim.yaml` `repos[].github`).
- Produces: `scripts/promote.sh gke [--soak <duration>] [--unsoaked] [--to <repo>=<sha>]... [--init]`; promotion log in the realm at `promotions/live-<n>.md` (committed by the operator); `scripts/protect-live.sh <realm>` creates or updates the two rulesets on each of the five repositories.

- [ ] **Step 1: Write the failing test** `tests/unit/promote-test.sh`. Stubs: `kubectl` (returns a state ConfigMap JSON with `healthySince` 30h ago for four repos and 2h for one; `get applications -o json` all Synced/Healthy at the recorded commits; `get pods -n heimdall` a pod name; `exec` answers the Prometheus query with an empty result), `gh` (records calls; answers `matching-refs/tags/live-` with `live-1` everywhere, and `git/ref/heads/live` with a sha). Assert: (a) with the 2h repo the script asks and, with stdin `n`, exits 3 having written nothing; (b) with `--unsoaked` it fast-forwards five `live` refs (`PATCH .../git/refs/heads/live` with `force: false`) then creates five `live-2` tags, in that order, and prints the ages; (c) a Degraded Application in the fixture refuses before any `gh` write (exit 2); (d) a Prometheus result with a non-Healthy sample refuses; (e) `--init` with no `live` ref creates `refs/heads/live` and tag `live-1`; (f) an incomplete `live-2` (four of five) is completed with the same commits recorded in `promotions/live-2.md`, never a new set.

- [ ] **Step 2: `scripts/promote.sh`:**

```bash
#!/usr/bin/env bash
# promote.sh — move GitHub's live branch to what homelab-prod has run healthy,
# as one numbered tag set across the five repositories (realm Phase 3 design,
# 3b-2). Health is a gate; the soak window is a recommendation (2026-11-12).
#
#   scripts/promote.sh gke [--soak <dur>] [--unsoaked] [--to <repo>=<sha>]... [--init]
#
# Runs against kubectl's CURRENT context, which must be homelab-prod (the live
# identity is checked). Reads forgejo-puller-state and the Applications there,
# queries Prometheus in heimdall over the window, then writes to GitHub with gh
# as whoever is logged in. Writes nothing until every check has passed. The
# promotion log is written to <realm>/promotions/live-<n>.md for you to commit.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$SCRIPT_DIR/lib/identity.sh"
[[ "${1:-}" == "gke" ]] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }; shift
SOAK="24h"; UNSOAKED=0; INIT=0; declare -A OVERRIDE=()
while [[ $# -gt 0 ]]; do case "$1" in
  --soak) SOAK="$2"; shift 2 ;; --unsoaked) UNSOAKED=1; shift ;; --init) INIT=1; shift ;;
  --to) [[ "$2" =~ ^([a-z0-9-]+)=([0-9a-f]{40})$ ]] || { echo "❌ --to wants <repo>=<40-hex sha>" >&2; exit 1; }; OVERRIDE[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}; shift 2 ;;
  *) echo "❌ unknown argument $1" >&2; exit 1 ;; esac; done
soak_seconds() { case "$1" in *h) echo $(( ${1%h} * 3600 )) ;; *d) echo $(( ${1%d} * 86400 )) ;; *m) echo $(( ${1%m} * 60 )) ;; *) echo "❌ --soak wants Nh, Nd or Nm" >&2; exit 1 ;; esac; }
SOAK_S=$(soak_seconds "$SOAK")
REALM="${REALM:-realm-siliconsaga}"; REALM_DIR="${REALM_DIR:-$(dirname "$(dirname "$SCRIPT_DIR")")/realms/$REALM}"
CLAIM="$REALM_DIR/cluster/forgejo/claim.yaml"
[[ -f "$CLAIM" ]] || { echo "❌ no Forgejo claim at $CLAIM" >&2; exit 1; }

cluster="$(identity_live_value cluster)"; role="$(identity_live_value role)"; sref="$(identity_live_value sourceRef)"
[[ "$role" == prod && "$sref" == main ]] || { echo "❌ current context is cluster '${cluster:-?}' (role ${role:-?}, sourceRef ${sref:-?}); promote.sh reads homelab-prod, a prod cluster on main. Switch context first." >&2; exit 1; }
echo "🎯 reading soak state from $cluster"

# repos: name → owner/repo, from the claim (flat `- {name: x, github: o/r}` lines)
declare -A GH=()
while read -r name upstream; do GH[$name]=$upstream; done < <(sed -n 's/^ *- *{ *name: *\([a-z0-9-]*\), *github: *\([A-Za-z0-9_./-]*\) *}.*/\1 \2/p' "$CLAIM")
[[ ${#GH[@]} -eq 5 ]] || { echo "❌ expected five maintained repositories in the claim, found ${#GH[@]}" >&2; exit 1; }

state=$(kubectl get configmap -n forgejo forgejo-puller-state -o jsonpath='{.data.state\.json}' 2>/dev/null) || state=""
[[ -n "$state" ]] || { echo "❌ no forgejo-puller-state on $cluster; the puller has not run" >&2; exit 1; }
apps=$(kubectl get applications -n argo -o json)
now=$(date -u +%s)

# ── the frozen candidate set ────────────────────────────────────────────────
declare -A SHA=() AGE=() NOTE=()
for name in "${!GH[@]}"; do
  if [[ -n "${OVERRIDE[$name]:-}" ]]; then SHA[$name]=${OVERRIDE[$name]}; AGE[$name]=-1; NOTE[$name]="overridden with --to"; continue; fi
  SHA[$name]=$(jq -r --arg n "$name" '.repos[$n].commit // ""' <<< "$state")
  [[ -n "${SHA[$name]}" ]] || { echo "❌ $name: no commit recorded by the puller" >&2; exit 2; }
  hs=$(jq -r --arg n "$name" '.repos[$n].healthySince // ""' <<< "$state")
  if [[ -z "$hs" ]]; then AGE[$name]=-1; NOTE[$name]="not healthy at the last puller run"; else AGE[$name]=$(( now - $(date -u -d "$hs" +%s) )); NOTE[$name]=""; fi
done

# ── health gate 1: live re-check ────────────────────────────────────────────
bad=$(jq -r --argjson want "$(for n in "${!SHA[@]}"; do printf '{"repo":"%s","sha":"%s"}\n' "$n" "${SHA[$n]}"; done | jq -s .)" '
  [ .items[] | select(.spec.source.repoURL | test("git.gitops.svc.cluster.local:3000/[^/]+/(" + ($want|map(.repo)|join("|")) + ")\\.git$")) ]
  | map(select(.status.sync.status != "Synced" or .status.health.status != "Healthy")) | map(.metadata.name) | join(" ")' <<< "$apps")
[[ -z "$bad" ]] || { echo "❌ health gate: not Synced and Healthy right now: $bad" >&2; exit 2; }
unhealthy_now=$(jq -r '[ .items[] | select(.status.health.status != "Healthy") | .metadata.name ] | join(" ")' <<< "$apps")
[[ -z "$unhealthy_now" ]] || { echo "❌ health gate: Applications not Healthy on $cluster: $unhealthy_now" >&2; exit 2; }

# ── health gate 2: Prometheus over the window ───────────────────────────────
prom=$(kubectl get pods -n heimdall -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[[ -n "$prom" ]] || { echo "❌ no Prometheus pod in heimdall; the window cannot be checked" >&2; exit 2; }
q='count_over_time(argocd_app_info{health_status!="Healthy"}['"${SOAK}"'])'
res=$(kubectl exec -n heimdall "$prom" -c prometheus -- wget -qO- "http://localhost:9090/api/v1/query?query=$(jq -rn --arg q "$q" '$q|@uri')" 2>/dev/null) || res=""
[[ -n "$res" ]] || { echo "❌ Prometheus did not answer" >&2; exit 2; }
cover=$(kubectl exec -n heimdall "$prom" -c prometheus -- wget -qO- "http://localhost:9090/api/v1/query?query=$(jq -rn --arg q "count_over_time(argocd_app_info[${SOAK}])" '$q|@uri')" 2>/dev/null | jq -r '.data.result | length')
[[ "${cover:-0}" -gt 0 ]] || { echo "❌ Prometheus has no argocd_app_info samples covering the last $SOAK" >&2; exit 2; }
sick=$(jq -r '[.data.result[] | .metric.name] | unique | join(" ")' <<< "$res")
[[ -z "$sick" ]] || { echo "❌ health gate: not Healthy at some point in the last $SOAK: $sick" >&2; exit 2; }

# ── the soak, a recommendation ──────────────────────────────────────────────
echo; echo "candidate set (soak window $SOAK):"; under=()
for name in $(printf '%s\n' "${!SHA[@]}" | sort); do
  if [[ ${AGE[$name]} -lt 0 ]]; then printf '  %-18s %s  UNSOAKED (%s)\n' "$name" "${SHA[$name]:0:12}" "${NOTE[$name]}"; under+=("$name")
  elif [[ ${AGE[$name]} -lt $SOAK_S ]]; then printf '  %-18s %s  %dh healthy, under the window\n' "$name" "${SHA[$name]:0:12}" $(( AGE[$name] / 3600 )); under+=("$name")
  else printf '  %-18s %s  %dh healthy\n' "$name" "${SHA[$name]:0:12}" $(( AGE[$name] / 3600 )); fi
done
waived=no
if [[ ${#under[@]} -gt 0 ]]; then
  if [[ $UNSOAKED -eq 1 ]]; then waived="yes (--unsoaked)"; else
    read -r -p "Promote with ${under[*]} under the window? [y/N] " ans </dev/tty
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "not promoting"; exit 3; }; waived="yes (confirmed)"
  fi
fi

# ── promotion number: finish an incomplete set, never reuse one ─────────────
declare -A HAVE=()
max=0
for name in "${!GH[@]}"; do
  tags=$(gh api "repos/${GH[$name]}/git/matching-refs/tags/live-" --jq '.[].ref' 2>/dev/null | sed 's|refs/tags/live-||' | sort -n)
  HAVE[$name]="$tags"; last=$(printf '%s\n' "$tags" | tail -1); [[ ${last:-0} -gt $max ]] && max=$last
done
complete=1; for name in "${!GH[@]}"; do grep -qx "$max" <<< "${HAVE[$name]}" || complete=0; done
if [[ $max -eq 0 ]]; then
  [[ $INIT -eq 1 ]] || { echo "❌ no live-<n> tag exists yet; run with --init for the first promotion" >&2; exit 1; }; n=1
elif [[ $complete -eq 0 ]]; then
  n=$max; echo "⚠ promotion live-$n is incomplete; finishing it with its recorded commits"
  logf="$REALM_DIR/promotions/live-$n.md"; [[ -f "$logf" ]] || { echo "❌ live-$n is incomplete and $logf is missing; cannot know its commits" >&2; exit 1; }
  while read -r r s; do SHA[$r]=$s; done < <(sed -n 's/^| \([a-z0-9-]*\) | \([0-9a-f]\{40\}\) |.*/\1 \2/p' "$logf")
else
  n=$((max + 1))
fi

# ── write: branches first, then the tag set, tags last ──────────────────────
for name in $(printf '%s\n' "${!GH[@]}" | sort); do
  repo=${GH[$name]}; sha=${SHA[$name]}
  if gh api "repos/$repo/git/ref/heads/live" --jq .object.sha >/dev/null 2>&1; then
    cur=$(gh api "repos/$repo/git/ref/heads/live" --jq .object.sha)
    if [[ "$cur" != "$sha" ]]; then
      echo "   $name: live $cur -> $sha"; gh api -X PATCH "repos/$repo/git/refs/heads/live" -f sha="$sha" -F force=false >/dev/null || { echo "❌ $name: fast-forward of live refused" >&2; exit 4; }
    fi
  else
    [[ $INIT -eq 1 ]] || { echo "❌ $name has no live branch; --init creates it" >&2; exit 4; }
    gh api -X POST "repos/$repo/git/refs" -f ref="refs/heads/live" -f sha="$sha" >/dev/null || exit 4
  fi
done
mkdir -p "$REALM_DIR/promotions"; logf="$REALM_DIR/promotions/live-$n.md"
{ echo "# live-$n — $(date -u +%Y-%m-%dT%H:%M:%SZ)"; echo; echo "Soak window $SOAK; waived: $waived. Promoted from $cluster."; echo
  echo "| repo | commit | healthy for | note |"; echo "|---|---|---|---|"
  for name in $(printf '%s\n' "${!GH[@]}" | sort); do printf '| %s | %s | %s | %s |\n' "$name" "${SHA[$name]}" "$([[ ${AGE[$name]} -ge 0 ]] && echo "$(( AGE[$name] / 3600 ))h" || echo "-")" "${NOTE[$name]}"; done
} > "$logf"
for name in $(printf '%s\n' "${!GH[@]}" | sort); do
  grep -qx "$n" <<< "${HAVE[$name]}" && continue
  gh api -X POST "repos/${GH[$name]}/git/refs" -f ref="refs/tags/live-$n" -f sha="${SHA[$name]}" >/dev/null || { echo "❌ ${GH[$name]}: tag live-$n failed; re-run to finish the set" >&2; exit 4; }
done
echo "✅ live-$n complete on all five repositories. Commit $logf to the realm."
```

- [ ] **Step 3: `scripts/protect-live.sh <realm>`:** for each of the five repositories creates (or `PUT`s when a ruleset of the same name exists) two rulesets via `gh api -X POST repos/<o>/<r>/rulesets --input <json>`: `live-branch` (`target: branch`, include `refs/heads/live`, rules `deletion`, `non_fast_forward`, `update`; bypass `{actor_id: 5, actor_type: RepositoryRole, bypass_mode: always}`) and `live-tags` (`target: tag`, include `refs/tags/live-*`, rules `deletion`, `update`, `creation`, same bypass). Step 1 of the task: run it on **one** repository, `gh api repos/<o>/<r>/rulesets --jq '.[] | {name, enforcement}'` lists both, and `gh api repos/<o>/<r>/rulesets/<id> --jq .bypass_actors` shows the admin role; then the remaining four.

- [ ] **Step 4: Run** `bash tests/unit/promote-test.sh` → `ALL PASS`; `bash tests/run.sh test && bash tests/run.sh lint` (add both scripts to `shell_files`).

- [ ] **Step 5: Commit.** Message `feat(promote): numbered live tag sets from homelab-prod's soak state; GitHub rulesets for live`.

---

### Task 16: `graduate.sh` (nordri)

**Files:**
- Create: `scripts/graduate.sh`, `tests/unit/graduate-test.sh`
- Modify: `tests/run.sh:7`, `docs/bootstrap.md` (a "Graduation" section)

**Interfaces:**
- Consumes: `lib/gitops.sh` (`gitops_git_service_target`, `gitops_ensure_git_service`), `lib/argo.sh`, `lib/identity.sh`, `lib/seed-access.sh`, `lib/hydrate.sh`; Forgejo's `forgejo-admin` Secret; the seed's commits' `Source-Commit:` trailers (Task 4).
- Produces: `scripts/graduate.sh <realm> <cluster> [--accept-diff] [--accept-unverified]`, `--rollback [--refresh-seed] [--accept-diff|--accept-unverified]`, `--retire-seed [--force]`. Service annotation `nordri.siliconsaga.org/repointed-at` (written by `gitops_ensure_git_service`).

- [ ] **Step 1: Write the failing test** `tests/unit/graduate-test.sh` with `kubectl`, `git`, `curl` stubs: asserts the preconditions (maturity not durable → exit 1 naming maturity; Forgejo unhealthy → exit 1; a missing repository → exit 1; a vendor tag the Applications pin that Forgejo lacks → exit 1), the content check (differing trees → exit 2 without `--accept-diff`, proceeds with it), the repoint (`gitops_ensure_git_service forgejo-http.forgejo.svc.cluster.local` then refresh then waits), `--rollback` with Forgejo down (`--accept-unverified` required; `--refresh-seed` refused), `--retire-seed` before three days (exit 1, `--force` passes the duration only), and the `test`-role populate step pushing to Forgejo first.

- [ ] **Step 2: `scripts/graduate.sh`.** Structure (every function short; the flow at the bottom):

```bash
#!/usr/bin/env bash
# graduate.sh — repoint a cluster's stable git Service from the seed to its
# Forgejo, roll it back, or retire the seed (realm Phase 3 design, 3b-3).
#   scripts/graduate.sh <realm> <cluster> [--accept-diff] [--accept-unverified]
#   scripts/graduate.sh <realm> <cluster> --rollback [--refresh-seed] [--accept-diff|--accept-unverified]
#   scripts/graduate.sh <realm> <cluster> --retire-seed [--force]
# Follows kubectl's current context; refuses when the live identity names
# another cluster. Reads both servers by port-forward; writes only the Service,
# the hard refresh, and (test role, or --refresh-seed) a verbatim push.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
for l in gitea hydrate identity gitops kube-context argo seed-access; do . "$SCRIPT_DIR/lib/$l.sh"; done
REALM="${1:-}"; CLUSTER="${2:-}"; shift 2 || true
MODE=graduate; ACCEPT_DIFF=0; ACCEPT_UNVERIFIED=0; REFRESH_SEED=0; FORCE=0
while [[ $# -gt 0 ]]; do case "$1" in
  --rollback) MODE=rollback ;; --retire-seed) MODE=retire ;; --accept-diff) ACCEPT_DIFF=1 ;;
  --accept-unverified) ACCEPT_UNVERIFIED=1 ;; --refresh-seed) REFRESH_SEED=1 ;; --force) FORCE=1 ;;
  *) echo "❌ unknown argument $1" >&2; exit 1 ;; esac; shift; done
[[ -n "$REALM" && -n "$CLUSTER" ]] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
live="$(identity_live_value cluster)"; [[ "$live" == "$CLUSTER" ]] || { echo "❌ the current context is cluster '${live:-?}', not '$CLUSTER'" >&2; exit 1; }
ROLE="$(identity_live_value role)"; MATURITY="$(identity_live_value maturity)"; TARGET="$(identity_live_value environment)"
require_kube_context "$TARGET" || exit 1
ORG="$(gitops_canonical_org "$REALM")"; VORG="$(gitops_vendor_org "$REALM")"
REPOS=(nordri nidavellir mimir heimdall "$REALM")
work=$(mktemp -d); trap 'rm -rf "$work"; [[ -n "${PF_PID:-}" ]] && kill "$PF_PID" 2>/dev/null' EXIT

forgejo_open() { # port-forward forgejo-http on 3001; sets FJ_URL FJ_USER FJ_PASS_FILE
  kubectl port-forward svc/forgejo-http -n forgejo 3001:3000 >/dev/null 2>&1 & PF_FJ=$!
  for _ in $(seq 1 30); do curl -fsS --max-time 2 http://localhost:3001/api/healthz >/dev/null 2>&1 && break; sleep 1; done
  curl -fsS --max-time 2 http://localhost:3001/api/healthz >/dev/null 2>&1 || return 1
  FJ_URL=http://localhost:3001; FJ_USER=$(kubectl get secret -n forgejo forgejo-admin -o jsonpath='{.data.username}' | base64 -d)
  umask 077; kubectl get secret -n forgejo forgejo-admin -o jsonpath='{.data.password}' | base64 -d > "$work/fjpw"; FJ_PASS_FILE="$work/fjpw"
  printf 'user = "%s:%s"\n' "$FJ_USER" "$(cat "$FJ_PASS_FILE")" > "$work/fj.cfg"
}
fj_api() { curl -sS -o "$work/resp" -w '%{http_code}' -K "$work/fj.cfg" "$FJ_URL/api/v1$1"; }
# Tags every Application pins on a vendor repository: (repo, tag) pairs.
pinned_vendor_tags() { kubectl get applications -n argo -o json | jq -r --arg v "$VORG" '.items[] | select(.spec.source.repoURL | test("/" + $v + "/")) | [(.spec.source.repoURL | capture("/(?<r>[^/]+)\\.git$").r), .spec.source.targetRevision] | @tsv'; }
tags_resolve_on() { # $1 base url (with creds in GITEA_GIT_BASE form or plain) → 0 when every pinned tag exists
  local ok=0 r t
  while IFS=$'\t' read -r r t; do [[ -z "$r" ]] && continue
    git ls-remote --exit-code --tags "$1/$VORG/$r.git" "refs/tags/$t" >/dev/null 2>&1 || { echo "   vendor tag $r@$t missing on $1" >&2; ok=1; }
  done < <(pinned_vendor_tags); return $ok
}
tree_sha() { # $1 url $2 ref → the tree sha of that commit, via a shallow fetch
  local d="$work/t-$RANDOM"; git init -q "$d" && git -C "$d" fetch -q --depth 1 "$1" "$2" 2>/dev/null && git -C "$d" rev-parse FETCH_HEAD^{tree}; rm -rf "$d"
}
content_diff() { # $1 from-base $2 to-base → prints differing repos; returns count
  local n=0 r a b
  for r in "${REPOS[@]}"; do a=$(tree_sha "$1/$ORG/$r.git" HEAD); b=$(tree_sha "$2/$ORG/$r.git" main)
    [[ -n "$a" && "$a" == "$b" ]] || { echo "   $r: trees differ (${a:0:12} vs ${b:0:12})"; n=$((n+1)); }
  done; return $n
}
populate_test_forgejo() { # role test: push the seed's trees verbatim into Forgejo (same push update-embedded-git.sh --target forgejo makes)
  echo "📤 role test: filling Forgejo from the seed"; local r d
  for r in "${REPOS[@]}"; do d="$work/p-$r"; git clone -q "$GITEA_GIT_BASE/$ORG/$r.git" "$d" || return 1
    git -C "$d" push -q --force "http://$FJ_USER:$(cat "$FJ_PASS_FILE")@localhost:3001/$ORG/$r.git" HEAD:refs/heads/main || return 1; done
}
preconditions() {
  [[ "$MATURITY" == durable || "$MATURITY" == full ]] || { echo "❌ maturity is '$MATURITY'; graduation needs durable" >&2; return 1; }
  forgejo_open || { echo "❌ Forgejo is not answering /api/healthz" >&2; return 1; }
  local r code
  for r in "${REPOS[@]}"; do code=$(fj_api "/repos/$ORG/$r/branches/main"); [[ "$code" == 200 ]] || { echo "❌ Forgejo $ORG/$r has no main (HTTP $code)" >&2; return 1; }; done
  while IFS=$'\t' read -r r _; do [[ -z "$r" ]] && continue; code=$(fj_api "/repos/$VORG/$r"); [[ "$code" == 200 ]] || { echo "❌ vendor mirror $VORG/$r missing on Forgejo" >&2; return 1; }; done < <(pinned_vendor_tags)
  if [[ "$ROLE" == prod ]]; then
    local last; last=$(kubectl get configmap -n forgejo forgejo-puller-state -o jsonpath='{.data.state\.json}' 2>/dev/null | jq -r '[.repos[].lastResult] | all(. == "ok")' 2>/dev/null)
    [[ "$last" == true ]] || { echo "❌ the puller's last run did not succeed for every repository" >&2; return 1; }
  fi
  tags_resolve_on "http://$FJ_USER:$(cat "$FJ_PASS_FILE")@localhost:3001" || { echo "❌ a pinned vendor tag does not resolve on Forgejo" >&2; return 1; }
}
repoint_and_wait() { gitops_ensure_git_service "$1" || return 1; argo_hard_refresh_all; argo_wait_operations_done 900 && argo_wait_synced_healthy 1200; }

case "$MODE" in
graduate)
  seed_access_open || exit 1
  preconditions || exit 1
  [[ "$ROLE" == test ]] && { populate_test_forgejo || exit 1; }
  echo "🔍 content: seed HEAD vs Forgejo main"
  if ! content_diff "$GITEA_GIT_BASE" "http://$FJ_USER:$(cat "$FJ_PASS_FILE")@localhost:3001"; then
    [[ $ACCEPT_DIFF -eq 1 ]] || { echo "❌ the repoint would change what the cluster runs; re-run with --accept-diff" >&2; exit 2; }
  fi
  repoint_and_wait "$GIT_FORGEJO_SERVICE" || exit 1
  echo "✅ $CLUSTER reads Forgejo. The seed stays as the rollback target (≥3 days; prod: until Phase 4's drills)." ;;
rollback)
  seed_access_open || exit 1
  tags_resolve_on "$GITEA_GIT_BASE" || { echo "❌ a pinned vendor tag does not resolve on the seed; rollback would leave that Application unable to sync" >&2; exit 1; }
  if forgejo_open; then
    if [[ $REFRESH_SEED -eq 1 ]]; then echo "📤 refreshing the seed from Forgejo main"; HYDRATE_COMMITTER="Nordri Rollback"
      for r in "${REPOS[@]}"; do d="$work/r-$r"; git clone -q --branch main "http://$FJ_USER:$(cat "$FJ_PASS_FILE")@localhost:3001/$ORG/$r.git" "$d" || exit 1; git -C "$d" push -q --force "$GITEA_GIT_BASE/$ORG/$r.git" HEAD:refs/heads/main || exit 1; done
      while IFS=$'\t' read -r r _; do [[ -z "$r" ]] && continue; curl -sS -o /dev/null -u "$GITEA_USER:$GITEA_PASS" -X POST "$GITEA_API_URL/api/v1/repos/$VORG/$r/mirror-sync" || true; done < <(pinned_vendor_tags)
    fi
    echo "🔍 content: Forgejo main vs seed HEAD"
    if ! content_diff "http://$FJ_USER:$(cat "$FJ_PASS_FILE")@localhost:3001" "$GITEA_GIT_BASE"; then
      [[ $ACCEPT_DIFF -eq 1 ]] || { echo "❌ rollback would change what the cluster runs; re-run with --accept-diff (or --refresh-seed)" >&2; exit 2; }
    fi
  else
    [[ $REFRESH_SEED -eq 0 ]] || { echo "❌ --refresh-seed needs Forgejo readable" >&2; exit 1; }
    echo "⚠ Forgejo cannot be read: comparing the seed snapshots' Source-Commit trailers with the revisions the cluster recorded (UNVERIFIED)"
    for r in "${REPOS[@]}"; do src=$(git ls-remote "$GITEA_GIT_BASE/$ORG/$r.git" HEAD | cut -c1-40); d="$work/s-$r"; git init -q "$d"; git -C "$d" fetch -q --depth 1 "$GITEA_GIT_BASE/$ORG/$r.git" "$src"
      trailer=$(git -C "$d" log -1 --format=%B FETCH_HEAD | sed -n 's/^Source-Commit: //p'); rec=$(kubectl get configmap -n forgejo forgejo-puller-state -o jsonpath='{.data.state\.json}' 2>/dev/null | jq -r --arg n "$r" '.repos[$n].commit // ""')
      printf '   %-18s seed snapshot from %s, cluster recorded %s %s\n' "$r" "${trailer:-?}" "${rec:-?}" "$([[ "$trailer" == "$rec" && -n "$rec" ]] && echo same || echo DIFFERENT)"; done
    [[ $ACCEPT_UNVERIFIED -eq 1 ]] || { echo "❌ unverified; re-run with --accept-unverified to repoint anyway" >&2; exit 2; }
  fi
  repoint_and_wait "$GIT_SEED_SERVICE" || exit 1; echo "✅ $CLUSTER reads the seed again." ;;
retire)
  at=$(kubectl get service git -n gitops -o jsonpath='{.metadata.annotations.nordri\.siliconsaga\.org/repointed-at}' 2>/dev/null)
  [[ "$(gitops_git_service_target)" == "$GIT_FORGEJO_SERVICE" ]] || { echo "❌ the git Service does not point at Forgejo; nothing to retire from" >&2; exit 1; }
  age=$(( $(date -u +%s) - $(date -u -d "$at" +%s) ))
  [[ $age -ge 259200 || $FORCE -eq 1 ]] || { echo "❌ repointed $((age/3600))h ago; the seed stays at least 72h (--force overrides only this)" >&2; exit 1; }
  [[ "$ROLE" != prod ]] || { echo "❌ a prod cluster keeps its seed until the Phase 4 restore drills pass (record's retirement gates); not implemented here by design" >&2; exit 1; }
  preconditions || exit 1
  helm uninstall gitea -n gitea && kubectl delete namespace gitea --wait=false && echo "✅ seed retired on $CLUSTER" ;;
esac
```

- [ ] **Step 3: Run** `bash tests/unit/graduate-test.sh` → `ALL PASS`; suites and lint.

- [ ] **Step 4: Docs.** `docs/bootstrap.md` "Graduation": the three modes, the three-day rule, that a prod cluster's seed stays through Phase 4.

- [ ] **Step 5: Commit.** Message `feat(graduate): repoint the git Service to Forgejo, roll back, retire the seed`.

- [ ] **Step 6: Graduate `homelab-prod`** (operations): context to homelab-prod; `scripts/graduate.sh realm-siliconsaga homelab-prod`; every Application green against Forgejo; `kubectl get svc git -n gitops` shows `forgejo-http.forgejo.svc.cluster.local`.

- [ ] **Step 7: Exercise rollback on a test cluster** (3b-8 gate): on Nano76 (`role test`, `durable`): `graduate.sh realm-siliconsaga homelab-nano76win11` (populates Forgejo, repoints), then `--rollback` (same content, no flag needed), then forward again. Record in the CR.

---

### Task 17: heimdall — Forgejo probe, two ArgoCD/puller rules, routing (heimdall)

**Files:**
- Modify: `crossplane/composition.yaml` (probe after `probe-grafana` ~1575; rules in group `heimdall.argocd` ~1279; a route in `alertmanager.config.route` ~250-332)
- Modify: `tests/e2e/probe-alerting/00-cmd.yaml` (rule names), `tests/render/` check (if a heimdall render check exists; else the kuttl assertion suffices)

- [ ] **Step 1: Probe.** After the Grafana probe, same shape, name `forgejo`, target `https://forgejo.{{ $domain }}/api/healthz`, labels `watched: "true"`, `service: "Forgejo"`, rendered `{{- if has ($identity.maturity | default "bootstrap") (list "durable" "full") }}` so a bootstrap cluster does not page on a Forgejo it does not run.

- [ ] **Step 2: Rules** in `heimdall.argocd`:

```yaml
                      - alert: ArgoCDApplicationUnhealthy
                        expr: argocd_app_info{health_status!="Healthy"} == 1
                        for: 10m
                        labels:
                          severity: warning
                          component: argocd
                        annotations:
                          summary: {{ `ArgoCD Application {{ $labels.name }} has not been Healthy for 10 minutes` | quote }}
                          description: {{ `{{ $labels.name }} reports health {{ $labels.health_status }}. promote.sh refuses a promotion while any sample in the soak window shows this; the puller clears healthySince for the repository.` | quote }}
                      - alert: ForgejoPullerStale
                        expr: time() - kube_cronjob_status_last_successful_time{cronjob="forgejo-puller", namespace="forgejo"} > 4 * 3600
                        for: 15m
                        labels:
                          severity: warning
                          component: forgejo
                        annotations:
                          summary: "The Forgejo puller has not succeeded in over 4 hours"
                          description: "Forgejo main may be behind its source ref. kubectl get configmap -n forgejo forgejo-puller-state -o jsonpath='{.data.state\\.json}' lists each repository's lastResult and pending moves; docs/forgejo.md 'Recovering a diverged main' if a move is refused."
```

- [ ] **Step 3: Routing** — add before the generic `severity =~ "warning|critical"` route: `- matchers: [alertname =~ "ForgejoPullerStale|ArgoCDApplicationUnhealthy"]` → `receiver: ntfy-workload` (priority 3, the design's mid-range).

- [ ] **Step 4: Tests.** Add `ArgoCDApplicationUnhealthy` and `ForgejoPullerStale` to the rule list in `tests/e2e/probe-alerting/00-cmd.yaml`. Render both identities with `crossplane render` (homelab durable identity needed: copy nidavellir's `cluster-identity-homelab-durable.yaml` into `tests/render/`) and grep: durable → `forgejo.homelab.local/api/healthz`; bootstrap → absent.

- [ ] **Step 5: Commit.** Message `feat(alerts): Forgejo health probe; ArgoCD unhealthy and puller-stale rules routed mid-range`.

---

### Task 18: `--retire-seed` on the test cluster (operations)

- [ ] Three days after Task 16 step 7's final forward repoint on Nano76: `scripts/graduate.sh realm-siliconsaga homelab-nano76win11 --retire-seed`. Expect the gate list re-checked, `helm uninstall gitea`, namespace `gitea` gone, every Application still green (nothing referenced the seed). This exercises the command in Phase 3, as the design asks; prod clusters keep their seed.

---

### Task 19: tailnet device listing and the ephemeral note (nordri, nidavellir docs)

**Files:**
- Create: `scripts/tailnet-devices.sh`, `tests/unit/tailnet-devices-test.sh`
- Modify: `tests/run.sh:7`, nidavellir `ntfy/README.md` (a "Lab and test clusters" subsection)

- [ ] **Step 1: Test.** A `curl` stub returns a token for the OAuth call and a devices JSON with `tailscale-operator-homelab-test-20261101-0900`, `tailscale-operator-homelab-test-20261113-1430`, `ntfy-homelab-test-20261113-1430`, `tailscale-operator-gke`; assert the output groups by cluster prefix, marks the newest per cluster `KEEP`, lists the older one as `prune candidate` with a printed `curl -X DELETE https://api.tailscale.com/api/v2/device/<id>` line, never issues a DELETE itself, and reads the client id and secret from files (`TS_OAUTH_CLIENT_ID_FILE`, `TS_OAUTH_CLIENT_SECRET_FILE`) or from the `tailscale/operator-oauth` Secret on the current context when the files are unset.

- [ ] **Step 2: Script.**

```bash
#!/usr/bin/env bash
# tailnet-devices.sh — list the operator and ntfy devices on the tailnet grouped
# by cluster, mark the newest per cluster, and PRINT the delete command for the
# rest. Never deletes: pruning is a human act (2026-11-13 review).
# Credentials: TS_OAUTH_CLIENT_ID_FILE / TS_OAUTH_CLIENT_SECRET_FILE, else the
# tailscale/operator-oauth Secret on the current kubectl context.
set -uo pipefail
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT; umask 077
if [[ -n "${TS_OAUTH_CLIENT_ID_FILE:-}" ]]; then cp "$TS_OAUTH_CLIENT_ID_FILE" "$work/id"; cp "$TS_OAUTH_CLIENT_SECRET_FILE" "$work/secret"; else
  kubectl get secret -n tailscale operator-oauth -o jsonpath='{.data.client_id}' | base64 -d > "$work/id"
  kubectl get secret -n tailscale operator-oauth -o jsonpath='{.data.client_secret}' | base64 -d > "$work/secret"; fi
[[ -s "$work/id" && -s "$work/secret" ]] || { echo "❌ no OAuth client credentials" >&2; exit 1; }
printf 'user = "%s:%s"\n' "$(cat "$work/id")" "$(cat "$work/secret")" > "$work/auth.cfg"
tok=$(curl -sS -K "$work/auth.cfg" -d grant_type=client_credentials https://api.tailscale.com/api/v2/oauth/token | jq -r .access_token)
[[ -n "$tok" && "$tok" != null ]] || { echo "❌ token request failed" >&2; exit 1; }
printf 'header = "Authorization: Bearer %s"\n' "$tok" > "$work/bearer.cfg"
curl -sS -K "$work/bearer.cfg" "https://api.tailscale.com/api/v2/tailnet/-/devices" > "$work/devices.json" || exit 1
# cluster prefix: strip the role prefix and an optional -<yyyymmdd-HHMM> stamp
jq -r '.devices[] | select(.hostname | test("^(tailscale-operator|ntfy)-")) | [.id, .hostname, .lastSeen] | @tsv' "$work/devices.json" \
 | awk -F'\t' '{ h=$2; sub(/^(tailscale-operator|ntfy)-/, "", h); c=h; sub(/-[0-9]{8}-[0-9]{4}$/, "", c); print c "\t" $2 "\t" $3 "\t" $1 }' | sort -k1,1 -k3,3r \
 | awk -F'\t' '{ kind=$2; sub(/-.*/, "", kind); key=$1 "/" kind; if (!(key in seen)) { seen[key]=1; printf "%-22s %-48s %s  KEEP (newest)\n", $1, $2, $3 } else { printf "%-22s %-48s %s  prune candidate:\n    curl -X DELETE -K <bearer.cfg> https://api.tailscale.com/api/v2/device/%s\n", $1, $2, $3, $4 } }'
```

- [ ] **Step 3: Docs.** nidavellir `ntfy/README.md` → "Lab and test clusters": the stamped names, the listing script, manual deletion, and the ad hoc check: `tailscale up --auth-key=<ephemeral key>` in a sidecar with `TS_STATE_DIR` unset and `TS_AUTHKEY` from an ephemeral, pre-authorized key (admin console → Keys), which removes itself minutes after the pod stops; the operator is for tests of the operator.

- [ ] **Step 4: Run, commit.** `bash tests/unit/tailnet-devices-test.sh` → `ALL PASS`. Message `feat(scripts): list tailnet devices per cluster, newest marked, deletes printed not run`.

---

### Task 20: GKE order of operations (operations; design 3b-4)

Step 1 (hydrate GKE with today's scripts) was done 2026-11-11.

- [ ] **Step 2 (after 3a merges), the backup cutover and migration together**, context `gke_…` set by the operator:
  1. `kubectl patch schedule -n velero daily-full --type merge -p '{"spec":{"paused":true}}'`; wait until `kubectl get backups -n velero -o jsonpath='{.items[?(@.status.phase=="InProgress")].metadata.name}'` is empty; record `kubectl get backups -n velero --no-headers | wc -l` as N.
  2. `gcloud storage cp -r gs://teralivekubernetes-velero/backups gs://teralivekubernetes-velero/gke-prod/backups` and the same for `restores`; verify: `gcloud storage ls -r gs://teralivekubernetes-velero/backups/** | sed 's|/backups/|/|' | sort` equals the destination listing with `gke-prod/backups/` stripped, name for name, and for every object `gcloud storage objects describe <src> --format='value(crc32c)'` equals the destination's (a loop over the listing; stop on the first mismatch).
  3. From nordri main: `scripts/migrate.sh realm-siliconsaga gke-prod`. Velero's generated Application now carries `prefix: gke-prod`; pgBackRest gets `repo2-path: /gke-prod/pgbackrest`; the PXC storage bucket `teralivekubernetes-mysql-backups/gke-prod`.
  4. After Velero's backup sync (`kubectl logs -n velero deploy/velero | grep -i "backup sync"`), `kubectl get backups -n velero --no-headers | wc -l` must equal N; then unpause the schedule.
  5. Verify a backup at each new location before relying on them: a manual `velero backup create prefix-verify --include-namespaces nordri` reaches `Completed` and `gcloud storage ls gs://teralivekubernetes-velero/gke-prod/backups/prefix-verify/` lists objects; a `PerconaPGBackup` `repo2-verify` per `docs/offsite-backups.md` and `pgbackrest info` shows the full backup under the new repository with a size line; a `PerconaXtraDBClusterBackup` `gcs-verify` is `Succeeded` **and** `gcloud storage ls -r gs://teralivekubernetes-mysql-backups/gke-prod/` lists its folder. Only then `gcloud storage rm -r gs://teralivekubernetes-velero/backups gs://teralivekubernetes-velero/restores`.
- [ ] **Step 3 (after `homelab-prod` graduated and soaked):** on homelab-prod's context `scripts/promote.sh gke --init`; then edit `clusters/gke-prod.yaml` `maturity: durable`, merge, pull; on GKE's context `scripts/identity.sh apply realm-siliconsaga gke-prod`. Forgejo comes up beside the seed (KMS-unsealed OpenBao already there; persistent disk; the wildcard certificate); the puller runs with `SOURCE_REF=live` and fills the five repositories from `live-1`.
- [ ] **Step 4:** soak with both servers; `scripts/graduate.sh realm-siliconsaga gke-prod` (prod: preconditions include the puller's last run); the seed stays until Phase 4's drills pass; `--retire-seed` refuses on prod by design until then.

---

### Task 21: soak and gates (design 3b-8)

- [ ] One change climbs the whole ladder: a lab cluster, `homelab-test`, `homelab-prod` (merge on GitHub, the puller brings it, it soaks), `scripts/promote.sh gke`, `gke-prod` picks up `live-<n>`. Record the change, the promotion number and the timings in the realm's `promotions/live-<n>.md`.
- [ ] `graduate.sh --rollback` exercised on a test cluster (Task 16 step 7) and `--retire-seed` (Task 18).
- [ ] The record's remaining gates stand for Phase 4 (restore drills); note them as open in the realm's `docs/forgejo.md` phase table and mark Phase 3 done there.

---

## Self-review (run at the end of writing, 2026-11-13)

**Spec coverage.** 3a-1: Tasks 1–5, 11 (`identity.sh`, bootstrap, `update-embedded-git.sh --target forgejo`, deletions, the two ApplicationSets, docs). 3a-2: Tasks 6–8, 14 (puller `sourceRef` behaviour). 3a-3: Task 9. 3a-4: Task 10, minus the `internalUrl` key (dropped, see Facts). 3a-5: Tasks 11–12. 3b-1: Task 13 and 16 step 6. 3b-2: Tasks 14–15. 3b-3: Task 16. 3b-4: Task 20. 3b-5: Task 17 step 1. 3b-6: Task 17 steps 2–3 (per-repository metric and the panel deferred to Phase 4, recorded). 3b-7: Task 14 step 4. 3b-8: Task 21. Decision 3's `recycle.sh` is replaced by Task 19 per the 2026-11-13 review. Decision 4's "adopt or wait" check: Task 12 step 2.

**Placeholders.** None of the forbidden phrases remain; every code step carries its code. Two deliberate literal sentinels exist in Git (`set-by-the-vegvisir-applicationset`, `set-by-the-shared-clusters-applicationset`) and both are asserted replaced by render checks.

**Type consistency.** `identity_resolve <realm_dir> <cluster>` and `identity_live_value <key>` (Task 1) are what Tasks 2, 4, 11, 15, 16 call; `gitea_ensure_repo <owner> <repo> [auto_init]`, `hydrate_working_tree_repo <src> <owner> <repo> <msg>`, `hydrate_vendor_mirrors <owner> <mirrors>` (Task 3) are what Tasks 4 and 11 call; `gitops_ensure_git_service [target]`, `gitops_git_service_target`, `GIT_SEED_SERVICE`, `GIT_FORGEJO_SERVICE` (Task 3) are what Tasks 4, 11, 16 use; `argo_wait_operations_done`, `argo_wait_synced_healthy`, `argo_hard_refresh_all`, `argo_remove_finalizer` (Task 11) are what Tasks 11 and 16 call; `seed_access_open` (Task 11) is used by Tasks 4, 11, 16; the state JSON keys (`repos.<name>.commit`, `healthySince`, `lastResult`, `pending`, `promotion`) written in Task 14 are the ones Tasks 15 and 16 read; label and annotation names are the Global Constraints list throughout.

