# Backstage DevEx Workspace Design

Status: design reference
Date: 2026-06-09
Provenance: this design was extracted from a mature Backstage sample app, companion docs, and current public Backstage documentation; company-specific names and repository identifiers are intentionally omitted from this reference.

## Purpose

This document is a reference design for turning a newly generated Backstage instance into a better developer workspace. It is not intended to be applied verbatim to an empty project. The goal is to give a fresh agent enough context to recognize what a strong Backstage workspace looks like, what to copy from the mature sample, what to avoid because it is dated or company-specific, and what to improve for a GitHub + Keycloak + Grafana/Loki/Prometheus environment.

The target reader is an agent or platform engineer starting from `npx @backstage/create-app@latest`, then adding a pragmatic baseline for local development, plugin work, secrets, testing, build/release automation, and a small set of useful plugins.

## Assumptions

- Source control is GitHub.
- SSO is Keycloak via generic OIDC.
- Observability is Grafana, Loki, and Prometheus, not Rootly.
- The instance should support both normal Backstage customization and custom plugin development.
- Commercial Spotify plugins such as Soundcheck and Skill Exchange are inspirational but unavailable.
- A mature Backstage sample informed this design, but the resulting recommendations are intended to stand alone without access to that sample.
- Prefer OpenBao or another open-source secret manager over newly adopting HashiCorp-branded products where practical.

## Current Upstream Context

Backstage has moved materially since many older mature instances were built. Current docs show stable Backstage at v1.51.0 in June 2026, and GitHub reports v1.51.0 as the latest release on 2026-05-19. New projects should assume the modern backend and frontend systems rather than copying legacy patterns.

The important upstream shifts are:

- The new backend system is the production-ready default direction. Backend features are built from backend instances, plugins, modules, services, and extension points. New backend plugins and modules should use the backend system APIs and `@backstage/backend-test-utils`.
- The new frontend system became the default for newly created Backstage apps in v1.49.0. Avoid starting with a legacy frontend or a hybrid compatibility bridge unless there is a specific plugin blocker.
- New Backstage repositories created with `@backstage/create-app` use Yarn 4 by default as of v1.31.0.
- Static configuration uses layered files: `app-config.yaml`, `app-config.<BACKSTAGE_ENV>.yaml`, `app-config.local.yaml`, and `app-config.<BACKSTAGE_ENV>.local.yaml`, plus explicit `--config` flags when needed. Config supports `$env` and `$file`, can be validated with `backstage-cli config:check`, and plugin authors should provide schemas with appropriate `frontend`, `backend`, or `secret` visibility.
- GitHub catalog discovery via `@backstage/plugin-catalog-backend-module-github` is the preferred way to ingest entities from GitHub organizations or GitHub Apps, but schedules and GitHub App authentication matter because API rate limits are easy to hit.
- Backstage's Plugin Directory marks plugins inactive if they have not been updated on NPM in more than 365 days. Treat the directory as a discovery source, not as a guarantee of support.

## What the Mature Sample Does Well

The strongest parts of the sample are not the company-specific integrations, but the working habits around them:

- **A root wrapper around the generated app.** The repository has a root `Makefile`, operational docs, CI, deployment/IaC material, and a nested `source/` Backstage app. That separation makes it clear which files are Backstage app code and which files operate the platform.
- **Local dev has a real path.** The docs describe Node versioning, Python/MkDocs tooling, pre-commit hooks, Docker Compose Postgres, secret-store login, env generation, source-based dev mode, Docker mode, debug mode, and remote port forwarding.
- **Configuration layering is documented.** The sample treats local overrides, local catalog population, and deployment overlays as normal developer workflows rather than tribal knowledge.
- **Secrets are centralized.** The sample docs describe adding secret-store paths, local developer secrets, deployment secrets, and environment-variable wiring. The approach is too enterprise-specific to copy directly, but the lifecycle thinking is good.
- **Integration seams are backend modules.** The sample uses backend modules to add catalog processors, entity providers, custom scaffolder actions, and filters. This is the right shape for a growing instance.
- **Multi-tenant plugin configuration is called out.** The sample captures a useful rule: prefer `instances:` style config when a tool may have multiple accounts or installations. That lesson transfers directly to GitHub, Jenkins, Prometheus, Grafana, Argo CD, and similar integrations.
- **The homegrown health-check system is a useful poor man's Soundcheck.** The companion docs describe `Block` entities (a set of "checks"), check modules, filters, optional enrollment, scheduled evaluation, retention, history, grids/levels, and tests. The design is a strong model for a custom scorecard system when Soundcheck is not available.
- **Template validation exists.** The sample validates important scaffolder templates on a schedule with explicit inputs, cleanup expectations, and owner notifications. This is exactly the kind of DevEx feature that keeps templates from rotting.
- **The CI documentation is unusually useful.** The sample explains pipeline triggers, change-based skipping, post-merge scans, release/deploy gates, and which failures block deployment. A GitHub Actions version of this should exist in the new instance.

