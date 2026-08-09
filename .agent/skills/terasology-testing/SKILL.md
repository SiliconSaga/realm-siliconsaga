---
name: terasology-testing
description: >
  Patterns for writing engine-level and MTE integration tests in Terasology.
  Use when creating, debugging, or reviewing tests for the Terasology engine.
---

# Terasology Testing Skill

Guidance for writing tests against the Terasology engine, especially
integration tests using the ModuleTestingEnvironment (MTE).

## When to Use

- Writing new engine or integration tests
- Debugging test failures (especially network/multiplayer)
- Reviewing test PRs for correctness
- Deciding which test level is appropriate for a change

## Reference

Read the full patterns doc before writing tests:

**`components/terasology/docs/Engine-Testing-Patterns.md`**

It covers:
- Test hierarchy (unit → integration → multiplayer)
- MTE setup (`@IntegrationEnvironment`, `@In` injection, `ModuleTestingHelper`)
- Network event testing — why inner-class events don't replicate and what to use instead
- Context/CoreRegistry isolation
- Service vs System distinction
- Gradle execution patterns (`cleanTest`, subproject targeting)

## Quick Reference

### Choose the right level

| What you're testing | Level |
|---|---|
| Pure logic, no engine deps | Unit test with mocks |
| Context, registry, injection | Unit test with `ContextImpl` |
| Entity/event behavior | MTE `@IntegrationEnvironment` |
| Client-server interaction | MTE with `NetworkMode.LISTEN_SERVER` |

### Share one engine per test class

Building an MTE engine costs ~20s. By default JUnit creates a new test instance
per method, and `MTEExtension` keys its engine on that instance — so each test
method builds its own engine. Add:

```java
@IntegrationEnvironment(dependencies = {"MyModule"})
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public class MyModuleTest { ... }
```

and the whole class shares one. `MTEExtensionTestWithPerClassLifecycle` in
engine-tests is the reference. The module-side MTE defaulted to this and had
`IsolatedMTEExtension` to opt out; the engine variant deliberately replaced that
machinery with JUnit's own annotation (#5039), so the capability is the same but
you have to ask for it.

**The bug this used to dodge is fixed — do not reach for it on those grounds.**
Until #5348 landed (2026-08-01), chunk generation stalled once a JVM had built
enough engines, and sharing one engine per class avoided building the extra
ones. ItemPipes now runs 3/3 with the annotation removed. What remains is a
performance tradeoff (~20s per extra engine), not a correctness requirement.

**And it costs isolation.** `MTEExtension` tears its engine down when the
extension context closes, not between test methods, so a shared engine carries
entity, component and world state from one test into the next. Reach for
`PER_CLASS` when a class's tests are read-only or share state deliberately.
When a test needs a clean world, keep the default lifecycle or add explicit
per-test cleanup — a passing suite that depends on method order is the failure
mode here, and it surfaces later, on someone else's machine.

### Key gotchas

- **Use `@In`, not `@Inject`** in MTE test classes — the harness uses `InjectionHelper`
- **Inner-class `@BroadcastEvent`/`@OwnerEvent`/`@ServerEvent` don't network-replicate** — use existing engine events or `TestEventReceiver` for local tests
- **Clean the task you are actually running.** Gradle derives one clean task per test task, so `cleanTest` clears `test` and nothing else. `engine-tests` also defines `unitTest`, `integrationTest`, `integrationTestFlaky`, `integrationTestDiagnostic` and `filesystemSideEffectTest` — pair each with its own `cleanUnitTest` / `cleanIntegrationTest` / etc., or use `--rerun`. Stale cache otherwise serves old failures
- **Register post-init probes with both** `ComponentSystemManager` and `EventSystem`
- **Read the test XML, not the exit code.** A Gradle run under `-q` has reported
  exit 0 with failing tests, and a task reporting `UP-TO-DATE` silently serves
  the previous run's results. Check
  `build/test-results/**/TEST-*.xml` and use `--rerun`.

> ### ⚠ MTE exists twice — keep both in sync
>
> There are two copies of ModuleTestingEnvironment:
>
> | Variant | Package |
> |---|---|
> | engine-tests | `org.terasology.engine.integrationenvironment` |
> | module | `org.terasology.moduletestingenvironment` |
>
> **When reviewing or changing anything MTE-related, check both** and carry
> discoveries across. They have already drifted — e.g. the engine variant
> replaces the global `CoreRegistry` context with a wrapper on setup while the
> module variant mutates the existing one, so only the engine variant
> accumulates contexts from shut-down engines across a test class.
>
> This is temporary. The intent is a single unified MTE — plausibly as a
> `gestalt-engine` component if Gestalt grows one — but until that lands, the
> duplication has to be maintained by hand. Note any divergence you find rather
> than fixing only the copy in front of you.

### Running tests

```bash
# Via ws CLI (recommended — auto-discovers subproject, clears cache)
ws test terasology MyTestClass

# Direct Gradle
./gradlew :engine-tests:cleanTest :engine-tests:test --tests "*.MyTestClass"
```

## Existing Test Examples

Good reference tests in `engine-tests/.../integrationenvironment/`:
- `ClientConnectionTest` — basic multiplayer client creation
- `ComponentSystemTest` — entity/event smoke test
- `ExampleTest` — comprehensive MTE demo with LISTEN_SERVER
- `TestEventReceiverTest` — local event testing pattern
