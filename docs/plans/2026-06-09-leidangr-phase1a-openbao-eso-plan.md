# Leiðangr Phase 1a — OpenBao + External Secrets Operator (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Cluster deploys are human-gated** (see Execution Model) — an agent prepares manifests and tests, a human (or an agent on the cluster-connected machine) runs the GitOps re-hydration and observes.

**Goal:** Stand up OpenBao (single-node, Raft, KV v2 + Kubernetes auth) and the External Secrets Operator as a reusable, env-aware secrets substrate in the SiliconSaga stack, validated with kuttl on homelab and GKE.

**Architecture:** OpenBao ships as a Crossplane composition inside the `nidavellir` repo (heimdall-style: `function-environment-configs` → `function-go-templating` rendering a `helm.crossplane.io` `Release`, env-aware via `cluster-identity`), fronted by an ArgoCD `Application`. ESO ships as a direct ArgoCD Helm `Application` (env-agnostic — no PVC/hostname). A `ClusterSecretStore` wires ESO to OpenBao over the Vault-compatible API using Kubernetes auth.

**Tech Stack:** Crossplane v2 (`function-environment-configs`, `function-go-templating`, `provider-helm` `Release`, `provider-kubernetes` `Object`), ArgoCD, OpenBao Helm chart, External Secrets Operator Helm chart, Gateway API (HTTPRoute), kuttl.

**Companion:** Plan 1b (Keycloak) is a separate doc. Design: [`2026-06-09-leidangr-design.md`](2026-06-09-leidangr-design.md) §7.

---

## Execution Model (read first)

This plan modifies the **`nidavellir`** repo only. Mimir is untouched (Plan 1b uses its Postgres claim).

- **Commits/CRs:** topic branch on `nidavellir`, via `ws commit nidavellir <bodyfile>` → `ws push nidavellir` → `ws cr nidavellir …`. Never raw git.
- **Deploy = GitOps, not `kubectl apply`.** homelab is staging. To exercise a branch: `bash scripts/ws exec nordri ./update-embedded-git.sh homelab` (re-hydrate in-cluster seed-Gitea), then hard-refresh the ArgoCD app (`kubectl annotate application <name> -n argo argocd.argoproj.io/refresh=hard --overwrite`). A direct `kubectl apply` over a `selfHeal: true` app flaps and reverts.
- **kuttl on Windows** runs via Docker (`components/<comp>/test.ps1`) or `ws test nidavellir`. The `.agent/skills/kuttl-testing/SKILL.md` gotchas apply (one-shot pod `phase` not `Ready`; exact-length condition matching).
- **Human-in-the-loop:** the unseal/init steps and every "observe in cluster" step are human-gated. Pause and let the operator run them and confirm before proceeding — do not assume success.

## Assumptions (confirm before starting)

1. **`provider-helm` + `function-environment-configs` + `function-go-templating` are installed** (heimdall uses all three — verify with `kubectl get providers,functions`).
2. **`cluster-identity` EnvironmentConfig exists** in each cluster with `storageClass` + `domain` (homelab: `local-path`/`homelab.local`; gke: `standard-rwo`/`cmdbee.org`).
3. **Gateway API + the `traefik-gateway` Gateway + `*.cmdbee.org` wildcard cert are live** (vegvisir). HTTPRoutes get TLS for free via `sectionName: websecure`. If homelab serves only `*.homelab.local`, the composition already keys the host on `$identity.domain`, so it resolves per-env automatically.
4. **OpenBao unseal posture = minimal** (per design decision): single replica, Raft, documented manual init+unseal, keys held short-term in a Kubernetes Secret. Auto-unseal/HA is a later hardening phase. This is acceptable for a staging substrate, NOT production-grade secret custody — call it out in the CR.

---

## File Structure

| Path (in `nidavellir` repo) | Responsibility |
|---|---|
| `openbao/xrd.yaml` | Defines the `OpenBaoInstance` claim + `XOpenBao` composite |
| `openbao/composition.yaml` | Renders the OpenBao Helm `Release` (env-aware) + HTTPRoute `Object` |
| `openbao/claim.yaml` | The single `OpenBaoInstance` instance ArgoCD applies |
| `openbao/secretstore.yaml` | `ClusterSecretStore` (ESO → OpenBao) + demo `ExternalSecret` |
| `apps/openbao-app.yaml` | ArgoCD `Application` (path: `openbao`) |
| `apps/external-secrets-app.yaml` | ArgoCD `Application` (ESO Helm chart) |
| `apps/kustomization.yaml` | Register both apps (uncomment `openbao-app.yaml`, add ESO) |
| `tests/e2e/openbao/00-assert.yaml` | kuttl: OpenBao pod Ready |
| `tests/e2e/external-secrets/00-apply.yaml` + `01-assert.yaml` | kuttl: ExternalSecret materializes a Secret |
| `kuttl-test.yaml` | Add the two test dirs |

