---
name: sweethome3d-mirror
description: Use when cloning, syncing, or maintaining the Sweet Home 3D git-svn mirror at components/sweethome3d, or preparing fork PRs or patches back to SourceForge.
---

# Sweet Home 3D mirror

A faithful git-svn mirror of Sweet Home 3D's SourceForge SVN at `components/sweethome3d` — work happens on `main` via PRs; patches flow back upstream. Tooling lives in `realms/realm-siliconsaga/sweethome3d/`; deeper docs in that dir's `README.md` and `realms/realm-siliconsaga/docs/plans/2026-05-25-sh3d-mirror-*.md`. For working with `.sh3d` house files, use the `sweethome3d` skill instead.

## When to Use

- Cloning, syncing, or otherwise maintaining the mirror
- Writing fork PRs or preparing patches back to SourceForge

## Scripts

`config.sh` (sourced by the rest) is the single place the SVN URL, the `IGNORE_PATHS` exclusion regex, the authors map, branch names, `GIT_BIN`, and the FD-limit raise are defined.

| Script | Does |
|---|---|
| `clone.sh [--force]` | (re-)clone the mirror; `--force` replaces an existing clone (fully regenerable). Sets up `upstream` (tracks SVN trunk) + `main` (fork work branch). |
| `sync.sh` | `git svn fetch` + fast-forward `upstream` to SVN trunk. Read-only + local; no push. Run from anywhere — it resolves the workspace root itself. |

```bash
bash realms/realm-siliconsaga/sweethome3d/sync.sh
```

A no-op prints `Already up to date.`; a real pull prints the fetched revisions plus a merge summary. Either way the final `>> '<upstream>' now at:` line shows the resulting HEAD — that line is how you confirm what happened. No-op is the normal outcome: the trunk is largely dormant and some releases ship outside the public SVN, so the mirror can lag actual releases — see the realm `sweethome3d/README.md` § Upstream status.

## Rules

- **Never** edit `upstream` by hand — it is machine-only; all work happens on `main` via PRs.
- `IGNORE_PATHS` MUST stay identical across clone and every fetch, or git-svn re-imports excluded paths (hence `config.sh`).
- Lean by exclusion (not LFS): jars, natives, installers, `3DModels`/`Textures`, and demo homes are filtered; full source + history kept (~162M `.git`, ~7790 commits).

## Common Mistakes

- **`git svn` missing** — Apple's `git` lacks it. macOS: `brew install git git-svn subversion` (`git-svn` is a separate formula). Scripts default `GIT_BIN=/opt/homebrew/bin/git`; override on Intel/CI.
- **`git svn fetch` dies with "Too many open files"** in low-FD contexts (overnight, detached, CI). `config.sh` raises the soft limit only (`ulimit -Sn`, raise-never-lower); if it still dies, check the limit *in that execution context* — it differs from an interactive shell.
- **Ephemeral CI runners** lack `.git/svn` metadata — a scheduled GitHub Action needs a metadata-rehydration wrapper before `sync.sh` (noted in the script).
