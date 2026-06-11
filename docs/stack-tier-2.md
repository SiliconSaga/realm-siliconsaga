# SiliconSaga — Tier 2 (Platform Services)

Platform-level capabilities every end-user app builds on. Deployed through Nordri's ArgoCD; consumed by Tier 3.

See also: [`stack.md`](stack.md) (overview + tier map), [`stack-tier-1.md`](stack-tier-1.md), [`stack-tier-3.md`](stack-tier-3.md).

---

## Nidavellir — The Forge (platform app-of-apps)

> *The dark fields where the dwarves forge the most powerful treasures of the gods.*

Repo: `components/nidavellir` ([SiliconSaga/nidavellir](https://github.com/SiliconSaga/nidavellir))

Nidavellir is the Tier 2 app-of-apps. Its `apps/` directory holds Application manifests for services that are platform-wide rather than component-owned:

- `vegvisir/` — Vegvísir Operator: shared Traefik Gateway + cert-manager wiring + TLS termination + (future) per-service routing standards
- `ntfy/` — phone-push notification destination + server-side template (`heimdall-template.yaml`)
- `tailscale-operator/` — Tailscale Kubernetes operator
- `openbao/` — secrets management: OpenBao composition + the ESO `ClusterSecretStore` wiring (Leiðangr Phase 1a)
- `external-secrets/` — External Secrets Operator (direct Helm app; delivers OpenBao values as plain Kubernetes Secrets)
- `keycloak/` — identity / SSO (planned, Leiðangr Phase 1b — will consume a Mimir Postgres claim and hold its credentials via OpenBao/ESO)

Adding a brand-new platform service that isn't owned by any one component? This is where it goes. New manifests get picked up by ArgoCD on the next sync (subject to the re-hydration step from `stack.md`'s GitOps section).

### The Secrets Path (a second Tier 2 narrative)

Like the alert pipeline below, the secrets path crosses ownership lines, so here's the shape:

```text
1. Operator writes a value: bao kv put secret/<path> (OpenBao, ns openbao)
2. A workload's namespace declares an ExternalSecret CR referencing
   the cluster-scoped openbao-kv ClusterSecretStore
3. ESO (ns external-secrets) authenticates to OpenBao via Kubernetes
   auth (no static credential) and reads the value
4. ESO materializes + refreshes a plain Kubernetes Secret next to the
   workload — which never knows OpenBao exists
```

The beginner-trap to know up front: **a restarted OpenBao pod always comes back sealed** (`0/1 Running`) and waits for a manual unseal — that's the design, not a failure. The full explainer ("sealing from zero", put/consume how-to, unseal + init runbooks, the KV v2 `data/` path gotcha, test-vs-live key custody) lives in nidavellir: [`components/nidavellir/docs/secrets-management.md`](../../../components/nidavellir/docs/secrets-management.md). Decision records: [`adrs/`](adrs/) 0001–0003.

---

## Heimdall — The Watcher (observability)

> *The vigilant guardian who watches for the coming of the giants.*

Repo: `components/heimdall` ([SiliconSaga/heimdall](https://github.com/SiliconSaga/heimdall))

The observability stack:

- **Prometheus** — metrics scrape + rule evaluation
- **AlertManager** — alert routing
- **Grafana** — dashboards (admin password via `existingSecret`, not plaintext in helm values)
- **Loki** — logs
- **Tempo** — traces
- **Thanos** (planned) — long-term metric storage

Heimdall ships the `kube-prometheus-stack` Helm chart with adjustments: noisy default `*Down` rules disabled for managed-K8s control planes (which don't expose `kube-controller-manager`, `kube-scheduler`, etc.), single-replica RWO Deployments use `strategy: Recreate` to avoid Multi-Attach deadlock, and on GKE there's a Cloud Logging dual-stack-cost discipline section (drop fluent-bit-GKE meta-chatter so you don't double-pay for ingestion of your own observability stack's noise).

The opinionated choices: **AlertManager** (not Grafana-managed alerting) for routing, and **ntfy** (in Nidavellir) as the notification destination.

Component skills:

- [`alertmanager-config`](../../../components/heimdall/.agent/skills/alertmanager-config/SKILL.md) — routing trees, the Watchdog dead-man's-switch idiom, webhook payload + header templating, `amtool` validation.
- [`kube-prometheus-stack`](../../../components/heimdall/.agent/skills/kube-prometheus-stack/SKILL.md) — chart wiring, `release:` label requirement on `ServiceMonitor`/`PrometheusRule`, RWO `Recreate` strategy, GKE dual-stack-cost recipe.

---

## Mimir — The Rememberer (data services)

> *The wise one who keeps the Well of Knowledge.*

Repo: `components/mimir` ([SiliconSaga/mimir](https://github.com/SiliconSaga/mimir))

Database and messaging services via Crossplane Compositions. Components don't run their own Postgres; they file a Claim against Mimir's API and Mimir's Composition provisions the actual operator-managed instance.

- **Postgres** (Percona PG operator)
- **MySQL** (Percona MySQL operator)
- **MongoDB** (Percona Server for MongoDB operator)
- **Kafka** (Strimzi operator)
- **Valkey** (Redis-compatible KV)

The Composition reads `cluster-identity` (see `stack.md` → Cluster Identity) to branch on environment — homelab uses Longhorn-backed PVCs and modest replica counts; GKE uses PD-backed storage and HA replication. Same Claim YAML lands the right shape in either environment.

---

## Vörðu — The Cairn (BDD roadmap visualization)

> *A landmark cairn — visible across the landscape.*

Repo: `components/vordu` ([SiliconSaga/vordu](https://github.com/SiliconSaga/vordu))

A Node.js web app that visualizes the matrixed roadmap dynamically. Reads BDD `.feature` files across the realm's components and renders progress/dependencies as a navigable map.

---

## Tafl — The Game Board (game server orchestration)

> *The Norse strategy game played on a checkered board.*

Repo: `components/tafl` ([SiliconSaga/tafl](https://github.com/SiliconSaga/tafl))

Manages the lifecycle of game servers. Deploys Agones (Kubernetes-native game server hosting) through ArgoCD; the Tafl API instructs Agones to spawn servers; Vegvísir routes traffic to the game servers; Crossplane connects the servers to S3 buckets for world data.

---

## Bifrost — The Bridge (cross-game federation)

> *The rainbow bridge connecting realms.*

Repo: `components/bifrost` ([SiliconSaga/bifrost](https://github.com/SiliconSaga/bifrost))

A federated game-metaverse bridge connecting engines (Java/Terasology, Godot, etc.) over WebSocket. Built on Agones for the server-side runtime. Currently the most aspirational of the Tier 2 services — moves on the user's research cadence rather than the platform's.

---

## The Alert Pipeline — End-to-End (a Tier 2 narrative)

A real example of how the Tier 2 pieces collaborate, since the alert path crosses three components:

```text
1. Your component fires a PrometheusRule (labeled `release: <chart-release>`)
2. Prometheus (Heimdall) scrapes + evaluates
3. AlertManager (Heimdall, ns `monitoring`) routes by `severity` label
4. webhook_configs receiver POSTs default envelope
5. ntfy (Nidavellir, ns `ntfy`) receives — URL `?template=<name>` triggers
   server-side templating; severity → priority mapping happens HERE
6. ntfy push to your phone
```

Component ownership of each segment:

- **The rule** — your component. Forget the `release:` label and the Operator's selector silently ignores the rule (the #1 silent-invisibility cause).
- **Prometheus + AlertManager** — Heimdall.
- **ntfy receiver + server-side template (`heimdall-template.yaml`)** — Nidavellir.
- **Phone subscription** — out-of-band, user-side.

The "wait, where does severity become priority?" answer: in Nidavellir's ntfy template, NOT in AlertManager. This is the gotcha worth memorizing.

---

## Dependencies on / from this tier

- **Below:** every Tier 2 service deploys *through* Nordri's ArgoCD (Tier 1) and (where data-backed) consumes Crossplane Claims fulfilled by Mimir's Compositions.
- **Above:** Tier 3 end-user applications hook into Heimdall for observability, Mimir for databases, Vegvísir for ingress, and Nidavellir's ntfy for alert delivery.
