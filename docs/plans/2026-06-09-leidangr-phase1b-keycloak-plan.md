# Leiðangr Phase 1b — Keycloak (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. **On a cluster-connected machine (e.g. the Loki homelab box), the agent can run the `kubectl`/`kuttl` steps directly** — but pause for human confirmation on live-observe steps and any credential handling.

**Goal:** Deploy a basic Keycloak (via the upstream Keycloak Operator) backed by a Mimir-provisioned Postgres, exposed at `keycloak.cmdbee.org` over the platform wildcard TLS, with one realm + a placeholder OIDC client — the SSO substrate Phase 2's Backstage (and later Ting) will consume.

**Architecture:** The Keycloak **Operator** ships as a direct ArgoCD `Application` syncing pinned, vendored operator manifests (env-agnostic). The Keycloak **instance** ships as plain manifests under `keycloak/` (a `Keycloak` CR + `KeycloakRealmImport` + `HTTPRoute`), synced by a second ArgoCD `Application`. Postgres comes from a Mimir `PostgreSQLInstance` claim. The hostname is fixed to `keycloak.cmdbee.org` on **both** environments so the `*.cmdbee.org` wildcard cert on the shared `traefik-gateway` provides TLS (OIDC requires HTTPS) — no per-env templating needed.

**Tech Stack:** Keycloak Operator (`k8s.keycloak.org/v2alpha1`: `Keycloak`, `KeycloakRealmImport`), Mimir Crossplane Postgres (`database.example.org/v1alpha1` `PostgreSQLInstance`, Percona operator), ArgoCD, Gateway API (HTTPRoute), kuttl.

**Companion:** Plan 1a (OpenBao + ESO) is a separate doc. Design: [`2026-06-09-leidangr-design.md`](2026-06-09-leidangr-design.md) §7. **Independent of Plan 1a** — Keycloak's Postgres is from Mimir, not OpenBao. (A later phase can migrate Keycloak's client secrets into OpenBao via ESO; not required here.)

---

## Execution Model (read first)

Modifies the **`nidavellir`** repo only; consumes Mimir's existing Postgres composition (Mimir untouched).

- **Commits/CRs:** topic branch on `nidavellir` via `ws commit`/`ws push`/`ws cr`. Never raw git.
- **Deploy = GitOps, not `kubectl apply`.** homelab is staging: `bash scripts/ws exec nordri ./update-embedded-git.sh homelab`, then hard-refresh the relevant ArgoCD app. A direct apply over a `selfHeal: true` app reverts.
- **kuttl** via `ws test nidavellir` (or `components/nidavellir/test.ps1` on Windows). Honor `.agent/skills/kuttl-testing/SKILL.md`: one-shot pod assert on `status.phase==Succeeded` (no Ready condition); exact-length condition matching; commands run from the test-case dir.
- **Human-in-the-loop:** pause and confirm before/after realm import and any live-observe step. The agent may run kubectl here, but the human watches sensitive transitions.

## Assumptions (confirm before starting)

1. **Mimir Postgres composition is healthy** (`kubectl get composition | grep -i postgres`; the e2e in `components/mimir/tests/e2e/postgres/` passes). Claim kind `PostgreSQLInstance`, selector `provider: percona, service: postgresql`.
2. **`*.cmdbee.org` wildcard cert + `traefik-gateway` are live on the target cluster** (vegvisir). ting already runs at `ting.cmdbee.org` on homelab, so `keycloak.cmdbee.org` will resolve + get TLS there too. If homelab does NOT serve `*.cmdbee.org`, promote the HTTPRoute to a Crossplane composition reading `$identity.domain` (mirror OpenBao in Plan 1a).
3. **Keycloak Operator version pinned** (set in Task B1.1). The `Keycloak`/`KeycloakRealmImport` CR schema shifts between Keycloak majors — every CR below has a "verify against the pinned CRD" step.
4. **Mimir's generated DB secret keys:** Task B2.1 inspects `<claim>-user-secret` to confirm whether it carries a username key; the Keycloak CR's `usernameSecret` is wired accordingly (fallback: a small literal secret).

