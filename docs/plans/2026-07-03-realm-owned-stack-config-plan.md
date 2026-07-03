# Realm-Owned Stack Config — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Externalize realm/app-specific config out of the Tier-2 platform so a stack is born with an owning realm that injects its own config, on top of a deduplicated hydration library.

**Architecture:** nordri (T1) extracts its copy-pasted hydration logic into a sourced `lib/`, then gains an owning-realm arg that hydrates the realm's `cluster/` subtree into the seed-Gitea and registers a generic ArgoCD realm root-app pointed at it. The realm owns its `cluster/` app-of-apps (the relocated keycloak realm-import + oidc-realm-secrets today; Tier-3/4 ApplicationSets later). nidavellir stays generic and loses the two realm-specific keycloak files.

**Tech Stack:** Bash (Git Bash / MSYS2 on this machine), ArgoCD Applications, Kustomize, Keycloak Operator `KeycloakRealmImport`, External Secrets Operator. Tests: plain-bash assertion scripts + `bash -n` for shell; `kubectl kustomize` for YAML.

## Global Constraints

- **Spec:** `realms/realm-siliconsaga/docs/plans/2026-07-03-realm-owned-stack-config-design.md` — every task serves it.
- **No behavior change in Phase 1** (the refactor): the hydrated seed content and script behavior must be identical before/after. Prove it, don't assume it.
- **nidavellir stays generic:** no task adds a realm/app/game/Tier-3-4 reference to nidavellir. It only *loses* files.
- **nordri stays realm-agnostic in its committed tree:** the realm name/URL enters only at runtime (the arg) or via a templated placeholder; no committed nordri file names `siliconsaga`.
- **Portable `sed -i`:** every `sed -i` must keep the existing `$OSTYPE == darwin*` two-branch form (BSD needs `''`, GNU/MSYS must not have it). Copy the pattern already in the scripts.
- **Gitea admin username is fixed** to `nordri-admin` (downstream repoURLs assume it) — do not parameterize it.
- **`<realm>`** throughout = the realm arg / directory name / seed-Gitea repo name (`realm-siliconsaga` for this realm; no extra prefix).
- **Commit via the workspace:** `ws commit <component> <bodyfile>` (bodyfile in `.commits/`), never raw `git commit`. One logical change per commit.
- **Install just-in-time only:** do not install `bats`/`shellcheck`/etc. `bash`, `git`, `kubectl` (+ kustomize), `jq` are already present; tasks use only those.

## Branch & CR Topology

Three repos, three branches, a coordinated CR train (land in this order so no window leaves the realm config homeless):

1. **nordri** branch `feat/realm-owned-config` — Phases 1, 2 (lib refactor; realm arg/hydrate/wire; vendor-mirror-in-bootstrap). CR #1.
2. **realm** branch `docs/realm-owned-stack-config` (already exists, carries the design spec) — Phase 3 (the `cluster/` subtree + relocated manifests). CR #2.
3. **nidavellir** branch `feat/externalize-realm-config` — Phase 4 (remove the two keycloak files). CR #3, lands last.

Phase 5 (live bootstrap validation) is **cluster-gated** — it runs after the Docker Desktop compatibility assessment, not as part of the code CRs.

---

## Phase 1 — Hydration-dedup refactor (nordri, branch `feat/realm-owned-config`)

Pure dedup of `bootstrap.sh` + `update-embedded-git.sh` into a sourced `lib/`. No behavior change.

### Task 1.1: Extract the nidavellir per-target patch into `lib/patch-nidavellir.sh`

