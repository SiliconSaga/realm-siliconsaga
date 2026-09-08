# Forgejo Day-2 — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the three prerequisites the [Forgejo day-2 design](2026-09-07-forgejo-day2-design.md) names for Phase 1 — OpenBao auto-unseal on both environments, the `maturity` field on cluster-identity, and the target-specific repoURL rewrite in nordri's hydration libs — without changing what any cluster deploys today.

**Architecture:** Three independent slices across three repos. nordri gains `maturity`, `gcpProject` and `gcpRegion` on cluster-identity, a `lib/patch-urls.sh` rewrite that is a no-op while manifests still carry seed URLs, a homelab seal-key step in `bootstrap.sh`, and an `openbao-seal-setup` action in `gke-provision.sh`. nidavellir's openbao composition grows a seal stanza that branches on `environment`: `gcpckms` through Workload Identity on GKE, `static` with a Secret-held key on homelab, with a claim-level `seal: shamir` opt-out. The live migration from Shamir to the new seal is a human-gated runbook, run once per cluster. Render fixtures in nidavellir and heimdall gain the new identity fields so offline checks keep matching the cluster.

**Tech Stack:** bash (nordri scripts, plain-bash unit tests via `tests/run.sh`), Crossplane Pipeline compositions (`function-environment-configs`, `function-go-templating`, provider-helm `Release`), OpenBao Helm chart 0.28.3 / OpenBao 2.5.4, GCP Cloud KMS + Workload Identity, kuttl for in-cluster checks, `crossplane render` for offline checks.

## Global Constraints

- The word is `maturity`, values exactly `bootstrap | durable | full`. Never `tier`.
- Phase 1 must not change what any cluster deploys at `bootstrap` maturity, except OpenBao's seal configuration. The URL rewrite must be a no-op against today's manifests.
- All nordri scripts stay portable across Git Bash, macOS and Linux: `sed -i ''` on darwin, `sed -i` elsewhere, as the existing libs do. No `make`.
- Commit through `ws commit <comp> <bodyfile>`; push through `ws push`; CRs through `ws cr`. Never raw `git commit` / `git push`. Bodyfiles live under the workspace `.commits/` and follow `templates/commit.md`. Prose in bodies is one line per paragraph, never hard-wrapped.
- Change-note style is `terse`: subject plus at most three body lines, and only when something non-obvious needs recording.
- Cluster-identity fields are added to **both** environment files at once, and to every render fixture that mirrors them (nidavellir and heimdall `tests/render/cluster-identity-*.yaml`).
- Any `kubectl` against the GKE cluster goes through `ws k8s` with a scope armed first: `ws k8s scope set --context gke_teralivekubernetes_us-east1-d_ttf-cluster --namespace openbao`. Any step that changes live cluster state is marked **HUMAN-GATED** and is run by the operator, not the agent.
- Seal migration on an initialized OpenBao needs two of its three Shamir shares. On GKE those live in the operator's password manager and in the `openbao-init` Secret. Never print them.
- OpenBao static seal key: exactly 32 random bytes, base64. Generated once per homelab cluster, never committed.

---

## File Structure

**nordri** (Tier 1)

| File | Responsibility |
|---|---|
| `platform/fundamentals/manifests/cluster-identity-gke.yaml` | gains `maturity`, `gcpProject: __GCP_PROJECT__`, `gcpRegion` |
| `platform/fundamentals/manifests/cluster-identity-homelab.yaml` | gains `maturity` |
| `lib/patch-velero.sh` | `patch_velero_tree` also stamps the project into `cluster-identity-gke.yaml` (same placeholder, same fail-closed check) |
| `lib/patch-urls.sh` (new) | `patch_repo_urls_tree <tree> <mode>`: mode `seed` rewrites committed Forgejo URLs to the seed URL, modes `forgejo` and `swap` leave the tree alone; carries the single seed-URL literal |
| `lib/hydrate.sh` | `hydrate_working_tree_repo` applies `patch_repo_urls_tree` after the optional per-component patch, driven by `HYDRATE_URL_MODE` (default `seed`) |
| `bootstrap.sh` | nordri inline block calls `patch_repo_urls_tree`; new Layer 2.9 creates the homelab `openbao-seal-key` Secret if absent |
| `update-embedded-git.sh` | nordri inline block calls `patch_repo_urls_tree` |
| `gke-provision.sh` | new `openbao-seal-setup` action: enables Cloud KMS, key ring + key, GSA, IAM, Workload Identity binding |
| `tests/unit/patch-urls-test.sh` (new) | three-mode assertion: seed snapshot has no `forgejo-http`, forgejo and swap snapshots have no `gitea-http` |
| `tests/unit/patch-velero-test.sh` (new) | project stamped into both files, placeholder survival fails |
| `docs/cluster-identity.md`, `docs/bootstrap.md` | document the new fields, Layer 2.9, and the `openbao-seal-setup` action |

**nidavellir** (Tier 2)

| File | Responsibility |
|---|---|
| `openbao/xrd.yaml` | new `parameters.seal` enum `auto \| shamir`, default `auto` |
| `openbao/composition.yaml` | seal stanza and chart values branch on `$identity.environment` and `$seal` |
| `tests/render/cluster-identity-gke.yaml`, `-homelab.yaml` | gain `maturity`, and for gke `gcpProject`, `gcpRegion` |
| `tests/render/check-openbao.sh` (new) | offline render asserts the seal seams per environment |
| `tests/platform/openbao/01-restart.yaml` (new) | kuttl: delete the pod, assert it returns Ready without a human |
| `docs/secrets-management.md` | unseal sections rewritten for auto-unseal; migration runbook |

**heimdall**

| File | Responsibility |
|---|---|
| `tests/render/cluster-identity-gke.yaml`, `-homelab.yaml` | gain `maturity` (and gke `gcpProject`, `gcpRegion`) so the fixture matches the cluster |

**realm-siliconsaga**

| File | Responsibility |
|---|---|
| `docs/adrs/0004-openbao-auto-unseal.md` (new) | records the seal decision per environment and the custody consequence |

---

### Task 1: `maturity`, `gcpProject`, `gcpRegion` on cluster-identity (nordri)

**Files:**
- Modify: `components/nordri/platform/fundamentals/manifests/cluster-identity-gke.yaml`
- Modify: `components/nordri/platform/fundamentals/manifests/cluster-identity-homelab.yaml`
- Modify: `components/nordri/lib/patch-velero.sh`
- Create: `components/nordri/tests/unit/patch-velero-test.sh`
- Modify: `components/nordri/docs/cluster-identity.md`

**Interfaces:**
- Produces: cluster-identity `data.maturity` (string, `bootstrap`), `data.gcpProject` (gke only, stamped at hydration), `data.gcpRegion` (gke only, `us-east1`). Consumed by Task 5's composition as `$identity.maturity`, `$identity.gcpProject`, `$identity.gcpRegion`.
- Produces: `patch_velero_tree <tree> <target>` now stamps `__GCP_PROJECT__` in both `platform/fundamentals/apps/velero-gke.yaml` and `platform/fundamentals/manifests/cluster-identity-gke.yaml`. Same signature, same return codes.

- [ ] **Step 1: Write the failing test for the extended stamp**

Create `components/nordri/tests/unit/patch-velero-test.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../../lib/patch-velero.sh"

fails=0
check() { if eval "$2"; then echo "ok - $1"; else echo "NOT OK - $1"; fails=$((fails+1)); fi; }

tree="$(mktemp -d)"; trap 'rm -rf "$tree"' EXIT
mkdir -p "$tree/platform/fundamentals/apps" "$tree/platform/fundamentals/manifests"
printf 'bucket: __GCP_PROJECT__-velero\n' > "$tree/platform/fundamentals/apps/velero-gke.yaml"
printf 'data:\n  gcpProject: __GCP_PROJECT__\n' > "$tree/platform/fundamentals/manifests/cluster-identity-gke.yaml"

# gke: both files stamped with the env-provided project.
GCP_PROJECT=example-proj-1 patch_velero_tree "$tree" gke >/dev/null; rc=$?
check "gke returns 0" "[ $rc -eq 0 ]"
check "velero app stamped" "grep -q 'example-proj-1-velero' '$tree/platform/fundamentals/apps/velero-gke.yaml'"
check "cluster-identity stamped" "grep -q 'gcpProject: example-proj-1' '$tree/platform/fundamentals/manifests/cluster-identity-gke.yaml'"
check "no placeholder survives" "! grep -rq '__GCP_PROJECT__' '$tree'"

# homelab: no-op, files untouched.
printf 'data:\n  gcpProject: __GCP_PROJECT__\n' > "$tree/platform/fundamentals/manifests/cluster-identity-gke.yaml"
patch_velero_tree "$tree" homelab >/dev/null; rc=$?
check "homelab returns 0" "[ $rc -eq 0 ]"
check "homelab leaves placeholder alone" "grep -q '__GCP_PROJECT__' '$tree/platform/fundamentals/manifests/cluster-identity-gke.yaml'"

# gke with cluster-identity missing must fail loudly.
rm -f "$tree/platform/fundamentals/manifests/cluster-identity-gke.yaml"
GCP_PROJECT=example-proj-1 patch_velero_tree "$tree" gke >/dev/null 2>&1; rc=$?
check "missing cluster-identity returns non-zero" "[ $rc -ne 0 ]"

echo "---"; [ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
```

