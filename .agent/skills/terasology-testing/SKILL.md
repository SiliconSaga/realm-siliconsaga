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
