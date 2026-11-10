# Forgejo day-2 — Phase 3 design: the URL train, testing a branch, and the GKE cutover

**Status:** Draft, in brainstorm. Decision 1 settled on 2026-11-10 (orgs as environments); paused at Decision 2, which org classes Phase 3 builds.
**Date:** 2026-11-06
**Owner:** Rasmus Praestholm
**Parent:** [Forgejo day-2 design](2026-09-07-forgejo-day2-design.md) (design of record; this document settles Phase 3's open points and records where the record no longer holds) · [Phase 2 design](2026-09-19-forgejo-day2-phase2-design.md)

## Where Phase 3 starts from

Phase 2 is merged and validated. On 2026-11-06 the owner tested it by hand on the Nano76 Docker Desktop cluster: logged in as the break-glass account, found the five maintained repositories and the vendor mirror, and edited a file on Forgejo's nordri `main` through the web UI. The next puller run was refused ("branch main is protected from force push"), the other four repositories synced, and the Job failed. That is the failure [`docs/forgejo.md`](../forgejo.md) describes. Recovering took three steps: delete the `main` rule, run the puller once (its `--force-with-lease` then reset `main` to GitHub's), and recreate the rule with a one-off copy of the configure Job.

Facts this design builds on, checked on 2026-11-06:

- **Forgejo has no force-push allowlist.** A protected branch refuses non-fast-forward pushes from every account, admins included, and the branch-protection API has no field to change that (Phase 2 plan, confirmed live above). The design of record's local-branch flow assumed "the account is on the `main` and force-push allowlists"; that sentence cannot be implemented.
- **18 ArgoCD Application manifests carry an in-cluster Git URL**, all still in the seed form: nordri 5 (`platform/root-app.yaml`, `platform/argocd/{app-of-apps,nidavellir-apps,realm-root-app.template}.yaml`, `platform/fundamentals/apps/garage.yaml`), nidavellir 10 (`apps/*`), mimir 3 (`argocd/apps/*`). The record counted sixteen. Every one of them tracks `targetRevision: HEAD`; the pinned revisions in the tree are all Helm chart versions on public chart repositories.
- **`lib/patch-urls.sh` already has the three modes** (`seed`, `forgejo`, `swap`) and fails closed on a URL of the wrong kind. The train only flips what is committed; the rewrite then becomes live instead of a no-op.
- **The root Application is applied directly, not synced.** `bootstrap.sh` copies `platform/root-app.yaml`, runs it through `patch_repo_urls_file`, and `kubectl apply`s it, as it does the rendered realm root-app. So repointing ArgoCD at a different Git source is one `kubectl apply`, not a commit.
- **`update-embedded-git.sh` hydrates the whole set** (nordri, the nidavellir/mimir/heimdall components, the vendor mirrors and the realm) on every run, and since nordri#41 it hard-refreshes every Application afterwards.
- **Maturity:** homelab's identity is committed at `durable`; GKE's is `bootstrap`. GKE graduation is therefore also Forgejo's first run on GKE, with KMS-unsealed OpenBao, persistent disk and the GKE wildcard certificate.

## Scope

Phase 3 delivers, per the record's phasing table:

1. The coordinated URL train (nordri, nidavellir, mimir, realm `ecosystem.yaml`), with the `nordri-admin` → `siliconsaga` org rename riding along.
2. A way to test an unmerged branch on a cluster once ArgoCD reads Forgejo (Decision 1).
3. `graduate.sh`: preconditions, the swap commit, rollback, and `--retire-seed`'s gates.
4. GKE graduation and cutover, then the soak.

Pulled in from Phase 2's out-of-scope list: the Heimdall blackbox probe on Forgejo's `/api/healthz`, now that a real hostname exists. Parked for this design to place: the owner's request (2026-11-06) for a Grafana sync dashboard and a mid-range sync-failure alert, since the divergence above was visible only in Job logs.

Out of scope: restore drills and Velero scope (Phase 4), `full` maturity (Phase 5), SSH access.

## Decisions

### Decision 1 (settled 2026-11-10): a branch reaches a cluster through its own org, and orgs become environments

The owner chose Option D and widened it. Forgejo orgs are cheap and Forgejo has a lot of room to grow, so the layout uses several orgs: for previews, other testing and staging environments, each with a clear purpose. The scratch org is the first of them. The next section gives the good-practice rules every org follows and the org classes they allow. Options A–C are kept below as the record of what was weighed.

The options as weighed:

Today a branch gets tested by hydrating working trees into the seed: an orphan snapshot is force-pushed onto the seed's `main`, ArgoCD syncs it, and the next hydration from `main` puts things back. The record carried that shape over to Forgejo, and that relies on the force-push allowlist that does not exist. Whatever replaces it must keep three properties: Forgejo's `main` stays a verbatim copy of GitHub's, the puller is the only writer of `main`, and a forgotten test is easy to find.

