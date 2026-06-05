# Sweet Home 3D — Workspace Structure & SVN→Git Mirror

**Status:** Draft for review · **Date:** 2026-05-25 · **Scope:** Track B (mirror/infra) + the structural decisions that enable Track A (house file)

## Purpose

Stand up a faithful, well-maintained GitHub mirror of Sweet Home 3D (SH3D) — the first of its kind — for safekeeping/provenance, for enabling review-bot-assisted bug fixes via PRs, and as a substrate for later modernization. This is explicitly **not** a refactor or a hostile fork. The intended spirit: honest mirror → fix via PRs on GitHub → submit patches upstream on SourceForge → (only if pushed) a renamed hard-fork.

## Context (why this is worth doing)

- SH3D was handed from eTeks/Emmanuel Puybaret to **Space Mushrooms srl** (Aug 2024). It remains **GPL-2.0**; the SVN is active on SourceForge (trunk HEAD **r9031**, Dec 2024; repo HEAD **r9047**, Apr 2025, on the `develop-SweetHome3D-7.7-Online` branch).
- Space Mushrooms holds the **`Sweet Home 3D®` trademark** and copyright.
- Upstream is **SVN-only** by the original author's deliberate, long-stated choice; existing GitHub mirrors are tiny/stale → a maintained mirror is **greenfield**.

## Workspace mapping

| Concept | Home | Holds |
|---|---|---|
| **Component** | `components/sweethome3d` | The code — a `git svn` mirror of SVN trunk |
| **Realm (meta)** | `realms/realm-siliconsaga` | Catalog entry, this spec, the modernization plan, sync-workflow docs, the parked "break free" contingency |
| **Hoard (personal)** | a dedicated hoard, separate from `borgr` | The house file `Refrhus.sh3d`, **exploded** for diffs, plus a pack/unpack script and planning notes |

## The mirror (component)

**Source:** `https://svn.code.sf.net/p/sweethome3d/code/`

**Clone decisions (captured at r9047):**

- `--stdlayout` — faithful trunk/branches/tags. *Fallback if branches/tags prove messy: a trunk-only re-clone.*
- `--authors-file` — 5 authors mapped (`puybaret` → Emmanuel Puybaret; `lgrignon`/`nur`/`root`/`(no author)` kept as usernames; SourceForge-convention emails). Persist out of `.tmp/` to `realms/realm-siliconsaga/sweethome3d/authors.txt`.
- `--ignore-paths` — the exclusion list (assets, junk, installers, jars, native libs, demo homes) is defined and justified in the companion doc `2026-05-25-sh3d-modernization-and-assets.md`. The same value MUST be reused on every `git svn fetch` or git-svn re-imports the excluded paths.

**Consequence accepted now:** changing the asset/layout/jar decision later means **re-importing** (git-svn metadata is tied to the chosen paths). We accept the chosen exclusion set as the mirror's permanent shape; excluded content remains available from upstream SVN if ever needed.

## Branch model — the `upstream` ↔ `main` map

Two branches with sharply separated roles:

- **`upstream`** — *machine-only, never hand-edited.* Exact SVN `trunk` minus the excluded paths. Updated **only by the sync** — `git svn fetch`, then a fast-forward `merge --ff-only remotes/origin/trunk` — and is append-only (never rebased/force-pushed). Not standalone-buildable (deps/natives excluded). This is the provenance line, pushed to a **protected** GitHub `upstream` branch that no PR targets.
- **`main`** — our buildable, improved GitHub version. Branched from `upstream`; absorbs upstream by periodic **merge** of `upstream` → `main` (never rebase — `main` is published).

**What lives only on `main` (the "special cases"):**

| Change type | Origin | Flow |
|---|---|---|
| Upstream code | SVN | SVN → `upstream` → merge → `main` (automatic) |
| Our bug fix | us | branch off `main` → PR → merge; **also export patch → SourceForge** |
| Infra: CI, `resolve-libs` dep tweak, `.gitignore`, README | us | `main` only, in **isolated new files** (permanent divergence) |
| Modernization (Gradle, modules) | us | `main` (Track C); may graduate to the renamed fork |

