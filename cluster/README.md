# Realm-Owned In-Cluster Config (`cluster/`)

This subtree holds the SiliconSaga realm's own in-cluster GitOps config — the config that must NOT live in the platform (nidavellir), per the tier boundary (nidavellir#20).

## How it reaches the cluster

`nordri/bootstrap.sh <realm> <cluster>` hydrates the whole realm checkout into the seed repo `realm-siliconsaga`, and the realm root Application reads `cluster/` from it. nordri learns only the realm's name — never its content. Day-2 changes: `nordri/update-embedded-git.sh realm-siliconsaga` re-hydrates the realm checkout. The cluster's identity comes from this realm's [`clusters/`](../clusters) files.

## Layout

- `keycloak/` — the SiliconSaga Keycloak realm import (`realm: siliconsaga`) plus the leidangr `openbao-cli` OIDC client + dev user, and the ESO delivery of `secret/leidangr/oidc`. Relocated here from nidavellir; the platform now ships only a generic Keycloak + OpenBao + ESO + the `sso-demo` sample.
- `forgejo/` — the `ForgejoInstance` claim: the two orgs (canonical `siliconsaga`, vendor `siliconsaga-vendor`), maintained repositories with their GitHub upstreams, vendor mirrors, break-glass admins. Inert until the cluster's identity says `maturity: durable`; the composition, its Jobs and the puller are nidavellir's (`docs/forgejo.md` there). No seeds: its credentials are born in-cluster and written to OpenBao create-only.

## Ordering

The realm root-app is a separate ArgoCD Application, so it is ordered by CRD-retry, not sync-waves: its `KeycloakRealmImport` / `ExternalSecret` retry until the platform's Keycloak-operator and ESO CRDs exist. The realm import's `${...}` placeholders stay unresolved until OpenBao holds `secret/leidangr/oidc`. On a fresh cluster nordri's bootstrap Layer 5b seeds that path with generated values from the realm's [`openbao-seeds`](../openbao-seeds) file (one line per path, then the key names; kept outside `cluster/` so ArgoCD never sees it), so the import runs without a human step. An existing path is never overwritten; rotation is an explicit `bao kv put`. The `ForgejoInstance` claim likewise retries until nidavellir's `XForgejo` XRD exists (sync-wave 11).

## Extending

Add realm-owned `ApplicationSet`s (or Applications) as resources in `kustomization.yaml` — e.g. tafl game-hosting, one ApplicationSet per wired game type, each pointing at that game's manifest repo, driven by realm config. This is where Tier-3/4 enablement lives; the platform stays generic.
