# Realm-Owned Stack Config — Externalizing Realm/App Config Out of the Platform

**Status:** Design · **Date:** 2026-07-03 · **Tracks:** SiliconSaga/nidavellir#20 · **Related:** SiliconSaga/nordri#21 (hydration-dedup, deferred here), `bootstrap-vendor-mirror-hydration` (Idunn arc), realm#17 (scaffolder, non-goal)

## Context

The stack grew bottom-up: the platform (nidavellir, Tier 2) landed first, apps later, so realm- and app-specific config accreted inside the platform. Nidavellir currently hardcodes `realm: siliconsaga` and the Tier-3 leidangr OIDC wiring (`keycloak/realm-import.yaml`, `keycloak/oidc-realm-secrets.yaml`). A Tier-2 platform should be unaware of any specific realm or any Tier-3/4 construct; the standing direction (Loki thalamus preference, restated across the tafl-enablement notes) is that higher tiers reach *down* — the realm owns the stack and injects its config, the platform stays generic.

This design also folds in a load-bearing prerequisite. `nordri/bootstrap.sh` and `nordri/update-embedded-git.sh` copy-paste their hydration logic 3–4× over (the per-component orphan-hydration blocks, the app-of-apps overlay `sed`, and — after the env-awareness work — a per-target nidavellir patch block duplicated into both). CodeRabbit flagged the patch-block duplication on nordri#21; the decision was to defer it into a dedicated refactor. Adding a fifth hydration path (the realm) on top of that copy-paste would compound the mess, so the refactor is the foundation this work is built on — same PR, earlier commits.

A third thread converges here: Idunn's tafl-game-hosting enablement design independently arrived at "nidavellir ships nothing game-specific; the realm carries which apps are enabled and their manifest repos; ApplicationSet generators fan them out." Realm-owned keycloak config (this issue), realm-driven app enablement (tafl), and realm-driven vendor-mirror selection are three faces of one architecture. This design establishes the seam the others reuse.

## Goals

- A stack is "born with" an owning realm: `bootstrap.sh <target> [realm]` hydrates realm-provided config and wires ArgoCD to it.
- Realm/app-specific config (the `siliconsaga` realm import + leidangr OIDC client/user) lives in the realm, not the platform.
- Nidavellir ships only generic capabilities (Keycloak, OpenBao, ESO) plus the self-contained `sso-demo` sample, and references no realm, app, game, or Tier-3/4 construct.
- The realm owns both its config and the ArgoCD ApplicationSet(s)/Applications that fan that config out; nordri provides only generic wiring to whatever realm it was born with.
- A stack with no realm degrades gracefully to demo-only, not a broken state.
- The hydration logic is deduplicated into a sourced `lib/` shared by both entry-point scripts.

## Non-Goals