- [ ] **Step 2: Run the suite to see it fail**

Run: `ws test nordri`
Expected: `RUN tests/unit/patch-velero-test.sh` shows `NOT OK - cluster-identity stamped` and `NOT OK - missing cluster-identity returns non-zero`; the runner ends with `1 unit-test file(s) FAILED`.

- [ ] **Step 3: Extend `patch_velero_tree` to stamp both files**

In `components/nordri/lib/patch-velero.sh`, replace the block from `local app="$tree/platform/fundamentals/apps/velero-gke.yaml"` through the final `echo` with:

```bash
    local app="$tree/platform/fundamentals/apps/velero-gke.yaml"
    local identity="$tree/platform/fundamentals/manifests/cluster-identity-gke.yaml"

    case "$target" in
        homelab)
            return 0
            ;;
        gke) ;;
        *)
            echo "❌ patch_velero_tree: unknown target '$target' (expected homelab|gke)." >&2
            return 1
            ;;
    esac

    # Both files carry the same placeholder. cluster-identity needs the project
    # because the OpenBao composition derives the KMS seal coordinates and the
    # Workload Identity service-account annotation from it; committing the id
    # there would tie the repo to one project the same way velero-gke.yaml would.
    local f
    for f in "$app" "$identity"; do
        if [[ ! -f "$f" ]]; then
            echo "❌ patch_velero_tree: expected ${f#"$tree"/} to exist for GKE hydration." >&2
            return 1
        fi
    done

    # Env var wins; otherwise fall back to gcloud's configured project so an
    # operator who has already run `gcloud config set project` needs no export.
    local project="${GCP_PROJECT:-}"
    if [[ -z "$project" ]] && command -v gcloud >/dev/null 2>&1; then
        project="$(gcloud config get-value project 2>/dev/null || true)"
    fi
    if [[ -z "$project" || "$project" == "(unset)" ]]; then
        echo "❌ GCP_PROJECT is not set and gcloud has no default project." >&2
        echo "   GKE hydration needs it for the Velero bucket, the Workload Identity" >&2
        echo "   annotations, and the OpenBao KMS seal coordinates." >&2
        echo "     export GCP_PROJECT=<your-project-id>" >&2
        echo "   or: gcloud config set project <your-project-id>" >&2
        return 1
    fi

    if [[ ! "$project" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        echo "❌ GCP_PROJECT '$project' is not a valid project id." >&2
        echo "   Expected 6-30 chars: lowercase letter, then letters/digits/hyphens." >&2
        return 1
    fi

    for f in "$app" "$identity"; do
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|__GCP_PROJECT__|$project|g" "$f" || return 1
        else
            sed -i "s|__GCP_PROJECT__|$project|g" "$f" || return 1
        fi
        # Fail closed. A surviving placeholder is worse than a hard error here,
        # because the resulting Velero looks installed and healthy, and an
        # OpenBao pointed at project "__GCP_PROJECT__" cannot unseal.
        if grep -q '__GCP_PROJECT__' "$f"; then
            echo "❌ patch_velero_tree: placeholders survived substitution in ${f#"$tree"/}." >&2
            return 1
        fi
    done

    echo "   GKE hydration pinned to project: $project"
```

- [ ] **Step 4: Add the fields to both cluster-identity manifests**

`components/nordri/platform/fundamentals/manifests/cluster-identity-gke.yaml`, replace the `data:` block:

```yaml
data:
  environment: gke
  storageClass: standard-rwo
  domain: cmdbee.org
  harborRole: central
  # Platform maturity: bootstrap | durable | full. Compositions gate their
  # durable-tier pieces (Forgejo, later Keycloak/Harbor) on this the same way
  # they branch on environment. Bumping it is the graduation step — see the
  # realm's 2026-09-07 Forgejo day-2 design. bootstrap.sh never sets more.
  maturity: bootstrap
  # Stamped at hydration by lib/patch-velero.sh (same placeholder as
  # velero-gke.yaml) so the repo carries no project identity. Read by the
  # OpenBao composition for the KMS seal and its Workload Identity annotation.
  gcpProject: __GCP_PROJECT__
  # Region of the KMS key ring the openbao-seal-setup action creates. Static:
  # the key ring lives beside the cluster and does not move.
  gcpRegion: us-east1
```

`components/nordri/platform/fundamentals/manifests/cluster-identity-homelab.yaml`, replace the `data:` block:

```yaml
data:
  environment: homelab
  storageClass: local-path
  domain: homelab.local
  harborRole: local
  harborCentral: harbor.cmdbee.org
  # Platform maturity: bootstrap | durable | full. See the gke file and the
  # realm's 2026-09-07 Forgejo day-2 design. No gcpProject/gcpRegion here:
  # homelab OpenBao seals with a static key, not KMS.
  maturity: bootstrap
```

- [ ] **Step 5: Run the suite to see it pass**

Run: `ws test nordri`
Expected: every `ok -` line in `patch-velero-test.sh`, then `✅ nordri: syntax clean + all unit tests pass`.

- [ ] **Step 6: Document the fields**

In `components/nordri/docs/cluster-identity.md`, replace the YAML block under "## What's in cluster-identity" with:

```yaml
apiVersion: apiextensions.crossplane.io/v1beta1
kind: EnvironmentConfig
metadata:
  name: cluster-identity
data:
  environment: homelab    # or "gke" — controls replica counts, etc.
  storageClass: local-path # or "standard-rwo" — used by all PVC-bound resources
  domain: homelab.local   # or "cmdbee.org" — base domain for ingress hosts
  maturity: bootstrap     # bootstrap | durable | full — gates the durable tier
  gcpProject: <stamped>   # gke only; stamped at hydration from GCP_PROJECT
  gcpRegion: us-east1     # gke only; where the OpenBao KMS key ring lives
```

and add this paragraph after that block:

```markdown
`maturity` is the platform's graduation switch (realm design `2026-09-07-forgejo-day2-design.md`). `bootstrap.sh` always produces a `bootstrap` cluster; compositions that belong to the durable tier render nothing until an operator commits a bump and hydrates it. `gcpProject` is a hydration-time stamp, never committed as a real id, so `git grep gcpProject` on the repo shows only the placeholder.
```

- [ ] **Step 7: Commit**

Write `.commits/nordri-identity-maturity.md`:

```markdown
---
message: "feat(cluster-identity): add maturity, gcpProject and gcpRegion"
add:
  - platform/fundamentals/manifests/cluster-identity-gke.yaml
  - platform/fundamentals/manifests/cluster-identity-homelab.yaml
  - lib/patch-velero.sh
  - tests/unit/patch-velero-test.sh
  - docs/cluster-identity.md
---

maturity is the graduation switch from the realm's Forgejo day-2 design; nothing reads it yet. gcpProject rides the existing __GCP_PROJECT__ stamp so the repo stays project-free.
```

Run: `ws commit nordri .commits/nordri-identity-maturity.md`
Expected: one commit on nordri's current branch listing five files.

---

### Task 2: Mirror the new identity fields into the render fixtures (nidavellir, heimdall)

**Files:**
- Modify: `components/nidavellir/tests/render/cluster-identity-gke.yaml`
- Modify: `components/nidavellir/tests/render/cluster-identity-homelab.yaml`
- Modify: `components/heimdall/tests/render/cluster-identity-gke.yaml`
- Modify: `components/heimdall/tests/render/cluster-identity-homelab.yaml`

**Interfaces:**
- Produces: fixtures whose `data` keys match nordri's manifests, with `gcpProject: example-project` as the stamped stand-in. Task 5's render check depends on the nidavellir fixtures carrying `gcpProject` and `gcpRegion`.

- [ ] **Step 1: Add the fields to the nidavellir gke fixture**

Replace the `data:` block in `components/nidavellir/tests/render/cluster-identity-gke.yaml`:

```yaml
data:
  domain: cmdbee.org
  environment: gke
  storageClass: standard-rwo
  harborRole: central
  maturity: bootstrap
  # Stand-in for the value bootstrap stamps from GCP_PROJECT at hydration.
  gcpProject: example-project
  gcpRegion: us-east1
```

- [ ] **Step 2: Add `maturity` to the nidavellir homelab fixture**

Append to the `data:` block in `components/nidavellir/tests/render/cluster-identity-homelab.yaml`:

```yaml
  maturity: bootstrap
```

- [ ] **Step 3: Same two edits in heimdall**

Append to `components/heimdall/tests/render/cluster-identity-gke.yaml` `data:`:

