# Leiðangr Phase 2 — Backstage Skeleton + DevEx (first slice)

**Date:** 2026-06-21
**Status:** Draft (brainstormed, pending implementation plan)
**Scope:** The first concrete slice of Leiðangr Phase 2 — a fresh, modern Backstage instance with a strong DevEx envelope that runs **locally**, can boot with **zero secrets**, and can pull a real secret from **OpenBao** to authenticate a **Gitea** catalog source. Deployment, Keycloak SSO sign-in, GitHub, CI, custom plugins, and the realm #15 facility/calendaring/event-template modeling are explicitly out of this slice.
**Parent:** [`2026-06-09-leidangr-design.md`](2026-06-09-leidangr-design.md) (§6 Phase Roadmap — Phase 2; §7 Phase 1 prerequisites, now complete).
**Reference:** [`2026-06-09-backstage-devex-workspace-design.md`](2026-06-09-backstage-devex-workspace-design.md) (the DevEx envelope reference this slice draws from).

---

## 1. What This Slice Is

Phase 1 stood up OpenBao + ESO and Keycloak as reusable platform services (both deployed, SSO manually verified 2026-06-19). This slice begins Phase 2 by creating the Backstage control-plane as a SiliconSaga component — but deliberately as a **local-first skeleton**, not a deployed instance. The aim is a complete, testable inner-loop: clone the repo, run one command, get a working Backstage; run one more command to log into OpenBao and have a real Gitea-backed catalog appear.

The component is codenamed **`leidangr`** for now (the umbrella name, used as the working name for this first component; trivially renamed later). It lives at `components/leidangr/` as its own standalone git repo, registered in the realm/ecosystem only **after** it boots green.

### Done signals (the two checkpoints)

- **Checkpoint 1 — green stub boot:** `make dev` brings up Backstage on localhost with the generated example catalog, guest auth, and **zero secrets or external services required**.
- **Checkpoint 2 — OpenBao → Gitea loop:** with OpenBao unsealed, `make secrets && make dev` retrieves a Gitea token from OpenBao (via browser OIDC login), renders a gitignored `.env.local`, and Backstage ingests a few hand-authored entities from a Gitea repo authenticated by that token.

## 2. Component Shape

Generated with `@backstage/create-app@latest` on the **new frontend and backend systems** (defaults since v1.49.0) and **Yarn 4**. Standard Backstage monorepo (`packages/app`, `packages/backend`) wrapped in a thin **root platform envelope**: the generated app stays modern and upgradeable; platform conveniences (commands, scripts, docs, compose file) live at the root, not tangled into app code.

Root command envelope (`Makefile` — boring and explicit, one command per workflow, each prints which config files it loads and where secrets came from, never their values):

- `doctor` — checks Node/Corepack/Yarn, `bao` CLI, `kubectl` + a reachable context, and required ports.
- `deps` — `corepack enable` + `yarn install --immutable`.
- `secrets` — runs `scripts/dev-secrets` (see §3).
- `db` — starts the optional local Postgres (docker-compose); **not required** for the default path (see §4).
- `dev` — starts frontend + backend with the explicit local config stack.
- `test`, `lint`, `config-check` — Jest (unit + BDD), repo lint, `backstage-cli config:check`.

## 3. Secrets — OpenBao via a Provider-Agnostic Script

**Decision: the running Backstage never knows or cares which OpenBao (or whether one exists).** It consumes only environment variables (Backstage `$env`) rendered into a gitignored `.env.local`. All provider-specific behavior is isolated in `scripts/dev-secrets`, which is the **only** supported local retrieval path. This is Approach A from the brainstorm; Approaches B (ESO-projected k8s Secret) and C (app reads OpenBao at runtime) were rejected for local dev — B is the *deployed* path for a future slice, C couples the app to the secret store.

`scripts/dev-secrets` flow:

1. **Resolve the OpenBao target inside the script** — port-forward to whatever `kubectl` context is active (local k3s **or** GKE), or use a directly reachable URL. The target is the script's concern; the app is agnostic by construction, so the same Backstage runs unchanged against a homelab OpenBao, a GKE OpenBao, or none.
2. **Authenticate via browser OIDC** — `bao login -method=oidc` launches a browser, authenticates against Keycloak (the OIDC provider already running from Phase 1), and returns an OpenBao token. Default callback `http://localhost:8250/oidc/callback`. This reproduces the day-job Vault UX (run a command, log in in the browser, get a local secrets file) using infrastructure we already operate. No Consul / consul-template needed — Backstage's native `$env`/`$file` loaders replace runtime templating.
3. **Read this app's dev-scope KV path** from the shared, multi-consumer OpenBao — `secret/leidangr/dev`. OpenBao is central platform infrastructure used by many consumers; this script reads only the leidangr dev-scope keys.
4. **Validate required keys, then render** the gitignored `.env.local`, printing key *presence/status* but never values.