---

## Part A1 — OpenBao composition

### Task A1.1: Verify the deployment substrate

- [ ] **Step 1: Confirm providers/functions are present**

Run (human, against homelab):
```bash
kubectl get providers.pkg.crossplane.io
kubectl get functions.pkg.crossplane.io
```
Expected: `provider-helm` and `provider-kubernetes` Healthy/Installed; `function-environment-configs`, `function-go-templating`, `function-auto-ready` present. If any are missing, STOP — they are prerequisites owned by nordri/nidavellir bootstrap, not this plan.

- [ ] **Step 2: Confirm the OpenBao chart coordinates and current version**

Run:
```bash
helm repo add openbao https://openbao.github.io/openbao-helm
helm repo update
helm search repo openbao/openbao --versions
```
Record the latest stable chart version (the manifests below use `0.18.0` as a placeholder-to-replace — substitute the real latest from this command). Also capture the values shape:
```bash
helm show values openbao/openbao --version <latest> | grep -nE 'standalone|dataStorage|raft|storageClass|injector|ha:' 
```
Expected: confirms `server.standalone`, `server.dataStorage.{enabled,size,storageClass}`, `injector.enabled` keys exist (the chart mirrors vault-helm).

### Task A1.2: Write the XRD

**Files:** Create `openbao/xrd.yaml`

- [ ] **Step 1: Create the XRD**

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xopenbaos.platform.siliconsaga.org
spec:
  group: platform.siliconsaga.org
  names:
    kind: XOpenBao
    plural: xopenbaos
  claimNames:
    kind: OpenBaoInstance
    plural: openbaoinstances
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                parameters:
                  type: object
                  properties:
                    storageSize:
                      type: string
                      default: "2Gi"
                    chartVersion:
                      type: string
                      default: "0.18.0"
                    domain:
                      type: string
                      description: "Override cluster-identity domain for the ingress host."
```

- [ ] **Step 2: Validate YAML**

Run: `bash scripts/ws exec nidavellir yq '.spec.names.kind' openbao/xrd.yaml`
Expected: `XOpenBao`

### Task A1.3: Write the composition

**Files:** Create `openbao/composition.yaml`

- [ ] **Step 1: Create the composition** (modeled on `components/heimdall/crossplane/composition.yaml`)

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: xopenbao-standalone
  labels:
    provider: openbao
spec:
  mode: Pipeline
  compositeTypeRef:
    apiVersion: platform.siliconsaga.org/v1alpha1
    kind: XOpenBao
  pipeline:
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

    - step: deploy-openbao
      functionRef:
        name: function-go-templating
      input:
        apiVersion: gotemplating.fn.crossplane.io/v1beta1
        kind: GoTemplate
        source: Inline
        inline:
          template: |
            {{- $identity := index .context "apiextensions.crossplane.io/environment" -}}
            {{- $storageClass := $identity.storageClass -}}
            {{- $version := .observed.composite.resource.spec.parameters.chartVersion | default "0.18.0" -}}
            {{- $size := .observed.composite.resource.spec.parameters.storageSize | default "2Gi" -}}
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
                  injector:
                    enabled: false
                  server:
                    image:
                      repository: quay.io/openbao/openbao
                    standalone:
                      enabled: true
                      config: |
                        ui = true
                        listener "tcp" {
                          address     = "[::]:8200"
                          tls_disable = 1
                        }
                        storage "raft" {
                          path = "/openbao/data"
                        }
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

    - step: deploy-ingress
      functionRef:
        name: function-go-templating
      input:
        apiVersion: gotemplating.fn.crossplane.io/v1beta1
        kind: GoTemplate
        source: Inline
        inline:
          template: |
            {{- $identity := index .context "apiextensions.crossplane.io/environment" -}}
            {{- $domain := .observed.composite.resource.spec.parameters.domain | default $identity.domain -}}
            apiVersion: kubernetes.crossplane.io/v1alpha2
            kind: Object
            metadata:
              name: {{ .observed.composite.resource.metadata.name }}-openbao-route
              annotations:
                gotemplating.fn.crossplane.io/composition-resource-name: openbao-route
            spec:
              forProvider:
                manifest:
                  apiVersion: gateway.networking.k8s.io/v1
                  kind: HTTPRoute
                  metadata:
                    name: openbao
                    namespace: openbao
                  spec:
                    parentRefs:
                      - name: traefik-gateway
                        namespace: kube-system
                        kind: Gateway
                        sectionName: websecure
                    hostnames:
                      - "openbao.{{ $domain }}"
                    rules:
                      - matches:
                          - path:
                              type: PathPrefix
                              value: /
                        backendRefs:
                          - name: {{ .observed.composite.resource.metadata.name }}-openbao
                            port: 8200

    - step: auto-ready
      functionRef:
        name: function-auto-ready
```

