# Leiðangr Phase 2 Backstage Skeleton — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a fresh, modern Backstage instance as the `leidangr` component that boots locally with zero secrets, then retrieves a Gitea token from OpenBao (browser OIDC) to ingest a few real catalog entities — all behind a self-contained DevEx envelope.

**Architecture:** A `@backstage/create-app` monorepo wrapped in a thin root platform envelope (`Makefile` + `scripts/`). The running app is secret-store-agnostic: it consumes only env vars rendered by `scripts/dev-secrets`, which is the single local retrieval path. Two checkpoints — a zero-secret stub boot, then the OpenBao→Gitea loop. BDD (jest-cucumber) drives acceptance over TDD'd TypeScript envelope tooling.

**Tech Stack:** Backstage (new frontend + backend systems), Node Active LTS (22), Yarn 4 (Corepack), TypeScript, Jest + `@backstage/backend-test-utils`, jest-cucumber, OpenBao (`bao` CLI, OIDC auth via Keycloak), Gitea integration, SQLite (dev DB).

**Design spec:** [`2026-06-21-leidangr-phase2-backstage-skeleton-design.md`](2026-06-21-leidangr-phase2-backstage-skeleton-design.md)
**Feature files (external, referenced by tasks below):** [`2026-06-21-leidangr-phase2-features/`](2026-06-21-leidangr-phase2-features/)

## Global Constraints

- **Node:** Active LTS, pinned to **22** via `.nvmrc`/`.node-version`. Yarn 4 via `corepack enable`.
- **Scaffold:** `@backstage/create-app@latest` on the **new frontend and backend systems** (defaults). No legacy/hybrid frontend.
- **App stays secret-store-agnostic:** the app reads secrets only through Backstage `$env`; `scripts/dev-secrets` is the **only** supported local retrieval path; secrets land **only** in gitignored `.env.local`, **never** in `app-config.local.yaml` or any committed file.
- **Default mode = stub:** SQLite dev DB, guest auth, generated example catalog, **zero secrets or external services required**. CI/test runs against stub + mocked integrations.
- **Catalog source = Gitea** via **static `catalog.locations` (`type: url`)**. GitHub deferred.
- **Secret reachability:** `scripts/dev-secrets` resolves the OpenBao target itself — `BAO_ADDR` direct URL when set, else a `kubectl` port-forward. The app never knows which.
- **Testing:** BDD via jest-cucumber from the external `.feature` files; envelope tooling (doctor, dev-secrets) is TDD'd as pure TypeScript with injected dependencies (no real exec/network in unit tests).
- **ADRs:** MADR v3 files under `docs/adrs/` from the first decision; the `@backstage-community/plugin-adr` plugin is **deferred** (GitHub-only today).
- **Portability:** `Makefile` + `scripts/` use only `kubectl`, `bao`, Node, and standard tools, and run identically standalone or under GDD. **No dependency on `ws`/yggdrasil.**
- **Component home:** `components/leidangr/` (own git repo). Registered in the realm/ecosystem **only after** Checkpoint 1 boots green.
- **Docs prose:** no hard-wrapping (realm convention) — one line per paragraph.

---

## File Structure

```text
components/leidangr/                  # new standalone git repo (create-app output + envelope)
  Makefile                           # root envelope: doctor/deps/db/dev/test/lint/config-check/secrets/ci
  .nvmrc                             # 22
  .gitignore                         # + .env.local, app-config.local.yaml
  .env.example
  app-config.yaml                    # shared non-secret defaults
  app-config.development.yaml        # stub-mode overlay (guest auth, example catalog, SQLite)
  app-config.local.yaml.example      # personal NON-secret overrides template
  docker-compose.yaml                # optional local Postgres (make db) — not required
  packages/app/                      # generated frontend
  packages/backend/                  # generated backend (+ gitea integration in Checkpoint 2)
  scripts/
    dev-secrets                      # thin bash orchestrator (bao login + KV read -> calls lib)
    lib/
      doctor.ts                      # PURE doctor logic (TDD)
      doctor.test.ts
      dev-secrets.ts                 # PURE target/validate/render logic (TDD)
      dev-secrets.test.ts
  tests/acceptance/
    checkpoint-1-stub-boot.feature   # copied from the plan's feature dir
    checkpoint-1.steps.ts
    checkpoint-2-openbao-gitea.feature
    checkpoint-2.steps.ts
  docs/
    adrs/                            # MADR v3 files (decisions captured from day one)
    development/setup.md
```