---

## File Structure

| Path (in `nidavellir` repo) | Responsibility |
|---|---|
| `keycloak-operator/` | Vendored pinned operator CRDs + controller manifests |
| `apps/keycloak-operator-app.yaml` | ArgoCD `Application` (path: `keycloak-operator`) |
| `keycloak/postgres-claim.yaml` | Mimir `PostgreSQLInstance` claim (`keycloak` DB) |
| `keycloak/keycloak.yaml` | `Keycloak` CR (db wired to Mimir secret, hostname, proxy headers) |
| `keycloak/realm-import.yaml` | `KeycloakRealmImport` — `siliconsaga` realm + placeholder client |
| `keycloak/httproute.yaml` | `HTTPRoute` `keycloak.cmdbee.org` → keycloak service |
| `apps/keycloak-app.yaml` | ArgoCD `Application` (path: `keycloak`) |
| `apps/kustomization.yaml` | Register both apps |
| `tests/e2e/keycloak/00-assert.yaml` | kuttl: Keycloak CR Ready |
| `tests/e2e/keycloak/01-oidc.yaml` | kuttl: OIDC discovery endpoint returns 200 |
| `kuttl-test.yaml` | Add the keycloak test dir |

---

## Part B1 — Keycloak Operator

### Task B1.1: Pin + vendor the operator

- [ ] **Step 1: Choose the Keycloak version and confirm operator manifest URLs**

Run:
```bash
# Latest stable Keycloak release tag:
gh release list --repo keycloak/keycloak --limit 5
```
Record the chosen version (e.g. `26.x.y` → call it `$KCVER`). The operator distributes two manifests per release:
- CRDs: `https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/<KCVER>/kubernetes/keycloaks.k8s.keycloak.org-v1.yml` and `…/keycloakrealmimports.k8s.keycloak.org-v1.yml`
- Operator: `https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/<KCVER>/kubernetes/kubernetes.yml`

