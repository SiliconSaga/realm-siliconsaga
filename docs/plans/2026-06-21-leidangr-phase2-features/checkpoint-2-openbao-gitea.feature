Feature: Checkpoint 2 - secrets flow from OpenBao and entities load from Gitea
  As a developer wiring the real inner loop
  I want a Gitea token retrieved from OpenBao to authenticate the catalog source
  So that Backstage ingests real entities with no secret living in the repo

  Scenario: dev-secrets renders .env.local from an OpenBao KV response
    Given an OpenBao KV response containing a "gitea_token" key
    When dev-secrets renders the local environment file
    Then the rendered file sets GITEA_TOKEN to the gitea_token value
    And the summary reports gitea_token as present without printing its value

  Scenario: dev-secrets fails clearly when a required key is missing
    Given an OpenBao KV response missing the "gitea_token" key
    When dev-secrets validates the required keys
    Then validation fails
    And it reports that the required key "gitea_token" is missing
    And no environment file is written

  Scenario: dev-secrets selects the target without the app knowing
    Given the BAO_ADDR environment variable is set to a direct URL
    When dev-secrets resolves the OpenBao target
    Then it uses the direct URL
    And it does not start a port-forward

  Scenario: dev-secrets falls back to a port-forward when no direct URL is set
    Given the BAO_ADDR environment variable is not set
    When dev-secrets resolves the OpenBao target
    Then it selects the port-forward target

  Scenario: The catalog ingests the Gitea-sourced entities
    Given a Gitea catalog location holding two entities
    And a GITEA_TOKEN available in the environment
    When the backend starts and processes the location
    Then both Gitea-sourced entities appear in the catalog

  @live
  Scenario: The real end-to-end loop against a live OpenBao and Gitea
    Given OpenBao is unsealed and reachable
    And Keycloak is reachable for OIDC login
    When I run "make secrets" and complete the browser login
    And I start Backstage with the rendered .env.local
    Then the catalog shows the entities from the live Gitea repository