---

## Task 1: Scaffold the Backstage app + repo hygiene

**Files:**
- Create: `components/leidangr/` (entire `@backstage/create-app` output)
- Create: `components/leidangr/.nvmrc`, `components/leidangr/.gitignore` additions
- Test: manual boot verification (generated code is not unit-tested; the deliverable is "it boots")

**Interfaces:**
- Produces: a booting Backstage monorepo with `packages/app`, `packages/backend`, `app-config.yaml`, Yarn 4, SQLite dev DB, guest/example catalog.

- [ ] **Step 1: Confirm toolchain**

Run: `node --version` (expect `v22.*`) and `corepack --version`. If Node is wrong, install Active LTS 22 first.

- [ ] **Step 2: Scaffold**

Run from `components/`: `npx @backstage/create-app@latest`
When prompted for the app name, enter `leidangr`. This creates `components/leidangr/`.
Expected: scaffold completes; output notes the new frontend/backend systems and Yarn 4.

- [ ] **Step 3: Initialize the component as its own git repo**

Run from `components/leidangr/`: `git init` then stage the generated tree (create-app may already `git init`; if so, skip).

- [ ] **Step 4: Pin Node + extend gitignore**

Create `components/leidangr/.nvmrc` containing exactly `22`.
Append to `components/leidangr/.gitignore`:

```gitignore
# leidangr envelope
.env.local
app-config.local.yaml
```

- [ ] **Step 5: Verify it boots in stub mode**

Run from `components/leidangr/`: `yarn install` then `yarn start` (or `yarn dev`).
Expected: frontend on `http://localhost:3000`, backend on `:7007`, guest sign-in, the generated example component visible in the catalog. No secrets prompted.

- [ ] **Step 6: Commit the baseline**

Bodyfile `.commits/leidangr-scaffold.md` with `add: [.]` (run from the component once it is a registered target, or commit with plain git inside the component until it is realm-registered — see Task 8). For now, inside `components/leidangr/`: `git add -A` then commit with message `chore: scaffold modern Backstage app (create-app, yarn 4, node 22)`.

---

## Task 2: doctor (TDD) + root Makefile envelope

**Files:**
- Create: `components/leidangr/scripts/lib/doctor.ts`, `scripts/lib/doctor.test.ts`
- Create: `components/leidangr/Makefile`

**Interfaces:**
- Produces: `runDoctor(deps: DoctorDeps): ToolCheck[]`, `checkNode(version: string, minMajor: number): ToolCheck`; a `Makefile` with `doctor/deps/db/dev/test/lint/config-check/secrets/ci` targets.

- [ ] **Step 1: Write the failing test**

```ts
// scripts/lib/doctor.test.ts
import { checkNode, runDoctor, DoctorDeps } from './doctor';

describe('checkNode', () => {
  it('passes when the major version meets the floor', () => {
    expect(checkNode('v22.3.0', 22)).toMatchObject({ name: 'node', ok: true });
  });
  it('fails when below the floor', () => {
    expect(checkNode('v18.19.0', 22)).toMatchObject({ name: 'node', ok: false });
  });
});

describe('runDoctor', () => {
  const deps: DoctorDeps = {
    which: (bin) => (bin === 'yarn' ? '/usr/bin/yarn' : null),
    nodeVersion: () => 'v22.3.0',
    portFree: (p) => p === 3000 || p === 7007,
  };
  it('reports a check per tool and never returns secret values', () => {
    const checks = runDoctor(deps);
    expect(checks.map((c) => c.name)).toEqual(
      expect.arrayContaining(['node', 'yarn', 'bao', 'port:3000', 'port:7007']),
    );
    expect(checks.find((c) => c.name === 'bao')).toMatchObject({ ok: false });
  });
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `yarn jest scripts/lib/doctor.test.ts`
Expected: FAIL — `doctor` module not found.

- [ ] **Step 3: Implement the minimal module**

```ts
// scripts/lib/doctor.ts
export interface ToolCheck { name: string; ok: boolean; detail: string; }
export interface DoctorDeps {
  which: (bin: string) => string | null;
  nodeVersion: () => string;
  portFree: (port: number) => boolean;
}