- [ ] **Step 2: Vendor the pinned manifests into the repo** (GitOps-reproducible — don't sync live URLs)

```bash
mkdir -p components/nidavellir/keycloak-operator
cd components/nidavellir/keycloak-operator
curl -fsSL -o crd-keycloaks.yaml         https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/<KCVER>/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
curl -fsSL -o crd-realmimports.yaml      https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/<KCVER>/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml
curl -fsSL -o operator.yaml              https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/<KCVER>/kubernetes/kubernetes.yml
```
(Use the Bash tool, one `curl` per call — no `&&` chains. The operator's `kubernetes.yml` deploys into the `keycloak` namespace; confirm by grepping the file for `namespace:`.)

- [ ] **Step 3: Capture the CR schema for later tasks**

Run: `grep -nE 'hostname|httpEnabled|proxy|usernameSecret|passwordSecret|vendor' components/nidavellir/keycloak-operator/crd-keycloaks.yaml | head -40`
Expected: confirms the `spec.db`, `spec.hostname`, `spec.http`, `spec.proxy` field names for `$KCVER`. **Adjust the Keycloak CR in Task B2.2 to match exactly** — these fields are the ones that drift across versions.

### Task B1.2: ArgoCD app for the operator

**Files:** Create `apps/keycloak-operator-app.yaml`; Modify `apps/kustomization.yaml`

- [ ] **Step 1: Create the Application** (git-path, namespace `keycloak`, early sync-wave so CRDs/controller exist before the instance)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: keycloak-operator
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "8"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: 'http://gitea-http.gitea.svc.cluster.local:3000/nordri-admin/nidavellir.git'
    targetRevision: HEAD
    path: keycloak-operator
    directory:
      recurse: false
  destination:
    server: https://kubernetes.default.svc
    namespace: keycloak
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true   # CRDs are large — SSA avoids last-applied annotation bloat
```
(Confirm `repoURL` against a sibling nidavellir-internal-path app. SSA matters here: Keycloak CRDs exceed the client-side-apply annotation size limit.)

- [ ] **Step 2: Register** — add `  - keycloak-operator-app.yaml` to `apps/kustomization.yaml` (replace the `# keycloak-app.yaml` TODO comment region; we add two entries — operator + instance).

### Task B1.3: Commit (HOLD until Plan 1a lands / per session direction)

- [ ] **Step 1: Stage the operator vendoring**

```bash
cp templates/commit.md .commits/phase1b-keycloak-operator.md
# message: "feat(keycloak): vendor + deploy Keycloak Operator (pinned <KCVER>)"
# add: keycloak-operator/, apps/keycloak-operator-app.yaml, apps/kustomization.yaml
bash scripts/ws commit nidavellir .commits/phase1b-keycloak-operator.md
```
(Push/deploy gated on session direction. The operator is harmless to land early — it only installs CRDs + a controller.)

## Part B2 — Postgres + Keycloak instance

### Task B2.1: Postgres claim

**Files:** Create `keycloak/postgres-claim.yaml`

- [ ] **Step 1: Create the claim** (modeled on `components/mimir/tests/e2e/postgres/00-apply.yaml`)

```yaml
apiVersion: database.example.org/v1alpha1
kind: PostgreSQLInstance
metadata:
  name: keycloak-postgres
  namespace: keycloak
spec:
  parameters:
    storageSize: 5Gi
    version: "15"
    replicas: 1
    databaseName: keycloak
  compositionSelector:
    matchLabels:
      provider: percona
      service: postgresql
```

- [ ] **Step 2: After deploy, inspect the generated secret keys** (informs Task B2.2's `usernameSecret`)

Run (post-sync):
```bash
kubectl get secret keycloak-postgres-user-secret -n keycloak -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}'
```
Expected keys include `password`. If a `user`/`username` key is ALSO present, wire `usernameSecret` to it in B2.2. If NOT, create a literal secret in B2.2 Step 0.

### Task B2.2: Keycloak CR

**Files:** Create `keycloak/keycloak.yaml`

- [ ] **Step 0 (conditional): username secret** — only if `keycloak-postgres-user-secret` lacks a username key:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-db-username
  namespace: keycloak
type: Opaque
stringData:
  username: keycloak
```

- [ ] **Step 1: Create the Keycloak CR** (field names per the CRD captured in B1.1 Step 3 — adjust to `$KCVER`)

```yaml
apiVersion: k8s.keycloak.org/v2alpha1
kind: Keycloak
metadata:
  name: keycloak
  namespace: keycloak
spec:
  instances: 1
  db:
    vendor: postgres
    host: keycloak-postgres        # the claim's service name
    port: 5432
    database: keycloak
    usernameSecret:
      name: keycloak-db-username    # or keycloak-postgres-user-secret if it has a username key
      key: username
    passwordSecret:
      name: keycloak-postgres-user-secret
      key: password
  hostname:
    hostname: keycloak.cmdbee.org    # host-only, matching the HTTPRoute; some operator versions' hostname-v2 schema wants a full URL — verify against the pinned CRD (Task B1.1 Step 3) and switch to https://keycloak.cmdbee.org only if required
  http:
    httpEnabled: true               # TLS terminates at the gateway; Keycloak serves HTTP internally
  proxy:
    headers: xforwarded             # honor X-Forwarded-* from Traefik
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: "1"
      memory: 1Gi
```

- [ ] **Step 2: Create the HTTPRoute** (`keycloak/httproute.yaml`, modeled on the whoami/vegvisir Gateway API pattern)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: keycloak
  namespace: keycloak
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: kube-system
      kind: Gateway
      sectionName: websecure
  hostnames:
    - "keycloak.cmdbee.org"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: keycloak-service     # operator-created service for the `keycloak` CR
          port: 8080
```
(Confirm the operator's service name with `kubectl get svc -n keycloak` after the CR is created — it's typically `<cr-name>-service`.)

### Task B2.3: Realm import

**Files:** Create `keycloak/realm-import.yaml`

- [ ] **Step 1: Create a basic realm + placeholder client**

```yaml
apiVersion: k8s.keycloak.org/v2alpha1
kind: KeycloakRealmImport
metadata:
  name: siliconsaga-realm
  namespace: keycloak
spec:
  keycloakCRName: keycloak
  realm:
    realm: siliconsaga
    enabled: true
    displayName: SiliconSaga
    clients:
      - clientId: placeholder
        name: "Placeholder (replaced when Backstage/Ting arrive)"
        enabled: true
        protocol: openid-connect
        publicClient: false
        standardFlowEnabled: true
        redirectUris:
          - "https://placeholder.cmdbee.org/*"
```
(The real `backstage` confidential client is added in Phase 2 — this proves realm import + OIDC discovery work.)

### Task B2.4: Instance ArgoCD app + register

**Files:** Create `apps/keycloak-app.yaml`; Modify `apps/kustomization.yaml`

- [ ] **Step 1: Create the Application** (path `keycloak`, later sync-wave than the operator)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: keycloak
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "12"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: 'http://gitea-http.gitea.svc.cluster.local:3000/nordri-admin/nidavellir.git'
    targetRevision: HEAD
    path: keycloak
  destination:
    server: https://kubernetes.default.svc
    namespace: keycloak
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - SkipDryRunOnMissingResource=true   # CRs depend on operator CRDs existing first
      - ServerSideApply=true
```

- [ ] **Step 2: Register** — add `  - keycloak-app.yaml` to `apps/kustomization.yaml`.

- [ ] **Step 3: Commit (HOLD push per session direction)**

```bash
cp templates/commit.md .commits/phase1b-keycloak-instance.md
# message: "feat(keycloak): Postgres claim + Keycloak instance + realm import + ingress"
# add: keycloak/, apps/keycloak-app.yaml, apps/kustomization.yaml
bash scripts/ws commit nidavellir .commits/phase1b-keycloak-instance.md
```

## Part B3 — Deploy + verify (homelab, then GKE)

### Task B3.1: Deploy on homelab

- [ ] **Step 1: Re-hydrate + sync, operator first**

```bash
bash scripts/ws exec nordri ./update-embedded-git.sh homelab
kubectl annotate application keycloak-operator -n argo argocd.argoproj.io/refresh=hard --overwrite
```
Observe: operator pod Ready in `keycloak` ns; `kubectl get crd | grep keycloak` shows both CRDs. THEN hard-refresh `keycloak`:
```bash
kubectl annotate application keycloak -n argo argocd.argoproj.io/refresh=hard --overwrite
```

- [ ] **Step 2: Watch the bring-up (HUMAN-IN-THE-LOOP)**

```bash
kubectl get postgresqlinstance,perconapgcluster -n keycloak     # Postgres claim → Ready
kubectl get keycloak,keycloakrealmimport -n keycloak            # Keycloak CR → Ready; import → Done
kubectl get pods -n keycloak
```
Pause and confirm the Postgres claim reaches Ready BEFORE expecting Keycloak to start (Keycloak crash-loops until its DB is reachable — that's expected, not a failure, during provisioning). If the DB secret key wiring was wrong (B2.1/B2.2), fix the `usernameSecret` reference and re-sync.

### Task B3.2: kuttl tests

**Files:** Create `tests/e2e/keycloak/00-assert.yaml`, `tests/e2e/keycloak/01-oidc.yaml`; Modify `kuttl-test.yaml`

- [ ] **Step 1: Keycloak CR readiness assertion** (verify exact status fields with `kubectl get keycloak keycloak -n keycloak -o yaml` and match all)

```yaml
apiVersion: k8s.keycloak.org/v2alpha1
kind: Keycloak
metadata:
  name: keycloak
  namespace: keycloak
status:
  conditions:
    - type: Ready
      status: "True"
```

- [ ] **Step 2: OIDC discovery test** (in-cluster, against the service — avoids external DNS/TLS; mirrors mimir's connection-test script + the one-shot pod `phase` gotcha)

```yaml
apiVersion: kuttl.dev/v1beta1
kind: TestStep
commands:
  - script: |
      # No --rm: kubectl would delete the pod on command exit, so the phase
      # poll below would never see it. Create, poll, dump logs on failure,
      # then delete explicitly.
      kubectl run kc-oidc-probe --restart=Never --image=curlimages/curl:8.10.1 -n $NAMESPACE -- \
        sh -c 'for i in $(seq 1 30); do
          curl -fsS http://keycloak-service.keycloak.svc:8080/realms/siliconsaga/.well-known/openid-configuration | grep -q authorization_endpoint && exit 0
          sleep 5
        done; exit 1'
      RESULT=1
      for i in $(seq 1 60); do
        PHASE=$(kubectl get pod kc-oidc-probe -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$PHASE" = "Succeeded" ]; then RESULT=0; break; fi
        if [ "$PHASE" = "Failed" ]; then break; fi
        sleep 2
      done
      if [ "$RESULT" -ne 0 ]; then
        kubectl logs kc-oidc-probe -n $NAMESPACE >&2 || true
      fi
      kubectl delete pod kc-oidc-probe -n $NAMESPACE --ignore-not-found
      exit $RESULT
```
(Confirm the service name/port from B2.2 Step 2. One-shot pods report status via `phase`, never a Ready condition — which is also why the probe pod is created without `--rm` and deleted explicitly after the poll.)

- [ ] **Step 3: Register the test dir** in `kuttl-test.yaml` (`./tests/e2e/keycloak`).

- [ ] **Step 4: Run** `bash scripts/ws test nidavellir`. Expected: keycloak test dir PASS. Commit the tests (`test(keycloak): kuttl smoke — CR ready + OIDC discovery`).

### Task B3.3: GKE validation + closeout

- [ ] **Step 1: Re-hydrate + sync GKE**, repeat B3.1/B3.2 against the GKE context. Confirm `keycloak.cmdbee.org` serves the OIDC discovery doc over HTTPS externally:
```bash
curl -fsS https://keycloak.cmdbee.org/realms/siliconsaga/.well-known/openid-configuration | head -c 400
```

- [ ] **Step 2: Open the CR**

```bash
cp templates/change.md .crs/phase1b-keycloak.md
# Summary (Keycloak Operator + instance + Postgres + realm), Test plan (kuttl green + external OIDC discovery), Related (design §7, Plan 1a)
bash scripts/ws cr nidavellir "feat: Keycloak SSO substrate (Leiðangr Phase 1b)" .crs/phase1b-keycloak.md
```

- [ ] **Step 3: Advance the `leidangr` thalamus arc** — Phase 1 (1a + 1b) shipped, `next:` → Phase 2 (Backstage skeleton, wiring to this Keycloak + OpenBao).

- [ ] **Step 4: ADR distillation** (design §9) — "Keycloak via the upstream Operator (CR-driven realms)," "OIDC clients use the generic OIDC provider re-badged as Keycloak."

---

## Self-Review

- **Spec coverage (design §7):** Keycloak deployed ✔ (B1–B2); Postgres via Mimir claim ✔ (B2.1); realm + placeholder client ✔ (B2.3); env handling resolved (fixed `cmdbee.org` host for TLS, with composition fallback documented) ✔; kuttl smoke — CR ready + OIDC discovery ✔ (B3.2); homelab + GKE ✔ (B3); closed out ✔ (B3.3).
- **Placeholder scan:** `$KCVER` and the CRD-field-verification steps are explicit "pin + verify against the chosen version" actions, not silent TBDs (the Keycloak CR schema genuinely drifts by version, so a verify step is the correct instruction). The conditional username-secret (B2.2 Step 0) is gated on the real secret inspection in B2.1 Step 2.
- **Consistency:** namespace `keycloak`, claim `keycloak-postgres` → service `keycloak-postgres` + secret `keycloak-postgres-user-secret`, Keycloak CR `keycloak` → service `keycloak-service`, realm `siliconsaga`, host `keycloak.cmdbee.org` used consistently across B2, B3, and the kuttl tests.
- **Cross-plan:** independent of Plan 1a as designed; no OpenBao dependency in any task.
