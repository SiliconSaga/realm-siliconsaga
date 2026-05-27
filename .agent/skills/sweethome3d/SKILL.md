---
name: sweethome3d
description: Use when editing, opening, or diffing a Sweet Home 3D .sh3d file (especially Refrhus.sh3d), or analyzing house geometry — walls, levels, footprint, HVAC ducts, level misalignment.
---

# Sweet Home 3D (house data)

The user's house model `Refrhus.sh3d` is tracked git-natively — exploded into the `refrhus` hoard — so design edits diff like code. Tooling lives in `realms/realm-siliconsaga/sweethome3d/`. For maintaining the upstream git-svn mirror/fork, use the `sweethome3d-mirror` skill instead.

## When to Use

- Editing, opening, or diffing a `.sh3d` file
- Analyzing house geometry — walls, levels, footprint, duct runs, level misalignment

## The .sh3d format

A `.sh3d` is a ZIP. What matters for diffing:

| Entry | What it is | Track? |
|---|---|---|
| `Home.xml` | the home as XML — **authoritative** (read in priority since v5.3) | yes — source of truth |
| `Home` | serialized-Java twin, re-added on every save | no — `normalize.sh` drops it |
| `ContentDigests`, numbered entries | digests + embedded images/models | yes |

`Home.xml` is plain XML, so walls / levels / rooms / furniture are inspectable and diffable — that is what makes overlay-vs-model geometry checks tractable.

## The workflow

Exploded dir is the source of truth; the `.sh3d` is a generated artifact. In `hoards/refrhus/`: `Refrhus.sh3d` (gitignored) ↔ `sh3d-internals/` (committed).

```bash
# explode + normalize — dest MUST be a subdir, never a repo/hoard root
bash realms/realm-siliconsaga/sweethome3d/unpack.sh hoards/refrhus/Refrhus.sh3d hoards/refrhus/sh3d-internals
# repack to open in the app
bash realms/realm-siliconsaga/sweethome3d/pack.sh hoards/refrhus/sh3d-internals hoards/refrhus/Refrhus.sh3d
```

**Invariant:** a no-op open→save→unpack diffs to nothing. `normalize.sh` enforces it by dropping `Home` and stripping volatile view state — editor `<property>` elements and the *default* cameras (`<observerCamera>`, `<camera attribute='topCamera'>`, matched by `attribute=` so named viewpoints survive). If no-op saves start churning again, a new view-state surface appeared: extend the `normalize.sh` grep, don't hand-edit `Home.xml`.

## Common Mistakes

- **`unpack.sh` clears its `dest`** (so deletions propagate) and refuses a `.git` root — always point it at a subdir.
- **`--raw`** skips normalization — for format debugging, not for committing.
