# Forgejo day-2 — Phase 3 design: the URL train, the promotion ladder, and the GKE cutover

**Status:** Draft, in brainstorm. Decisions 1 and 2 settled on 2026-11-10 (cluster roles and a promotion ladder; a `live` branch for GKE; canonical and vendor orgs only). Next: item 3, URL train mechanics.
**Date:** 2026-11-06
**Owner:** Rasmus Praestholm
**Parent:** [Forgejo day-2 design](2026-09-07-forgejo-day2-design.md) (design of record; this document settles Phase 3's open points and records where the record no longer holds) · [Phase 2 design](2026-09-19-forgejo-day2-phase2-design.md)

## Where Phase 3 starts from

Phase 2 is merged and validated. On 2026-11-06 the owner tested it by hand on the Nano76 Docker Desktop cluster: logged in as the break-glass account, found the five maintained repositories and the vendor mirror, and edited a file on Forgejo's nordri `main` through the web UI. The next puller run was refused ("branch main is protected from force push"), the other four repositories synced, and the Job failed. That is the failure [`docs/forgejo.md`](../forgejo.md) describes. Recovering took three steps: delete the `main` rule, run the puller once (its `--force-with-lease` then reset `main` to GitHub's), and recreate the rule with a one-off copy of the configure Job.

Facts this design builds on, checked on 2026-11-06 and 2026-11-10:

- **Forgejo has no force-push allowlist.** A protected branch refuses non-fast-forward pushes from every account, admins included, and the branch-protection API has no field to change that (Phase 2 plan, confirmed live above). The design of record's local-branch flow assumed "the account is on the `main` and force-push allowlists"; that sentence cannot be implemented.
- **18 ArgoCD Application manifests carry an in-cluster Git URL**, all still in the seed form: nordri 5 (`platform/root-app.yaml`, `platform/argocd/{app-of-apps,nidavellir-apps,realm-root-app.template}.yaml`, `platform/fundamentals/apps/garage.yaml`), nidavellir 10 (`apps/*`), mimir 3 (`argocd/apps/*`). The record counted sixteen. Every one of them tracks `targetRevision: HEAD`; the pinned revisions in the tree are all Helm chart versions on public chart repositories.
- **A child Application does not inherit its parent's revision.** The Applications form nested app-of-apps, so pointing one repository at a topic branch means changing every child of that repository, and a parent with `selfHeal` reverts a hand-edited child within minutes.
- **`lib/patch-urls.sh` already has the three modes** (`seed`, `forgejo`, `swap`) and fails closed on a URL of the wrong kind. The train only flips what is committed; the rewrite then becomes live instead of a no-op.
- **The root Application is applied directly, not synced.** `bootstrap.sh` copies `platform/root-app.yaml`, runs it through `patch_repo_urls_file`, and `kubectl apply`s it, as it does the rendered realm root-app.
- **Bootstrap already deploys local checkouts.** `update-embedded-git.sh` hydrates the whole set (nordri, the nidavellir/mimir/heimdall components, the vendor mirrors and the realm) from the working trees on every run, and since nordri#41 it hard-refreshes every Application afterwards. A `bootstrap`-maturity cluster can therefore run any mix of topic branches with no new code.
- **`ecosystem.yaml` carries no refs.** Its component entries hold a tier and nothing else, so a per-cluster bill of materials would be new (see "Later arcs").
- **Maturity:** homelab's identity is committed at `durable`; GKE's is `bootstrap`. GKE graduation is therefore also Forgejo's first run on GKE, with KMS-unsealed OpenBao, persistent disk and the GKE wildcard certificate.

## Scope

Phase 3 delivers, per the record's phasing table:

1. The coordinated URL train (nordri, nidavellir, mimir, realm `ecosystem.yaml`), with the `nordri-admin` → `siliconsaga` org rename and the vendor org move riding along.
2. A way to test an unmerged change before it reaches a prod cluster (Decision 1: the promotion ladder).
3. The `live` branch and the promotion step that feeds GKE (Decision 1).
4. `graduate.sh`: preconditions, the swap commit, rollback, and `--retire-seed`'s gates.
5. GKE graduation and cutover, then the soak.

Pulled in from Phase 2's out-of-scope list: the Heimdall blackbox probe on Forgejo's `/api/healthz`, now that a real hostname exists. Parked for this design to place: the owner's request (2026-11-06) for a Grafana sync dashboard and a mid-range sync-failure alert, since the divergence above was visible only in Job logs.

Out of scope: restore drills and Velero scope (Phase 4, which gains the cross-site backup requirement below), `full` maturity (Phase 5), SSH access, the cluster BOM (its own arc).

## Terms

Each term answers one question. Keeping them apart is what stops "environment" from meaning three things.