- [ ] **Step 2: Render the composition offline to catch templating errors**

Run (no cluster needed — per the `crossplane render` note in the thalamus testing observations):
```bash
bash scripts/ws exec nidavellir crossplane render openbao/claim.yaml openbao/composition.yaml /dev/null
```
(If `crossplane render` requires a functions file and an XR rather than a claim, fall back to validating YAML with `yq` on each doc.) Expected: renders a `Release` and an `Object`/HTTPRoute with `openbao.<domain>` and `storageClassName` populated, no template errors.

### Task A1.4: Write the claim + ArgoCD app + register

**Files:** Create `openbao/claim.yaml`, `apps/openbao-app.yaml`; Modify `apps/kustomization.yaml`

- [ ] **Step 1: Create the claim**

```yaml
apiVersion: platform.siliconsaga.org/v1alpha1
kind: OpenBaoInstance
metadata:
  name: openbao
  namespace: openbao
spec:
  parameters:
    storageSize: "2Gi"
```

- [ ] **Step 2: Create the ArgoCD Application** (`apps/openbao-app.yaml`, modeled on `apps/heimdall-app.yaml`)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openbao
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "10"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: 'http://gitea-http.gitea.svc.cluster.local:3000/nordri-admin/nidavellir.git'
    targetRevision: HEAD
    path: openbao
  destination:
    server: https://kubernetes.default.svc
    namespace: openbao
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - SkipDryRunOnMissingResource=true
      - ServerSideApply=true
```
(Confirm the `repoURL` matches how other nidavellir-internal-path apps reference the nidavellir repo — copy the exact value from a sibling app like `ntfy-app.yaml` if it differs.)

- [ ] **Step 3: Register the app**

In `apps/kustomization.yaml`, replace the commented line `# openbao-app.yaml ...` with `  - openbao-app.yaml`.

- [ ] **Step 4: Commit (OpenBao manifests, pre-deploy)**

```bash
cp templates/commit.md .commits/phase1a-openbao-manifests.md
# message: "feat(openbao): env-aware OpenBao composition + ArgoCD app"
# add: openbao/xrd.yaml, openbao/composition.yaml, openbao/claim.yaml, apps/openbao-app.yaml, apps/kustomization.yaml
bash scripts/ws commit nidavellir .commits/phase1a-openbao-manifests.md
bash scripts/ws push nidavellir
```

### Task A1.5: Deploy + init/unseal (HUMAN-GATED)

- [ ] **Step 1: Re-hydrate homelab + sync**

```bash
bash scripts/ws exec nordri ./update-embedded-git.sh homelab
kubectl annotate application openbao -n argo argocd.argoproj.io/refresh=hard --overwrite
```
Observe: `kubectl get pods -n openbao` → the `openbao-0` pod should reach `Running` but **Not Ready** (sealed/uninitialized is expected before init).

- [ ] **Step 2: Initialize and unseal** (minimal posture — document the keys handling)