The transferable details from the mature sample are summarized in [Appendix: Extracted Sample Patterns](#appendix-extracted-sample-patterns). A future agent should not need the original sample repository to understand the intended patterns.

## What Not to Copy Blindly

The sample also shows debt that a fresh project should avoid:

- **Do not commit generated build outputs or dependencies.** The local checkout contains `node_modules`, `dist`, and backend bundle outputs under the Backstage source tree. A fresh project should keep those ignored and reproducible.
- **Do not require broad secrets just to boot.** Local development should degrade gracefully when optional integrations are missing. Missing Grafana, Jenkins, Sentry, or external API credentials should disable a card/module or show a clear local stub, not break entity pages.
- **Do not let `app-config.yaml` become the integration junk drawer.** The sample has many proxy endpoints and credentials in one file. A fresh instance should split environment overlays and keep per-plugin config schemas strict.
- **Avoid casual `dangerously-allow-unauthenticated` proxy routes.** The sample uses this where upstream bearer tokens are passed through. In a fresh instance, every proxy route should have a short threat-model note, narrow methods, narrow headers, and an owner.
- **Avoid a permanent hybrid frontend.** The sample is in hybrid mode because existing plugins still need migration. New projects should start on the new frontend system and only add compatibility shims when a chosen plugin forces it.
- **Avoid custom one-off plugin sprawl.** Custom plugins are normal in Backstage, but each plugin should have an owner, package boundary, config schema, test harness, and deprecation path. A pile of internal packages with no ownership becomes the real product.
- **Avoid copying non-GitHub CI and auth assumptions.** Translate the intent to GitHub Actions, GitHub Apps, OIDC, and repository environments rather than translating every job mechanically.

## Recommended Approach

Use a fresh Backstage app as the base, then apply a curated DevEx overlay. Do not transplant the mature instance.

Three approaches were considered:

| Approach | Shape | Pros | Cons | Recommendation |
|---|---|---|---|---|
| Copy the mature repo | Start from the sample, delete company-specific pieces, then adapt | Lots of working examples | Carries stale dependencies, hidden coupling, legacy CI, single-vendor secret-manager assumptions, company assumptions, and too many plugins | Avoid |
| Fresh app plus curated overlay | Generate current Backstage, add wrapper scripts, secrets tooling, tests, plugin baseline, docs | Starts modern, keeps lessons, easier upgrades | Requires design effort to rebuild conveniences | Recommended |
| Minimal app, add only when needed | Start with core catalog/templates/docs and defer all DevEx | Fast first boot | Agents and humans will rediscover basic tooling gaps repeatedly | Too thin |

The recommended path is the second: keep the generated app modern, then build a small platform envelope around it.

## Workspace Shape

Use the standard Backstage monorepo shape, with a thin root-level platform envelope:

```text
backstage-portal/
  README.md
  package.json
  yarn.lock
  .yarnrc.yml
  .nvmrc or .node-version
  .env.example
  app-config.yaml
  app-config.development.yaml
  app-config.production.yaml
  app-config.local.yaml.example
  docker-compose.yaml
  Makefile or justfile
  docs/
    development/
    operations/
    plugins/
    decisions/
  packages/
    app/
    backend/
  plugins/
    <custom-plugin>/
    <custom-plugin>-backend/
    <custom-plugin>-node/
  scripts/
    dev-env
    dev-secrets
    doctor
```

The root wrapper should be boring and explicit. Provide commands such as:

- `make doctor` or `just doctor` - checks Node, Corepack/Yarn, Docker, OpenBao/1Password/Infisical/cloud secret manager CLI if used, GitHub auth, and required ports.
- `make deps` - runs `corepack enable` and `yarn install --immutable`.
- `make secrets` - retrieves or renders local secrets into a gitignored file or shell environment.
- `make db` - starts local Postgres.
- `make dev` - starts frontend and backend with the local config stack.
- `make test`, `make lint`, `make typecheck`, `make config-check`, `make e2e`.

Prefer one command per workflow over a clever shell script. The command should print what config files it is using and where secrets came from, without printing secret values.

## Local Development

The local path should be one page and one command after prerequisites:

1. Install Node Active LTS and enable Corepack.
2. Authenticate to the secret source.
3. Run `make doctor`.
4. Run `make dev`.

Use Docker Compose for local dependencies:

- Postgres for the Backstage database.
- Optional Keycloak container for a fully local SSO loop, with an imported realm/client fixture.
- Optional Prometheus/Grafana/Loki fixtures only if plugin development needs them. Do not make the full observability stack mandatory for normal Backstage work.

Keep `app-config.local.yaml` for human overrides and provide `app-config.local.yaml.example`. Use `BACKSTAGE_ENV=development` for repeatable local overlays, and run Backstage with explicit `--config` flags in scripts so it is obvious which files are loaded.

Local development should have integration modes:

- **Stub mode:** no external tokens required; optional plugins disabled or pointed at fake data.
- **Personal token mode:** developer-provided tokens for GitHub, Grafana, Jenkins, etc.
- **Shared dev mode:** read-only service credentials pulled from the secret store.

The default should be stub or shared read-only mode, not personal-token mode.

## Secrets and Configuration

The sample's secret-store + template-rendering flow proves the value of automatic local secrets, but the fresh design should make it less fragile and less tied to one vendor.

Recommended design:

- Store non-secret defaults in versioned `app-config.*.yaml` files.
- Store secrets in a real secret manager: OpenBao, 1Password, Infisical, Doppler, or a cloud secret manager. If a Vault-compatible workflow is desirable, prefer OpenBao as the open-source-first candidate unless there is a deliberate reason to accept HashiCorp's Business Source License posture.
- Treat OpenBao as a preferred candidate, not an untested assumption. Official OpenBao docs describe it as an open-source, community-driven fork managed under Linux Foundation OpenSSF; its library docs say it intends to remain Vault API compatible, while the API docs still warn that full backwards compatibility is not yet promised. Pin a version, test the exact auth method and KV/API paths used by `scripts/dev-secrets`, and keep provider-specific calls behind that script.
- Provide `scripts/dev-secrets` as the only supported local retrieval path. It should authenticate, fetch only development-scope values, validate required keys, and write a gitignored `.env.local` or shell-export file.
- Keep the Backstage app secret-store-agnostic. `scripts/dev-secrets` may call `bao`, `op`, `infisical`, a cloud CLI, or another provider, but application config should consume only environment variables or files.
- Generate `.env.local` from `.env.example` plus secret metadata, not from an opaque template that overwrites human additions. If humans need personal overrides, reserve `.env.personal` or `app-config.local.yaml`.
- Prefer Backstage config `$env` and `$file` support over ad hoc `source env.simple` flows.
- Every custom plugin with config must ship a `config.d.ts` or JSON schema. Secret fields should use Backstage's `secret` visibility. Run `backstage-cli config:check` in CI with all relevant config files.
- Missing optional secrets should disable optional plugins cleanly. The backend should log `Plugin X disabled: missing <config key>` once at startup.
- For production, use GitHub Actions OIDC to fetch deployment secrets from the chosen secret manager or cloud platform. Avoid long-lived repository secrets where OIDC is viable.

For Keycloak SSO, use Backstage's generic OIDC provider and brand it as Keycloak. The Backstage OIDC docs explicitly call out Keycloak as the example implementation and require installing `@backstage/plugin-auth-backend-module-oidc-provider`, configuring the provider in `app-config.yaml`, defining a sign-in resolver, and wiring the frontend sign-in page. Keep GitHub auth separate as a delegated provider for GitHub APIs if plugins need user-scoped GitHub access.

## GitHub Integration

Use GitHub Apps for platform-level integration wherever possible:

- Catalog discovery: `@backstage/plugin-catalog-backend-module-github`.
- Scaffolder publishing and PR actions: `@backstage/plugin-scaffolder-backend-module-github`.
- Events/webhooks: `@backstage/plugin-events-backend` and `@backstage/plugin-events-backend-module-github`.
- CI visibility: `@backstage-community/plugin-github-actions`.

Catalog ingestion should use provider IDs per organization or app installation, with schedules tuned for rate limits. The GitHub discovery docs warn that automatic discovery can hit rate limits; prefer GitHub Apps for higher limits and lower token blast radius.

Entity annotations should be documented early. At minimum, standardize:

```yaml
metadata:
  annotations:
    github.com/project-slug: owner/repository
    backstage.io/source-location: url:https://github.com/owner/repository
    backstage.io/techdocs-ref: dir:.
spec:
  owner: group:default/team-name
  lifecycle: production
  system: system-name
```

Add schema validation for `catalog-info.yaml` in VS Code and CI. Maintain a standalone annotation reference for GitHub, Grafana, Prometheus, TechDocs, Kubernetes, scorecards, and any custom plugins.

## Testing Strategy

The testing baseline should cover the parts of Backstage that most often rot:

- **Config tests:** `yarn backstage-cli config:check --config app-config.yaml --config app-config.development.yaml` and equivalent production/staging checks.
- **Type/lint/build:** `yarn tsc`, `yarn backstage-cli repo lint`, `yarn backstage-cli repo build --all`.
- **Backend plugin/module tests:** use `@backstage/backend-test-utils`, `startTestBackend`, and `supertest` for backend routes and modules.
- **Frontend plugin tests:** React Testing Library for entity cards and route-level rendering.
- **Scaffolder action tests:** test custom action handlers directly, including validation, dry-run behavior, and failure cleanup.
- **Template dry-run tests:** use Backstage's Template Editor and dry-run support for authoring, plus automated fixtures in CI for templates that must stay working.
- **E2E smoke tests:** Playwright against a local backend with stubbed external services. Keep these few and high-value.
- **Plugin contract fixtures:** for each custom integration, keep sample catalog entities and mocked API responses so a plugin can be exercised without real external systems.

Adopt the template-validation pattern in [Appendix: Extracted Sample Patterns](#appendix-extracted-sample-patterns), but tune it for GitHub: scheduled CI or a Backstage backend task should dry-run critical templates with known inputs, verify expected files/actions, and alert owners when templates fail. For templates that create real resources, require explicit cleanup metadata or a teardown action.

## Build, Release, and Upgrade Tooling

Use GitHub Actions with fast PR feedback and slower post-merge checks:

- PR: install, config check, lint, typecheck, unit tests, targeted build, and focused e2e smoke.
- Main: full build, image build, vulnerability/dependency scanning, TechDocs build, and optional scorecard/template validation.
- Release: publish container to GHCR or the chosen registry, deploy via Helm/GitOps, record release notes, and run a post-deploy smoke check.

Use Renovate or Dependabot, but treat Backstage upgrades as a managed workflow rather than arbitrary package bumps. Backstage moves quickly and frequently includes framework migrations. A practical cadence is monthly patch/minor review with a quarterly larger migration window if the instance has many plugins. Each upgrade should run `backstage-cli versions:bump`, any applicable migration helpers, config checks, and plugin smoke tests.

The release doc should explain when jobs run, why they run, what skips on documentation-only changes, what is post-merge-only, what is non-blocking, and what blocks deployment.

## Plugin Architecture Guidelines

New custom work should follow these rules:

- Use the new backend system from the start.
- Keep backend plugin implementation in `plugins/<id>-backend`.
- Put extension points and shared backend utilities in `plugins/<id>-node` when other modules need to extend the plugin.
- Put frontend plugin code in `plugins/<id>` or `plugins/<id>-react` depending on whether it exports a page/plugin or reusable components.
- Use backend modules to extend core plugins such as catalog and scaffolder. Do not keep adding everything to `packages/backend/src/index.ts`.
- Every plugin gets an owner, README, config schema, fixture catalog entities, tests, and an "available when" predicate for entity pages.
- Prefer multi-tenant config objects over single global tokens. Treat `instances:` style config as the default whenever a plugin may connect to multiple accounts, installations, teams, environments, or providers.
- External integrations should have explicit health checks and clear disabled states.

## Scorecards and Poor Man's Soundcheck

Do not try to clone Soundcheck wholesale. The useful concepts to copy are checks, grouped initiatives, levels/certification, history, and leadership/team rollups.

Recommended starting point:

- Install and evaluate the open-source `@backstage-community/plugin-tech-insights` stack first. It already models facts, checks, scorecards, fact retrievers, historical data, and JSON rules.
- If Tech Insights fits, build custom fact retrievers for GitHub repository hygiene, TechDocs presence, workflow health, Kubernetes ownership labels, Prometheus alert coverage, and dependency/security status.
- If Tech Insights is too constrained, build a custom health-check plugin modeled on the sample's `Block` and `Grid` system: catalog-defined check groups, filters, enrollment annotations, scheduled execution, result retention, and entity/team pages.
- Avoid treating scorecards as punishment. Start with advisory levels, clear remediation links, and visible owners. Add hard gates only for narrow production-readiness checks with strong consensus.

A Block/Grid-style health-check system has particularly good ideas to preserve:

- Catalog-defined `Block` entities keep scorecard definitions out of code.
- Enrollment prevents broad checks from surprising every catalog entity.
- Scheduled execution makes pages fast and preserves history.
- Retention avoids unbounded data growth.
- Grids/levels give a readable maturity model.
- Tests live alongside check modules and validate success, failure, and misconfiguration paths.

Suggested first tracks:

- **Catalog Hygiene:** owner, system, lifecycle, description, source location, TechDocs ref.
- **GitHub Hygiene:** branch protection, CODEOWNERS, required reviews, Dependabot/Renovate enabled, recent default-branch CI success.
- **Operational Basics:** Pager/owner link if used, Grafana dashboard link, Prometheus alert annotation, runbook/TechDocs present.
- **Production Readiness:** Kubernetes annotations present when deployed, SLO or alert coverage, deployment history visible, last release within expected freshness window.

## Plugin Recommendations

Treat this list as a starting shortlist, not as a package manifest. Check current package activity, compatibility with the new frontend/backend systems, and auth model before installing.

| Area | Recommendation | Notes |
|---|---|---|
| Core | Software Catalog, Software Templates, TechDocs, Search, Kubernetes, Home, Permission, Notifications | These are foundational. Start with catalog/templates/docs before adding specialty plugins. |
| GitHub | GitHub catalog backend module, GitHub scaffolder backend module, GitHub Actions plugin, GitHub Pull Requests plugin | GitHub Actions plugin is actively maintained in `@backstage-community` and surfaces workflow status, details, logs, and retry where permissions allow. |
| Keycloak | OIDC auth provider plus Keycloak catalog/org provider if needed | Use OIDC for sign-in. Use Keycloak org/catalog sync only if Keycloak is the source of users/groups; otherwise sync org data from GitHub or another IdP source. |
| Observability | Kubernetes, Prometheus, Grafana | Prometheus plugin is a good fit for alerts/metrics cards. Grafana plugin is useful for dashboard links/embeds, but its package appears older than Prometheus; verify maintenance before committing. |
| GitOps/deployments | Argo CD if you use GitOps | Not in the stated stack, but commonly valuable if deployment state is managed by Argo CD. |
| Scorecards | Tech Insights, custom health-check plugin, possibly System scoring | Tech Insights is the closest OSS Soundcheck substitute. A Block/Grid-style model from the sample is a strong custom alternative. |
| Security | Security Insights, Snyk/FOSSA/DependencyTrack depending on your tools | Pick based on the actual scanner you use; avoid duplicating security portals unless Backstage adds context. |
| CI/CD legacy | Jenkins plugin | The Jenkins plugin has improved: community package, new backend support, multi-project support, scaffolder actions, and recent releases. It still has project-type limitations, so use it only if Jenkins remains important. For a GitHub-first instance, prefer GitHub Actions. |
| InnerSource/community | Synergy, Playlist, Q&A, Entity Feedback | Synergy is aimed at inner-source projects/issues/maintainers. Playlist helps curated collections. Q&A and Entity Feedback can support community knowledge loops. Verify maintenance and UX before broad rollout. |
| Learning/volunteering | Custom "Skill Exchange Lite" plugin or catalog entity model | There is no obvious OSS replacement for Spotify Skill Exchange. Model opportunities as catalog entities or a small plugin: request help, offer mentorship, track temporary project needs, and link to GitHub issues/projects. |
| Resource/time tracking | TimeSaver, DORA metrics plugins, OpenCost/Infracost | Use TimeSaver only if you actively measure scaffolder value. Use DORA/cost plugins only when teams will act on the data. |

Plugin due diligence checklist:

- Is it active in the Backstage Plugin Directory or recently published on NPM?
- Does it support the new backend and frontend systems?
- Does it require browser-side OAuth, backend service tokens, or both?
- Does it support multiple instances/accounts?
- Does it have entity availability predicates so empty tabs do not appear?
- Can it be tested locally with fixtures or mocks?
- Who owns support after installation?

## Community and Skill Exchange Lite

Spotify Skill Exchange is commercial, but the idea is straightforward enough to pilot in open source Backstage:

- Define an `Opportunity` catalog kind or a custom plugin data model with fields for type, owner, skills offered/needed, time window, expected commitment, GitHub issue/project link, and status.
- Support types such as `mentoring`, `pairing`, `temporary-help`, `hack-project`, `plugin-maintainer-needed`, and `reviewer-needed`.
- Render opportunities on team pages and user pages.
- Integrate with GitHub Issues or Projects for the actual work queue instead of building a full task tracker.
- Add lightweight notifications through Backstage Notifications, chat, or email later.

This should be a second-phase plugin, not part of the first bootstrap. Start with GitHub issue labels and a Backstage page/card that indexes them.

## Documentation Set

Create docs early. The mature sample proves that operational docs are part of the product.

Recommended files:

```text
docs/
  README.md
  development/
    setup.md
    local-config.md
    secrets.md
    plugin-development.md
    template-development.md
    testing.md
    debugging.md
  operations/
    ci-cd.md
    deployment.md
    upgrades.md
    observability.md
    incident-response.md
  reference/
    catalog-info.md
    annotations.md
    plugin-inventory.md
    config.md
  decisions/
    0001-modern-backend-and-frontend.md
    0002-keycloak-oidc.md
    0003-secrets-management.md
    0004-multi-tenant-plugin-config.md
    0005-scorecards.md
```

Keep user-facing docs separate from operator/developer docs if the audience grows. For a small instance, one `docs/` tree is enough.

## First Implementation Slice

A fresh agent should not start by installing twenty plugins. The first useful slice is:

1. Generate current Backstage.
2. Confirm modern frontend/backend defaults.
3. Add root commands: `doctor`, `deps`, `db`, `dev`, `test`, `config-check`.
4. Add Docker Compose Postgres.
5. Add `app-config.development.yaml`, `app-config.production.yaml`, and examples for local overrides.
6. Add Keycloak OIDC sign-in with a local or dev Keycloak option.
7. Add GitHub App integration, GitHub catalog discovery, GitHub scaffolder actions, and GitHub Actions visibility.
8. Add TechDocs and local docs preview.
9. Add CI with install, config check, lint, typecheck, tests, and build.
10. Add a minimal plugin inventory doc and annotation reference.

Second slice:

1. Add Prometheus and Grafana entity cards with annotations.
2. Add Tech Insights or the first custom health-check plugin.
3. Add template dry-run and scheduled validation for one critical template.
4. Add upgrade workflow docs and Renovate/Dependabot rules.

Third slice:

1. Add community/inner-source affordances.
2. Add custom plugin packaging standards.
3. Add richer scorecard rollups by team/system.
4. Add production deployment automation.

## Risks

- **Backstage maintenance load:** Backstage is a product, not a config file. Keep the initial plugin set small and maintain an upgrade cadence.
- **Plugin sprawl:** Every plugin adds package, auth, config, UX, and support surface. Maintain a plugin inventory with owner, package, status, config keys, annotations, and test coverage.
- **Secret leakage:** Avoid checked-in generated files, avoid broad proxy routes, and validate config visibility. CI should run secret scanning.
- **Catalog distrust:** If ownership and metadata are wrong, every plugin becomes less useful. Prioritize catalog hygiene and validation.
- **Scorecard backlash:** If checks are opaque or punitive, teams will ignore them or game them. Start transparent and advisory.
- **GitHub API throttling:** Use GitHub Apps, webhooks/events, schedules, and page-size tuning. Avoid naive org-wide polling.

## Appendix: Extracted Sample Patterns

This appendix embeds the transferable practices from the mature Backstage sample so this design can be used without access to that repository. It deliberately omits organization names, private URLs, internal service names, groups, namespaces, tokens, and product-specific identifiers.

### Root Workspace Envelope

The sample separates Backstage app code from platform operations. The app lives in the standard Backstage package layout, while root-level files hold commands, CI, deployment material, and docs. The useful pattern is a thin root envelope around the generated app, not a large custom framework.

Transferable practices:

- Provide root commands for authentication, dependency install, build, local development, container build, deployment, restart, port-forwarding, and diagnostics.
- Pin runtime versions with `.nvmrc`, `.node-version`, Corepack/Yarn settings, or equivalent files so new developers and CI use the same toolchain.
- Include pre-commit hooks, Prettier, EditorConfig, linting, and type checks as first-class setup steps.
- Use Docker Compose or equivalent local dependency orchestration for Postgres and optional local services.
- Document source-based development as the normal path and container-based development as a secondary path for Dockerfile/image work.
- Document remote development port forwarding when the app may run on a remote workstation but the UI, backend, database, and auth callbacks need local access.
- Keep optional integrations quiet in local development. If an integration cannot run locally without special access, the app should disable that module or show a stub instead of breaking pages.

### Configuration Layering

The sample uses local config overrides and deployment overlays to keep developer settings out of committed defaults. The transferable pattern is explicit config layering plus examples.

Recommended isolated version:

- Keep shared non-secret defaults in `app-config.yaml`.
- Add environment overlays such as `app-config.development.yaml`, `app-config.staging.yaml`, and `app-config.production.yaml` when behavior differs by environment.
- Provide `app-config.local.yaml.example` and gitignore `app-config.local.yaml` for personal developer overrides.
- Run development scripts with explicit `--config` flags so the loaded config stack is visible.
- Use local config to populate a small local catalog fixture set rather than requiring the full production catalog to be reachable.
- Validate config in CI with `backstage-cli config:check` across the same config combinations used by local, staging, and production runs.

### Secret Lifecycle

The sample has a valuable end-to-end secret lifecycle: define the secret path, make development credentials available, wire deployment secrets, render local environment variables, validate the rendered values, and reference them from Backstage config. The provider-specific details should not be copied.

Recommended isolated version:

- Maintain separate development, staging, and production secret scopes.
- Prefer shared read-only development credentials for optional integrations where possible, so every developer can boot the app without personal tokens.
- If shared development credentials are not available, the app must still boot with the integration disabled or stubbed.
- Keep local retrieval behind one command such as `make secrets` or `scripts/dev-secrets`.
- Render secrets into a gitignored file such as `.env.local` or a shell export file, and print key presence/status without printing values.
- Use Backstage `$env` and `$file` config loaders rather than bespoke runtime string replacement in app code.
- Deployment should fetch secrets through workload identity, OIDC, External Secrets, or another environment-appropriate mechanism rather than relying on long-lived repository secrets.
- Adding a new secret should include a validation step and a note about what happens when the secret is absent.

### CI And Release Flow

The sample's CI documentation is useful because it explains behavior instead of merely listing jobs. The important design lesson is to make pipeline intent inspectable: what runs on pull requests, what runs after merge, what runs on release, what is non-blocking, and what actually blocks deployment.

Recommended GitHub Actions translation:

- Pull request workflows should run fast feedback: install, config check, lint, typecheck, unit tests, focused build, catalog validation, and a small smoke suite.
- Documentation-only pull requests may skip expensive build/test jobs if the skip rules are explicit and easy to audit.
- Default-branch workflows should run the broader checks: full build, image build, secret scanning, vulnerability scanning, TechDocs build, template validation, and scorecard validation.
- Slower advisory scans may be non-blocking after merge, but that choice should be documented. Blocking security checks should be narrow and intentional.
- Release should be explicit: build/publish image, tag or create release, deploy to staging, run smoke, then require a manual production gate if production deployment is in scope.
- The CI docs should include a "why didn't my job run?" section, a "what blocks deployment?" section, and a table of workflow triggers.
- Path filters should be used carefully. Skipping tests on docs-only changes is useful; skipping validation when config, package, Docker, deployment, or template files change is risky.

### Catalog And Annotation Hygiene

The sample maintains catalog documentation and validates catalog entity files. The transferable pattern is to treat catalog metadata as product data, not decorative YAML.

Recommended isolated version:

- Maintain a catalog annotation reference with examples for each installed plugin.
- Validate `catalog-info.yaml` in CI and editor tooling.
- Require `owner`, `lifecycle`, `system`, source location, and TechDocs reference where appropriate.
- Keep local catalog fixtures for development and plugin tests.
- Add scorecard checks for catalog hygiene before adding more ambitious operational checks.
- Prefer small, documented custom kinds when the domain needs them rather than overloading `Component`.

### Template Validation

The sample validates scaffolder templates by marking templates as validation-enabled, providing representative input values, running validation on a schedule, cleaning up generated resources, and notifying the owner when validation fails. This is a strong pattern for any Backstage instance with important templates.

Recommended isolated version:

- Add metadata or annotations that opt a template into validation.
- Store representative validation inputs close to the template, but avoid secrets in those inputs.
- Provide a short-interval debug group for template authors and a normal scheduled group for ongoing validation.
- Require templates that create resources to include lifecycle, expiration, cleanup metadata, or a teardown action.
- Validate that the generated repository/entity/resource is registered correctly in the catalog.
- Send failure notifications to the template owner and record logs in the normal observability stack.
- Keep at least one critical template under scheduled validation before expanding to the full template catalog.

### Scorecards And Health Checks

The sample demonstrates two generations of scorecard thinking: simple per-entity health checks and a richer Block/Grid-style model. Both are useful.

Simple health-check pattern:

- Each check returns a name, status, optional message, and optional debugging URL.
- Checks return "not applicable" when the entity lacks the required annotation or config, rather than reporting failure.
- Entity pages show all applicable checks and why unavailable checks did not run.
- Home or owner pages summarize the least healthy status across owned production entities.
- Status values should distinguish healthy, warning, error, pending/running, aborted, misconfigured, no data, and communication failure.

Block/Grid-style pattern:

- Catalog-defined check groups keep scorecard definitions out of code.
- Enrollment annotations prevent broad checks from surprising every entity.
- Scheduled execution keeps entity pages fast and preserves historical results.
- Retention policy prevents unbounded result growth.
- Grids and levels create a readable maturity model.
- Tests for checks should cover success, failure, unavailable data, misconfiguration, and external API errors.

### Plugin Extension Practices

The sample's strongest code-level pattern is putting integration seams in backend modules rather than centralizing every extension in the backend entrypoint.

Recommended isolated version:

- Use backend modules to extend catalog, scaffolder, auth, search, events, and other core plugins.
- Keep custom actions, processors, providers, transforms, filters, and retrievers in focused modules with tests.
- Use multi-instance config for integrations that may connect to more than one account, organization, environment, or service instance.
- Every plugin or module should have an owner, config schema, fixture entities, local test strategy, and disabled-state behavior.
- Avoid installing plugins that cannot be made quiet when annotations or credentials are absent.

### Sample Anti-Patterns To Avoid

The same mature sample also shows failure modes that a fresh instance should avoid.

- Do not commit generated dependencies, build outputs, or backend bundles.
- Do not make broad integration credentials mandatory for local boot.
- Do not collect every proxy route and integration secret in one giant `app-config.yaml`.
- Do not use unauthenticated proxy routes without a written threat model, narrow methods, narrow headers, and an owner.
- Do not carry a hybrid frontend indefinitely if a fresh app can start on the new frontend system.
- Do not copy legacy CI or auth assumptions when the target platform is GitHub and Keycloak.
- Do not let custom plugins accumulate without ownership, tests, config schemas, fixtures, and retirement paths.

## Appendix: Community Resource and Volunteer Coordination

This appendix describes a non-software domain that can still benefit from the Backstage control-plane pattern: a local community platform for youth sports, school-support groups, PTAs, volunteer projects, mentoring, gear swaps, facility coordination, and similar community operations. The point is not to pretend that shoes, sports fields, volunteer skills, and community groups are software components. The point is to reuse Backstage's strengths - identity, catalog metadata, ownership, docs, search, permissions, plugins, and admin workflows - while giving busy parents and volunteers a simpler purpose-built frontend for day-to-day interaction.

### Product Shape

Use Backstage as the power-user and administrator surface, not necessarily as the only user interface.

- **Backstage:** admin and operator view for group metadata, activity definitions, resource catalogs, volunteer opportunity configuration, scorecards, audit trails, docs, and integrations.
- **Mini-frontend:** mobile-first parent and volunteer view for "I can help", "I need this", "I can offer this", "I want to learn", "I can mentor", "I can give/lend this item", and "I can sign up for this shift".
- **Backend/API:** shared service that owns dynamic data such as offers, needs, claims, reservations, messages, and moderation state.
- **Catalog:** stable index of groups, activities, programs, facilities, resource categories, and ownership, with links into the mini-frontend for live interactions.

The recommended strategy is a hybrid. Keep stable, owned, documented things in Backstage/catalog-friendly structures; keep volatile marketplace and signup data in an application database behind a custom backend plugin or companion API. A gear-swap listing or volunteer claim should not require editing YAML.

### Design Principles

- **Parent-first UX:** assume users are busy, on phones, and not interested in Backstage terminology.
- **Adult accounts only by default:** avoid child accounts unless there is a deliberate legal/privacy review and a strong need.
- **Minimal child data:** model age group, grade band, team, season, or size when needed; avoid storing children's names, photos, precise schedules, medical details, or unnecessary education records.
- **Private by default:** offers, needs, and contact details should be visible only to the relevant group, approved volunteers, or moderators.
- **Moderated exchange:** gear swaps, facility access, and volunteer roles need moderation, report/flag workflows, and admin audit trails.
- **No exact public locations:** use managed pickup points, event handoff windows, or moderator-mediated contact rather than public home addresses.
- **Time-boxed data:** seasons end, children grow, needs expire, and offers get claimed. Every dynamic record should have an expiry or archival path.
- **Community trust over gamification:** recognition can help, but avoid leaderboards that shame volunteers or expose family circumstances.

### Architecture Options

| Option | Shape | Pros | Cons | Recommendation |
|---|---|---|---|---|
| Catalog-first | Define custom catalog kinds for groups, activities, resources, facilities, opportunities, and maybe offers/needs | Simple to inspect, easy for admins, strong ownership and docs, low app complexity | YAML is a bad fit for fast-moving inventory, claims, parent UX, privacy, and matching | Useful only for stable objects |
| App/database-first | Build a small community app with its own database and expose a Backstage plugin for admins | Best UX for parents, natural fit for offers/needs/signups, easier privacy controls | More product surface, requires schema/API work, less Backstage-native metadata unless integrated | Good if the community app is the real product |
| Hybrid | Catalog stable objects; database dynamic interactions; Backstage plugin administers both; mini-frontend serves parents | Balances Backstage strengths with real user needs, keeps volatile data out of YAML, supports simple frontend | Requires clear boundaries and integration discipline | Recommended |
| External-tools-first | Start with Google Forms/Sheets, Airtable, GitHub Issues, or a lightweight form tool, then import/index into Backstage | Very fast pilot, low engineering effort, easy to validate demand | Permission sprawl, data quality issues, privacy concerns, hard to scale matching/moderation | Good for discovery, not the long-term platform |
| Marketplace-first | Build gear/resource exchange first, then generalize to volunteering and mentoring | Tangible value, easy adoption before a season, clear workflows | Can overfit to inventory and miss broader community organization needs | Good first mini-frontend slice |
| Volunteer-exchange-first | Build Skill Exchange-style profiles and opportunities first | Aligns with mentoring/learning goals, supports PTAs and community groups | Harder to motivate without concrete activities, more privacy-sensitive | Better as the second slice |

### Suggested Domain Objects

Do not force these into Backstage's `Component` kind. Create domain-specific kinds or database tables with clear names.

| Object | Purpose | Stable or Dynamic | Backstage Fit |
|---|---|---|---|
| `CommunityGroup` | PTA, sports league, team, committee, booster group, local nonprofit, school-support group | Stable | Strong catalog fit |
| `Program` or `Season` | Soccer season, school year, fundraising drive, tournament, reading program | Stable-ish | Good catalog fit |
| `Activity` | Gear swap, volunteer day, field cleanup, tournament support, fundraiser, mentoring night | Stable-ish | Good catalog fit when activity has owners/docs |
| `Opportunity` | A need for help, mentoring, reviewing, coaching, setup, cleanup, translation, carpentry, grant writing, etc. | Dynamic or semi-stable | Hybrid |
| `VolunteerProfile` | Adult's skills, interests, availability, learning goals, mentoring offers, preferred groups | Dynamic and private | App database, Backstage admin summary |
| `Skill` or `Interest` | Controlled vocabulary for what volunteers can do, teach, or want to learn | Stable | Catalog/config fit |
| `ResourceType` | Cleats, shin guards, uniforms, cones, tents, tables, coolers, laptops, books, facility access | Stable | Catalog/config fit |
| `ResourceOffer` | "I have size 2 cleats to give/lend" or "I can loan a canopy for Saturday" | Dynamic | App database |
| `ResourceNeed` | "Need size 3 cleats" or "Need two tables for the event" | Dynamic | App database |
| `Facility` | Sports field, gym, meeting room, storage closet, concession stand, parking lot | Stable | Catalog fit with access controls |
| `Reservation` | Time-boxed booking or claim for a facility, item, or volunteer shift | Dynamic | App database |
| `Transfer` | Matched handoff between an offer and a need | Dynamic and sensitive | App database with audit |
| `Policy` | Rules for eligibility, privacy, pickup, donations, facility use, background checks, and data retention | Stable | Docs/TechDocs fit |

### Activity Patterns

- **Gear swap:** parents list give-away or lendable items by category, size, condition, season, and pickup method; other parents request or claim; moderators can approve, hide, expire, or mark fulfilled.
- **Volunteer signup:** organizers publish shifts, roles, required skills, background-check requirements, and time windows; volunteers claim slots; admins see coverage gaps.
- **Skill exchange:** adults list skills they can teach, mentor, or contribute and skills they want to learn; opportunities can request skills without exposing private personal details broadly.
- **Facility and equipment coordination:** groups can request fields, rooms, storage, tables, tents, or sports gear; admins can approve reservations or route requests to the right owner.
- **Community project board:** local groups publish project ideas and needed help, linked to GitHub Issues/Projects if the work is technical or to a simpler task board if it is operational.
- **Donation and resource drives:** organizers publish target resources, quantities, deadlines, accepted conditions, drop-off rules, and fulfillment status.
- **Season readiness checks:** a scorecard-like view can show whether a season has coaches, background checks, field reservations, gear coverage, emergency contacts, docs, and volunteer slots ready.

### Parent Mini-Frontend Ideas

The mini-frontend should not look or feel like Backstage. It should be a focused web app, probably installable/PWA-style, with a small number of flows.

- A landing screen with three actions: `Offer`, `Need`, and `Volunteer`.
- Fast filters for group, season, age/grade band, item size, activity date, location area, and pickup/drop-off method.
- "I have extra gear" flow with category, size, condition, photo optional, give/lend, preferred handoff, expiry date, and visibility.
- "I need gear" flow with category, size, needed-by date, acceptable condition, and whether a loan is acceptable.
- "I can help" flow with skills, availability, preferred groups, background-check status if applicable, and mentoring/learning interests.
- "I want to learn" flow for adults who want coaching, mentoring, first-aid training, scorekeeping, event organizing, grant writing, technical help, or other skills.
- Match suggestions that reveal only enough information to proceed, with contact details hidden until both sides opt in or a moderator approves.
- Moderator handoff mode for sensitive exchanges, where the system routes both parties to a public pickup point or event table instead of sharing direct contact details.
- Expiry nudges before a season starts: "these offers expire Friday", "these needs are still open", "this activity is short two volunteers".

### Backstage Admin and Power-User Surface

Backstage should give organizers the richer view that ordinary parents do not need.

- Catalog pages for `CommunityGroup`, `Program`, `Activity`, `Facility`, and `ResourceType`.
- Entity cards showing open needs, available offers, volunteer coverage, upcoming events, stale listings, and moderation queue counts.
- Docs pages for rules, volunteer onboarding, background-check process, gear condition guidelines, facility use, and season playbooks.
- Search across groups, activities, facilities, docs, and public resource categories.
- Permission-controlled admin routes for approving groups, editing taxonomies, seeing reports, handling moderation, and exporting summaries.
- Backend scheduled tasks for expiring old offers/needs, sending reminders, detecting uncovered volunteer slots, and archiving completed seasons.
- Notifications for organizers when critical roles are unfilled or resource needs remain open near a deadline.
- Optional scorecards for readiness and coverage, framed as operational status rather than team judgment.

### Data and Privacy Notes

This domain involves children, schools, families, locations, volunteer eligibility, and potentially sensitive need signals. Treat privacy and safety as primary product requirements.

- Avoid collecting personal information from children. The FTC's COPPA guidance is relevant if an online service is directed to children under 13 or knowingly collects personal information from them.
- Avoid treating the system as a school records system. If the platform interacts with a school district or education records, FERPA and district policy may apply; keep the community app focused on adult volunteers and non-educational operational data unless reviewed.
- Keep child identity out of inventory exchange. Prefer "size 2 cleats needed for U8 soccer" over child names.
- Do not store home addresses by default. Prefer pickup sites, event handoff windows, or moderator-mediated exchange.
- Use role-based visibility: parent, organizer, group admin, district liaison, moderator, system admin.
- Keep audit logs for moderator/admin actions, claim state changes, and permission changes.
- Add abuse/reporting workflows before broad rollout, even if they are simple.
- Define data retention early: expire unclaimed gear offers, archive old seasons, delete stale personal preferences, and give adults a way to remove their profile.

### Matching Strategies

| Strategy | How it works | Pros | Cons |
|---|---|---|---|
| Manual browse | Users search/filter offers and needs themselves | Simple, transparent, low risk | Requires user effort, weak at scale |
| Moderator matching | Organizers see likely matches and coordinate handoff | Safer for sensitive communities, good for early trust | More admin work |
| Rule-based matching | Match category, size, group, season, location area, condition, and dates | Predictable, explainable, easy to test | Can miss nuanced cases |
| Preference-aware matching | Use volunteer interests, skills, availability, and learning goals | Better for Skill Exchange-style volunteering | More profile data and privacy surface |
| Recommendation engine | Rank opportunities/resources automatically | Powerful later | Too complex and potentially opaque for MVP |

Start with manual browse plus moderator matching. Add rule-based matching once the fields stabilize. Defer recommendation-style matching until there is enough usage and trust.

### First Pilot Slice

A useful first slice is a gear-swap MVP because it is concrete, seasonal, and easy for families to understand.

1. Define `CommunityGroup`, `Program`, `Activity`, `ResourceType`, and `Facility` as stable catalog-backed concepts.
2. Build a small backend table/API for `ResourceOffer`, `ResourceNeed`, `Transfer`, and moderation state.
3. Build a parent mini-frontend with `Offer`, `Need`, browse, claim/request, and expiry.
4. Add a Backstage admin plugin page for open needs, offers, stale listings, moderation, and simple exports.
5. Keep identity adult-only through Keycloak/OIDC or another community identity source.
6. Run one season-bound gear swap with a few resource categories and explicit pickup rules.
7. After the pilot, decide whether the next slice is volunteer signup, Skill Exchange-style profiles, facility reservations, or community project boards.

### Later Expansion Ideas

- Volunteer skill profiles with "can mentor", "can help", and "want to learn" sections.
- Activity templates for gear swap, fundraiser, field cleanup, tournament support, PTA event, reading night, and community tech help.
- Facility calendar and request workflow for fields, gyms, rooms, and storage.
- Background-check eligibility flags for roles that require it, stored minimally and visible only to authorized organizers.
- Resource kits for recurring activities, such as "soccer season starter kit", "field day kit", or "fundraiser table kit".
- Group playbooks in TechDocs, linked directly from activities and volunteer roles.
- Integration with GitHub Issues/Projects for technical community efforts, while nontechnical tasks remain in the simpler mini-frontend.
- Public read-only pages for approved activities and needs, with private details hidden.
- Lightweight impact reporting: fulfilled needs, volunteer slots covered, gear reused, estimated savings, and unresolved gaps.

### Fit Assessment

This appendix stretches Backstage beyond its original software-catalog center, but the fit is reasonable if Backstage is treated as the admin/control-plane and not forced to be the parent-facing marketplace UI. The strongest overlap is ownership, metadata, documentation, permissions, search, workflows, and extension points. The weakest overlap is high-churn human interaction: claims, messaging, handoffs, personal preferences, inventory state, and mobile-first UX. That weak area should be handled by a small custom frontend and database, with Backstage used to configure, inspect, and operate it.

## Appendix: Distilling Agent Plans Into ADRs

This appendix describes a workflow for turning heavy agent-written design specs and implementation plans into compact Architecture Decision Records that remain useful after the original working documents have served their purpose. The goal is not to convert every plan into an ADR. The goal is to preserve the decisions, rationale, rejected options, and lasting constraints while letting bulky planning artifacts become historical provenance.

### Format Fit

Agent design specs and implementation plans are usually too broad for ADRs. A plan describes how to do work; an ADR records one significant decision and why it was made. The useful post-processing step is therefore distillation, not summarization.

Good ADR candidates from an agent plan:

- A technology choice, such as Keycloak OIDC instead of another SSO provider.
- A platform boundary, such as "Backstage is the admin/control-plane, a mini-frontend serves parents".
- A workflow convention, such as "plans are distilled into ADRs after implementation".
- A data model choice, such as catalog-backed stable objects plus database-backed dynamic interactions.
- A security or governance stance, such as OpenBao-first secret management or adult-only community accounts.
- A durable tradeoff that future maintainers are likely to question.

Poor ADR candidates:

- A step-by-step implementation checklist.
- A temporary investigation note.
- A plan section that simply restates obvious work.
- A task ordering decision with no lasting architectural consequence.
- A speculative idea that was never accepted, unless it explains why a tempting option was rejected.

### Backstage ADR Plugin Compatibility

The current Backstage Community ADR plugin expects ADR files associated with catalog entities. The entity points to the ADR directory with `backstage.io/adr-location`, and the plugin can expose ADRs on entity pages and through Backstage Search. The current community docs say the default parser supports MADR v2.x and MADR 3.x, and the backend can be extended with a custom parser if a different format is needed.

Recommended setup for a new instance:

```yaml
metadata:
  annotations:
    backstage.io/adr-location: docs/adrs
```

Recommended directory shape:

```text
repo-root/
  catalog-info.yaml
  docs/
    adrs/
      0000-adr-template.md
      0001-use-keycloak-oidc.md
      0002-use-openbao-compatible-secret-workflow.md
      0003-distill-agent-plans-into-adrs.md
    plans/
      2026-06-09-backstage-devex-workspace-design.md
```

Prefer `docs/adrs` for records intended to stay discoverable in Backstage. Keep `docs/plans` or `docs/superpowers/specs` for heavy working documents. If the repo has multiple entities, each entity can have its own ADR directory; if the repo is itself the platform entity, a single `docs/adrs` directory is usually enough.

### Provenance Anchors

Each distilled ADR should include stable links back to the full design and implementation plan when those documents were committed. Use immutable commit URLs, not branch URLs.

Recommended provenance fields:

- `source-design`: URL to the design/spec at a commit SHA.
- `source-plan`: URL to the implementation plan at a commit SHA.
- `implemented-by`: URL to the pull request, change request, or merge commit.
- `first-implemented`: commit SHA that first made the decision real.
- `reviewed-after`: optional later commit, release, or date when the decision was revalidated.

Example:

```markdown
## More Information

- Source design: https://github.com/example/backstage-portal/blob/0123456789abcdef/docs/plans/2026-06-09-backstage-devex-workspace-design.md
- Source implementation plan: https://github.com/example/backstage-portal/blob/0123456789abcdef/docs/plans/2026-06-10-backstage-devex-workspace-plan.md
- Implemented by: https://github.com/example/backstage-portal/pull/42
- First implemented in: `89abcdef01234567`
```

This lets old plans be pruned from the visible docs tree later while still remaining recoverable from Git history, assuming the repository history is retained and not rewritten. If long-term availability matters more than repository cleanliness, keep a compressed plan archive under `docs/plans/archive/` or attach the original plan to the implementation PR.

### Distillation Workflow

Run this workflow after implementation is complete or after a design is accepted but before the heavy plan is deleted.

1. Identify the source artifacts: design spec, implementation plan, final diff, commit SHA, PR/change request, review notes, and any relevant issues.
2. Extract candidate decisions: scan for chosen options, rejected alternatives, constraints, risks accepted, conventions introduced, and boundaries future maintainers may revisit.
3. Filter aggressively: keep only decisions with lasting architectural, operational, security, data-model, or workflow impact.
4. Split by decision: one ADR per significant decision. Do not create one giant ADR for an entire plan unless the plan has exactly one durable decision.
5. Normalize to MADR: use title, context/problem, decision drivers, considered options, outcome, consequences, confirmation, and more information.
6. Add provenance anchors: include immutable links to the original plan/spec and implementation commit or PR.
7. Mark status: use `proposed` while still under discussion, `accepted` when adopted, `superseded` when replaced, and `deprecated` when no longer recommended.
8. Validate discoverability: ensure the owning entity has `backstage.io/adr-location`, the filename matches the ADR plugin filter, and Backstage Search indexes the record if search is configured.
9. Decide plan retention: keep, archive, or delete the heavy plan only after the ADR and implementation provenance are committed.

### Mapping From Agent Plan To ADR

| Agent artifact section | ADR destination | Notes |
|---|---|---|
| Problem statement or user goal | `Context and Problem Statement` | Preserve the durable problem, not the whole conversation. |
| Requirements and constraints | `Decision Drivers` | Keep the forces that made the decision non-obvious. |
| Proposed approaches | `Considered Options` and `Pros and Cons of the Options` | Collapse variants that no longer matter. |
| Recommendation | `Decision Outcome` | State the chosen option plainly. |
| Tradeoffs and risks | `Consequences` | Include both benefits and costs. |
| Test/verification plan | `Confirmation` | Describe how future reviewers can tell the decision is still implemented. |
| Implementation checklist | Usually omitted | Keep only high-level implementation anchors or links. |
| Follow-up work | `More Information` or a separate issue | Do not turn backlog into ADR content. |
| Final commits/PR | `More Information` | Use immutable links. |

### Recommended MADR-Sized Template

This template is intentionally small. It should parse cleanly with the ADR plugin's MADR-oriented defaults, while leaving room for provenance.

```markdown
---
status: accepted
date: 2026-06-09
decision-makers:
  - platform owner
consulted:
  - agent
---

# Distill Agent Plans Into ADRs

## Context and Problem Statement

Agent-assisted design specs and implementation plans are useful while work is active, but they are too large and too procedural to keep as permanent reference documentation. Future maintainers need the decision, rationale, tradeoffs, and provenance without reading the full working plan.

## Decision Drivers

* Preserve durable rationale after heavy plans are archived.
* Keep Backstage ADR discovery useful and searchable.
* Avoid turning every implementation checklist into permanent documentation.
* Preserve a commit-level path back to the full plan when deeper audit is needed.

## Considered Options

* Keep all design specs and implementation plans forever.
* Delete plans after implementation.
* Distill accepted plans into ADRs with provenance links.

## Decision Outcome

Chosen option: "Distill accepted plans into ADRs with provenance links", because it keeps the permanent decision log small while retaining an audit path to the full source material.

### Consequences

* Good, because future maintainers can find the decision in Backstage without reading a long plan.
* Good, because old plans can be archived or pruned without losing the rationale.
* Bad, because distillation is another workflow step and can lose nuance if done carelessly.
* Bad, because commit links depend on retained repository history and access.

### Confirmation

Confirm by checking that accepted decisions have ADR files under `docs/adrs`, the catalog entity has `backstage.io/adr-location`, the ADR links to the source plan at a commit SHA, and Backstage can display or index the ADR.

## Pros and Cons of the Options

### Keep all design specs and implementation plans forever

* Good, because no context is lost.
* Bad, because the docs tree becomes heavy, stale, and hard to search.

### Delete plans after implementation

* Good, because the docs tree stays clean.
* Bad, because rationale and rejected options disappear from normal discovery.

### Distill accepted plans into ADRs with provenance links

* Good, because ADRs remain concise and plans remain recoverable.
* Neutral, because it requires a consistent post-processing skill or checklist.
* Bad, because it depends on someone deciding which plan content is architecturally significant.

## More Information

* Source design: <commit-stable URL to design/spec>
* Source implementation plan: <commit-stable URL to plan>
* Implemented by: <PR/change request URL>
* First implemented in: `<commit-sha>`
```

### Candidate GDD Skill Shape

This could become a workspace skill named something like `gdd-adr-distillation`. It should be a post-implementation or post-acceptance skill, not part of initial brainstorming.

Trigger conditions:

- User asks to archive, summarize, distill, or clean up design specs/plans.
- A plan has been implemented and the repository has no ADR for the durable decision.
- `docs/plans` or `docs/superpowers/specs` contains stale heavy plans that should be converted into permanent references.

Inputs:

- Path to design/spec.
- Path to implementation plan.
- Current commit or merge commit.
- PR/change request URL if available.
- Owning catalog entity and ADR directory.
- Status to use: usually `accepted`, occasionally `proposed` or `superseded`.

Workflow:

1. Read the source plan/spec and final diff.
2. Identify candidate durable decisions.
3. Ask the human which candidates deserve ADRs if there is more than one plausible split.
4. Draft one ADR per accepted decision using the MADR-sized template.
5. Include immutable source links and implementation provenance.
6. Verify ADR filename convention, status/date, plugin parse compatibility, and catalog annotation.
7. Offer to archive or prune the heavy plan only after ADRs are committed or otherwise preserved.

Guardrails:

- Never write an ADR that only says "we followed the plan".
- Never collapse unrelated decisions into one ADR for convenience.
- Never delete or archive a heavy plan unless the human explicitly approves that cleanup.
- Keep the ADR short enough to read in Backstage.
- Preserve uncertainty: if the decision was provisional, mark it `proposed` or add a review trigger.
- Prefer an ADR over a plan summary only when there is a lasting decision future maintainers will need.

### Open Questions For A Future Skill

- Should the skill create ADRs in every component repo, or only in the repo that owns the affected catalog entity?
- Should plan archives stay in Git forever, move to `docs/plans/archive/`, or rely on commit links?
- Should the skill generate one ADR per decision automatically, or always ask before splitting?
- Should ADR status be changed automatically after merge, or should acceptance remain a human-controlled step?
- Should the Backstage instance use the default MADR parser, or should it add a custom parser/decorator for provenance frontmatter?

## Source Notes

- Backstage GitHub repository: https://github.com/backstage/backstage
- Backstage standalone installation docs: https://backstage.io/docs/next/getting-started/
- Backstage backend system docs: https://backstage.io/docs/backend-system/
- Backstage frontend app docs: https://backstage.io/docs/frontend-system/building-apps/
- Backstage static configuration docs: https://backstage.io/docs/next/conf/
- Backstage configuration schema docs: https://backstage.io/docs/next/conf/defining/
- Backstage OIDC provider docs: https://backstage.io/docs/auth/oidc/
- Backstage GitHub discovery docs: https://backstage.io/docs/next/integrations/github/discovery/
- Backstage software templates docs: https://backstage.io/docs/features/software-templates/
- Backstage writing templates docs: https://backstage.io/docs/features/software-templates/writing-templates/
- Backstage built-in scaffolder actions docs: https://backstage.io/docs/features/software-templates/builtin-actions/
- Backstage Plugin Directory: https://backstage.io/plugins/
- Backstage Plugin Directory Audit: https://backstage.io/docs/next/plugins/plugin-directory-audit/
- Backstage v1.31.0 release notes for Yarn 4 default: https://backstage.io/docs/releases/v1.31.0/
- Backstage v1.49.0 release notes for new frontend default: https://backstage.io/docs/next/releases/v1.49.0/
- Backstage Community ADR frontend plugin README: https://github.com/backstage/community-plugins/blob/main/workspaces/adr/plugins/adr/README.md
- Backstage Community ADR backend plugin README: https://github.com/backstage/community-plugins/blob/main/workspaces/adr/plugins/adr-backend/README.md
- MADR overview and template: https://adr.github.io/madr/
- HashiCorp Business Source License announcement: https://www.hashicorp.com/blog/hashicorp-adopts-business-source-license
- OpenBao project home: https://openbao.org/
- OpenBao migration guide: https://openbao.org/docs/migration-guide/
- OpenBao API library compatibility note: https://openbao.org/api-docs/next/libraries/
- Roadie GitHub Actions plugin guide: https://roadie.io/backstage/plugins/github-actions/
- Roadie Jenkins plugin guide: https://roadie.io/backstage/plugins/jenkins/
- Roadie Tech Insights plugin guide: https://roadie.io/backstage/plugins/tech-insights/
- Roadie Prometheus plugin guide: https://roadie.io/backstage/plugins/prometheus/
- Roadie Grafana plugin guide: https://roadie.io/backstage/plugins/grafana/
- Spotify Soundcheck overview: https://backstage.spotify.com/docs/portal/core-features-and-plugins/soundcheck
- Spotify Skill Exchange overview: https://backstage.spotify.com/docs/plugins/skill-exchange
- FTC COPPA overview: https://www.ftc.gov/legal-library/browse/rules/childrens-online-privacy-protection-rule-coppa
- U.S. Department of Education student records and privacy FAQ: https://www.ed.gov/about/contact-us/faqs/Student%20Records%20and%20Privacy
