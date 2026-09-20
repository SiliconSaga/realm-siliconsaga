# Sweet Home 3D tooling

Two script families for the SiliconSaga Sweet Home 3D work — both **live** here
(versioned, single source of truth):

- **Mirror maintenance** — the git-svn mirror at `components/sweethome3d`. Agent skill: `sweethome3d-mirror`.
- **House-file workflow** — explode / normalize / repack a `.sh3d` so a house diffs like code (used by `hoards/refrhus`). Agent skill: `sweethome3d`.

Design notes: `docs/plans/2026-05-25-sh3d-mirror-design.md` and `docs/plans/2026-05-25-sh3d-modernization-and-assets.md`.

## Upstream status (awareness — mirror)

Maintenance passed from eTeks (Emmanuel Puybaret) to **Space Mushrooms** (Milan) in Aug 2024 with v7.5; the project stays GPL on SourceForge. Two things a mirror maintainer should know:

- **The public SVN is no longer the full source of truth for releases.** A 7.6 build shipped to SourceForge's *file/download area* (and via email links) in Feb 2025, then was rolled back, with no matching SVN commit or tag; store builds (Mac App Store / Microsoft Store) carry their own numbers (e.g. 7.9.x). This mirror tracks the public SVN **source**, which can therefore lag or omit what actually ships.
- **SVN velocity is low.** trunk last moved Dec 2024; the freshest branch is `develop-SweetHome3D-7.7-Online` (Apr 2025, the web-version line). No-op syncs are the norm. If core development clearly leaves SourceForge, that is the signal to re-evaluate the mirror's basis.

## Mirror scripts

These **operate on** the local clone at `<workspace>/components/sweethome3d`, where the `.git/svn` metadata lives. Run them from anywhere — they resolve the workspace root from their own location.

- `config.sh` — shared config (SVN URL, the `IGNORE_PATHS` exclusion regex, authors file, branch names). Sourced by the others; **the one place the exclusion regex is defined.**
- `authors.txt` — SVN→git author map (used by clone).
- `clone.sh [--force]` — (re-)clone the mirror. `--force` replaces an existing clone (fully regenerable). Sets up `upstream` (mirror) + `main` (fork) branches.
- `sync.sh` — `git svn fetch` + fast-forward `upstream` to SVN trunk. Run manually for now; later wrapped by a scheduled GitHub Action.

### Maintenance rules

1. **Never** edit `upstream` by hand — it is machine-only. Do all work on `main` via PRs.
2. The exclusion regex MUST stay identical across clone and every fetch (hence `config.sh`), or git-svn re-imports excluded paths.
3. If upstream changes its dependencies, `upstream` won't carry the new jar (it's ignored) — update the fork's `resolve-libs` to match.

## House-file scripts

A `.sh3d` is a ZIP; tracking it **exploded** lets git diff a house like code. The exploded directory is the source of truth; the `.sh3d` is a generated artifact.

- `unpack.sh <file.sh3d> <dest-dir> [--raw]` — explode a `.sh3d` into `<dest-dir>` for diffable tracking, then normalize (unless `--raw`). **Clears `<dest-dir>` first** so deletions in the `.sh3d` propagate — point it at a SUBDIR, never a repo/hoard root (guarded: refuses a `.git` root, a symlink, `/`, and `$HOME`).
- `normalize.sh <dest-dir>` — strip non-design noise so a no-op open→save→unpack diffs to nothing: drop the serialized `Home` blob (`Home.xml` is authoritative since v5.3) and the volatile editor/session + default-camera state from `Home.xml`. Called automatically by `unpack.sh`; named viewpoints are preserved.
- `pack.sh <exploded-dir> <out.sh3d>` — repack the exploded tree into an app-openable `.sh3d`. Inverse of `unpack.sh`.
- `tag.py list|set|clear <exploded-dir> …` — read and write [Eldr](https://github.com/SiliconSaga/eldr) assembly tags on walls and rooms. See below.

### Assembly tags (`tag.py`)

Eldr lets a single surface declare which assembly it is, so a house with 248 ft² of uninsulated wall among 1,321 ft² of insulated wall gets both numbers instead of one blend. A tag is an `eldr.assembly` property naming a side-car key like `exterior_wall/r0`.

**Walls and rooms need this tool; windows and doors do not.** Sweet Home 3D's UI cannot edit custom properties at all, and a wall has no name to type into — but furniture does, so a window is tagged by renaming it in the furniture list to something like `Bedroom window [window/single]`, where you can see which window you are naming. `tag.py` deliberately refuses windows and doors for that reason.

```bash
# what is taggable, and what carries a tag already
python3 realms/realm-siliconsaga/sweethome3d/tag.py list hoards/refrhus/sh3d-internals

# tag a wall, then a room (a room may carry one key per category — it has both a
# ceiling and a floor, and they are different assemblies)
python3 realms/realm-siliconsaga/sweethome3d/tag.py set hoards/refrhus/sh3d-internals \
    wall 7 exterior_wall/r0
python3 realms/realm-siliconsaga/sweethome3d/tag.py set hoards/refrhus/sh3d-internals \
    room 17 ceiling/r19 buffer_floor/none
```

Three things worth knowing:

- **Indices come from the immediately preceding `list`** and move whenever the model is edited. List, set, verify — never save an index for later.
- **It edits text, not parsed XML.** A parse-and-rewrite would renormalise attribute order and whitespace across the whole document, burying a one-line change in a file-wide diff and breaking the no-op-save invariant `normalize.sh` protects. Every byte outside the tag is left as Sweet Home 3D wrote it, so `git diff` shows exactly one added line.
- **Tags survive everything.** Sweet Home 3D round-trips unknown properties through its own open→save (`HomeXMLExporter` writes every name `getPropertyNames()` returns, filtered against nothing), and `normalize.sh` strips only `com.eteks.sweethome3d.*` editor state. They do *not* survive **redrawing** the wall — a new wall is a new id with no properties, which is what Eldr's *Assembly coverage* report block exists to make visible.

### Round-trip (Refrhus)

```bash
# after editing in the app: re-explode + normalize, then commit the diff in hoards/refrhus
bash realms/realm-siliconsaga/sweethome3d/unpack.sh hoards/refrhus/Refrhus.sh3d hoards/refrhus/sh3d-internals

# rebuild the openable .sh3d from the exploded tree, then open it in Sweet Home 3D
bash realms/realm-siliconsaga/sweethome3d/pack.sh   hoards/refrhus/sh3d-internals hoards/refrhus/Refrhus.sh3d
```

## Prerequisites

- **Mirror:** `git-svn` + `subversion` (Apple's git lacks git-svn). On macOS: `brew install git git-svn subversion`. Scripts default `GIT_BIN=/opt/homebrew/bin/git`; override `GIT_BIN` in CI.
- **House-file:** `zip` / `unzip` (standard on macOS and most Linux).