```bash
kubectl exec -n openbao openbao-0 -- bao operator init -key-shares=3 -key-threshold=2 -format=json > openbao-init.json
# Unseal with 2 of 3 keys:
kubectl exec -n openbao openbao-0 -- bao operator unseal <key-1>
kubectl exec -n openbao openbao-0 -- bao operator unseal <key-2>
```
Store `openbao-init.json` (unseal keys + root token) **off the cluster, short-term** (e.g. the operator's password manager). Harden-later note: a future phase replaces this with KMS auto-unseal so manual unseal after restart is unnecessary.

- [ ] **Step 3: Enable KV v2 + Kubernetes auth + an ESO policy/role**

```bash
export VAULT_TOKEN=<root-token-from-init>
kubectl exec -n openbao openbao-0 -- sh -c 'BAO_TOKEN=$VAULT_TOKEN bao secrets enable -version=2 -path=secret kv'
kubectl exec -n openbao openbao-0 -- sh -c 'BAO_TOKEN=$VAULT_TOKEN bao auth enable kubernetes'
# Configure k8s auth to trust the in-cluster API:
kubectl exec -n openbao openbao-0 -- sh -c 'BAO_TOKEN=$VAULT_TOKEN bao write auth/kubernetes/config kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"'
# Read-only policy for ESO over secret/*:
kubectl exec -n openbao openbao-0 -- sh -c 'BAO_TOKEN=$VAULT_TOKEN echo "path \"secret/data/*\" { capabilities = [\"read\"] }" | bao policy write eso-read -'
# Role binding the ESO ServiceAccount to that policy:
kubectl exec -n openbao openbao-0 -- sh -c 'BAO_TOKEN=$VAULT_TOKEN bao write auth/kubernetes/role/eso-role bound_service_account_names=external-secrets bound_service_account_namespaces=external-secrets policies=eso-read ttl=1h'
```
(Exact env-var passing into `bao` may need a small wrapper; the intent — KV v2 at `secret/`, k8s auth, an `eso-read` policy, an `eso-role` bound to ESO's ServiceAccount — is what matters. Confirm each `bao` call returns success.)

- [ ] **Step 4: Seed a demo value (for the ESO smoke test later)**

```bash
kubectl exec -n openbao openbao-0 -- sh -c 'BAO_TOKEN=$VAULT_TOKEN bao kv put secret/demo foo=bar'
```

## Part A2 — External Secrets Operator

### Task A2.1: Deploy ESO

**Files:** Create `apps/external-secrets-app.yaml`; Modify `apps/kustomization.yaml`

- [ ] **Step 1: Confirm chart version**

Run:
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm search repo external-secrets/external-secrets --versions
```
Record the latest stable (manifests use `0.20.0` as a replace-me placeholder).

- [ ] **Step 2: Create the ESO Application** (direct Helm — env-agnostic, modeled on `apps/tailscale-operator-app.yaml`)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets
  namespace: argo
  annotations:
    argocd.argoproj.io/sync-wave: "9"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://charts.external-secrets.io
    chart: external-secrets
    targetRevision: "0.20.0"
    helm:
      values: |
        installCRDs: true
  destination:
    server: https://kubernetes.default.svc
    namespace: external-secrets
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

- [ ] **Step 3: Register + commit + deploy**

Add `  - external-secrets-app.yaml` to `apps/kustomization.yaml`. Commit via `ws commit nidavellir` (message `feat(eso): deploy External Secrets Operator`, add the new app + kustomization), push, re-hydrate homelab, hard-refresh `external-secrets` app. Observe: `kubectl get pods -n external-secrets` all Ready; `kubectl get crd | grep external-secrets` shows `clustersecretstores`, `externalsecrets`.

### Task A2.2: ClusterSecretStore + demo ExternalSecret

**Files:** Create `openbao/secretstore.yaml`

- [ ] **Step 1: Create the store + demo ExternalSecret**

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: openbao-kv
spec:
  provider:
    vault:
      server: "http://openbao.openbao.svc:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "eso-role"
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: demo-from-openbao
  namespace: external-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: openbao-kv
    kind: ClusterSecretStore
  target:
    name: demo-from-openbao
  data:
    - secretKey: foo
      remoteRef:
        key: secret/demo
        property: foo
```

- [ ] **Step 2: Apply via the openbao app, then verify materialization**

`secretstore.yaml` lives under `openbao/` so the `openbao` ArgoCD app picks it up. Commit (`feat(eso): ClusterSecretStore + demo ExternalSecret over OpenBao`), push, re-hydrate, hard-refresh. Observe (human):
```bash
kubectl get clustersecretstore openbao-kv -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'   # → True
kubectl get secret demo-from-openbao -n external-secrets -o jsonpath='{.data.foo}' | base64 -d            # → bar
```
If `Ready` is not `True`, debug the k8s-auth role/policy from Task A1.5 Step 3 before continuing.

## Part A3 — kuttl tests

### Task A3.1: OpenBao readiness assertion

**Files:** Create `tests/e2e/openbao/00-assert.yaml`

- [ ] **Step 1: Write the assertion** (StatefulSet Ready; one condition per kuttl exact-match rule)

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: openbao
  namespace: openbao
status:
  readyReplicas: 1
```
(Confirm the workload kind/name with `kubectl get sts,deploy -n openbao` after deploy — the OpenBao chart uses a StatefulSet named `openbao` in standalone mode; adjust if the release-name prefix differs.)

### Task A3.2: ESO materialization assertion

**Files:** Create `tests/e2e/external-secrets/00-apply.yaml`, `tests/e2e/external-secrets/01-assert.yaml`

- [ ] **Step 1: Apply step — seed KV + an ExternalSecret in the test namespace** (script, mirrors `mimir/tests/e2e/postgres/02-connection.yaml`)

```yaml
apiVersion: kuttl.dev/v1beta1
kind: TestStep
commands:
  - script: |
      # Seed a known KV value (idempotent)
      kubectl exec -n openbao openbao-0 -- sh -c 'BAO_TOKEN=$VAULT_TOKEN bao kv put secret/kuttl-demo k=v' || true
      kubectl apply -n $NAMESPACE -f - <<EOF
      apiVersion: external-secrets.io/v1
      kind: ExternalSecret
      metadata:
        name: kuttl-demo
      spec:
        refreshInterval: 1m
        secretStoreRef:
          name: openbao-kv
          kind: ClusterSecretStore
        target:
          name: kuttl-demo
        data:
          - secretKey: k
            remoteRef:
              key: secret/kuttl-demo
              property: k
      EOF
```

- [ ] **Step 2: Assert the Secret materialized**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: kuttl-demo
type: Opaque
```

- [ ] **Step 3: Register the test dirs**

In `kuttl-test.yaml`, add `./tests/e2e/openbao` and `./tests/e2e/external-secrets` to `testDirs` (confirm the existing key shape first).

- [ ] **Step 4: Run kuttl on homelab**

```bash
bash scripts/ws test nidavellir
# or on Windows: components/nidavellir/test.ps1
```
Expected: both new test dirs PASS. (Per the kuttl skill: if the StatefulSet assert fails on condition count, check `kubectl get sts openbao -n openbao -o yaml` and match all status fields exactly.)

- [ ] **Step 5: Commit the tests**

`ws commit nidavellir` (message `test(openbao): kuttl smoke for OpenBao readiness + ESO materialization`, add the three test files + `kuttl-test.yaml`), push.

## Part A4 — GKE validation + closeout

### Task A4.1: Validate on GKE

- [ ] **Step 1: Re-hydrate + sync GKE**

```bash
bash scripts/ws exec nordri ./update-embedded-git.sh gke
kubectl annotate application openbao external-secrets -n argo argocd.argoproj.io/refresh=hard --overwrite
```
Repeat the init/unseal (A1.5) against the GKE `openbao-0` (separate cluster = separate OpenBao state). Confirm `storageClass` rendered as `standard-rwo` and the HTTPRoute host as `openbao.cmdbee.org`.

- [ ] **Step 2: Run kuttl against GKE** (if a `kuttl-test-gke.yaml`-style config is wired for nidavellir; otherwise run the same suite with the GKE kube-context). Expected: PASS.

### Task A4.2: Close out

- [ ] **Step 1: Open the CR**

```bash
cp templates/change.md .crs/phase1a-openbao-eso.md
# Fill Summary (OpenBao + ESO substrate, minimal-unseal posture called out), Test plan (kuttl green homelab + GKE), Related (design §7)
bash scripts/ws cr nidavellir "feat: OpenBao + External Secrets Operator (Leiðangr Phase 1a)" .crs/phase1a-openbao-eso.md
```

- [ ] **Step 2: Update the thalamus arc** — add/advance a `leidangr` arc with Phase 1a shipped, `next:` pointing at Plan 1b (Keycloak).

- [ ] **Step 3: ADR distillation** (per design §9) — draft ADRs: "OpenBao-first secrets management," "minimal-unseal in Phase 1, KMS auto-unseal deferred," "ESO over the Vault-compatible API with Kubernetes auth." Use the MADR-sized template from the Backstage reference doc.

---

## Self-Review

- **Spec coverage (design §7):** OpenBao deployed env-aware ✔ (A1); ESO wired ✔ (A2); Postgres via Mimir is Plan 1b (Keycloak), not here ✔; kuttl smoke ✔ (A3); homelab + GKE ✔ (A4); closed out as reusable platform ✔ (A4.2). Gap: none for the OpenBao/ESO half.
- **Placeholder scan:** chart versions (`0.18.0`, `0.20.0`) are explicit replace-me values gated behind a "confirm latest version" research step — not silent TBDs. The `bao` env-var wrapper detail is flagged as needing confirmation, with the required end-state spelled out.
- **Consistency:** `eso-role`/`eso-read`/`secret/` path, `ClusterSecretStore` name `openbao-kv`, namespace `openbao`/`external-secrets`, and the `external-secrets` ServiceAccount are used consistently across A1.5, A2.1, A2.2, and A3.