- **A general OpenBao-OIDC platform helper** (parameterizing leidangr's `configure-openbao-oidc.sh` into per-app mounts / shared-client-by-role). Named in nidavellir#20 as a possible split; likely drifts in later, but out of scope here.
- **The realm#17 app-of-apps *scaffolder*** (generating a starter tree from ecosystem config). Separate "is it worth building" decision.
- **Full DNS-hostnames-from-realm-config automation.** This design fixes the *ownership principle* for the CoreDNS rewrite (below) but leaves the concrete homelab `coredns-custom` manifest where it is; wiring hostnames from realm data is a thin follow-up.
- **The Forgejo-URL realm source.** Today the realm hydrates from a local checkout into the ephemeral seed-Gitea. When forgejo-day2 makes a persistent Forgejo the primary in-cluster source, the realm graduates to living there and the source swaps from "hydrate local checkout" to "point ArgoCD at the realm in Forgejo (a URL)." The realm-source is designed as a seam (below) so that swap is a substitution, not a rewrite — but building it is claimed for the forgejo-day2 arc.

## Current State

- **Tier violation:** `nidavellir/keycloak/realm-import.yaml` declares `realm: siliconsaga` with the leidangr `openbao-cli` client + `leidangr-dev` user; `nidavellir/keycloak/oidc-realm-secrets.yaml` is the ESO delivery of `secret/leidangr/oidc`. Both are realm/app-specific config sitting in the platform repo.
- **No realm→cluster path:** the realm (`realms/realm-siliconsaga/`) is workspace-tooling config today (ecosystem.yaml, adapters, docs). Nothing in it reaches the cluster. In-cluster GitOps is nidavellir's app-of-apps synced from the seed-Gitea.
- **Hydration duplication:** `bootstrap.sh` and `update-embedded-git.sh` each carry near-identical Gitea helpers (divergently named `create_gitea_repo` vs `ensure_gitea_repo`), per-component hydrate blocks (nidavellir/mimir/heimdall), the app-of-apps overlay `sed`, and the per-target nidavellir patch block. The vendor-mirror loop exists only in `update-embedded-git.sh` — a fresh `bootstrap.sh` cannot resolve the `keycloak-operator` tag pin, which is the `bootstrap-vendor-mirror-hydration` bug.
- **GitOps model (unchanged by this design):** ArgoCD lives in ns `argo` and syncs from the in-cluster seed-Gitea, hydrated from local checkouts by these scripts. Pushing to GitHub does not reach the cluster.

## Architecture

The tier line this design enforces:

- **nordri (Tier 1, substrate):** generic ArgoCD wiring. Given an owning realm, it hydrates the realm's `cluster/` subtree and registers a generic realm root-app pointing at it. It learns the realm's *name/URL*, never its content.
- **nidavellir (Tier 2, platform):** generic Keycloak, OpenBao, ESO, `sso-demo`. Knows nothing about any realm, app, or Tier-3/4 construct.
- **realm (realm-siliconsaga):** owns its config *and* the ApplicationSet(s)/Applications that fan it out to Tier-3/4. Keycloak realm-import now; tafl game-hosting ApplicationSets (one per wired game type, one repo each, per realm config) later — with zero platform change.

```text
realm cluster/ (realm-owned app-of-apps)
  ├─ keycloak/  → Application: realm-import + oidc-realm-secrets   [#20, now]
  └─ tafl/      → ApplicationSet per wired game type, one repo each [later, per realm config]
        │ hydrate (Commit 2)
        ▼
   seed-Gitea  <realm>  repo
        ▲ repoURL
        └── ArgoCD "realm root-app"  ← bootstrap generates + registers, templated from the
            realm arg (nordri/substrate wiring). No realm arg → not registered.
            nidavellir NEVER references the realm.
```

## Design

### Commit 1 — Hydration refactor foundation (nordri#21 dedup)

Extract the copy-pasted hydration logic into a sourced `nordri/lib/`, consumed by both `bootstrap.sh` and `update-embedded-git.sh`. No behavior change — this commit is a pure dedup, validated by confirming the hydrated seed output is byte-identical before/after.

- `lib/gitea.sh` — unify the Gitea plumbing: one `ensure_gitea_repo` (201/409-as-success + retry), `urlencode`, `probe_gitea`, and the URL-base builders. Resolves the `create_gitea_repo`/`ensure_gitea_repo` naming divergence.
- `lib/hydrate.sh` — a `hydrate_working_tree_repo <src_dir> <gitea_repo> [patch_fn]` helper (copy checkout → strip `.git` → `git init`/commit → force-push to seed, with an optional per-tree patch hook), the nordri-platform hydration variant (platform copy + envs + overlay `sed` + root-app), and the vendor-mirror loop (`hydrate_vendor_mirrors <list>`).
- `lib/patch-nidavellir.sh` — the per-target nidavellir patch (vegvisir overlay path + tailscale-operator hostname), guard + post-`sed` verification intact. This is the block CodeRabbit named.

**Bonus outcome:** `bootstrap.sh` calls `hydrate_vendor_mirrors` too, closing the `bootstrap-vendor-mirror-hydration` gap for free (a fresh bootstrap becomes reproducible without the manual `update-embedded-git.sh` step). This design assumes `keycloak-k8s-resources` is cloned/declared; if absent the loop warn-skips as it does today.

### Commit 2 — Realm as a hydrated source

Add the owning-realm input to both entry points: `bootstrap.sh <target> [realm]` and `update-embedded-git.sh <target> [realm]`. The realm directory resolves as: explicit `REALM_DIR` env override → the workspace `realms/<realm>/` relative to the nordri checkout → error if named-but-unresolvable. Omitting the realm arg skips realm hydration entirely (demo-only path).

When a realm resolves, hydrate its `cluster/` subtree into a seed-Gitea repo whose name matches the realm arg / directory name (written `<realm>` throughout; `realm-siliconsaga` for this realm) via `hydrate_working_tree_repo`. Only the `cluster/` subtree is hydrated — the realm's workspace-tooling config (ecosystem.yaml, adapters, docs) never reaches the cluster.

### Commit 3 — Move the config

Relocate `nidavellir/keycloak/realm-import.yaml` and `nidavellir/keycloak/oidc-realm-secrets.yaml` into `realms/realm-siliconsaga/cluster/keycloak/`. Nidavellir's `keycloak/` retains only the generic operator + instance + generic supporting resources; nidavellir keeps generic Keycloak, OpenBao, ESO, and the `sso-demo` sample. The moved manifests are unchanged in content (they already use the born-in-OpenBao → ESO → `${...}` placeholder pattern); only their home changes.

### Commit 4 — Injection seam (realm-owned)

The realm owns its app-of-apps. `realms/realm-siliconsaga/cluster/` carries a realm-owned app-of-apps (a `kustomization.yaml` plus Application/ApplicationSet manifests) that fans out realm resources. For #20 that is `cluster/keycloak/` producing the realm-import + oidc-realm-secrets Application. Future Tier-3/4 enablement (tafl game-hosting) is added here as realm-owned ApplicationSet(s) — one per wired game type, its own manifest repo, driven by realm config — needing no platform change.

nordri does the generic wiring. Given `[realm]`, bootstrap generates and applies a generic ArgoCD **realm root-app** Application whose `repoURL` is the hydrated `<realm>` seed-Gitea repo and whose path is `cluster/`. nordri templates this from the realm arg at hydrate time (as it already applies `nordri/root-app.yaml`); it commits no realm-named file, so the substrate tree stays realm-agnostic. No realm arg → no realm root-app.

**Ordering:** the realm root-app and the Applications it fans out sync after nidavellir's generic Keycloak + ESO are Healthy (ArgoCD sync-wave), so the relocated realm-import's ESO `${...}` placeholders resolve against a running platform. Until the OpenBao path that backs `secret/leidangr/oidc` is seeded, the import waits on unresolved placeholders — the same designed resting state as today.

## Sub-Decisions

- **CoreDNS rewrite ownership.** The moved OIDC client only works in-cluster because a `keycloak.localhost` → Traefik CoreDNS rewrite lets the OpenBao pod resolve, server-side, the same issuer the browser uses. Principle: the **hostname is realm data**, the **rewrite mechanism is platform/substrate (nordri)**. First cut states the principle and leaves the existing homelab `coredns-custom` manifest in nordri; deriving the rewrite hostnames from realm config is a thin follow-up. On Docker Desktop the mechanism differs (no `coredns-custom` drop-in — the main Corefile must be edited), which is a bootstrap-time substrate concern handled where the DNS plumbing lives, not in the realm.
- **Degrade path.** No realm → nidavellir's generic platform + `sso-demo` is the self-contained proof; no realm root-app is registered. This is the "designed resting state" the realm-import comments already describe.
- **Naming.** Realm in-cluster config subtree: `cluster/`. Seed-Gitea repo: `<realm>` (the realm arg / directory name, e.g. `realm-siliconsaga` — no extra prefix). Realm root-app path: `cluster/`. These are conventions, revisable in the plan.
- **Realm-source seam.** Hydration is the current implementation behind a stable boundary (`hydrate the realm's cluster/` → `register a root-app at its repoURL`). The forgejo-day2 swap replaces the *source* of that repoURL (seed-Gitea → persistent Forgejo) without touching the realm's `cluster/` layout or the ApplicationSet contract.

## Testing

- **`lib/` refactor:** `shellcheck` + `bash -n` on both scripts and the lib files; an isolated function test that runs the hydrate/patch helpers against a fake tree carrying the placeholder strings (per Idunn's note) and asserts the substitutions/verifications fire; a before/after diff of the hydrated seed content to prove no behavior change.
- **Injection:** `kubectl kustomize` / `kustomize build` on the realm `cluster/` app-of-apps and the relocated keycloak manifests; render-validate that the realm root-app points at `<realm>` `cluster/`.
- **Degrade:** bootstrap with no realm arg still produces a green platform + `sso-demo` (the no-realm regression proof).
- **End-to-end (bootstrap-time, gated on a working cluster):** a realm-carrying bootstrap brings up generic Keycloak, then the realm root-app fans out the realm-import; the sso-demo path stays the no-realm baseline.

## Open Questions / Risks

- **Substrate (this machine):** Docker Desktop Kubernetes is a fourth flavor vs Loki (Rancher/k3s) and Idunn (Orbstack/k3s). The homelab overlay assumes k3s-isms (Longhorn/Garage need `iscsid`; `coredns-custom`; single-node layout). Bootstrap validation targets Docker Desktop until it breaks too hard; Rancher Desktop is the sanctioned fallback.
- **Helm 4:** this machine installed Helm v4.2.2 while the stack was built against Helm 3 — a possible bootstrap-time compatibility gotcha to watch.
- **Realm-dir resolution when nordri runs standalone:** bootstrap is designed to run from the nordri checkout without the full workspace. The `REALM_DIR` override covers that; the workspace-relative default covers the common case.

## Follow-Ups Discovered During Implementation

- **Realm config testing (needs its own design pass).** Externalizing the realm import surfaced a coverage gap: the nidavellir e2e `tests/e2e/keycloak/01-oidc.yaml` asserted the `siliconsaga` realm landed. Because that config is no longer in nidavellir, the test was retargeted to Keycloak's built-in `master` realm so the *platform* e2e stays generic (proves Keycloak serves OIDC discovery, no realm coupling). The realm-specific assertion now has no home — realms have no test harness today (`realms/*/adapters/` wire *component* build/lint, not `cluster/` config). Designing one is a small arc of its own. Shape it as two tiers: (1) **offline/contract** — `kubectl kustomize cluster/` builds + schema-validates (cheap, CI-able, no cluster; already the manual check used here); (2) **live/e2e** — after a realm-carrying bootstrap, assert the realm root-app syncs, the `KeycloakRealmImport` reports `Done=True`, `/realms/siliconsaga/.well-known/openid-configuration` serves, and the `openbao-cli` client + `leidangr-dev` user exist. Open design questions: where a realm test harness lives and what runs it (kuttl needs a live cluster + the platform up — a cross-tier test dependency the component model doesn't express today); how a realm test declares "depends on platform Keycloak/ESO/OpenBao being up"; and how to handle the ESO-placeholder resting state (the import waits until OpenBao seeds `secret/leidangr/oidc`, so a test must seed it or assert the waiting state). Until built, coverage is the offline `kubectl kustomize cluster/` check plus the generic nidavellir master-realm probe.
- **CoreDNS hostnames from realm config.** Sub-decision above sets the principle (mechanism = nordri/substrate, hostname = realm data); wiring the rewrite hostname list from realm config (so the realm declares `keycloak.localhost` rather than nordri carrying it) is a thin follow-up not built here. On Docker Desktop the mechanism differs (no `coredns-custom` drop-in — the main Corefile must be edited), a substrate concern for the eventual bootstrap.

## References

- SiliconSaga/nidavellir#20 (this issue), SiliconSaga/nordri#21 (hydration-dedup, deferred here).
- `nordri/bootstrap.sh`, `nordri/update-embedded-git.sh` (hydration entry points), `nordri/docs/bootstrap.md` (layer sequence).
- `nidavellir/keycloak/realm-import.yaml`, `nidavellir/keycloak/oidc-realm-secrets.yaml` (config that moves), `nidavellir/demos/sso` (the sample pattern reused as the no-realm proof).
- Idunn thalamus arcs: `bootstrap-vendor-mirror-hydration`, `homelab-cluster-env-awareness`, and the tafl-game-hosting enablement architecture note (the ApplicationSet + realm-config convergence).
- `realms/realm-siliconsaga/docs/stack-tier-1.md`, `stack-tier-2.md`, `stack-tier-3.md` (tier narrative).
