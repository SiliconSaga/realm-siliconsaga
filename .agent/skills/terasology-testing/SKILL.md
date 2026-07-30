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

### Key gotchas

- **Use `@In`, not `@Inject`** in MTE test classes — the harness uses `InjectionHelper`
- **Inner-class `@BroadcastEvent`/`@OwnerEvent`/`@ServerEvent` don't network-replicate** — use existing engine events or `TestEventReceiver` for local tests
- **Always `cleanTest` for targeted Gradle runs** — stale cache serves old failures
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
