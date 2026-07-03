# Realm-Owned In-Cluster Config (`cluster/`)

This subtree holds the SiliconSaga realm's own in-cluster GitOps config — the config that must NOT live in the platform (nidavellir), per the tier boundary (nidavellir#20).

## How it reaches the cluster

`nordri/bootstrap.sh <target> realm-siliconsaga` hydrates this `cluster/` subtree into the in-cluster seed-Gitea as a repo named `realm-siliconsaga` (its contents at the repo root), then registers a generic ArgoCD **realm root-app** pointed at it. nordri learns only the realm's name — never its content. Day-2 changes: `nordri/update-embedded-git.sh <target> realm-siliconsaga` re-hydrates this subtree. Without the realm arg, none of this happens and the stack is generic/demo-only.

## Layout

- `keycloak/` — the SiliconSaga Keycloak realm import (`realm: siliconsaga`) plus the leidangr `openbao-cli` OIDC client + dev user, and the ESO delivery of `secret/leidangr/oidc`. Relocated here from nidavellir; the platform now ships only a generic Keycloak + OpenBao + ESO + the `sso-demo` sample.

## Ordering

The realm root-app is a separate ArgoCD Application, so it is ordered by CRD-retry, not sync-waves: its `KeycloakRealmImport` / `ExternalSecret` retry until the platform's Keycloak-operator and ESO CRDs exist. The realm import's `${...}` placeholders stay unresolved until OpenBao seeds `secret/leidangr/oidc` — the designed resting state.

## Extending

Add realm-owned `ApplicationSet`s (or Applications) as resources in `kustomization.yaml` — e.g. tafl game-hosting, one ApplicationSet per wired game type, each pointing at that game's manifest repo, driven by realm config. This is where Tier-3/4 enablement lives; the platform stays generic.
