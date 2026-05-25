# Sweet Home 3D mirror tooling

Utility scripts for maintaining the Sweet Home 3D git-svn mirror at `components/sweethome3d`. Design: `docs/plans/2026-05-25-sh3d-mirror-design.md` and `…-modernization-and-assets.md`.

## Where it lives vs runs

These scripts **live** here (versioned, single source of truth). They **operate on** the local clone at `<workspace>/components/sweethome3d`, where the `.git/svn` metadata lives. Run them from anywhere — they resolve the workspace root from their own location.

## Scripts

- `config.sh` — shared config (SVN URL, the `IGNORE_PATHS` exclusion regex, authors file, branch names). Sourced by the others; **the one place the exclusion regex is defined.**
- `authors.txt` — SVN→git author map (used by clone).
- `clone.sh [--force]` — (re-)clone the mirror. `--force` replaces an existing clone (fully regenerable). Sets up `upstream` (mirror) + `main` (fork) branches.
- `sync.sh` — `git svn fetch` + fast-forward `upstream` to SVN trunk. Run manually for now; later wrapped by a scheduled GitHub Action.

## Maintenance rules

1. **Never** edit `upstream` by hand — it is machine-only. Do all work on `main` via PRs.
2. The exclusion regex MUST stay identical across clone and every fetch (hence `config.sh`), or git-svn re-imports excluded paths.
3. If upstream changes its dependencies, `upstream` won't carry the new jar (it's ignored) — update the fork's `resolve-libs` to match.

## Prerequisites

`git-svn` + `subversion` (Apple's git lacks git-svn). On macOS: `brew install git git-svn subversion`. Scripts default `GIT_BIN=/opt/homebrew/bin/git`; override `GIT_BIN` in CI.