```yaml
  maturity: bootstrap
  gcpProject: example-project
  gcpRegion: us-east1
```

Append to `components/heimdall/tests/render/cluster-identity-homelab.yaml` `data:`:

```yaml
  maturity: bootstrap
```

- [ ] **Step 4: Prove the heimdall render is unaffected**

Run from `components/heimdall`: `crossplane render tests/render/heimdall-xr.yaml crossplane/composition.yaml tests/render/functions.yaml --extra-resources tests/render/cluster-identity-gke.yaml`
Expected: renders without error; output identical to before the edit (no template reads the new keys). If `crossplane` is not on PATH, the CLI install is in the realm's `docs/dev-setup.md`; on Windows the binary is `crank.exe` from `https://releases.crossplane.io/stable/current/bin/windows_amd64/crank.exe`.

- [ ] **Step 5: Commit both repos**

`.commits/nida-identity-fixtures.md`:

```markdown
---
message: "test(render): mirror maturity, gcpProject and gcpRegion into the cluster-identity fixtures"
add:
  - tests/render/cluster-identity-gke.yaml
  - tests/render/cluster-identity-homelab.yaml
---
```

Run: `ws commit nidavellir .commits/nida-identity-fixtures.md`

`.commits/heimdall-identity-fixtures.md`:

```markdown
---
message: "test(render): mirror maturity, gcpProject and gcpRegion into the cluster-identity fixtures"
add:
  - tests/render/cluster-identity-gke.yaml
  - tests/render/cluster-identity-homelab.yaml
---
```

Run: `ws commit heimdall .commits/heimdall-identity-fixtures.md`

---

### Task 3: Target-specific repoURL rewrite in the hydration libs (nordri)

**Files:**
- Create: `components/nordri/lib/patch-urls.sh`
- Create: `components/nordri/tests/unit/patch-urls-test.sh`
- Modify: `components/nordri/lib/hydrate.sh` (`hydrate_working_tree_repo`)
- Modify: `components/nordri/bootstrap.sh` (nordri inline hydration block, ~line 386-405; the `INTERNAL_GITEA_URL` line 87)
- Modify: `components/nordri/update-embedded-git.sh` (nordri inline hydration block)

**Interfaces:**
- Produces: `patch_repo_urls_tree <tree> <mode>` with `mode ∈ {seed, forgejo, swap}`. Returns 0 on success, 1 on unknown mode. Rewrites every occurrence of `http://forgejo-http.forgejo.svc.cluster.local:3000/siliconsaga/` to `http://gitea-http.gitea.svc.cluster.local:3000/nordri-admin/` in `*.yaml` files under the tree when mode is `seed`; touches nothing otherwise. Echoes the count of files changed.
- Produces: `HYDRATE_URL_MODE` environment knob read by `hydrate_working_tree_repo`, default `seed`. Phase 3's `graduate.sh` and the `--swap` flag set it; Phase 1 only defines it.
- Produces: `SEED_GIT_BASE_URL` and `FORGEJO_GIT_BASE_URL` constants in `lib/patch-urls.sh`, the single home for both literals.

- [ ] **Step 1: Write the failing three-mode test**

Create `components/nordri/tests/unit/patch-urls-test.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../../lib/patch-urls.sh"

fails=0
check() { if eval "$2"; then echo "ok - $1"; else echo "NOT OK - $1"; fails=$((fails+1)); fi; }

forgejo='http://forgejo-http.forgejo.svc.cluster.local:3000/siliconsaga'
seed='http://gitea-http.gitea.svc.cluster.local:3000/nordri-admin'

make_tree() { # a fake hydrated tree carrying the COMMITTED (Forgejo) form
    local t; t="$(mktemp -d)"
    mkdir -p "$t/platform/argocd" "$t/apps"
    printf "    repoURL: '%s/nordri.git'\n" "$forgejo" > "$t/platform/argocd/app-of-apps.yaml"
    printf "    repoURL: '%s/nidavellir.git'\n" "$forgejo" > "$t/apps/mimir-app.yaml"
    printf "not a manifest: %s/should-not-change.git\n" "$forgejo" > "$t/README.md"
    printf '%s' "$t"
}

# seed: every yaml rewritten to the seed form, non-yaml untouched.
tree="$(make_tree)"
out="$(patch_repo_urls_tree "$tree" seed)"; rc=$?
check "seed returns 0" "[ $rc -eq 0 ]"
check "seed snapshot has no forgejo-http in yaml" "! grep -rq 'forgejo-http' --include='*.yaml' '$tree'"
check "seed snapshot carries the seed URL" "grep -q \"$seed/nordri.git\" '$tree/platform/argocd/app-of-apps.yaml'"
check "seed rewrites nested apps too" "grep -q \"$seed/nidavellir.git\" '$tree/apps/mimir-app.yaml'"
check "seed leaves non-yaml alone" "grep -q 'forgejo-http' '$tree/README.md'"
check "seed reports two files" "[ \"$out\" = '2' ]"
rm -rf "$tree"

# forgejo: nothing changes.
tree="$(make_tree)"
patch_repo_urls_tree "$tree" forgejo >/dev/null; rc=$?
check "forgejo returns 0" "[ $rc -eq 0 ]"
check "forgejo snapshot has no gitea-http" "! grep -rq 'gitea-http' '$tree'"
check "forgejo snapshot keeps forgejo-http" "grep -q 'forgejo-http' '$tree/platform/argocd/app-of-apps.yaml'"
rm -rf "$tree"

# swap: same as forgejo — the URLs are the whole point of the swap commit.
tree="$(make_tree)"
patch_repo_urls_tree "$tree" swap >/dev/null; rc=$?
check "swap returns 0" "[ $rc -eq 0 ]"
check "swap snapshot has no gitea-http" "! grep -rq 'gitea-http' '$tree'"
rm -rf "$tree"

# a tree already in seed form (today's manifests) is a no-op in seed mode.
tree="$(mktemp -d)"; mkdir -p "$tree/platform/argocd"
printf "    repoURL: '%s/nordri.git'\n" "$seed" > "$tree/platform/argocd/app-of-apps.yaml"
out="$(patch_repo_urls_tree "$tree" seed)"; rc=$?
check "seed-form tree is a no-op" "[ $rc -eq 0 ] && [ \"$out\" = '0' ]"
rm -rf "$tree"

# unknown mode fails fast.
tree="$(make_tree)"
patch_repo_urls_tree "$tree" github >/dev/null 2>&1; rc=$?
check "unknown mode returns non-zero" "[ $rc -ne 0 ]"
check "unknown mode changed nothing" "grep -q 'forgejo-http' '$tree/platform/argocd/app-of-apps.yaml'"
rm -rf "$tree"

echo "---"; [ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
```

- [ ] **Step 2: Run it to see it fail**

Run: `ws test nordri`
Expected: `bash: .../lib/patch-urls.sh: No such file or directory` under `RUN tests/unit/patch-urls-test.sh`, and the runner reports a failed file.

- [ ] **Step 3: Write `lib/patch-urls.sh`**

```bash
# components/nordri/lib/patch-urls.sh
# Target-specific repoURL rewrite for hydrated trees. Sourced by bootstrap.sh,
# update-embedded-git.sh and lib/hydrate.sh.
#
# Git carries the DURABLE form of every ArgoCD repoURL — the in-cluster Forgejo
# host — because after the Forgejo cutover Forgejo's main is GitHub's main
# verbatim, and a committed seed URL would be pulled straight back over the
# cutover. The seed Gitea only ever sees a hydrated copy, so the seed form is
# applied here, at hydration, the same way overlay paths and the GCP project
# are stamped. See realm-siliconsaga docs/plans/2026-09-07-forgejo-day2-design.md.
#
# Modes:
#   seed     rewrite Forgejo URLs -> seed URLs (bootstrap, day-2 seed hydration)
#   forgejo  leave the tree alone (hydration into Forgejo)
#   swap     leave the tree alone (the cutover commit pushed INTO the seed, which
#            must point ArgoCD at Forgejo — the only seed hydration without the
#            rewrite; distinct from `forgejo` so callers say what they mean)
#
# These two literals are the ONLY place either host lives in nordri's scripts.
FORGEJO_GIT_BASE_URL="http://forgejo-http.forgejo.svc.cluster.local:3000/siliconsaga"
SEED_GIT_BASE_URL="http://gitea-http.gitea.svc.cluster.local:3000/nordri-admin"

# patch_repo_urls_tree <tree> <mode>
# Echoes the number of files rewritten. Only *.yaml files are touched: docs
# and scripts that mention a host are prose, not manifests.
patch_repo_urls_tree() {
    local tree="$1" mode="$2"
    case "$mode" in
        seed) ;;
        forgejo|swap)
            echo 0
            return 0
            ;;
        *)
            echo "❌ patch_repo_urls_tree: unknown mode '$mode' (expected seed|forgejo|swap)." >&2
            return 1
            ;;
    esac
    local changed=0 f
    while IFS= read -r -d '' f; do
        grep -q "$FORGEJO_GIT_BASE_URL" "$f" || continue
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|$FORGEJO_GIT_BASE_URL|$SEED_GIT_BASE_URL|g" "$f" || return 1
        else
            sed -i "s|$FORGEJO_GIT_BASE_URL|$SEED_GIT_BASE_URL|g" "$f" || return 1
        fi
        # Fail closed, as patch-velero does: a Forgejo URL surviving into the
        # seed means ArgoCD would try a host that does not exist yet.
        if grep -q "$FORGEJO_GIT_BASE_URL" "$f"; then
            echo "❌ patch_repo_urls_tree: Forgejo URL survived rewrite in ${f#"$tree"/}." >&2
            return 1
        fi
        changed=$((changed + 1))
    done < <(find "$tree" -type f -name '*.yaml' -print0)
    echo "$changed"
}
```