This is the block CodeRabbit named (nordri#21) and the most testable unit — a pure tree transform.

**Files:**
- Create: `components/nordri/lib/patch-nidavellir.sh`
- Create: `components/nordri/tests/unit/patch-nidavellir-test.sh`
- Modify: `components/nordri/bootstrap.sh:410-457` (replace inline block with a call)
- Modify: `components/nordri/update-embedded-git.sh:297-344` (replace inline block with a call)

**Interfaces:**
- Produces: `patch_nidavellir_tree <tree_dir> <target>` — rewrites `apps/vegvisir-app.yaml` overlay path `homelab`→`<target>` and `apps/tailscale-operator-app.yaml` `tailscale-operator-MACHINE`→`tailscale-operator-<host-or-gke>`; guards missing files and verifies both substitutions; returns non-zero (does not `exit`) on any failure so callers control flow. Reads `$OSTYPE`. Echoes the resolved `TS_HOSTNAME` on success.

- [ ] **Step 1: Write the failing test**

```bash
# components/nordri/tests/unit/patch-nidavellir-test.sh
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../../lib/patch-nidavellir.sh"

fails=0
check() { if eval "$2"; then echo "ok - $1"; else echo "NOT OK - $1"; fails=$((fails+1)); fi; }

# Arrange: a fake hydrated tree carrying the placeholder strings.
tree="$(mktemp -d)"; trap 'rm -rf "$tree"' EXIT
mkdir -p "$tree/apps"
printf 'path: vegvisir/manifests/overlays/homelab\n' > "$tree/apps/vegvisir-app.yaml"
printf 'hostname: tailscale-operator-MACHINE\n'      > "$tree/apps/tailscale-operator-app.yaml"

# Act + assert: homelab target rewrites overlay to homelab and stamps a host name.
out="$(patch_nidavellir_tree "$tree" homelab)"; rc=$?
check "homelab returns 0" "[ $rc -eq 0 ]"
check "vegvisir overlay stays homelab" "grep -q 'overlays/homelab' '$tree/apps/vegvisir-app.yaml'"
check "tailscale hostname stamped (not literal MACHINE)" "! grep -q 'tailscale-operator-MACHINE' '$tree/apps/tailscale-operator-app.yaml'"

# gke target rewrites overlay to gke and uses the fixed gke hostname.
printf 'path: vegvisir/manifests/overlays/homelab\n' > "$tree/apps/vegvisir-app.yaml"
printf 'hostname: tailscale-operator-MACHINE\n'      > "$tree/apps/tailscale-operator-app.yaml"
patch_nidavellir_tree "$tree" gke >/dev/null
check "gke overlay rewritten" "grep -q 'overlays/gke' '$tree/apps/vegvisir-app.yaml'"
check "gke hostname is tailscale-operator-gke" "grep -q 'tailscale-operator-gke' '$tree/apps/tailscale-operator-app.yaml'"

# Renamed placeholder must fail loudly (verification catches a no-op sed).
printf 'path: vegvisir/manifests/overlays/RENAMED\n' > "$tree/apps/vegvisir-app.yaml"
printf 'hostname: tailscale-operator-MACHINE\n'      > "$tree/apps/tailscale-operator-app.yaml"
patch_nidavellir_tree "$tree" homelab >/dev/null 2>&1; rc=$?
check "renamed vegvisir placeholder returns non-zero" "[ $rc -ne 0 ]"

# Missing file must fail loudly.
rm -f "$tree/apps/vegvisir-app.yaml"
patch_nidavellir_tree "$tree" homelab >/dev/null 2>&1; rc=$?
check "missing manifest returns non-zero" "[ $rc -ne 0 ]"

echo "---"; [ "$fails" -eq 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash components/nordri/tests/unit/patch-nidavellir-test.sh`
Expected: FAIL — `patch_nidavellir_tree: command not found` (the lib doesn't exist yet).

- [ ] **Step 3: Create the lib by moving the block out of `bootstrap.sh`**

Create `components/nordri/lib/patch-nidavellir.sh` from the current `bootstrap.sh:410-457` body, wrapped in a function that takes `(tree_dir, target)`, uses locals, and `return`s instead of `exit`s:

```bash
# components/nordri/lib/patch-nidavellir.sh
# Per-target patching of a hydrated nidavellir tree. Sourced by bootstrap.sh
# and update-embedded-git.sh. Returns non-zero on any failure (caller decides
# whether to exit). Echoes the resolved tailscale hostname on success.
patch_nidavellir_tree() {
    local tree="$1" target="$2"
    local vegvisir_app="$tree/apps/vegvisir-app.yaml"
    local tailscale_app="$tree/apps/tailscale-operator-app.yaml"
    local f ts_hostname machine
    for f in "$vegvisir_app" "$tailscale_app"; do
        if [[ ! -f "$f" ]]; then
            echo "❌ Expected nidavellir manifest missing: ${f#"$tree"/} — has apps/ been renamed?" >&2
            return 1
        fi
    done
    if [[ "$target" == "gke" ]]; then
        ts_hostname="tailscale-operator-gke"
    else
        machine="$(scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || hostname)"
        machine="$(printf '%s' "$machine" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-' | sed 's/^-*//;s/-*$//')"
        [[ -z "$machine" ]] && machine="local"
        ts_hostname="tailscale-operator-$machine"
    fi
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|path: vegvisir/manifests/overlays/homelab|path: vegvisir/manifests/overlays/$target|g" "$vegvisir_app"
        sed -i '' "s|tailscale-operator-MACHINE|$ts_hostname|g" "$tailscale_app"
    else
        sed -i "s|path: vegvisir/manifests/overlays/homelab|path: vegvisir/manifests/overlays/$target|g" "$vegvisir_app"
        sed -i "s|tailscale-operator-MACHINE|$ts_hostname|g" "$tailscale_app"
    fi
    if ! grep -q "path: vegvisir/manifests/overlays/$target" "$vegvisir_app"; then
        echo "❌ vegvisir overlay path not patched — the 'overlays/homelab' placeholder may have changed." >&2
        return 1
    fi
    if ! grep -q "$ts_hostname" "$tailscale_app"; then
        echo "❌ tailscale operator hostname not stamped — the 'tailscale-operator-MACHINE' placeholder may have changed." >&2
        return 1
    fi
    printf '%s' "$ts_hostname"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash components/nordri/tests/unit/patch-nidavellir-test.sh`
Expected: `ALL PASS`.

- [ ] **Step 5: Wire both scripts to source the lib and call it**

In `bootstrap.sh`, near the top after `SCRIPT_DIR=...` add `. "$SCRIPT_DIR/lib/patch-nidavellir.sh"`. Replace the inline block at `bootstrap.sh:410-457` with:

```bash
    if ! TS_HOSTNAME="$(patch_nidavellir_tree "$NIDAVELLIR_HYDRATE" "$TARGET")"; then
        exit 1
    fi
    echo "   Patched nidavellir for target '$TARGET' (tailscale hostname: $TS_HOSTNAME)."
```

Do the identical source-line + replacement in `update-embedded-git.sh` (inline block `297-344`).

- [ ] **Step 6: Syntax-check both scripts**

Run: `bash -n components/nordri/bootstrap.sh` then `bash -n components/nordri/update-embedded-git.sh`
Expected: no output, exit 0 for each.

- [ ] **Step 7: Commit**

Bodyfile `.commits/nordri-lib-patch.md` (`add:` = `lib/patch-nidavellir.sh`, `tests/unit/patch-nidavellir-test.sh`, `bootstrap.sh`, `update-embedded-git.sh`), then:
Run: `ws commit nordri .commits/nordri-lib-patch.md`
Message: `refactor(hydration): extract nidavellir per-target patch into lib/ (nordri#21)`

### Task 1.2: Extract Gitea helpers into `lib/gitea.sh`

**Files:**
- Create: `components/nordri/lib/gitea.sh`
- Modify: `components/nordri/bootstrap.sh` (remove inline `create_gitea_repo` + url building; source lib; rename calls)
- Modify: `components/nordri/update-embedded-git.sh` (remove inline `ensure_gitea_repo`/`urlencode`/`probe_gitea`; source lib)

**Interfaces:**
- Produces: `urlencode <s>`; `gitea_build_urls` (reads `GITEA_SCHEME/GITEA_HOST/GITEA_USER/GITEA_PASS`, sets `GITEA_API_URL`, `GITEA_GIT_BASE`, `GITEA_PROBE_URL`); `gitea_probe`; `gitea_ensure_repo <name>` (201/409-as-success + 5× retry). These match the current `update-embedded-git.sh` bodies verbatim (they are the more complete pair).

- [ ] **Step 1: Create the lib** by moving `update-embedded-git.sh`'s `urlencode` (129), `probe_gitea` (139-141), `ensure_gitea_repo` (149-180) into `lib/gitea.sh`, renaming to the `gitea_*` names above, and adding a `gitea_build_urls` that wraps lines 130-134. Keep bodies identical.

- [ ] **Step 2: Add a smoke test for `gitea_build_urls`** (the only offline-testable piece — repo creation/probe need a cluster):

```bash
# components/nordri/tests/unit/gitea-urls-test.sh
#!/usr/bin/env bash
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/../../lib/gitea.sh"
GITEA_SCHEME=http; GITEA_HOST=localhost:3000; GITEA_USER='nordri-admin'; GITEA_PASS='p@ss:/w#rd'
gitea_build_urls
[ "$GITEA_API_URL" = "http://localhost:3000" ] && \
  printf '%s' "$GITEA_GIT_BASE" | grep -q 'nordri-admin:p%40ss%3A%2Fw%23rd@localhost:3000' \
  && echo "ALL PASS" || { echo "FAIL: $GITEA_API_URL / $GITEA_GIT_BASE"; exit 1; }
```

Run: `bash components/nordri/tests/unit/gitea-urls-test.sh` → Expected: `ALL PASS`.

- [ ] **Step 3: Rewire both scripts** — source `lib/gitea.sh`, delete the now-duplicated inline defs, call `gitea_build_urls` where the URL vars were assembled, and replace `create_gitea_repo`/`ensure_gitea_repo` call-sites with `gitea_ensure_repo`.

- [ ] **Step 4: Syntax-check both.** Run: `bash -n` on each → exit 0.

- [ ] **Step 5: Commit** `.commits/nordri-lib-gitea.md` → `ws commit nordri` — `refactor(hydration): extract Gitea helpers into lib/gitea.sh`.

### Task 1.3: Extract tree hydration + vendor mirrors into `lib/hydrate.sh`

**Files:**
- Create: `components/nordri/lib/hydrate.sh`
- Create: `components/nordri/tests/unit/hydrate-prepare-test.sh`
- Modify: `components/nordri/bootstrap.sh` (nidavellir/mimir/heimdall blocks → helper calls; add vendor-mirror call)
- Modify: `components/nordri/update-embedded-git.sh` (same blocks + the vendor loop → helper calls)

**Interfaces:**
- Produces:
  - `hydrate_prepare_tree <src_dir> <dest_dir>` — `cp -r <src>/. <dest>/` then `rm -rf <dest>/.git`. Offline-testable.
  - `hydrate_push_tree <dest_dir> <gitea_repo> <commit_msg>` — `git init`/config/checkout main/add/commit/remote/`push --force` to `$GITEA_GIT_BASE/$GITEA_USER/<repo>.git`. Needs cluster.
  - `hydrate_working_tree_repo <src_dir> <gitea_repo> <commit_msg> [patch_fn]` — guards `-d src`; `gitea_ensure_repo`; mktemp registered in `TEMP_DIRS`; `hydrate_prepare_tree`; if `patch_fn` given, call `patch_fn <tmp> "$TARGET"`; `hydrate_push_tree`. Emits the existing ✅/⚠️ messages.
  - `hydrate_vendor_mirrors <space_separated_list>` — the loop from `update-embedded-git.sh:440-479` verbatim, resolving `$(dirname "$SCRIPT_DIR")/<name>` per entry.
- Consumes: `gitea_ensure_repo`, `$GITEA_GIT_BASE`, `$GITEA_USER`, `$TARGET`, `$SCRIPT_DIR`, `TEMP_DIRS` (from Task 1.2 + the scripts).

- [ ] **Step 1: Write the failing test for `hydrate_prepare_tree`:**

```bash
# components/nordri/tests/unit/hydrate-prepare-test.sh
#!/usr/bin/env bash
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/../../lib/hydrate.sh"
src="$(mktemp -d)"; dst="$(mktemp -d)"; trap 'rm -rf "$src" "$dst"' EXIT
mkdir -p "$src/.git" "$src/apps"; echo x > "$src/apps/a.yaml"; echo secret > "$src/.git/config"
hydrate_prepare_tree "$src" "$dst"
[ -f "$dst/apps/a.yaml" ] && [ ! -e "$dst/.git" ] && echo "ALL PASS" || { echo "FAIL"; exit 1; }
```

Run it → Expected: FAIL (`hydrate_prepare_tree: command not found`).

- [ ] **Step 2: Create `lib/hydrate.sh`** with the four functions above, lifting bodies from the current scripts (nidavellir block `bootstrap.sh:405-469` sans the patch, the mimir/heimdall blocks, and the vendor loop `update-embedded-git.sh:440-479`).

- [ ] **Step 3: Run the test → `ALL PASS`.**

- [ ] **Step 4: Rewire `update-embedded-git.sh`** — replace the nidavellir block with:

```bash
hydrate_working_tree_repo "$NIDAVELLIR_DIR" "$NIDAVELLIR_GITEA_REPO" "Update for $TARGET" patch_nidavellir_tree
```

replace the mimir/heimdall blocks with `hydrate_working_tree_repo` calls (no patch_fn), and the vendor loop with `hydrate_vendor_mirrors "$VENDOR_MIRRORS"`.

- [ ] **Step 5: Rewire `bootstrap.sh`** — same three `hydrate_working_tree_repo` calls, AND add `hydrate_vendor_mirrors "${VENDOR_MIRRORS:-keycloak-k8s-resources}"` after the heimdall hydrate (this closes the `bootstrap-vendor-mirror-hydration` gap; add the `VENDOR_MIRRORS` default near the other config vars).

- [ ] **Step 6: Syntax-check both → exit 0.**

- [ ] **Step 7: Structural no-behavior-change check** — confirm each script still contains exactly one hydrate call per component and the vendor call:

Run: `grep -c hydrate_working_tree_repo components/nordri/bootstrap.sh`
Expected: `3`
Run: `grep -c hydrate_vendor_mirrors components/nordri/bootstrap.sh`
Expected: `1`

- [ ] **Step 8: Commit** `.commits/nordri-lib-hydrate.md` → `ws commit nordri` — `refactor(hydration): extract tree hydration + vendor mirrors into lib/hydrate.sh; run vendor mirrors in bootstrap (closes vendor-mirror gap)`.

---

## Phase 2 — Realm as a hydrated source + injection wiring (nordri, same branch)

### Task 2.1: Owning-realm arg + `cluster/` hydration

**Files:**
- Modify: `components/nordri/bootstrap.sh` (arg parse ~55, config vars ~79, after heimdall hydrate)
- Modify: `components/nordri/update-embedded-git.sh` (arg parse ~44, config vars ~71, after heimdall hydrate)
- Modify: `components/nordri/docs/bootstrap.md` (document the new positional arg)

**Interfaces:**
- Consumes: `hydrate_working_tree_repo` (Task 1.3).
- Produces: `REALM` (arg 2, may be empty), `REALM_DIR` (resolved dir or empty), and — when resolved — a hydrated seed repo `<realm>` from `<REALM_DIR>/cluster/`.

- [ ] **Step 1: Add arg + resolution** after the target validation in both scripts:

```bash
REALM="${2:-}"                         # optional owning realm (name or dir)
REALM_DIR="${REALM_DIR:-}"
if [[ -n "$REALM" && -z "$REALM_DIR" ]]; then
    # Default: <workspace>/realms/<realm> — nordri lives at <ws>/components/nordri
    REALM_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")/realms/$REALM"
fi
if [[ -n "$REALM" && ! -d "$REALM_DIR/cluster" ]]; then
    echo "❌ Owning realm '$REALM' has no cluster/ config at: $REALM_DIR/cluster" >&2
    echo "   Pass a realm whose repo carries cluster/, or set REALM_DIR, or omit the arg for demo-only." >&2
    exit 1
fi
```

Update the two usage strings to `Usage: ./bootstrap.sh [gke|homelab] [realm]`.

- [ ] **Step 2: Hydrate the realm** after the heimdall hydrate, in both scripts:

```bash
if [[ -n "$REALM_DIR" ]]; then
    echo "💧 Hydrating owning realm '$REALM' (cluster/) to Seed Gitea..."
    hydrate_working_tree_repo "$REALM_DIR/cluster" "$REALM" "Realm config for $TARGET"
fi
```

- [ ] **Step 3: Verify the arg wiring parses** with a stubbed dry inspection:

Run: `bash -n components/nordri/bootstrap.sh` and `bash -n components/nordri/update-embedded-git.sh`
Expected: exit 0.
Run: `REALM=nope REALM_DIR=/tmp/does-not-exist bash -c 'set -e; SCRIPT_DIR=components/nordri; REALM=nope; REALM_DIR=/tmp/does-not-exist; [[ -n "$REALM" && ! -d "$REALM_DIR/cluster" ]] && echo GUARD-FIRES'`
Expected: `GUARD-FIRES` (confirms the missing-cluster guard logic).

- [ ] **Step 4: Commit** `.commits/nordri-realm-arg.md` → `ws commit nordri` — `feat(bootstrap): accept an owning-realm arg and hydrate its cluster/ subtree (nidavellir#20)`.

### Task 2.2: Generic realm root-app template + registration

**Files:**
- Create: `components/nordri/platform/argocd/realm-root-app.template.yaml`
- Modify: `components/nordri/bootstrap.sh` (register after the ArgoCD layer / root-app apply)

**Interfaces:**
- Consumes: `$REALM` (repo name in seed-Gitea), `$INTERNAL_GITEA_URL` (already defined `http://gitea-http.gitea.svc.cluster.local:3000`), the fixed `nordri-admin` owner.
- Produces: an in-cluster `Application/realm-<name>` in ns `argo` syncing the realm repo `cluster/` path.

- [ ] **Step 1: Create the template** (placeholders `__REALM_REPO__`) mirroring the existing nordri root-app shape (namespace `argo`, project `default`, automated sync, `CreateNamespace=true`), synced after the platform is up (annotate sync-wave later than nidavellir's Keycloak/ESO):

```yaml
# components/nordri/platform/argocd/realm-root-app.template.yaml
# Generic realm root-app. bootstrap.sh substitutes __REALM_REPO__ with the
# owning realm's seed-Gitea repo name and applies it. nordri never commits a
# realm-specific value — this file stays realm-agnostic.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: __REALM_REPO__
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "20"
spec:
  project: default
  source:
    repoURL: http://gitea-http.gitea.svc.cluster.local:3000/nordri-admin/__REALM_REPO__.git
    targetRevision: main
    path: cluster
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
```

- [ ] **Step 2: Register it** after ArgoCD is installed and the nordri root-app is applied, in `bootstrap.sh` only (day-2 `update-embedded-git.sh` re-hydrates the realm repo but does not re-apply cluster-scoped ArgoCD wiring):

```bash
if [[ -n "$REALM" ]]; then
    echo "🔗 Registering realm root-app for '$REALM'..."
    sed "s|__REALM_REPO__|$REALM|g" "$SCRIPT_DIR/platform/argocd/realm-root-app.template.yaml" \
        | kubectl apply -f -
fi
```

- [ ] **Step 3: Render-verify the template substitutes cleanly** (no cluster needed):

Run: `sed 's|__REALM_REPO__|realm-siliconsaga|g' components/nordri/platform/argocd/realm-root-app.template.yaml | kubectl apply --dry-run=client -f -`
Expected: `application.argoproj.io/realm-siliconsaga created (dry run)`.

- [ ] **Step 4: Commit** `.commits/nordri-realm-rootapp.md` → `ws commit nordri` — `feat(bootstrap): register a generic realm root-app pointed at the hydrated realm repo (nidavellir#20)`.

---

## Phase 3 — Realm `cluster/` subtree + relocated config (realm, branch `docs/realm-owned-stack-config`)

### Task 3.1: Create the realm `cluster/` app-of-apps with the relocated keycloak config

**Files:**
- Create: `realms/realm-siliconsaga/cluster/kustomization.yaml`
- Create: `realms/realm-siliconsaga/cluster/keycloak/kustomization.yaml`
- Create: `realms/realm-siliconsaga/cluster/keycloak/realm-import.yaml` (moved from nidavellir, content unchanged)
- Create: `realms/realm-siliconsaga/cluster/keycloak/oidc-realm-secrets.yaml` (moved, unchanged)
- Create: `realms/realm-siliconsaga/cluster/README.md`

**Interfaces:**
- Consumes: nothing (leaf manifests). Synced by the nordri realm root-app (Task 2.2) at path `cluster/`.
- Produces: the in-cluster `KeycloakRealmImport/siliconsaga-realm` + `ExternalSecret/leidangr-oidc-realm-secrets` in ns `keycloak`.

- [ ] **Step 1: Copy the two manifests verbatim** from the current `components/nidavellir/keycloak/realm-import.yaml` and `oidc-realm-secrets.yaml` into `cluster/keycloak/`. Do not edit their content — they already use the born-in-OpenBao → ESO → `${...}` pattern.

- [ ] **Step 2: Write `cluster/keycloak/kustomization.yaml`:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - realm-import.yaml
  - oidc-realm-secrets.yaml
```

- [ ] **Step 3: Write `cluster/kustomization.yaml`** (the realm-owned app-of-apps root; today it includes only keycloak; Tier-3/4 ApplicationSets append here later):

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
# Realm-owned in-cluster config. The nordri realm root-app syncs this path.
# Add realm-owned ApplicationSets (e.g. tafl game-hosting, one per wired game
# type) as resources here — nidavellir stays unaware.
resources:
  - keycloak
```

- [ ] **Step 4: Write `cluster/README.md`** stating: this subtree is hydrated into seed-Gitea as repo `realm-siliconsaga` and synced by nordri's realm root-app; it holds realm/app-specific in-cluster config that must NOT live in the platform; ordering — keycloak config resolves after nidavellir's generic Keycloak + ESO are up.

- [ ] **Step 5: Validate the kustomize builds:**

Run: `kubectl kustomize realms/realm-siliconsaga/cluster`
Expected: emits both objects — a `KeycloakRealmImport` named `siliconsaga-realm` and an `ExternalSecret` named `leidangr-oidc-realm-secrets`, no error.

- [ ] **Step 6: Commit** `.commits/realm-cluster.md` (target `realm-siliconsaga`) → `ws commit realm-siliconsaga` — `feat(cluster): add realm-owned cluster/ config with keycloak realm-import + oidc secrets (nidavellir#20)`.

---

## Phase 4 — Remove the config from the platform (nidavellir, branch `feat/externalize-realm-config`)

### Task 4.1: Delete the two realm-specific keycloak files from nidavellir

**Files:**
- Delete: `components/nidavellir/keycloak/realm-import.yaml`
- Delete: `components/nidavellir/keycloak/oidc-realm-secrets.yaml`
- Modify: `components/nidavellir/keycloak/` any `kustomization.yaml` that references them

**Interfaces:**
- Consumes: nothing. Leaves nidavellir with generic Keycloak + OpenBao + ESO + `sso-demo` only.

- [ ] **Step 1: Check for references** so removal doesn't leave a dangling kustomize resource:

Run: `grep -rn "realm-import.yaml\|oidc-realm-secrets.yaml" components/nidavellir`
Expected: note every hit (likely a `keycloak/kustomization.yaml` list entry).

- [ ] **Step 2: Remove the files and any kustomization references** found in Step 1. If `keycloak/kustomization.yaml` lists them under `resources:`, delete those two lines.

- [ ] **Step 3: Verify nidavellir keycloak still builds generic:**

Run: `kubectl kustomize components/nidavellir/keycloak`
Expected: builds with no error and no longer emits `KeycloakRealmImport/siliconsaga-realm` or the leidangr `ExternalSecret` (grep the output to confirm neither `siliconsaga-realm` nor `leidangr-oidc` appears).

- [ ] **Step 4: Confirm sso-demo (the no-realm proof) is untouched:**

Run: `grep -rn "siliconsaga\|leidangr" components/nidavellir` — Expected: no matches in `keycloak/`, `apps/`, or `openbao/` (a match only under `demos/`/docs is acceptable if pre-existing and demo-scoped; a match in platform manifests is a failure to investigate).

- [ ] **Step 5: Commit** `.commits/nidavellir-remove-realm.md` (target `nidavellir`) → `ws commit nidavellir` — `refactor(keycloak): remove siliconsaga realm-import + leidangr OIDC config; platform stays generic (nidavellir#20)`.

---

## Phase 5 — Live bootstrap validation (CLUSTER-GATED — after Docker Desktop assessment)

Not part of the code CRs. Run once a cluster is available (Docker Desktop or Rancher Desktop fallback), with `helm` on PATH (restart the shell after the winget install).

- [ ] **Step 1: Assess the substrate first** — storage classes, whether a `coredns-custom` mechanism exists, ingress/LB — per task #8 in the session. Decide Docker Desktop vs Rancher Desktop.
- [ ] **Step 2: Clone the remaining hydration inputs** so the vendor loop + app hydrations have sources: `ws clone heimdall`, `ws clone mimir`, `ws clone keycloak-k8s-resources`.
- [ ] **Step 3: Realm-carrying bootstrap:** from the nordri checkout, `./bootstrap.sh homelab realm-siliconsaga`. Expected: nordri/nidavellir/mimir/heimdall hydrate, the vendor mirror pushes its tags, the realm repo hydrates, and the realm root-app registers.
- [ ] **Step 4: Verify the injection** — the realm root-app `realm-siliconsaga` appears in ns `argo` and syncs; once generic Keycloak + ESO are up and `secret/leidangr/oidc` is seeded (nidavellir OpenBao runbook), `KeycloakRealmImport/siliconsaga-realm` reports `Done=True`.
- [ ] **Step 5: Verify the degrade path** — a second run/cluster with `./bootstrap.sh homelab` (no realm arg) brings up generic platform + `sso-demo`, registers no realm root-app, and shows no `siliconsaga-realm` import.

---

## Self-Review Notes (spec coverage)

- Owning-realm arg → Task 2.1. Config moves out of platform → Tasks 3.1 (add) + 4.1 (remove). Injection mechanism (realm-owned app-of-apps + generic root-app) → Tasks 2.2 + 3.1. Degrade gracefully → Task 5 Step 5 (+ the no-arg guard in 2.1). Hydration dedup foundation → Tasks 1.1–1.3, with the vendor-mirror-in-bootstrap bonus in 1.3 Step 5. CoreDNS-ownership + Forgejo-source-swap are spec non-goals — intentionally no tasks. B (OpenBao-OIDC helper) and C (realm#17 scaffolder) — spec non-goals, no tasks.