| Term | Answers | Examples | Declared in |
|---|---|---|---|
| **Site** | Where is the hardware or provider? | `homelab`, `gke` | realm config |
| **Cluster** | Which Kubernetes cluster? | `homelab-prod`, `homelab-test`, `gke-prod`, `homelab-<hostname>` for a lab machine | its cluster-identity |
| **Maturity** | How durable is this cluster's platform? | `bootstrap`, `durable`, `full` | cluster-identity, per cluster |
| **Role** | What is this cluster for? | `lab`, `test`, `prod` | cluster-identity, per cluster |
| **Source ref** | Which GitHub branch does this cluster's Forgejo mirror? | `main`, `live` | cluster-identity, per cluster |

Every cluster that reaches `durable` runs its own Forgejo. A site can hold several clusters (the homelab server is expected to run `homelab-prod` and `homelab-test`), and none of them reads another cluster's Forgejo. Maturity and role are independent: a test cluster may be `durable` to exercise the durable layer, and a prod cluster may still be `bootstrap` while it graduates, as GKE is today.

## Decisions

### Decision 1 (settled 2026-11-10): changes climb a ladder of clusters, and GKE follows a `live` branch

A change is tested on clusters that exist to be broken, merged on GitHub, soaked on `homelab-prod`, and then promoted to GKE.

| Step | Cluster | Role | Maturity | Runs | Fed by |
|---|---|---|---|---|---|
| 1 | `homelab-<hostname>`, a lab machine | `lab` | `bootstrap` | local checkouts | seed Gitea, by bootstrap / hydration |
| 2 | `homelab-test` (recycled at will) | `test` | `bootstrap`, or `durable` when testing the durable layer | local checkouts or topic branches | seed Gitea, or its own Forgejo by hydration |
| — | *merge the PRs on GitHub* | | | | |
| 3 | `homelab-prod` | `prod` | `durable` | GitHub `main` | its Forgejo; pullers follow `main`; the change soaks here |
| — | *`ws promote gke`: fast-forward `live` to the soaked commit* | | | | |
| 4 | `gke-prod` | `prod` | `durable` | GitHub `live` | its Forgejo; pullers follow `live` |

What this settles:

- **Lab and test clusters carry no real workloads.** They are recycled whenever a test calls for a clean start, so nothing on them is backed up and nothing outside them depends on them.
- **A test cluster's own Forgejo is its scratch space.** When `homelab-test` runs at `durable`, its canonical org is fed by hydration from working trees: unprotected, no puller. The cluster's `role: test` is what tells the composition to skip protection and the puller. No separate scratch org exists, and no prod cluster is ever repointed at a test source, so there is no forgotten test to alert on.
- **Lab clusters are named `homelab-<hostname>`.** Any spare machine can run one; the homelab server runs `homelab-prod` and `homelab-test`.
- **`main` is what homelab runs; `live` is what GKE runs.** Each cluster's identity names its source ref, and its pullers mirror that GitHub branch into Forgejo's `main`. Applications keep `targetRevision: HEAD`, so no manifest changes per cluster. The asymmetry is deliberate: `main` quietly means "homelab prod", and `live` means "promoted after the homelab soak".
- **Promotion happens on GitHub.** `live` is a protected GitHub branch in every maintained repository, moved only by fast-forward. `ws promote gke` fast-forwards all of them together to the commits homelab soaked, so GKE always receives a set that ran together. It refuses if any repository's `live` is not an ancestor of the target, and it records the promoted commits in its output for the arc notes.
- **GKE-only changes take a GKE test cluster.** Changes that only run on GCP (the GKE Velero setup, KMS unseal, the wildcard certificate) are not exercised by the homelab soak. A risky one gets a temporary `gke-test` cluster: step 2 of the ladder, run on GCP, torn down after.
- **Backups cross sites around a promotion.** Homelab backs up before and after a change and uploads to GCP; GKE backs up before and after its promotion, to its own buckets and to homelab. That is a requirement placed on Phase 4's Velero scope, not built here.

The options weighed before the ladder, kept as the record:

- **D — a scratch org per tester, hydrated and repointed at.** Superseded: the ladder puts testing on clusters that exist for it, so a prod cluster never reads a scratch org.
- **A — a test branch and a retargeted `targetRevision`.** Rejected: needs a YAML-aware rewrite of every child, keyed on the sibling `repoURL`, because `targetRevision` also pins chart versions.
- **B — remove protection around a test push.** Rejected: `main` diverges from GitHub for the whole test, and the puller stops being the only writer.
- **C — keep the seed as the permanent test target.** Partly kept: the seed remains the source for `bootstrap`-maturity lab and test clusters, but no durable cluster keeps it.
- **Retarget running Applications with `argocd app set --revision`.** Rejected as a mechanism: parents with `selfHeal` revert it, and it leaves no record. Acceptable as a hand poke at a single leaf on a test cluster.
- **GKE lagging by a release tag, or by turning off auto-sync.** Rejected for a branch: tags need the puller to resolve "newest", and manual sync leaves GKE showing OutOfSync whenever it lags.

