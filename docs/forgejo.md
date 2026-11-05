# Forgejo in the SiliconSaga Stack

Forgejo is the stack's own Git server: the place the cluster will read its configuration from once it has grown up. This page explains what it is for, what it changes for you, and how to use it. Operating it — Jobs, tokens, teardown, troubleshooting — is in nidavellir's [Forgejo runbook](https://github.com/SiliconSaga/nidavellir/blob/main/docs/forgejo.md). Why it is built this way is in the [day-2 design](plans/2026-09-07-forgejo-day2-design.md) and its [Phase 2 design](plans/2026-09-19-forgejo-day2-phase2-design.md).

## Why the stack needs its own Git server

ArgoCD needs a Git server it can always reach. Today that is the **seed Gitea**: a small, deliberately disposable Gitea that `nordri/bootstrap.sh` creates on every cluster so ArgoCD has something to sync from on day one. It keeps nothing on disk, so every time its pod is replaced the repositories vanish and every Application drops to `Unknown` until someone re-hydrates it. On GKE that has happened several times, once costing sixteen hours of dead GitOps.

Forgejo is the durable replacement: same job, but with persistent storage, a real database, credentials kept in OpenBao, and a process that keeps it in step with GitHub on its own.

## Where the truth lives

| | Owns | You use it for |
|---|---|---|
| **GitHub** | `main` of every repository, and all code review | Pull requests, as today. Nothing about review changes. |
| **Forgejo** | A copy of `main`, refreshed by the *puller* (hourly unless the cluster-identity sets `pullerSchedule`); anything else you push to it | What ArgoCD reads (from Phase 3); a place to push a branch and try it on a cluster |
| **Seed Gitea** | Nothing lasting | Getting a brand-new cluster to its first sync |

The rule that keeps this simple: **only the puller writes Forgejo's `main`**, and it only ever copies GitHub's. Once ArgoCD reads Forgejo (Phase 3), merging on GitHub reaches the cluster by the puller's next run, with no hydration step. No GitHub credential exists anywhere in the stack — the repositories are public and the puller fetches anonymously.

Third-party repositories the stack depends on (today `keycloak-k8s-resources`, whose release tags the Keycloak operator is pinned to) are kept as read-only Forgejo pull-mirrors, so a cluster never needs to reach out to them at sync time.

## Maturity: when a cluster gets Forgejo

Every cluster carries a `maturity` value on its cluster-identity:

- **`bootstrap`** — what `bootstrap.sh` always produces. Seed Gitea only. Forgejo's pieces are installed but render nothing. The alert for ArgoCD losing its Git source (Phase 2) needs nothing from Forgejo, so it is active here too. Throwaway Docker Desktop clusters stay here.
- **`durable`** — Forgejo runs. Phase 3 switches ArgoCD over to it, and Phase 4 adds restore drills for its backups.
- **`full`** — later: single sign-on through Keycloak, Harbor and Backstage.

Graduating a cluster starts with a one-line change to its cluster-identity, hydrated in, which brings Forgejo up. ArgoCD keeps reading the seed Gitea until an operator runs the Phase 3 cutover. Once Forgejo's resources exist, going back down is refused unless the Forgejo claim says `allowTeardown: true`, so lowering maturity by accident cannot delete repositories. A cluster that never brought Forgejo up has nothing to lose and steps down freely.

## What a durable cluster looks like

| | Homelab | GKE |
|---|---|---|
| Address | `https://forgejo.homelab.local` | `https://forgejo.cmdbee.org` (covered by the existing wildcard DNS and certificate) |
| Repository storage | `local-path` | persistent disk |
| Database | the shared Mimir PostgreSQL | the shared Mimir PostgreSQL |
| Backups | not yet — homelab backups are an open decision | Velero disk snapshots, plus pgBackRest to Cloud Storage. Both already cover GKE's other data. Restoring Forgejo from them stays unproven until the Phase 4 drills. |

The organisation is `siliconsaga`. It holds the five maintained repositories (`nordri`, `nidavellir`, `mimir`, `heimdall`, `realm-siliconsaga`) and the vendor mirror. Which repositories exist is decided by one realm file, [`cluster/forgejo/claim.yaml`](../cluster/forgejo/claim.yaml); the platform never hard-codes them.

## Using it

**Logging in.** Your account is a *break-glass* admin: its password was generated inside the cluster and written to OpenBao, so nobody ever typed or saw it. To read it without printing it to your terminal:

```bash
umask 077; d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT INT TERM
kubectl get secret -n forgejo forgejo-admin-cervator -o jsonpath='{.data.password}' | base64 -d > "$d/pw"
# paste from "$d/pw" into the login form; the file goes when this shell exits, or sooner with: rm -r "$d"
```

On a homelab, `forgejo.homelab.local` does not resolve by itself: map it in your hosts file to the address where the cluster's ingress listens. The homelab certificate is self-signed, so check it before you type the password: the SHA-256 fingerprint your browser shows must match `kubectl get secret -n kube-system traefik-gateway-default-cert -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -fingerprint -sha256`. If you cannot check it, use the port-forward below. On Docker Desktop's built-in Kubernetes that is `127.0.0.1` on port 443, so `https://forgejo.homelab.local` works as is. The k3d cluster from [dev-setup](dev-setup.md) also listens on `127.0.0.1`, but publishes HTTPS on 8443, so use `https://forgejo.homelab.local:8443`. A homelab on another machine needs that machine's address. Wherever the ingress is, `kubectl port-forward -n forgejo svc/forgejo-http 3000:3000` and `http://localhost:3000` always work.

**Pushing a branch to try it.** Any branch other than `main` is yours to push. For pushes from a workstation, mint a personal access token under your Forgejo user settings with the `write:repository` scope and keep it as `FORGEJO_TOKEN` in the yggdrasil workspace's `.env`, beside `GH_TOKEN`. That file sits at the workspace root, outside this repository, and yggdrasil's `.gitignore` excludes it. Never put it in a `.env` inside a component or realm checkout. Hand it to Git through a credential helper, never in a remote URL or on a command line, where it would land in `.git/config` or shell history. Do not use the admin password for Git. Phase 3 adds a helper that does this for you and a hydration flow that temporarily points a cluster at your branch.

**What you should not do.** Push to `main` on Forgejo. Branch protection lets the admin and break-glass accounts push there (it is how the puller works), but a commit on Forgejo's `main` that GitHub does not have puts the two out of step: the puller's next push is no longer a fast-forward, Forgejo refuses it, and that repository stops syncing until someone resets it. Change `main` on GitHub instead.

## What can go wrong, and what tells you

- **A puller run fails.** Usually GitHub or the network for a moment; the next scheduled run catches up. A failed run raises the generic Kubernetes Job-failure alert.
- **ArgoCD cannot reach its Git source.** Applications sit in `Unknown` while still claiming `Healthy` — the exact failure the seed wipes caused. Heimdall's `ArgoCDApplicationUnknown` alert fires once an Application has been `Unknown` for five minutes. With the rule evaluated once a minute and Alertmanager's 30-second group wait, the page can take up to about six and a half. It applies on any cluster that has the Phase 2 changes hydrated.
- **Forgejo itself is lost.** `main` can always be rebuilt from GitHub by the puller. Anything that exists only in Forgejo — your branches, accounts, tokens — depends on backups. GKE has the mechanisms in place, but no Forgejo restore has been tried until the Phase 4 drills. Homelab still needs a decision.

## Where this is going

| Phase | State |
|---|---|
| 0 — slim the seed so a wipe costs one rehydrate | done |
| 1 — OpenBao auto-unseal, the `maturity` field | done |
| 2 — Forgejo, its credentials, the puller, the ArgoCD alert | done, validated on homelab |
| 3 — point ArgoCD at Forgejo, `graduate.sh`, GKE cutover | next |
| 4 — backups and restore drills, retire the seed | after the cutover |
| 5 — `full`: single sign-on and the rest | later |
