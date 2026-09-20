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

## Custom properties (how metadata rides along)

Every object worth annotating accepts arbitrary `<property name='…' value='…'/>` children — the DTD in `HomeXMLHandler.java` declares `property*` on `home`, `level`, `wall`, `room`, `pieceOfFurniture` and `doorOrWindow`. Four facts govern how usable they are:

- **They round-trip through Sweet Home 3D's own save.** `HomeXMLExporter.writeProperties` iterates `getPropertyNames()` and emits every one, filtered against no known-key list; `HomeXMLHandler` reads them back the same way. A property written by tooling is still there after the owner opens the model, moves a wall and saves. They are emitted **sorted by name**, so they stay diff-stable.
- **They survive `normalize.sh`**, which strips only `com.eteks.sweethome3d.*` editor state. Never give a property that prefix.
- **The Sweet Home 3D UI cannot edit them.** No dialog exposes custom properties — they are a plugin-API surface. Writing one needs tooling.
- **They die with the object.** Redraw a wall and it is a new id with no properties. Nothing can detect that directly; only a report comparing runs can.

**Walls have no editable text at all** — their attributes are ids, endpoints, heights, thickness, arc extent, pattern and colours. Rooms and furniture *do* carry an editable `name`.

### Eldr assembly tags

[Eldr](https://github.com/SiliconSaga/eldr) reads an `eldr.assembly` property naming a side-car key like `exterior_wall/r0`, so one surface can differ from its category's default U-value. Two conventions, forced by the asymmetry above:

- **Walls and rooms** — `tag.py set <exploded-dir> wall 7 exterior_wall/r0`. A room takes one key per category (it has both a ceiling and a floor): `room 17 ceiling/r19 buffer_floor/none`.
- **Windows and doors** — rename them in Sweet Home 3D's furniture list: `Bedroom window [window/single]`. A bracketed token counts only if it contains `/` and its prefix is a real category, so ordinary names like `[kitchen]` are ignored. Prefer this over tooling — you can see which window you are naming.

**Rooms are property-only, never name-tagged**, because Sweet Home 3D draws a room's name on the plan and a bracketed tag there would be visible clutter on every drawing.

A tag selects a U-value *within* the category the geometry already resolved. It can never change the category — that stays `walls: {boundary: …}` in the side-car, keyed by wall id.

## Working with the owner on geometry

**The model is the collaboration medium — not prose, not diagrams.** Ad-hoc spatial descriptions and topology sketches do not survive translation between a person and an agent; east and west get flipped, and the error is invisible until something is built. The model is already spatially correct at real coordinates, the agent can edit and diff it precisely, and the owner can *see* it and judge it. Route spatial disagreement through the model rather than through paragraphs.

**Divide the work by strength.** The owner supplies spatial truth — measurements, "this register is about here, nearest joist 14". The agent places it precisely, keeps naming and elevations consistent, and produces the diff. **The agent never invents a position**; it places, normalises and connects what the owner specifies.

**Anchor against named walls and furniture, not compass directions.** Cardinal labels are where the repeated east/west mistakes come from. "The wall containing the bar counter" cannot be flipped; "the west wall" can.

**Anchors before contents.** Structural references — joists, beams, posts, a conduit hole, the unit position — are durable and get pinned accurately first. What passes between them is disposable by comparison and can be designed on a branch. Split work by what persists, not by what already exists.

**When a measurement and the model disagree, the owner is looking at the house.** An agent measuring a drawing it cannot see should hold its own numbers loosely — see the reader trap below for what that costs when ignored.

## Reading furniture geometry

Each `pieceOfFurniture` carries `x` / `y` (plan centre), `elevation`, `width` / `depth` / `height`, and up to three rotations: `angle` (yaw, about the vertical axis), `pitch`, and `roll`. A duct run drawn as a horizontal cylinder is an upright cylinder with `pitch='1.5707964'`.

**When a piece is tilted, Sweet Home 3D publishes the rotated box itself** — `widthInPlan`, `depthInPlan`, `heightInPlan` — and `elevation` then measures to the bottom of *that* box, not of the upright model. Use them:

```python
wp = float(f.get("widthInPlan")  or f.get("width"))
dp = float(f.get("depthInPlan")  or f.get("depth"))
hp = float(f.get("heightInPlan") or f.get("height"))
z0, z1 = elevation, elevation + hp          # vertical extent, done
cs, sn = abs(cos(angle)), abs(sin(angle))   # yaw still applies to the footprint
ex, ey = wp * cs + dp * sn, wp * sn + dp * cs
```

Yaw is the only rotation left to apply, because it does not change which dimension is vertical.

**Reconstructing the tilt yourself from `width`/`depth`/`height` is the trap**, and a costly one: it lands the plan position correctly while putting the elevation off by tens of inches. Runs that are visibly joined on screen then read as broken chains, and the plausible numbers invite you to go fix a model that was never wrong. Prefer the published attributes over any rotation of your own — and if an adjacency result contradicts what the owner sees on screen, suspect the reader before the model.

## Common Mistakes

- **`unpack.sh` clears its `dest`** (so deletions propagate) and refuses a `.git` root — always point it at a subdir.
- **`--raw`** skips normalization — for format debugging, not for committing.
- **Never hand-edit `Home.xml` to add a property** — use `tag.py`, which splices text in place. Reparsing and rewriting the file renormalises attribute order and whitespace document-wide, which buries the change and breaks the no-op-save invariant.
- **`tag.py` indices come from the immediately preceding `list`** and move whenever the model is edited.