**Option D — a scratch org on Forgejo, used the way the seed is used today (recommended).** The configure Job also creates an unprotected org, say `siliconsaga-scratch`, holding a repository for each maintained one. `update-embedded-git.sh --target scratch` force-pushes orphan snapshots there, and `patch-urls.sh` gains a fourth mode that rewrites `…/siliconsaga/` to `…/siliconsaga-scratch/`: the same literal, fail-closed rewrite the seed mode already does, with another host and org. The script then re-applies the root Application against the scratch org. `--resume` re-applies it against `siliconsaga`, and the next sync puts every child back. *For:* `main` is never touched, so protection stays on and the puller never pauses. The design's suspend/resume step goes away. It reuses the most proven code in the flow, and a forgotten test shows up in one place: the root Application's `repoURL`. *Against:* a second set of repositories, and the scratch copies are whole snapshots, so hydration stays all-or-nothing as it is today.

**Option A — a test branch and a retargeted revision.** Snapshots go to an unprotected branch `hydrate/<user>` in the real repositories. A new patch rewrites `targetRevision: HEAD` to that branch on every Application whose `repoURL` is Forgejo, and the root Application is re-applied on the branch. *For:* one set of repositories, and each tester gets their own branch. *Against:* the new patch has to be YAML-aware, keyed on the sibling `repoURL`, because `targetRevision` also pins chart versions. That is a different and less safe kind of rewrite than a literal URL swap. Test branches would also sit next to real work in the repositories people browse.

**Option B — remove protection around the push (the record's flow, plus tonight's recovery).** Suspend the puller, delete the `main` rule, force-push the snapshot, and to resume delete the rule again, let the puller lease-push back to GitHub's `main`, then recreate the rule. *For:* the closest to how hydration works today, and ArgoCD is never repointed. *Against:* `main` is unprotected and differs from GitHub for the whole test window. A workstation token would need repository-admin rights to edit protection. The puller stops being the only writer of `main`, and that was the rule that kept the model simple.

**Option C — keep the seed as the permanent test target.** Never retire it. Tests hydrate into the seed and repoint the root there. *Against:* two Git servers forever, a test target whose `emptyDir` wipes on any pod replacement, and it reverses the record's `--retire-seed`.

**Recommendation: D.** It keeps every invariant Phase 2 established, deletes a mechanism (puller suspension) instead of adding one, and its one new piece is a mode of a library that already has three and a test suite. A is the fallback if a second set of repositories is unwelcome.

### Organisation layout: orgs as environments

#### Good-practice rules

These hold for every org, whatever its class.

1. **An org is a trust class and a lifecycle, not a folder.** Protection, writers, retention and backup are decided per org, never per repository. A repository's class can be read from its org's name.
2. **Every protected org mirrors a GitHub ref.** What a protected org holds is a copy of something on GitHub, written only by a puller. Work never starts on Forgejo and is never promoted between Forgejo orgs: promotion is a merge or a tag on GitHub, and every org downstream catches up. This is Phase 2's "only the puller writes `main`" rule, applied to every org.
3. **Every unprotected org is disposable.** It holds nothing that cannot be recreated by hydrating again from a working tree or a GitHub ref. Nothing in it is backed up, and nothing durable may depend on it.
4. **Names are `<realm>-<class>[-<qualifier>]`, except the canonical org.** That one keeps the bare realm name (`siliconsaga`) because every committed repoURL names it. Examples: `siliconsaga-scratch-cervator`, `siliconsaga-pr-123`, `siliconsaga-staging`. The realm prefix keeps a Forgejo shared by several realms legible later.
5. **The realm declares orgs; nidavellir never names one.** The claim's single `org` field becomes an `orgs` list, with a `class` on each entry. The composition gives each class its protection, writers and retention, and the configure Job reconciles them as it does today's single org.
6. **The cluster says which org it reads.** Committed repoURLs name the canonical org. A long-lived environment that reads a different org says so in its cluster-identity (for example `gitOrg: siliconsaga-staging`), and hydration rewrites the org segment to match. That rewrite is the same literal, fail-closed swap `patch-urls.sh` already does, generalised from a fixed scratch mode to `org:<name>`. A short-lived test, such as a scratch hydration, repoints only the root Application, so nothing is committed for it.
7. **A cluster that is not on its own org is noticed.** The puller (or the visibility work in item 6 below) exposes which org each cluster's root Application reads. If a cluster reads a scratch or preview org for longer than a threshold, a low-priority alert fires, so a forgotten test cannot hang around unnoticed.
8. **Least privilege per class.** Forgejo token scopes go by category, not by org, so separation comes from accounts. Each puller-written class gets its own bot account, which is a member only of the orgs it writes. A human's scratch token sits on an account that is a member of that human's scratch org only.
9. **Ephemeral orgs carry their own expiry.** An org created for a PR or a test records its creator and an expiry in its description. A reaper (a CronJob beside the puller) deletes expired ones. Quotas on unprotected orgs, if the pinned Forgejo supports them, stop one stray hydration from filling the volume. That has to be checked against Forgejo 15 rather than assumed.