**Reachability — two paths, one script.** `bao login -method=oidc` needs the *browser* to reach Keycloak's authorize endpoint **and** the `bao` CLI (plus its localhost callback) to reach the **OpenBao API** — that is where both the login exchange and the KV read happen. So OpenBao itself, not only Keycloak, must be reachable by the developer's machine. For the cluster owner that is a **port-forward** (the skeleton's default). For a contributor without port-forward rights it must be a **direct URL** (`BAO_ADDR=https://openbao.<domain>`). `scripts/dev-secrets` supports both and selects by config — port-forward when it can, direct URL when told — so the same script and the same agnostic app serve both audiences.

**Non-secret** local overrides live in `app-config.local.yaml` (gitignored, with a committed `.example`); secrets never go there.

**Portability is a hard rule:** the `Makefile` and `scripts/dev-secrets` use only `kubectl`, `bao`, and standard tools, and live *inside* the Backstage repo. They run identically whether someone cloned just `leidangr` or is working in the GDD workspace. GDD's `ws` may *wrap* them (e.g. `ws run leidangr secrets`) but is never a dependency. There is no GKE dependency: local k3s OpenBao is a first-class target.

## 4. Local Development Modes

Three first-class modes, not a single linear path:

- **Stub / mock (default, zero secrets):** the create-app default **SQLite** dev database (so the first boot needs nothing external — important given uncertain Docker availability under Rancher Desktop over remote access), guest auth, generated example entities / mocked external data. This is what a standalone-repo developer with no cluster gets, what CI runs against, and what BDD scenarios exercise. "Accept the limitations" is a supported, deliberate mode.
- **Local-secrets:** `make secrets` → OpenBao-via-OIDC → `.env.local` → real Gitea integration. An optional `docker-compose` Postgres (`make db`) is provided as the prod-like database path but is not required.
- **Deployed (future slice):** in-cluster Backstage consuming ESO-projected Kubernetes Secrets — out of scope here, noted so the secret model stays forward-compatible.

### Contributor access (live/GKE phase — out of scope for this slice)

When Backstage development opens to external contributors on GKE, port-forward stops being viable — most contributors will not have `kubectl` port-forward rights into the cluster. The browser-OIDC model then *requires* OpenBao to be exposed at a contributor-reachable URL, since that is where both the OIDC login exchange and the KV read happen (exposing only Keycloak is insufficient). This is a normal OpenBao posture — the API, guarded by auth methods + ACL policies + audit, is the security boundary, not network isolation — but it is more sensitive than exposing Keycloak, so it is recorded here as a deliberate later decision with its security shape:

- **TLS** via the already-shipped `*.cmdbee.org` wildcard (an `openbao.cmdbee.org` ingress is cheap).
- **OIDC → Keycloak → policy:** a contributor Keycloak group maps to an OpenBao role/policy granting **read-only** access to `secret/leidangr/dev` and nothing else, with short-lived tokens.
- **Audit logging** enabled, rate limiting / WAF as appropriate.
- **Lower-exposure option:** expose OpenBao through the **already-running Tailscale operator** (contributors join the tailnet) instead of the public internet — defense-in-depth for a smaller trusted contributor set, upgradeable to fully public later.

This slice changes nothing here — it stays port-forward on the owner's own cluster — but the `dev-secrets` direct-URL branch is built now so the live transition is config-only, not a rewrite.

## 5. Catalog Source — Gitea

The skeleton's source of catalog entities is the **in-cluster Gitea** (healthy from Phase 1), not GitHub. This matches the intent ("entities could come out of Gitea"), keeps everything local, and makes the OpenBao secret naturally a Gitea access token. Backstage has full Gitea support — both static *Locations* and org *Discovery*. The skeleton uses **static `catalog.locations` (`type: url`)** pointing at a `catalog-info.yaml` in a small Gitea repo with 2–3 hand-authored entities; Gitea Discovery is a trivial later toggle. GitHub integration is deferred to a later slice.

## 6. Testing — BDD Outside-In over TDD'd Tooling

**Decision: BDD from day one.** Stand up a Gherkin runner (jest-cucumber, sharing the Backstage Jest toolchain) and express the two checkpoint done-signals as executable `.feature` files:

- A "green stub boot" scenario runnable in CI against stub mode.
- An "OpenBao secret flows and Gitea entities ingest" scenario. Because `bao login -method=oidc` is interactive and OpenBao may be sealed, the CI form of this scenario runs against **mocked** OpenBao KV responses and a **mocked/stub** Gitea source; a `@live` (or `@manual`) tag marks the real end-to-end variant for hands-on runs.

Beneath the BDD layer, the **envelope tooling is test-driven in TypeScript** (rather than untested bash): `scripts/dev-secrets` target-resolution, key-validation, and `.env.local` rendering, plus `doctor`'s checks, are authored as small TS modules with Jest unit tests (RED→GREEN→REFACTOR). `@backstage/backend-test-utils` (`startTestBackend`, supertest) is the standing pattern for any future backend plugin/module. `backstage-cli config:check` runs in CI across the local config combinations.

## 7. Architecture Decision Records

**Decision: capture ADRs as MADR files from decision #1; defer the ADR *plugin*.** Each architectural decision in this design (modern frontend/backend systems, SQLite-default dev DB, OpenBao-via-OIDC-script secrets, app-agnostic secret consumption, Gitea-as-source, guest-auth-first, BDD-from-day-one) is recorded as a MADR v3 file under `docs/adrs/` in the leidangr repo, starting immediately. The `@backstage-community/plugin-adr` plugin is **GitHub-only today** (GitLab is an open RFC; Gitea unsupported), so wiring it would force a GitHub ADR source and break this slice's Gitea-only cleanliness. The plugin is deferred to the later slice that introduces GitHub integration, at which point it renders the already-written ADRs in-app. The practice starts now; the plugin follows the source.

## 8. Checkpoint Detail

### Checkpoint 1 — green stub boot
- Scaffold fresh Backstage; confirm modern frontend/backend defaults and Yarn 4.
- Root `Makefile` envelope (`doctor`, `deps`, `db`, `dev`, `test`, `lint`, `config-check`).
- Config layering: `app-config.yaml`, `app-config.development.yaml`, `app-config.local.yaml.example` (+ gitignore the real one). `.nvmrc`/`.node-version`, `.env.example`, gitignores for `node_modules`/`dist`/bundles.
- SQLite dev DB; guest sign-in; generated example catalog.
- BDD: "green stub boot" `.feature` passing in CI. TDD: first envelope-tooling unit tests (`doctor`).
- **Acceptance:** `make dev` → Backstage on localhost, example entities, guest auth, no secrets.

### Checkpoint 2 — OpenBao → Gitea loop
- Setup (needs OpenBao unsealed): configure the OpenBao OIDC auth role against Keycloak with the correct `allowed_redirect_uris`; seed a Gitea read token into `secret/leidangr/dev`.
- `scripts/dev-secrets` (TS, unit-tested) + `make secrets`: resolve target → `bao login -method=oidc` → read KV → validate → render `.env.local`.
- Backstage `integrations.gitea` consumes the `$env` token; a static `catalog.locations` entry points at a Gitea repo holding 2–3 catalog entities.
- BDD: "secret flows + Gitea entities ingest" scenario green against mocks in CI; `@live` variant for the real loop.
- **Acceptance:** with OpenBao unsealed, `make secrets && make dev` → Backstage ingests the Gitea entities, authenticated by the OpenBao-sourced token.

## 9. Out of Scope (YAGNI for this slice)

Keycloak OIDC *sign-in to Backstage* (separate from OpenBao's OIDC auth, which we do use); GitHub integration; the ADR plugin; custom plugins (including the CycloneDX/BOM entity provider from `bom-architecture.md`); scorecards / Tech Insights; the realm #15 facility / league / calendaring / reservation / event-template modeling (Phase 3); TechDocs; CI/CD release pipeline; in-cluster deploy (ArgoCD / Helm / image registry).

## 10. Open Items — verify at plan time

- Exact OpenBao OIDC role + Keycloak client config and the full `allowed_redirect_uris` list (`http://localhost:8250/oidc/callback` and any UI callback).
- Mechanism + scope for seeding the Gitea token into OpenBao KV (which Gitea account/token scope; read-only).
- Node version pin (Active LTS) and Backstage version at scaffold time.
- jest-cucumber wiring into the create-app Jest config (or a parallel config) so `.feature` files run under `make test`.
- Where the 2–3 sample catalog entities live (a dedicated tiny Gitea repo vs. reuse of an existing one).
- Whether Rancher Desktop exposes a docker-compatible socket for the optional `make db` Postgres path (SQLite default sidesteps this).
- (Live phase, not this slice) Decide OpenBao contributor exposure — public `openbao.cmdbee.org` ingress vs Tailscale-only — and author the read-only contributor policy/role mapped from a Keycloak group.

## 11. References

- Parent design: [`2026-06-09-leidangr-design.md`](2026-06-09-leidangr-design.md)
- DevEx reference: [`2026-06-09-backstage-devex-workspace-design.md`](2026-06-09-backstage-devex-workspace-design.md)
- OpenBao JWT/OIDC auth method + Keycloak: https://openbao.org/docs/auth/jwt/ · https://openbao.org/docs/auth/jwt/oidc-providers/keycloak/
- Backstage Gitea integration (locations + discovery): https://backstage.io/docs/integrations/gitea/locations/ · https://backstage.io/docs/integrations/gitea/discovery/
- Backstage ADR plugin (GitHub-only; GitLab RFC #13675): https://www.npmjs.com/package/@backstage-community/plugin-adr
