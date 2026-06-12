# SSO Demo — Combined Design + Plan

> **For agentic workers:** combined design+plan (small scope, ~10 manifests + kuttl + README). Implementation in `nidavellir`, branched on Phase 1b (PR #15). Homelab deploys are agent-drivable; the browser walkthrough is the human's payoff.

**Goal:** a small, GitOps-managed demo proving the Leiðangr Phase 1 substrate end to end — secrets born in OpenBao, delivered by ESO, consumed simultaneously by Keycloak (realm/client provisioning via placeholder injection) and by a real OIDC app (oauth2-proxy fronting whoami). Usable by a human in a browser on BOTH environments, and by automation as a browserless acceptance test. This is also the designated use case for the eventual GKE validation of Phases 1a+1b.

**Decision trail (Cervator, 2026-06-11):** oauth2-proxy + whoami over a custom app; a separate disposable `demo` realm over extending `siliconsaga`; lifecycle "both" — GitOps-managed standing fixture that remains plain-`kubectl`-applyable; homelab browser access is a requirement, not a nice-to-have.

## The proof at the center

```text
            bao kv put secret/sso-demo …            (human or test seeds ONCE)
                        │
                   OpenBao KV
                        │  ClusterSecretStore openbao-kv (k8s auth)
            ┌───────────┴────────────┐
   ExternalSecret (ns keycloak)   ExternalSecret (ns sso-demo)
            │                            │
   Secret sso-demo-realm-secrets   Secret sso-demo-oauth2-proxy
            │ placeholders               │ env
   KeycloakRealmImport `demo`      oauth2-proxy ──upstream──▶ whoami
   (client sso-demo + user demo)         ▲
                        └── OIDC code flow ──┘
```

One set of values feeds both sides of the handshake. A successful browser login (or the password-grant acceptance check) proves OpenBao → ESO → Keycloak → app in a single observable act. whoami then echoes the `X-Forwarded-User`/`-Email` headers oauth2-proxy injects — the human-visible "Keycloak says I am demo@example.com".

## Environment story (the homelab browser answer)

`cmdbee.org` is GKE-only and homelab's `websecure` listener is down (vegvisir wildcard drift), but the `web` HTTP listener works and browsers auto-resolve `*.localhost` to 127.0.0.1 (the `gitea.localhost` precedent). So:

| | GKE | homelab |
|---|---|---|
| Demo URL | `https://sso-demo.cmdbee.org` (websecure) | `http://sso-demo.localhost` (web) |
| Keycloak URL | `https://keycloak.cmdbee.org` (websecure) | `http://keycloak.localhost` (web, route rendered by the demo composition, homelab branch only — avoids exposing plain-HTTP Keycloak on the GKE LB) |
| oauth2-proxy config | Clean OIDC discovery against the external issuer; secure cookies | Split-horizon lab config: browser-facing login URL on `keycloak.localhost`, backchannel token/JWKS via `keycloak-service.keycloak.svc`, `--insecure-oidc-skip-issuer-verification`, `cookie-secure=false`. Lab compromises stay on the homelab branch. |

**Prerequisite change to Phase 1b's Keycloak CR:** drop the pinned `hostname` in favor of hostname-v2 dynamic resolution (`hostname.strict: false`). A pinned `keycloak.cmdbee.org` makes the OIDC issuer unreachable from a homelab browser; dynamic mode issues per-request-host (`https://keycloak.cmdbee.org/...` on GKE, `http://keycloak.localhost/...` on homelab). Per-env re-pinning is a future hardening item alongside TLS.

## Shape: one claim, full-stack composition

The env-branched oauth2-proxy config makes this a textbook `function-environment-configs` + `function-go-templating` composition (the stack idiom), which also makes the demo thematically complete — a single `SSODemo` claim exercises cluster-identity, compositions, OpenBao, ESO, Keycloak, and Gateway API at once. Offline `crossplane render` against the existing homelab/gke identity fixtures validates both branches without a cluster.

| Artifact (nidavellir) | Content |
|---|---|
| `sso-demo/xrd.yaml` | `SSODemo`/`XSSODemo` (`nidavellir.siliconsaga.org`), no required params |
| `sso-demo/composition.yaml` | Renders: the two ExternalSecrets; the `demo` KeycloakRealmImport (client `sso-demo`, confidential, `directAccessGrantsEnabled` for browserless acceptance, both redirect URIs; user `demo`/`demo@example.com`, `emailVerified: true`, password via placeholder); whoami (`traefik/whoami:v1.10`) + Service; oauth2-proxy (`quay.io/oauth2-proxy/oauth2-proxy:v7.15.3`) + Service with the per-env flag sets above; HTTPRoute (env-matched hostname/listener); homelab-only `keycloak.localhost` HTTPRoute |
| `sso-demo/claim.yaml` | `SSODemo` `sso-demo` in ns `sso-demo` |
| `sso-demo/README.md` | Human walkthrough: seed/read values via `bao kv`, browse, log in as `demo`, see the headers; per-env URLs |
| `apps/sso-demo-app.yaml` + kustomization | ArgoCD app, sync-wave 14 (after keycloak) |
| `keycloak/keycloak.yaml` | hostname pin → `strict: false` (see above) |
| `tests/e2e/sso-demo/` | Acceptance: seed-if-missing (idempotent, parked root token — manual seeds never clobbered) → Secrets materialize → password-grant token from `/realms/demo/.../token` using the materialized client secret → `/oauth2/start` 302 points at the demo realm's auth endpoint |

**Seeding:** three values at `secret/sso-demo` — `client-secret`, `cookie-secret` (32-byte base64), `demo-user-password`. Humans seed/read via documented `bao kv` commands (custody UX is part of the demo); the kuttl test self-seeds only when absent. Until seeded, the ExternalSecrets and realm-import job simply wait — GitOps converges once values exist. Secret material never touches git.

**Non-goals:** production hardening (TLS in-cluster, pinned hostnames, real users/roles), Backstage's `siliconsaga` realm (untouched), homelab websecure TLS (vegvisir's own pass).

## Acceptance criteria

1. `crossplane render` of the claim against both identity fixtures produces the env-correct flag sets and routes.
2. On homelab: kuttl `sso-demo` case passes (secrets materialize, token grant succeeds with OpenBao-derived credentials, oauth2-proxy 302 targets the demo realm).
3. On homelab: a human can browse `http://sso-demo.localhost`, sign in as `demo` with the password read from OpenBao, and see their identity echoed by whoami.
4. On GKE (deferred to the Phase 1 GKE validation pass): same as 2–3 at `https://sso-demo.cmdbee.org` with clean discovery and secure cookies.