- [ ] **Step 4: Run the test to see it pass**

Run: `ws test nordri`
Expected: all `ok -` lines for `patch-urls-test.sh`; `ALL PASS`.

- [ ] **Step 5: Wire it into `hydrate_working_tree_repo`**

In `components/nordri/lib/hydrate.sh`, update the header comment's knob list and the function. Add to the knobs comment block:

```bash
#   HYDRATE_URL_MODE   seed (default) | forgejo | swap — passed to
#                      patch_repo_urls_tree after the per-component patch;
#                      see lib/patch-urls.sh.
```

Replace the body of `hydrate_working_tree_repo` from `if [[ -n "$patch_fn" ]]; then` through `hydrate_push_tree "$tmp" "$gitea_repo" "$commit_msg"` with:

```bash
    if [[ -n "$patch_fn" ]]; then
        local patch_out
        if ! patch_out="$("$patch_fn" "$tmp" "$TARGET")"; then
            return 1
        fi
        echo "   Patched $gitea_repo for target '$TARGET' ($patch_out)."
    fi
    # URL form is a property of the hydration TARGET, not the component, so it
    # runs for every working-tree repo after any component-specific patch.
    local url_count
    if ! url_count="$(patch_repo_urls_tree "$tmp" "${HYDRATE_URL_MODE:-seed}")"; then
        return 1
    fi
    [[ "$url_count" != "0" ]] && echo "   Rewrote repoURLs in $url_count file(s) for '${HYDRATE_URL_MODE:-seed}'."
    hydrate_push_tree "$tmp" "$gitea_repo" "$commit_msg"
```

And add the dependency note to the top comment: `# Depends on lib/gitea.sh (...) and lib/patch-urls.sh (patch_repo_urls_tree).`

- [ ] **Step 6: Source the lib and patch the nordri inline blocks in both scripts**

In `components/nordri/bootstrap.sh`:

Line 56-57 area, after `. "$SCRIPT_DIR/lib/hydrate.sh"` add:

```bash
. "$SCRIPT_DIR/lib/patch-urls.sh"
```

Replace line 87 `INTERNAL_GITEA_URL="http://gitea-http.gitea.svc.cluster.local:3000"` with:

```bash
# The seed host literal now lives in lib/patch-urls.sh (SEED_GIT_BASE_URL).
INTERNAL_GITEA_URL="${SEED_GIT_BASE_URL%/nordri-admin}"
```

After `patch_velero_tree "$HYDRATE_DIR" "$TARGET" || exit 1` in the nordri block, add:

```bash
# Rewrite committed Forgejo repoURLs to the seed form. A no-op until the
# manifests move to the durable form (realm Forgejo day-2 design, Phase 3).
patch_repo_urls_tree "$HYDRATE_DIR" "${HYDRATE_URL_MODE:-seed}" >/dev/null || exit 1
```

In `components/nordri/update-embedded-git.sh`, after `. "$SCRIPT_DIR/lib/patch-velero.sh"` add:

```bash
. "$SCRIPT_DIR/lib/patch-urls.sh"
```

and after its `patch_velero_tree "$HYDRATE_DIR" "$TARGET" || exit 1` add the same three-line block as above.

Then check nothing else in the scripts dereferences `INTERNAL_GITEA_URL` differently:

Run: `grep -n "INTERNAL_GITEA_URL" components/nordri/bootstrap.sh`
Expected: the definition line plus its existing uses under Layer 3 (`repoURL` in the root app apply), all of which expect the bare `http://gitea-http.gitea.svc.cluster.local:3000` form that the `%/nordri-admin` strip produces.

- [ ] **Step 7: Syntax-check and run the suite**

Run: `ws test nordri`
Expected: `== syntax check ==` clean for `bootstrap.sh`, `update-embedded-git.sh`, `lib/*.sh`; all unit tests pass.

- [ ] **Step 8: Commit**

`.commits/nordri-patch-urls.md`:

```markdown
---
message: "feat(hydrate): rewrite committed Forgejo repoURLs to the seed form at hydration"
add:
  - lib/patch-urls.sh
  - lib/hydrate.sh
  - bootstrap.sh
  - update-embedded-git.sh
  - tests/unit/patch-urls-test.sh
---

A no-op against today's manifests: nothing carries a Forgejo URL yet. It exists so the Phase 3 URL PR train can land without the seed breaking, and so the seed host literal has exactly one home.
```

Run: `ws commit nordri .commits/nordri-patch-urls.md`

---

### Task 4: `openbao-seal-setup` action and the homelab seal-key step (nordri)

**Files:**
- Modify: `components/nordri/gke-provision.sh` (new `openbao-seal-setup)` case before `credentials)`; usage text)
- Modify: `components/nordri/bootstrap.sh` (new Layer 2.9 after the ProviderConfigs step, before Layer 3 ArgoCD)
- Modify: `components/nordri/docs/bootstrap.md`

**Interfaces:**
- Produces on GCP (gke): KMS key ring `openbao` in `$GCP_REGION` (default `us-east1`, must equal cluster-identity `gcpRegion`), crypto key `unseal`, service account `openbao-seal@<project>.iam.gserviceaccount.com` holding `roles/cloudkms.cryptoKeyEncrypterDecrypter` on that key only, and a `roles/iam.workloadIdentityUser` binding for `<project>.svc.id.goog[openbao/openbao]`. Task 5's composition annotates the KSA with that GSA email and names that key ring and key.
- Produces on homelab: Secret `openbao-seal-key` in namespace `openbao`, key `key`, value base64 of 32 random bytes. Task 5's composition injects it as `BAO_SEAL_STATIC_KEY`.

- [ ] **Step 1: Add the `openbao-seal-setup` action**

In `components/nordri/gke-provision.sh`, insert before the `credentials)` case:

```bash
openbao-seal-setup)
    # One-time Cloud KMS + IAM setup so OpenBao on GKE unseals itself through
    # Workload Identity (realm ADR 0004; supersedes the manual-unseal posture of
    # ADR 0002). A separate action for the same reason velero-setup is: the
    # long-lived production cluster was not made by this script. Idempotent —
    # re-running repairs drift.
    #
    # Names are FIXED, not overridable, because the OpenBao composition in
    # nidavellir derives them from cluster-identity (gcpProject, gcpRegion) plus
    # these literals. Two sources of truth for a key name would mean an OpenBao
    # that cannot decrypt its own barrier.
    SEAL_REGION="${GCP_REGION:-us-east1}"
    SEAL_KEYRING="openbao"
    SEAL_KEY="unseal"
    SEAL_SA="openbao-seal@${GCP_PROJECT}.iam.gserviceaccount.com"
    SEAL_KEY_RESOURCE="projects/${GCP_PROJECT}/locations/${SEAL_REGION}/keyRings/${SEAL_KEYRING}/cryptoKeys/${SEAL_KEY}"

    echo ""
    echo "🔐 Setting up OpenBao KMS auto-unseal..."
    echo "   Key:             ${SEAL_KEY_RESOURCE}"
    echo "   Service account: ${SEAL_SA}"
    echo ""

    # The API is off by default on a project that has never used KMS — this one
    # had not, as of 2026-09-07 — and every kms command below fails with
    # PERMISSION_DENIED until it is on. Enable explicitly rather than let gcloud
    # prompt, since this script also runs non-interactively.
    echo "🔌 Enabling the Cloud KMS API (no-op if already enabled)..."
    gcloud services enable cloudkms.googleapis.com --project="$GCP_PROJECT" >/dev/null

    echo "🔑 Ensuring key ring ${SEAL_KEYRING} in ${SEAL_REGION}..."
    if gcloud kms keyrings describe "$SEAL_KEYRING" --location="$SEAL_REGION" --project="$GCP_PROJECT" >/dev/null 2>&1; then
        echo "   ✅ Key ring already exists."
    else
        gcloud kms keyrings create "$SEAL_KEYRING" --location="$SEAL_REGION" --project="$GCP_PROJECT"
        echo "   ✅ Key ring created."
    fi

    # Symmetric encrypt/decrypt is what the gcpckms seal needs. Rotation is left
    # at the default (none); OpenBao re-wraps on demand and a rotated KMS key
    # version stays decryptable, so enabling rotation later is safe.
    echo "🔑 Ensuring crypto key ${SEAL_KEY}..."
    if gcloud kms keys describe "$SEAL_KEY" --keyring="$SEAL_KEYRING" --location="$SEAL_REGION" --project="$GCP_PROJECT" >/dev/null 2>&1; then
        echo "   ✅ Crypto key already exists."
    else
        gcloud kms keys create "$SEAL_KEY" --keyring="$SEAL_KEYRING" --location="$SEAL_REGION" \
            --project="$GCP_PROJECT" --purpose=encryption
        echo "   ✅ Crypto key created."
    fi

    echo "👤 Ensuring service account (skipped if it already exists)..."
    if gcloud iam service-accounts describe "$SEAL_SA" --project="$GCP_PROJECT" >/dev/null 2>&1; then
        echo "   ✅ Service account already exists."
    else
        gcloud iam service-accounts create openbao-seal \
            --project="$GCP_PROJECT" \
            --display-name "OpenBao KMS auto-unseal"
        echo "   ✅ Service account created."
        # Same propagation lag velero-setup hit: describe answers before the IAM
        # backends accept the account as a member. Poll a real policy read.
        printf "   ⏳ Waiting for the service account to propagate to IAM"
        for _ in $(seq 1 30); do
            if gcloud iam service-accounts get-iam-policy "$SEAL_SA" \
                --project="$GCP_PROJECT" >/dev/null 2>&1; then
                printf " ready\n"
                break
            fi
            printf "."
            sleep 2
        done
    fi

    # Scoped to the ONE key, not the key ring or project: this account can
    # wrap and unwrap OpenBao's barrier key and nothing else.
    echo "🔐 Granting encrypt/decrypt on the key..."
    retry_gcloud gcloud kms keys add-iam-policy-binding "$SEAL_KEY" \
        --keyring="$SEAL_KEYRING" --location="$SEAL_REGION" --project="$GCP_PROJECT" \
        --member="serviceAccount:${SEAL_SA}" \
        --role=roles/cloudkms.cryptoKeyEncrypterDecrypter >/dev/null

    # Workload Identity binding for the KSA the OpenBao chart creates. The KSA is
    # plain `openbao` in namespace `openbao` because the composition sets
    # fullnameOverride: openbao — verified live (kubectl get sa -n openbao).
    #
    # Unconditioned, deliberately. velero-setup proved on 2026-09-01 that the
    # providerId IAM condition never matches on this cluster, so a conditioned
    # binding here would only reproduce the "denied getAccessToken" failure. Same
    # identity-sameness caveat as Velero: any cluster in this project running a
    # pod as openbao/openbao can use this key. Acceptable while ttf-cluster is
    # the only cluster; revisit before a second one exists.
    echo "🔗 Binding openbao/openbao to ${SEAL_SA}..."
    retry_gcloud gcloud iam service-accounts add-iam-policy-binding "$SEAL_SA" \
        --project="$GCP_PROJECT" \
        --role=roles/iam.workloadIdentityUser \
        --member="serviceAccount:${GCP_PROJECT}.svc.id.goog[openbao/openbao]" \
        --condition=None >/dev/null

    echo ""
    echo "✅ OpenBao KMS seal ready."
    echo ""
    echo "Next, on an ALREADY-INITIALIZED OpenBao (this cluster), the seal must be"
    echo "migrated once with two Shamir shares — see nidavellir docs/secrets-management.md"
    echo "→ 'Migrating to auto-unseal'. On a fresh cluster, init as usual; the seal is"
    echo "picked up automatically and the init output holds RECOVERY keys, not unseal keys."
    ;;
```

Update the usage text at the bottom of the script: change `echo "Usage: $0 [create|delete|credentials|velero-setup]"` to include `openbao-seal-setup`, and add the line:

```bash
    echo "  openbao-seal-setup  One-time KMS key + IAM so OpenBao auto-unseals (idempotent)"
```

Also update the header comment's `Usage:` line the same way.

- [ ] **Step 2: Syntax-check**

Run: `ws test nordri`
Expected: `== syntax check ==` passes (gke-provision.sh is not in `shell_files`, so also run `bash -n components/nordri/gke-provision.sh` directly; expected no output).

- [ ] **Step 3: Add Layer 2.9 to `bootstrap.sh`**

Find the comment `# --- Step 3: ... ArgoCD` (the `echo "🔗 [Layer 3] Connecting Argo to Seed Gitea..."` block is later; insert before the ArgoCD Helm install step). Insert:

```bash
# --- Step 2.9: OpenBao seal key (homelab only) ---
# Homelab OpenBao unseals with a STATIC key (realm ADR 0004): 32 random bytes
# held in a Secret the composition injects as BAO_SEAL_STATIC_KEY. Created here,
# once, if absent — a composition cannot generate random material (every
# reconcile would re-render a different key and permanently seal the vault).
# GKE needs nothing here: it seals through KMS via Workload Identity, set up by
# `gke-provision.sh openbao-seal-setup`.
#
# The Secret must exist BEFORE the OpenBao pod is created; an env var sourced
# from a missing Secret leaves the pod in CreateContainerConfigError. ArgoCD
# deploys OpenBao at wave 10, long after this point.
if [[ "$TARGET" == "homelab" ]]; then
    echo "🔐 [Layer 2.9] Ensuring the homelab OpenBao static seal key..."
    kubectl create namespace openbao --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    if kubectl get secret -n openbao openbao-seal-key >/dev/null 2>&1; then
        echo "   ✅ openbao-seal-key already present — leaving it alone (replacing it would seal the vault for good)."
    else
        kubectl create secret generic openbao-seal-key -n openbao \
            --from-literal=key="$(openssl rand -base64 32)" >/dev/null
        echo "   ✅ openbao-seal-key created. Back it up off-cluster if this homelab holds anything you would miss."
    fi
fi
```

- [ ] **Step 4: Syntax-check again**

Run: `ws test nordri`
Expected: clean.

- [ ] **Step 5: Document both**

In `components/nordri/docs/bootstrap.md`, after the "### Layer 2.8" section add:

```markdown
### Layer 2.9 — OpenBao seal key (homelab only)
- Creates namespace `openbao` and, if absent, Secret `openbao-seal-key` holding a random 32-byte static seal key
- Never replaced on re-run: a new key cannot decrypt the existing barrier
- GKE skips this; its OpenBao seals through Cloud KMS via Workload Identity, provisioned once by `./gke-provision.sh openbao-seal-setup` (see below)
```

And after the "## Post-Bootstrap (GKE)" heading's first paragraph add:

```markdown
### OpenBao auto-unseal (one-time)

```bash
./gke-provision.sh openbao-seal-setup
```

Enables Cloud KMS, creates key ring `openbao` / key `unseal` in `us-east1` (the region cluster-identity's `gcpRegion` names), a service account with encrypt/decrypt on that key only, and the Workload Identity binding for `openbao/openbao`. Idempotent. On a cluster whose OpenBao is already initialized, follow it with the one-time seal migration in nidavellir's `docs/secrets-management.md`.
```

- [ ] **Step 6: Commit**

`.commits/nordri-openbao-seal.md`:

```markdown
---
message: "feat(openbao): provision the KMS seal on GKE and a static seal key on homelab"
add:
  - gke-provision.sh
  - bootstrap.sh
  - docs/bootstrap.md
---

Unconditioned Workload Identity binding on purpose: the providerId condition never matched for Velero on this cluster (2026-09-01), so the same caveat about identity sameness applies and is written down next to it.
```

Run: `ws commit nordri .commits/nordri-openbao-seal.md`

---

### Task 5: Seal stanza in the OpenBao composition (nidavellir)

**Files:**
- Modify: `components/nidavellir/openbao/xrd.yaml`
- Modify: `components/nidavellir/openbao/composition.yaml`
- Create: `components/nidavellir/tests/render/check-openbao.sh`

**Interfaces:**
- Consumes: cluster-identity `environment`, `gcpProject`, `gcpRegion` (Task 1, fixtures Task 2); Secret `openbao-seal-key` on homelab and the KMS key ring `openbao` / key `unseal` plus GSA `openbao-seal@<project>` on GKE (Task 4).
- Produces: `OpenBaoInstance.spec.parameters.seal` enum `auto | shamir`, default `auto`. `shamir` renders today's config unchanged, for a cluster where the seal setup has not run yet.

- [ ] **Step 1: Write the failing render check**

Create `components/nidavellir/tests/render/check-openbao.sh`:

```bash
#!/usr/bin/env bash
# Offline render check for the OpenBao composition's seal seams. Requires
# Docker and the crossplane CLI (realm docs/dev-setup.md). Run from the
# nidavellir repo root:
#   bash tests/render/check-openbao.sh
set -euo pipefail

command -v crossplane >/dev/null || { echo "crossplane CLI not on PATH — install from https://docs.crossplane.io/latest/cli/" >&2; exit 1; }

render() { # $1=env $2=xr-file
    crossplane render "$2" openbao/composition.yaml \
        tests/render/functions.yaml --extra-resources "tests/render/cluster-identity-$1.yaml"
}

fail=0
check() { # $1=label $2=haystack-file $3=want(yes|no) $4=needle
    if grep -Fq -- "$4" "$2"; then found=yes; else found=no; fi
    if [[ "$found" != "$3" ]]; then
        echo "FAIL [$1]: expected $4 present=$3, got present=$found" >&2
        fail=1
    fi
}

tmp_home=$(mktemp "${TMPDIR:-/tmp}/openbao-home.XXXXXX") tmp_gke=$(mktemp "${TMPDIR:-/tmp}/openbao-gke.XXXXXX") tmp_shamir=$(mktemp "${TMPDIR:-/tmp}/openbao-shamir.XXXXXX")
trap 'rm -f "$tmp_home" "$tmp_gke" "$tmp_shamir"' EXIT
render homelab tests/render/openbao-xr.yaml > "$tmp_home"
render gke     tests/render/openbao-xr.yaml > "$tmp_gke"
render gke     tests/render/openbao-xr-shamir.yaml > "$tmp_shamir"

# homelab: static seal fed from the openbao-seal-key Secret; no KMS, no WI annotation.
check homelab "$tmp_home" yes 'seal "static"'
check homelab "$tmp_home" yes 'current_key    = "env://BAO_SEAL_STATIC_KEY"'
check homelab "$tmp_home" yes 'secretName: openbao-seal-key'
check homelab "$tmp_home" no  'seal "gcpckms"'
check homelab "$tmp_home" no  'iam.gke.io/gcp-service-account'

# gke: KMS seal with coordinates from cluster-identity; WI annotation on the KSA; no static key.
check gke "$tmp_gke" yes 'seal "gcpckms"'
check gke "$tmp_gke" yes 'project    = "example-project"'
check gke "$tmp_gke" yes 'region     = "us-east1"'
check gke "$tmp_gke" yes 'key_ring   = "openbao"'
check gke "$tmp_gke" yes 'crypto_key = "unseal"'
check gke "$tmp_gke" yes 'iam.gke.io/gcp-service-account: openbao-seal@example-project.iam.gserviceaccount.com'
check gke "$tmp_gke" no  'seal "static"'
check gke "$tmp_gke" no  'BAO_SEAL_STATIC_KEY'

# seal: shamir opt-out renders no seal stanza at all, on either environment.
check shamir "$tmp_shamir" no 'seal "gcpckms"'
check shamir "$tmp_shamir" no 'seal "static"'
check shamir "$tmp_shamir" no 'iam.gke.io/gcp-service-account'

# unchanged seams from before this change
check homelab "$tmp_home" yes 'storageClass: local-path'
check gke     "$tmp_gke"  yes 'openbao.cmdbee.org'

[[ $fail -eq 0 ]] && echo "openbao render checks: PASS"
exit $fail
```

Create `components/nidavellir/tests/render/openbao-xr-shamir.yaml`:

```yaml
# Offline-render fixture: the seal opt-out. A cluster whose seal setup has not
# run yet keeps the manual Shamir posture by setting parameters.seal: shamir.
apiVersion: nidavellir.siliconsaga.org/v1alpha1
kind: XOpenBao
metadata:
  name: openbao
spec:
  parameters:
    storageSize: "2Gi"
    seal: shamir
```

- [ ] **Step 2: Run it to see it fail**

Run from `components/nidavellir`: `bash tests/render/check-openbao.sh`
Expected: `FAIL [homelab]: expected seal "static" present=yes, got present=no` and the gke equivalents; exit 1. (The shamir render fails schema-free since render does not validate the XRD; that is fine here.)

- [ ] **Step 3: Add the `seal` parameter to the XRD**

In `components/nidavellir/openbao/xrd.yaml`, under `parameters.properties` add after `domain`:

```yaml
                    seal:
                      type: string
                      enum: ["auto", "shamir"]
                      # Revised after the final review (see "Revisions" below): the
                      # default is shamir so merging changes nothing; graduation
                      # sets auto on the claim.
                      default: "shamir"
                      description: "auto renders the environment's auto-unseal seal (gcpckms via Workload Identity on gke, static key from Secret openbao-seal-key on homelab; realm ADR 0004). shamir renders no seal stanza — the manual-unseal posture of ADR 0002 — for a cluster whose seal prerequisites have not been provisioned yet."
```

