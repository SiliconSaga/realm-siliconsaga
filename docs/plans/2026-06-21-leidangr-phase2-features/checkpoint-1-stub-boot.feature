Feature: Checkpoint 1 - Backstage boots in stub mode with zero secrets
  As a developer who just cloned the leidangr repo
  I want Backstage to start with no external services or secrets
  So that the inner loop works offline and in CI

  Background:
    Given a freshly installed leidangr workspace
    And no .env.local file is present
    And neither OpenBao nor Gitea is reachable

  Scenario: The development config is valid without any secrets
    When I run the configuration check for the development config
    Then the configuration check succeeds
    And no secret values are required to load it

  Scenario: doctor reports the local toolchain without leaking secrets
    When I run the doctor command
    Then it reports the status of Node, Yarn, and the required dev ports
    And it never prints any secret values

  Scenario: The catalog serves the generated example entities in stub mode
    Given the backend is started in stub mode with guest auth
    When I query the catalog for all entities
    Then the generated example component is present
    And the request is authorized as the guest identity