**Conflict surface is tiny by design:** excluded jars/assets never exist on `upstream`, so they never conflict on merge. The dependency tweak lives in *new* files (`ivy.xml` / `bootstrap-libs.sh`); the **only** edit to an upstream-owned file is a one-line `<import>`/hook in each module `build.xml` — the single realistic merge-conflict point. Keep our fixes as small, isolated commits so they stay cleanly exportable as SourceForge patches.

**Maintenance rules to bank:**
1. The sync must always fetch with the **same `--ignore-paths`** (stored in-repo) or git-svn re-imports excluded content.
2. Upstream changes to ignored/infra paths (deps, natives, build files) don't appear in `upstream` — so `sync.sh` runs a **change radar**: it scans each incoming SVN range (via remote `svn log -v`, no second checkout) against the ignore/infra patterns and **flags** dep/build changes for review, then we update `resolve-libs` to match. Scripted detection, not a manual watch. Modes: default report-then-fetch, `--check` (preview, no fetch), `--strict` (exit non-zero if flagged — a CI gate).

## Ongoing sync

`git svn` *is* the bridge that maintains the mirror. Two phases:

1. **Local (now):** `git svn fetch` → fast-forward `upstream` → push. Run by hand initially; wrap in a `ws` subcommand if it recurs (per the gdd-workflow-audit skill).
2. **Automated (later):** a scheduled **GitHub Action** modeled on `wch/r-source-git-svn` — commit the `.git/svn` metadata into the repo and rehydrate it each run (Actions runners are ephemeral), then `git svn fetch` (same ignore-paths), fast-forward `upstream`, push, and **open a PR `upstream` → `main`** for review (so the build.xml-hook conflict, if any, is resolved deliberately). Daily cron.

## GitHub hosting & contribution

- Push to a GitHub repo under the user's org. A **mirror** may use the name **descriptively** — `sweethome3d-mirror` truthfully identifies what it mirrors (intended as descriptive/nominative use — subject to legal review, not a settled legal conclusion). The trademark caution is for a **branded fork** (the "break free" product presenting itself *as* a product), which would need its own distinct name.
- Protect `upstream` (machine-written); do all human work via PRs into `main`. Enable review bots (CodeRabbit / Copilot) on `main` PRs.
- **Fixes:** branch off `main` → PR (bot-reviewed) → also submit the patch upstream on SourceForge (honest-mirror etiquette; aim to "light the way" toward an eventual GitHub migration).

## "Break free" contingency (parked — Track C)

If Space Mushrooms relicenses in a way that breaks the sync, or objects to the mirror: convert to a **renamed hard-fork** (new name, trademark/identity scrub, keep the sync workflow running until a license change forecloses it), then let the community decide where to land. A dormant design doc worth writing *now* and hoping never to use — out of scope here; tracked separately.

## House hoard (enables Track A)

- Track the **exploded** `.sh3d` (it is a ZIP) in git: `Home.xml` (text — walls/rooms/levels/furniture), the `.obj`/`.mtl` model files, `ContentDigests`, plus the few binary background images. The `.sh3d` itself becomes a **generated artifact** via a pack/unpack script (the script lives in the realm tooling, not the hoard).
- Enables **"PR your house"**: branch `hvac-next-gen`, diff the change, show the contractor, merge when built.
- **Diff-stability** depends on SH3D writing `Home.xml` deterministically — to verify empirically; if noisy, the unpack script gains a **normalize** step.
- A **dedicated** hoard (not `borgr`); `borgr` (the PKM) only links to it.

## Risks & verification

- **stdlayout edge cases** → watch the clone log; fall back to trunk-only. (First clone confirmed clean: trunk + 6 develop branches + ~150 version tags as git-svn refs.)
- **Clone interruption** → resumable via `git svn fetch`.
- **Home.xml read-priority** + **diff-stability** → empirical in-app checks (Track A, next session).
- **Mirror acceptance checks:** authors mapped in `git log`; history reaches trunk HEAD; no file ≥100 MB; a `git svn fetch` immediately after clone is a clean no-op. (All passed on the lean clone.)

## Out of scope (separate specs)

- Track A house-file operations (level realignment, duct finishing, airflow / Manual-D sizing).
- Track C modernization detail (Gradle migration, module system, AI/MCP) — see the modernization-and-assets doc.
- The full "break free" hard-fork design.