Do **not** set `seal` in `openbao/claim.yaml`: the XRD default carries it, and setting it in the claim in the same commit would wedge ArgoCD on the schema diff (nordri's `crossplane-compositions` skill, "Adding an XRD Field and Using It in the Same Commit").

- [ ] **Step 4: Render the seal stanza and chart values in the composition**

In `components/nidavellir/openbao/composition.yaml`, replace the `deploy-openbao` step's template from `{{- $identity := ...` through the end of `resources:` `limits:` block with:

```yaml
        template: |
          {{- $identity := index .context "apiextensions.crossplane.io/environment" -}}
          {{- $storageClass := $identity.storageClass -}}
          {{- $version := .observed.composite.resource.spec.parameters.chartVersion | default "0.28.3" -}}
          {{- $size := .observed.composite.resource.spec.parameters.storageSize | default "2Gi" -}}
          {{- $seal := .observed.composite.resource.spec.parameters.seal | default "auto" -}}
          {{- $env := $identity.environment -}}
          {{- if and (eq $seal "auto") (eq $env "gke") (not $identity.gcpProject) -}}
          {{ fail "cluster-identity gcpProject is required for the gcpckms seal on gke (stamped by nordri hydration from GCP_PROJECT)" }}
          {{- end -}}
          apiVersion: helm.crossplane.io/v1beta1
          kind: Release
          metadata:
            name: {{ .observed.composite.resource.metadata.name }}-openbao
            annotations:
              gotemplating.fn.crossplane.io/composition-resource-name: openbao-release
          spec:
            forProvider:
              chart:
                name: openbao
                repository: https://openbao.github.io/openbao-helm
                version: "{{ $version }}"
              namespace: openbao
              values:
                fullnameOverride: openbao
                injector:
                  enabled: false
                server:
                  {{- if and (eq $seal "auto") (eq $env "gke") }}
                  # Workload Identity: the KSA the chart creates (plain `openbao`
                  # via fullnameOverride) impersonates the GSA that holds
                  # encrypt/decrypt on the KMS key. Provisioned by
                  # nordri/gke-provision.sh openbao-seal-setup.
                  serviceAccount:
                    annotations:
                      iam.gke.io/gcp-service-account: openbao-seal@{{ $identity.gcpProject }}.iam.gserviceaccount.com
                  {{- end }}
                  {{- if and (eq $seal "auto") (eq $env "homelab") }}
                  # Static seal key from the Secret nordri bootstrap Layer 2.9
                  # creates. The seal stanza reads it via env://.
                  extraSecretEnvironmentVars:
                    - envName: BAO_SEAL_STATIC_KEY
                      secretName: openbao-seal-key
                      secretKey: key
                  {{- end }}
                  standalone:
                    enabled: true
                    config: |
                      ui = true
                      listener "tcp" {
                        address         = "[::]:8200"
                        cluster_address = "[::]:8201"
                        tls_disable     = 1
                      }
                      storage "raft" {
                        path = "/openbao/data"
                      }
                      {{- if and (eq $seal "auto") (eq $env "gke") }}
                      seal "gcpckms" {
                        project    = "{{ $identity.gcpProject }}"
                        region     = "{{ $identity.gcpRegion }}"
                        key_ring   = "openbao"
                        crypto_key = "unseal"
                      }
                      {{- end }}
                      {{- if and (eq $seal "auto") (eq $env "homelab") }}
                      seal "static" {
                        current_key_id = "homelab-1"
                        current_key    = "env://BAO_SEAL_STATIC_KEY"
                      }
                      {{- end }}
                  dataStorage:
                    enabled: true
                    size: {{ $size }}
                    storageClass: {{ $storageClass }}
                  ha:
                    enabled: false
                  resources:
                    requests:
                      cpu: 100m
                      memory: 128Mi
                    limits:
                      cpu: 500m
                      memory: 512Mi
```

Also update the step's header comment: replace `minimal unseal posture — manual init/unseal, runbooks in docs/secrets-management.md` with `auto-unseal per environment (realm ADR 0004), seal: shamir opts out; runbooks in docs/secrets-management.md`.

- [ ] **Step 5: Run the render check to see it pass**

Run from `components/nidavellir`: `bash tests/render/check-openbao.sh`
Expected: `openbao render checks: PASS`.

- [ ] **Step 6: Validate the XRD schema offline**

Run from `components/nidavellir`: `crossplane beta validate openbao/xrd.yaml tests/render/openbao-xr-shamir.yaml`
Expected: `Total 1 resources: 0 missing schemas, 1 success cases, 0 failure cases`.

- [ ] **Step 7: Commit**

`.commits/nida-openbao-seal.md`:

```markdown
---
message: "feat(openbao): auto-unseal — gcpckms on gke, static key on homelab, seal: shamir opt-out"
add:
  - openbao/xrd.yaml
  - openbao/composition.yaml
  - tests/render/check-openbao.sh
  - tests/render/openbao-xr-shamir.yaml
---

The claim is deliberately untouched: the XRD default carries `seal: shamir` (revised from `auto` after the final review), so this commit changes nothing on a running cluster, and setting a new field in the claim in the same commit would wedge ArgoCD on the schema diff anyway. Graduation is a later `seal: auto` on the claim followed by the one-time `unseal -migrate` in nidavellir's docs/secrets-management.md.
```

Run: `ws commit nidavellir .commits/nida-openbao-seal.md`

---

### Task 6: Runbook and restart test (nidavellir)

**Files:**
- Modify: `components/nidavellir/docs/secrets-management.md`
- Create: `components/nidavellir/tests/platform/openbao/01-restart.yaml`

**Interfaces:**
- Consumes: Task 5's composition deployed on a cluster, seal migrated.
- Produces: a kuttl step proving a restarted pod returns Ready with no human; the runbook the operator follows in Task 7.

- [ ] **Step 1: Write the kuttl restart step**

Create `components/nidavellir/tests/platform/openbao/01-restart.yaml`:

```yaml
# Auto-unseal proof: kill the pod and require it to come back Ready on its own.
# Under the ADR 0002 manual posture this step could never pass — readiness
# gates on seal status and a restarted pod always came back sealed. Under ADR
# 0004 it must pass on both environments. 00-assert.yaml already proved the
# first Ready; this proves the SECOND, which is the one that matters.
apiVersion: kuttl.dev/v1beta1
kind: TestStep
commands:
  - command: kubectl delete pod openbao-0 -n openbao --wait=false
```

Create `components/nidavellir/tests/platform/openbao/01-assert.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: openbao
  namespace: openbao
status:
  readyReplicas: 1
```

(kuttl pairs `01-restart.yaml`'s step with `01-assert.yaml`; the suite timeout of 120s in `kuttl-test.yaml` covers a pod restart plus KMS unwrap comfortably.)

- [ ] **Step 2: Rewrite the unseal sections of the runbook**

In `components/nidavellir/docs/secrets-management.md`:

Replace the table row `| **unseal** | After EVERY process start ... |` with:

```markdown
| **unseal** | Automatic after every process start (ADR 0004): gke unwraps the barrier key through Cloud KMS via Workload Identity, homelab through a static key in Secret `openbao-seal-key`. Manual only on a cluster that set `parameters.seal: shamir`. | Until unsealed the pod runs but stays **NotReady** — readiness gates on seal status, so a pod that stays NotReady after a restart is the signal that the seal prerequisites are broken, not that someone forgot a step. |
```

Replace the bullet `- **A restarted OpenBao pod comes back sealed. Always.** ...` with:

```markdown
- **A restarted OpenBao pod unseals itself.** If it stays `0/1` after a restart, the seal backend is unreachable: on gke check the KSA annotation and the KMS IAM (`./gke-provision.sh openbao-seal-setup` repairs both), on homelab check that Secret `openbao-seal-key` exists. `bao status` says `Sealed true` with `Seal Type gcpckms`/`static` in that case; a `Seal Type shamir` means the seal migration below never ran.
```

Replace the bullet `- This manual dance can be replaced with **KMS auto-unseal** ...` with:

```markdown
- The Shamir shares from init did not disappear: after migration they are **recovery keys**, needed for `bao operator generate-root` and for `-migrate`-ing back to Shamir. Keep them where they were.
```

Replace the whole "### The pod restarted and shows 0/1 — unseal it" runbook with:

```markdown
### The pod restarted and shows 0/1

Expected to resolve itself within a minute. If it does not:

```bash
kubectl exec -n openbao openbao-0 -- bao status      # Seal Type + Sealed
kubectl logs -n openbao openbao-0 --tail=50          # "failed to unseal" names the backend error
```

Only a cluster still on `Seal Type shamir` needs the old two-share unseal; run the migration below instead of unsealing by hand again.

### Migrating an initialized OpenBao to auto-unseal (one-time, HUMAN-GATED)

Prerequisite on gke: `./gke-provision.sh openbao-seal-setup` has run. On homelab: bootstrap Layer 2.9 created `openbao-seal-key` (on an older homelab cluster, run `kubectl create secret generic openbao-seal-key -n openbao --from-literal=key="$(openssl rand -base64 32)"` once).

1. Hydrate the composition change (`update-embedded-git.sh <env> realm-siliconsaga`). ArgoCD rolls the StatefulSet; the pod comes back **sealed**, because a Shamir-initialized barrier does not know the new seal yet. This is the only restart that still needs a human.
2. Migrate with two shares (password manager on live envs, else `openbao-init`):

```bash
kubectl exec -n openbao openbao-0 -- bao operator unseal -migrate <share-1>
kubectl exec -n openbao openbao-0 -- bao operator unseal -migrate <share-2>
```

3. Verify: `bao status` now reports `Seal Type gcpckms` (or `static`) and `Recovery Seal Type shamir`, `Sealed false`.
4. Prove it: `kubectl delete pod openbao-0 -n openbao`, then watch it return `1/1` unaided. This is also `tests/platform/openbao/01-restart.yaml`.

Rolling back: set `parameters.seal: shamir` on the claim, hydrate, then `bao operator unseal -migrate` with the same shares reverses the migration.
```

Replace the "Custody posture" paragraph's last bullet `- **Hardening phase (future):** GCP KMS auto-unseal ...` with:

```markdown
- **Auto-unseal (ADR 0004, landed with the Forgejo day-2 Phase 1):** gke holds the barrier key in Cloud KMS, reached through Workload Identity; homelab holds a static key in Secret `openbao-seal-key`. The parked `openbao-init` material remains the recovery keys and root token. The homelab posture is honest about being homelab: anyone who can read Secrets in `openbao` can unseal, exactly as before, but nobody has to.
```

And under "## What's deliberately NOT here yet", replace the first bullet with:

```markdown
- **HA** — still a single replica. Auto-unseal landed (ADR 0004); a second replica is its own change.
```

- [ ] **Step 3: Commit**

`.commits/nida-openbao-runbook.md`:

```markdown
---
message: "docs(openbao): auto-unseal runbook and a kuttl restart proof"
add:
  - docs/secrets-management.md
  - tests/platform/openbao/01-restart.yaml
  - tests/platform/openbao/01-assert.yaml
---
```

Run: `ws commit nidavellir .commits/nida-openbao-runbook.md`

---

### Task 7: ADR 0004 (realm)

**Files:**
- Create: `realms/realm-siliconsaga/docs/adrs/0004-openbao-auto-unseal.md`

- [ ] **Step 1: Write the ADR** in the MADR shape of `0002-minimal-unseal-phase1.md`:

```markdown
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

Chosen option: "KMS on gke, static on homelab", selected by cluster-identity `environment` in the openbao composition with a `seal: shamir` claim-level opt-out. gke unwraps the barrier key through `roles/cloudkms.cryptoKeyEncrypterDecrypter` on one key, bound to the `openbao/openbao` ServiceAccount through Workload Identity; homelab reads a 32-byte key from Secret `openbao-seal-key` that nordri bootstrap creates once.

### Consequences

* Good, because restarts self-heal and the durable tier can depend on OpenBao.
* Good, because homelab stays offline-capable and identical in shape.
* Bad, because homelab custody is the same soft spot ADR 0002 accepted: anyone who can read Secrets in `openbao` holds the seal key. Accepted for a homelab, as before.
* Bad, because the gke Workload Identity binding is unconditioned (the providerId condition does not match on this cluster, per the Velero finding of 2026-09-01), so identity sameness across clusters in the project is unmitigated until a second cluster exists.

### Confirmation

`tests/platform/openbao/01-restart.yaml` deletes the pod and asserts it returns Ready unaided; `tests/render/check-openbao.sh` asserts the seal seams render per environment.

## More Information

* Realm design: `docs/plans/2026-09-07-forgejo-day2-design.md` (Credentials § Prerequisite)
* Plan: `docs/plans/2026-09-07-forgejo-day2-phase1-plan.md`
* Supersedes the unseal posture of ADR 0002; ADR 0002's init material becomes the recovery keys.
```

- [ ] **Step 2: Commit**

`.commits/realm-adr-0004.md`:

```markdown
---
message: "docs(adrs): 0004 — OpenBao auto-unseal per environment"
add:
  - docs/adrs/0004-openbao-auto-unseal.md
---
```

Run: `ws commit realm-siliconsaga .commits/realm-adr-0004.md`

---

### Task 8: Open the CR train and land it

**Files:** none new. Branches: nordri `feat/forgejo-phase1`, nidavellir `feat/openbao-auto-unseal`, heimdall `test/identity-fixtures`, realm `docs/adr-0004`.

- [ ] **Step 1: Push and open CRs** with `ws push <comp>` then `ws cr <comp> <title> <bodyfile>` using `templates/change.md`. Land order, which the CR bodies state: **nordri first** (fields and libs are inert until consumed), then nidavellir and heimdall in either order, realm last.

- [ ] **Step 2: Review feedback** through `ws review <comp> <cr#>`; push fixes, do not reply per thread or resolve.

---

### Task 9: Live migration on GKE (HUMAN-GATED)

Run by the operator, in order, with the agent watching read-only through `ws k8s`.

- [ ] **Step 1: Provision the seal**

From `components/nordri`: `GCP_PROJECT=teralivekubernetes ./gke-provision.sh openbao-seal-setup`
Expected: `✅ OpenBao KMS seal ready.` The Cloud KMS API is enabled as part of this; it was off on 2026-09-07.

- [ ] **Step 2: Hydrate** after the nordri and nidavellir CRs are merged and pulled:

```text
GITEA_HOST=gitea.cmdbee.org GITEA_SCHEME=https GCP_PROJECT=teralivekubernetes ./update-embedded-git.sh gke realm-siliconsaga
```

Expected: nordri's hydration output includes `GKE hydration pinned to project: teralivekubernetes`; ArgoCD syncs `layer4-fundamentals` (cluster-identity gains the fields) and `openbao` (StatefulSet rolls). `openbao-0` comes back `0/1`, `bao status` shows `Seal Type shamir` still, `Sealed true`.

- [ ] **Step 3: Migrate** with two shares from the password manager, per the runbook. Verify `bao status`: `Seal Type gcpckms`, `Recovery Seal Type shamir`, `Sealed false`.

- [ ] **Step 4: Prove it**: `ws k8s delete pod openbao-0 -n openbao` (scope armed to `openbao`), then `ws k8s get pods -n openbao -w` until `1/1`. Then confirm ESO recovered: `ws k8s get clustersecretstore openbao-kv` reports Ready.

- [ ] **Step 5: Record** in Loki's thalamus `heimdall-alerting` arc that "OpenBAO auto-unseal" is done, and in `forgejo-day2` that Phase 1 is complete on GKE.

---

### Task 10: Live migration on a homelab cluster (HUMAN-GATED)

- [ ] **Step 1**: On an existing homelab cluster, create the key once: `kubectl create secret generic openbao-seal-key -n openbao --from-literal=key="$(openssl rand -base64 32)"`. On a fresh cluster, `bootstrap.sh homelab` Layer 2.9 does it.
- [ ] **Step 2**: Hydrate: `./update-embedded-git.sh homelab realm-siliconsaga`.
- [ ] **Step 3**: Migrate with two shares from `openbao-init`, verify `Seal Type static`.
- [ ] **Step 4**: Run the kuttl platform suite: `./test.ps1 openbao` from `components/nidavellir`. Expected: both `00-assert` and `01-assert` pass.

---

## Revisions from the final whole-branch review (2026-09-08)

Recorded here rather than rewritten into the tasks above, so the tasks still read as what was executed. These supersede the task text where they conflict.

- **The seal change does not restart the pod on either environment.** The openbao 0.28.3 chart's StatefulSet uses `updateStrategy: OnDelete` and carries no config checksum (verified with `helm template`). Task 5's composition change therefore leaves a running `openbao-0` on its old Shamir config. Tasks 9 and 10 gain an explicit `kubectl delete pod openbao-0 -n openbao` between hydrating and migrating; the runbook in nidavellir's `docs/secrets-management.md` says so. Skipping it leaves the migration armed but not done, and the next unplanned restart lands sealed.
- **The XRD default is `shamir`, not `auto`.** Merging the nidavellir CR is then genuinely inert on the live cluster: nothing changes until the operator sets `parameters.seal: auto` on `openbao/claim.yaml` as the first step of Task 9 / Task 10, after the seal prerequisites exist. The claim carries `auto` from then on, so fresh bootstraps get auto-unseal. The ArgoCD schema-diff wedge is avoided because the XRD lands (and updates the live CRD) in an earlier hydration than the claim change. Render fixtures: `openbao-xr.yaml` sets `seal: auto` (the graduated state), `openbao-xr-shamir.yaml` omits the field (the default).
- **`patch_repo_urls_tree` fails closed in `forgejo`/`swap` mode too**: a manifest still carrying the seed URL is an error, since in the swap commit it would point ArgoCD back at the seed being retired. A single-file entry point `patch_repo_urls_file` covers the two manifests bootstrap applies from the source tree rather than from a hydrated repo (`platform/root-app.yaml`, the realm root-app template): both are now applied from a patched copy. `update-embedded-git.sh` and `bootstrap.sh` copy `root-app.yaml` before the tree rewrite, not after.
- **`openbao-seal-setup` reads the region from `cluster-identity-gke.yaml`** instead of defaulting it, and refuses a `GCP_REGION` that disagrees, so the key ring cannot be created in a region the seal stanza does not name.
- **The kuttl restart step waits for the delete** (`kubectl delete` without `--wait=false`, plus `kubectl wait --for=delete`); with `--wait=false` the assert could match the pre-delete `readyReplicas: 1` and prove nothing.
- **`crossplane beta validate` no longer exists in CLI v2.5**; Task 5 Step 6 is dropped. `helm template openbao/openbao --version 0.28.3` was used instead to confirm the chart consumes `server.serviceAccount.annotations` and `server.extraSecretEnvironmentVars` (annotation lands on the ServiceAccount, the env var lands on the server container as a `secretKeyRef`). nidavellir's `docs/testing.md` now documents the render checks and this extra step.
- **Task 9 Step 2 expectation corrected:** after hydration `openbao-0` stays `1/1` on Shamir until deleted; and the `openbao` XR may show a transient render failure if it reconciles before `layer4-fundamentals` has applied the new cluster-identity fields. Both are expected.
- **Task 9 order (Task 10 mirrors it with the static key):** 1) `openbao-seal-setup`; 2) unseal the old way if currently sealed, then take and verify a Raft snapshot (`bao operator raft snapshot save` + `inspect`, `kubectl cp` it off-cluster) — the checkpoint to restore from if anything below goes wrong; 3) commit `seal: auto` on the claim and hydrate, then **wait until the `openbao` XR renders successfully** (`Synced=True`, no render error; up to five minutes; if it never does, the cluster-identity fields did not arrive and the procedure stops here); 4) delete the pod and wait for the replacement container to be **Running** — not Ready, it comes back sealed; 5) `kubectl exec -it … bao operator unseal -migrate` twice, typing the shares at the prompt rather than on the command line; 6) verify `bao status`; 7) delete the pod again and watch it return Ready. The runbook in nidavellir `docs/secrets-management.md` carries the commands.
- **Minor:** `INTERNAL_GITEA_URL` was deleted from `bootstrap.sh` (nothing read it); ADR 0002 is marked superseded by 0004; the realm's `dev-setup.md` `go install` line for the Crossplane CLI is stale for the v2 module layout and the direct download now checksums correctly — a follow-up, not part of this branch.