export function checkNode(version: string, minMajor: number): ToolCheck {
  const major = Number(version.replace(/^v/, '').split('.')[0]);
  const ok = Number.isFinite(major) && major >= minMajor;
  return { name: 'node', ok, detail: ok ? version : `need >= v${minMajor}, found ${version}` };
}

export function runDoctor(deps: DoctorDeps): ToolCheck[] {
  const bin = (name: string): ToolCheck => {
    const path = deps.which(name);
    return { name, ok: path !== null, detail: path ?? 'not found on PATH' };
  };
  const port = (p: number): ToolCheck => ({
    name: `port:${p}`, ok: deps.portFree(p), detail: deps.portFree(p) ? 'free' : 'in use',
  });
  return [
    checkNode(deps.nodeVersion(), 22),
    bin('yarn'),
    bin('bao'),
    port(3000),
    port(7007),
  ];
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `yarn jest scripts/lib/doctor.test.ts`
Expected: PASS.

- [ ] **Step 5: Write the Makefile envelope**

```makefile
# components/leidangr/Makefile
.PHONY: doctor deps db dev test lint config-check secrets ci
doctor:    ; node --experimental-strip-types scripts/lib/run-doctor.ts
deps:      ; corepack enable && yarn install --immutable
db:        ; docker compose up -d postgres
dev:       ; yarn start
test:      ; yarn jest
lint:      ; yarn backstage-cli repo lint
config-check: ; yarn backstage-cli config:check --config app-config.yaml --config app-config.development.yaml
secrets:   ; bash scripts/dev-secrets
ci:        ; $(MAKE) config-check && $(MAKE) lint && $(MAKE) test
```

Add a tiny `scripts/lib/run-doctor.ts` that wires `runDoctor` to real `which`/`node`/port probes and prints a table (presence only). Keep real-IO wiring out of the unit-tested module.

- [ ] **Step 6: Commit**

Inside `components/leidangr/`: `git add scripts/lib Makefile && git commit -m "feat(envelope): tested doctor + Makefile targets"`.

---

## Task 3: BDD harness + Checkpoint 1 acceptance

**Files:**
- Modify: `components/leidangr/package.json` (add `jest-cucumber` devDependency)
- Create: `components/leidangr/tests/acceptance/checkpoint-1-stub-boot.feature` (copied from the plan)
- Create: `components/leidangr/tests/acceptance/checkpoint-1.steps.ts`

**Interfaces:**
- Consumes: `runDoctor` (Task 2), the generated catalog backend.
- Produces: passing Checkpoint-1 BDD scenarios under `yarn jest`.

- [ ] **Step 1: Add jest-cucumber**

Run: `yarn add --dev jest-cucumber`

- [ ] **Step 2: Copy the feature file verbatim from the plan**

Copy `realms/realm-siliconsaga/docs/plans/2026-06-21-leidangr-phase2-features/checkpoint-1-stub-boot.feature` to `components/leidangr/tests/acceptance/checkpoint-1-stub-boot.feature`. Do not edit it.

- [ ] **Step 3: Write the step definitions (fail first)**

```ts
// tests/acceptance/checkpoint-1.steps.ts
import { loadFeature, defineFeature } from 'jest-cucumber';
import { runDoctor } from '../../scripts/lib/doctor';
import { execFileSync } from 'node:child_process';

const feature = loadFeature('tests/acceptance/checkpoint-1-stub-boot.feature');

defineFeature(feature, (test) => {
  test('The development config is valid without any secrets', ({ when, then, and }) => {
    let result: { code: number; out: string };
    when('I run the configuration check for the development config', () => {
      try {
        const out = execFileSync('yarn', ['backstage-cli', 'config:check',
          '--config', 'app-config.yaml', '--config', 'app-config.development.yaml'],
          { encoding: 'utf8' });
        result = { code: 0, out };
      } catch (e: any) { result = { code: e.status ?? 1, out: String(e.stdout ?? e) }; }
    });
    then('the configuration check succeeds', () => expect(result.code).toBe(0));
    and('no secret values are required to load it', () =>
      expect(result.out).not.toMatch(/\$\{/));
  });

  test('doctor reports the local toolchain without leaking secrets', ({ when, then, and }) => {
    let checks: ReturnType<typeof runDoctor>;
    when('I run the doctor command', () => {
      checks = runDoctor({ which: () => '/x', nodeVersion: () => 'v22.0.0', portFree: () => true });
    });
    then('it reports the status of Node, Yarn, and the required dev ports', () =>
      expect(checks.map((c) => c.name)).toEqual(
        expect.arrayContaining(['node', 'yarn', 'port:3000', 'port:7007'])));
    and('it never prints any secret values', () =>
      checks.forEach((c) => expect(c.detail).not.toMatch(/token|secret|password/i)));
  });

  test('The catalog serves the generated example entities in stub mode', ({ given, when, then, and }) => {
    // Use @backstage/backend-test-utils startTestBackend with the catalog plugin
    // loading the generated example location; assert the example component is present
    // and the request resolves as the guest identity. See development/testing.md for
    // the exact startTestBackend wiring (kept here as a thin call, refined at execution).
    given('the backend is started in stub mode with guest auth', async () => { /* startTestBackend */ });
    when('I query the catalog for all entities', async () => { /* GET /entities via supertest */ });
    then('the generated example component is present', () => { /* expect entity by name */ });
    and('the request is authorized as the guest identity', () => { /* expect guest */ });
  });
});
```

- [ ] **Step 4: Run, verify the first two scenarios fail then pass; wire the catalog scenario**

Run: `yarn jest tests/acceptance/checkpoint-1.steps.ts`
Implement the catalog scenario using `startTestBackend` from `@backstage/backend-test-utils` (refer to `docs/development/testing.md`, written in this task) until all three scenarios pass.

- [ ] **Step 5: Commit**

Inside `components/leidangr/`: `git add tests package.json yarn.lock docs/development/testing.md && git commit -m "test(bdd): checkpoint-1 stub-boot acceptance via jest-cucumber"`.

---

## Task 4: Config layering + stub-mode guarantees

**Files:**
- Create/Modify: `components/leidangr/app-config.development.yaml`, `app-config.local.yaml.example`, `.env.example`

**Interfaces:**
- Produces: a development overlay that guarantees guest auth + example catalog + SQLite with no secrets; `make config-check` green.

- [ ] **Step 1: Write `app-config.development.yaml` (stub overlay)**

```yaml
# app-config.development.yaml — stub mode: zero secrets
backend:
  database:
    client: better-sqlite3
    connection: ':memory:'
auth:
  providers:
    guest: {}
catalog:
  locations:
    - type: file
      target: ../../examples/entities.yaml   # generated example catalog
```

- [ ] **Step 2: Create the non-secret local override example**

`app-config.local.yaml.example` — a comment-only template stating that secrets must NOT go here (they live in `.env.local`, rendered by `make secrets`).

- [ ] **Step 3: Create `.env.example`**

List the env var names the app may consume (e.g. `GITEA_TOKEN=`) with empty values and a note that real values come from `make secrets`.

- [ ] **Step 4: Run config-check**

Run: `make config-check`
Expected: PASS across `app-config.yaml` + `app-config.development.yaml`.

- [ ] **Step 5: Commit**

`git add app-config.development.yaml app-config.local.yaml.example .env.example && git commit -m "feat(config): stub-mode development overlay, no secrets required"`.

---

## Task 5: dev-secrets logic (TDD)

**Files:**
- Create: `components/leidangr/scripts/lib/dev-secrets.ts`, `scripts/lib/dev-secrets.test.ts`

**Interfaces:**
- Produces: `resolveTarget(env): { mode: 'direct'|'port-forward'; addr?: string }`, `validateKeys(data, required): { ok: boolean; missing: string[] }`, `renderEnvLocal(data, mapping): { content: string; presentKeys: string[] }`.

- [ ] **Step 1: Write the failing tests**

```ts
// scripts/lib/dev-secrets.test.ts
import { resolveTarget, validateKeys, renderEnvLocal } from './dev-secrets';

describe('resolveTarget', () => {
  it('uses BAO_ADDR direct URL when set', () =>
    expect(resolveTarget({ BAO_ADDR: 'https://openbao.cmdbee.org' }))
      .toEqual({ mode: 'direct', addr: 'https://openbao.cmdbee.org' }));
  it('falls back to port-forward when unset', () =>
    expect(resolveTarget({})).toEqual({ mode: 'port-forward' }));
});

describe('validateKeys', () => {
  it('passes when all required keys present', () =>
    expect(validateKeys({ gitea_token: 'x' }, ['gitea_token'])).toEqual({ ok: true, missing: [] }));
  it('reports missing keys', () =>
    expect(validateKeys({}, ['gitea_token'])).toEqual({ ok: false, missing: ['gitea_token'] }));
});

describe('renderEnvLocal', () => {
  it('maps kv keys to env vars and lists present keys without values', () => {
    const r = renderEnvLocal({ gitea_token: 'super-secret' }, { gitea_token: 'GITEA_TOKEN' });
    expect(r.content).toBe('GITEA_TOKEN=super-secret\n');
    expect(r.presentKeys).toEqual(['gitea_token']);
  });
});
```

- [ ] **Step 2: Run, verify fail**

Run: `yarn jest scripts/lib/dev-secrets.test.ts` → FAIL (module missing).

- [ ] **Step 3: Implement**

```ts
// scripts/lib/dev-secrets.ts
export function resolveTarget(env: Record<string, string | undefined>):
  { mode: 'direct'; addr: string } | { mode: 'port-forward' } {
  return env.BAO_ADDR ? { mode: 'direct', addr: env.BAO_ADDR } : { mode: 'port-forward' };
}

export function validateKeys(data: Record<string, string>, required: string[]) {
  const missing = required.filter((k) => !(k in data));
  return { ok: missing.length === 0, missing };
}

export function renderEnvLocal(data: Record<string, string>, mapping: Record<string, string>) {
  const presentKeys = Object.keys(mapping).filter((k) => k in data);
  const content = presentKeys.map((k) => `${mapping[k]}=${data[k]}\n`).join('');
  return { content, presentKeys };
}
```

- [ ] **Step 4: Run, verify pass**

Run: `yarn jest scripts/lib/dev-secrets.test.ts` → PASS.

- [ ] **Step 5: Write the thin bash orchestrator**

`scripts/dev-secrets` (bash): resolve target (export `BAO_ADDR` or `kubectl -n openbao port-forward svc/openbao 8200:8200 &`), `bao login -method=oidc`, `bao kv get -format=json secret/leidangr/dev`, pipe the JSON `.data` into a small node call that imports the lib functions, validates `['gitea_token']`, writes `.env.local` from `renderEnvLocal`, and prints the present-keys summary. Refuse to write on validation failure (non-zero exit).

- [ ] **Step 6: Commit**

`git add scripts && git commit -m "feat(secrets): tested dev-secrets target/validate/render logic + bao orchestrator"`.

---

## Task 6: Gitea integration + Checkpoint 2 acceptance (mocked)

**Files:**
- Modify: `components/leidangr/app-config.yaml` (gitea integration + static location, `$env` token)
- Create: `components/leidangr/tests/acceptance/checkpoint-2-openbao-gitea.feature` (copied)
- Create: `components/leidangr/tests/acceptance/checkpoint-2.steps.ts`

**Interfaces:**
- Consumes: `resolveTarget`, `validateKeys`, `renderEnvLocal` (Task 5).
- Produces: passing Checkpoint-2 BDD scenarios (mocked); `@live` scenario tagged for manual runs.

- [ ] **Step 1: Wire the Gitea integration (token via `$env`)**

```yaml
# app-config.yaml (additions)
integrations:
  gitea:
    - host: gitea.localhost
      token: ${GITEA_TOKEN}
catalog:
  locations:
    - type: url
      target: https://gitea.localhost/leidangr/catalog-seed/raw/branch/main/catalog-info.yaml
```

- [ ] **Step 2: Copy the feature file verbatim**

Copy `.../2026-06-21-leidangr-phase2-features/checkpoint-2-openbao-gitea.feature` to `components/leidangr/tests/acceptance/`.

- [ ] **Step 3: Write step definitions over the Task-5 functions + a mocked catalog**

Map the first four scenarios directly to `resolveTarget`/`validateKeys`/`renderEnvLocal`. For "The catalog ingests the Gitea-sourced entities", use `startTestBackend` with a mocked URL reader returning a two-entity `catalog-info.yaml` and assert both entities appear. Configure jest-cucumber to skip `@live` by default (`tagFilter: 'not @live'`).

- [ ] **Step 4: Run, verify pass (mocked)**

Run: `yarn jest tests/acceptance/checkpoint-2.steps.ts`
Expected: PASS for all non-`@live` scenarios.

- [ ] **Step 5: Commit**

`git add app-config.yaml tests && git commit -m "test(bdd): checkpoint-2 openbao->gitea acceptance (mocked); @live deferred"`.

---

## Task 7: ADRs (MADR v3) for the decisions

**Files:**
- Create: `components/leidangr/docs/adrs/0001-modern-backend-and-frontend.md` … `0006-bdd-from-day-one.md`

**Interfaces:**
- Produces: MADR v3 ADRs capturing each design decision; no plugin wiring (deferred).

- [ ] **Step 1: Write one MADR v3 file per decision**

`0001` modern frontend/backend systems; `0002` SQLite-default stub mode (zero secrets); `0003` OpenBao-via-OIDC `dev-secrets`, app secret-store-agnostic; `0004` Gitea as catalog source (GitHub deferred); `0005` guest auth first (Keycloak sign-in deferred); `0006` BDD-from-day-one over TDD'd tooling. Each: Context / Decision / Consequences, drawn from the design spec.

- [ ] **Step 2: Commit**

`git add docs/adrs && git commit -m "docs(adr): capture skeleton architecture decisions (MADR v3)"`.

---

## Task 8: Live wiring artifacts + realm registration

**Files:**
- Create: `components/leidangr/docs/development/openbao-setup.md` (KV seeding + OIDC role runbook)
- Modify: realm/ecosystem to declare `leidangr` (after green)

**Interfaces:**
- Produces: a reproducible setup for the `@live` scenario + the component declared in the realm.

- [ ] **Step 1: Write the OpenBao setup runbook**

Document: unseal (2-of-3, link the nidavellir runbook); configure the OIDC auth role against the `siliconsaga` Keycloak realm with `allowed_redirect_uris` including `http://localhost:8250/oidc/callback`; `bao kv put secret/leidangr/dev gitea_token=<token>` (read-only Gitea token scope). Mark exact commands; nothing sensitive committed.

- [ ] **Step 2: Seed the Gitea catalog repo**

Create a small Gitea repo `leidangr/catalog-seed` with a `catalog-info.yaml` holding 2–3 entities (the `leidangr` Component itself + one or two examples).

- [ ] **Step 3: Run the @live scenario manually**

With OpenBao unsealed: `make secrets` (complete browser login) → `make dev` → confirm the Gitea entities appear. Run `yarn jest --config <tagFilter @live>` if wired, else verify in-app.

- [ ] **Step 4: Register the component in the realm**

Add `leidangr` to the realm ecosystem (tier 2/3 as appropriate) now that it boots green, following the pattern of existing component declarations.

- [ ] **Step 5: Commit (realm) via ws**

Use `ws commit realm-siliconsaga .commits/<name>.md` for the realm-side registration change.

---

## Self-Review

- **Spec coverage:** §2 component shape → Task 1; §2 envelope → Task 2; §6 BDD → Tasks 3, 6; §3 secrets (agnostic, OIDC, reachability) → Tasks 5, 6, 8; §4 modes (stub default) → Tasks 1, 4; §5 Gitea source → Task 6; §7 ADRs → Task 7; §4 contributor-access (live) → Task 8 runbook + design (out of slice scope, documented); component registration → Task 8. All mapped.
- **Placeholders:** the catalog `startTestBackend` step (Task 3 Step 3/4) is intentionally thin — flagged for execution-time wiring against `@backstage/backend-test-utils`, with the `testing.md` doc as its companion; all pure-logic tasks carry full code.
- **Type consistency:** `runDoctor`/`ToolCheck`/`DoctorDeps` (Task 2) and `resolveTarget`/`validateKeys`/`renderEnvLocal` (Task 5) are referenced with identical signatures in their consuming BDD tasks (3, 6).

---

## Notes for the executor

- **create-app is interactive** (prompts for the app name) — Task 1 cannot run fully unattended. Do not background it.
- **OpenBao is currently sealed** — Tasks 1–7 need no cluster. Only Task 8's `@live` step needs an unseal (2-of-3 shares per the nidavellir runbook).
- Until the component is realm-registered (Task 8), commit with plain `git` **inside** `components/leidangr/`; realm-side changes use `ws commit realm-siliconsaga`.