### Organisation layout

These rules hold for every org on every cluster's Forgejo.

1. **An org is a trust class, not a folder.** Protection, writers, retention and backup are decided per org, never per repository.
2. **A protected org mirrors a GitHub ref, written only by a puller.** Work never starts on Forgejo and is never promoted between orgs or Forgejos; promotion is a GitHub branch moving.
3. **An unprotected org is disposable.** It holds nothing that cannot be recreated by hydrating again. It exists only on clusters whose role is `lab` or `test`.
4. **Names are `<realm>-<class>`, except the canonical org,** which keeps the bare realm name (`siliconsaga`) because every committed repoURL names it.
5. **The realm declares orgs; nidavellir never names one.** The claim's single `org` field becomes an `orgs` list with a `class` on each entry, and the configure Job reconciles them as it does today's single org.
6. **Least privilege comes from accounts.** Forgejo token scopes go by category, not by org, so each puller-written class gets its own bot account, a member only of the orgs it writes.

### Decision 2 (settled 2026-11-10): Phase 3 builds the canonical and vendor orgs

| Class | Org | Fed by | Protection | Clusters |
|---|---|---|---|---|
| **canonical** | `siliconsaga` | puller from the cluster's source ref; or hydration on a `test` cluster | `main` protected, puller only; none on `test` | every `durable` cluster |
| **vendor** | `siliconsaga-vendor` | Forgejo pull-mirrors from upstream tags | read-only mirrors | every `durable` cluster |

Vendor gets its own org so that "mirror of someone else's code" is a trust class of its own; the URL train touches every repoURL anyway, so moving `keycloak-k8s-resources` costs least now. The `orgs` list and `class` field are built in general form so a later class is a new entry, not a redesign.

Recorded, not built: **preview** orgs (`siliconsaga-pr-123`) fed from trusted GitHub PR heads by a preview puller, gated on the realm's PR trust list as naust's PR bays are, carrying their creator and expiry and deleted by a reaper. They wait for a preview cluster to read them.

### Decisions still to come, in order

Listed so the next session resumes cleanly.

3. **URL train mechanics.** It merges in one coordinated push, ordered so that no hydration from `main` can land halfway: nordri's `patch-urls` already rewrites, so the train is safe to merge before any cluster graduates. That still has to be confirmed against `bootstrap.sh` and `update-embedded-git.sh` on a `bootstrap`-maturity cluster, where Forgejo does not exist. The realm's `defaults.gitea.internalUrl` → `defaults.forgejo.internalUrl` rides along, and the vendor mirror's URL moves to `siliconsaga-vendor`. Then where `role` and the source ref live in cluster-identity, and how they reach the puller and the configure Job.
4. **`graduate.sh`: placement and preconditions.** The record leans to nordri. Its preconditions include "the puller has run after the train merged" and "the vendor mirror refs Applications pin resolve on Forgejo". On a `test` cluster it graduates from the working trees instead of GitHub.
5. **`live` branch and `ws promote gke`.** Creating `live` at current `main` in each maintained repository, its GitHub protection, and where the promote command lives.
6. **GKE order of operations.** The owner wants the GKE hydrate from current `main`, plus heimdall's XRD, after this design and before implementation finishes. After that: create `live`, bump GKE to `durable` with source ref `live`, let Phase 2's Jobs run on GKE for the first time, soak, and only then run the swap.
7. **Sync visibility (the owner's parked request).** The puller emits per-repository state somewhere Prometheus can scrape. Then a mid-range alert ("repository X has not matched its source ref for N runs", ntfy priority 3–4, not a page) and a Grafana panel with the last good pull per repository, whether Forgejo's `main` matches the source ref, how far `live` trails `main`, and the mirrors' last sync. Phase 3 or Phase 4 depending on size; the Forgejo `/api/healthz` probe is Phase 3 regardless.
8. **Recovering a diverged `main`.** The three steps from 2026-11-06 become a runbook entry in nidavellir, and possibly a `ROTATE`-style mode of the configure Job, so recreating the rule does not need a hand-built Job.
9. **Soak and gates.** The record's gate list mostly stands. Its line "the local-branch loop has been exercised against Forgejo, including suspend and resume" becomes "one change has climbed the whole ladder: lab, `homelab-test`, `homelab-prod`, `ws promote gke`, `gke-prod`".

## Later arcs

- **Cluster BOM.** A per-cluster bill of materials in the realm (`clusters/<cluster>.yaml`: identity, maturity, role, and a ref per component), with the per-repository parent Applications turned into ApplicationSets so children follow the chosen ref. It would let a durable cluster run a chosen mix of branches, and it is the natural way in for community members running their own variant of the stack. Phase 3 does not depend on it.