## Self-review against the design

- **Auto-unseal, gke KMS via WI, homelab static seal in a Secret** → Tasks 4, 5, 6, 7, 9, 10. Covered, including the "fails loudly if sealed" property the Forgejo Job relies on, since a sealed OpenBao now means a broken backend rather than a missing step.
- **`maturity` on cluster-identity, existing components unaffected** → Tasks 1, 2. No composition reads it yet; Phase 2's Forgejo composition is the first consumer.
- **URL rewrite as a no-op while manifests carry seed URLs** → Task 3; the `seed-form tree is a no-op` assertion is the direct check. The three modes named in the design (`seed`, `forgejo`, `swap`) exist; the `--target`/`--swap` CLI flags that select them are Phase 3 work with `graduate.sh`, and this plan only defines `HYDRATE_URL_MODE`.
- **Not in Phase 1 by design:** the ArgoCD-Unknown alert (Phase 4, can be pulled forward independently), any Forgejo resource, any repoURL change.
- **Type consistency:** `patch_repo_urls_tree <tree> <mode>` and `HYDRATE_URL_MODE` are named identically in Tasks 3 and the design; `SEED_GIT_BASE_URL` strip in `bootstrap.sh` yields the same host `INTERNAL_GITEA_URL` held before. Seal names `openbao`/`unseal`/`openbao-seal@` match between Task 4's script and Task 5's template. Fixture stand-in `example-project` matches Task 5's render assertions.