#### Org classes the rules allow

| Class | Example | Fed by | Protection | Lifecycle | Read by |
|---|---|---|---|---|---|
| **canonical** | `siliconsaga` | puller, from GitHub `main` | `main` protected, puller only | permanent | every production cluster |
| **vendor** | `siliconsaga-vendor` | Forgejo pull-mirrors, from upstream tags | read-only mirrors | permanent | Applications pinned to vendor tags |
| **scratch** | `siliconsaga-scratch-cervator` | a human's `update-embedded-git.sh --target scratch` | none; orphan force-pushes are expected | permanent org, contents disposable | one cluster at a time, while a test runs |
| **preview** | `siliconsaga-pr-123` | a preview puller, from a GitHub PR head | protected, preview bot only | created on PR open, reaped on close or expiry | a preview cluster or namespace |
| **staging** | `siliconsaga-staging` | puller, from a GitHub `staging` branch or release tag | protected, puller only | permanent | the staging cluster, via `gitOrg` |

Notes on the classes:

- **Vendor gets its own org** so that "mirror of someone else's code" is a trust class of its own, instead of sitting beside our repositories. The URL train touches every repoURL anyway, so moving `keycloak-k8s-resources` costs least now.
- **Preview orgs follow PR trust.** Only a PR the realm trusts gets an org. That is the same trust-list idea naust's PR bays use, and it matters because a preview cluster runs what the PR says. Fork PRs never get one automatically.
- **Staging is a GitHub decision.** What staging runs is a GitHub branch or tag, so moving a change to staging is reviewed where every other change is.

### Decision 2 (OPEN): which classes Phase 3 builds

The rules cost little to write into the composition now. Each class costs real work to build. The options:

- **Build canonical, vendor and scratch now; record preview and staging as designed but unbuilt (recommended).** Canonical exists already. Vendor rides the URL train for free. Scratch is what Decision 1 needs. The `orgs` list, the `class` field and `org:<name>` rewriting are built in their general form, so adding preview or staging later is a new class entry plus its puller, not a redesign.
- **Canonical and scratch only.** Smallest, but the vendor mirror moves in a second URL change later.
- **All five.** Preview needs a preview puller, the reaper and a trust gate, and staging needs a staging cluster to read it. Neither has a consumer yet.

*Owner's call needed here.* After it: per-human scratch orgs versus one shared scratch org. The rules above lean per-human, because each tester gets their own token and the forgotten-test alert can name who left it.

### Decisions still to come, in order

Listed so the next session resumes cleanly.

3. **URL train mechanics.** It merges in one coordinated push, ordered so that no hydration from `main` can land halfway: nordri's `patch-urls` already rewrites, so the train is safe to merge before any cluster graduates. That still has to be confirmed against `bootstrap.sh` and `update-embedded-git.sh` on a `bootstrap`-maturity cluster, where Forgejo does not exist. The realm's `defaults.gitea.internalUrl` → `defaults.forgejo.internalUrl` rides along, and the vendor mirror's URL moves to its own org if Decision 2 says so.
4. **`graduate.sh`: placement and preconditions.** The record leans to nordri. Its preconditions include "the puller has run after the train merged" and "the vendor mirror refs Applications pin resolve on Forgejo". It also gains `--resume`, which brings a cluster back to its own org after a scratch test.
5. **GKE order of operations.** The owner wants the GKE hydrate from current `main`, plus heimdall's XRD, after this design and before implementation finishes. After that: bump GKE to `durable`, let Phase 2's Jobs run on GKE for the first time, soak, and only then run the swap.
6. **Sync visibility (the owner's parked request).** The puller emits per-repository state, and per-cluster which org the root reads (rule 7), somewhere Prometheus can scrape. Then a mid-range alert ("repository X has not matched GitHub for N runs", ntfy priority 3–4, not a page) and a Grafana panel with the last good pull per repository, whether Forgejo's `main` matches GitHub's, and the mirrors' last sync. Phase 3 or Phase 4 depending on size; the Forgejo `/api/healthz` probe is Phase 3 regardless.
7. **Recovering a diverged `main`.** The three steps from 2026-11-06 become a runbook entry in nidavellir, and possibly a `ROTATE`-style mode of the configure Job, so recreating the rule does not need a hand-built Job.
8. **Soak and gates.** The record's gate list mostly stands. Its line "the local-branch loop has been exercised against Forgejo, including suspend and resume" becomes "a scratch hydration and `--resume` have been run on the cluster, and the forgotten-test alert has fired once".
