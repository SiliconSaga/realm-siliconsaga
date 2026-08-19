---
name: sh3d-envelope
description: Use when deciding what belongs in a house's thermal envelope, reading or changing a Sweet Home 3D model for HVAC load purposes, running Eldr, or reconciling Eldr's numbers against a professional Manual J. Covers the edit-run-compare loop and which divergences are deliberate.
---

# The thermal envelope (reasoning about a house for load calculations)

For the `.sh3d` format and the pack/unpack loop use the `sweethome3d` skill; for the upstream mirror use `sweethome3d-mirror`. This skill is about **what the model should contain and why**, which is the part no tooling can check for you.

The founding split: **Sweet Home 3D owns geometry, the side-car owns thermal properties.** Eldr never writes the model. If a number is wrong, decide first which of those two it lives in — that answers who fixes it and how.

## What is in the envelope

The envelope is the boundary of *conditioned* space. Everything below follows from that one sentence, and each has been got wrong at least once.

- **A surface on unconditioned space is not envelope.** A window in an attached garage contributes nothing, because the garage is outside the boundary — the *wall between garage and house* is the envelope surface, not the garage's own exterior wall. Professional reports drop these for the same reason; if yours and theirs disagree on window count, this is the first thing to check.
- **An opening that is no longer an opening is not a window.** A basement window bricked up between basement and crawlspace is opaque wall now. Left drawn as glass it overstates loss on both sides of the boundary.
- **Interior doors are not envelope doors.** Only doors between conditioned space and outside (or a buffer space) count. Over-counting here is easy because a door object looks identical either way.
- **A window in a well is still a window.** A well does not insulate, so it takes the full ΔT — but it gets essentially no solar gain, which matters for cooling, not heating.
- **A garage door belongs to the garage.** It separates unconditioned space from outdoors, so it is outside the envelope entirely.
- **Undrawn floor area silently inflates the wall area.** A wall is on the envelope when a conditioned room sits on *exactly one* side. Conditioned space not yet drawn as a room therefore reads as outdoors, and every interior partition bordering it gets counted as exterior. Drawing the rooms is the fix; the report's *Schematic gaps* block is the symptom.

## Buffer spaces, and why summer is not winter

A buffer space (attic, crawlspace, garage) sits between conditioned space and outdoors and floats at some fraction of the design ΔT. Two things are worth internalising:

- **`vented` and `factor` are WINTER shorthands.** Both cap a space at or below outdoor air, which is backwards for a sunlit attic in July. Eldr substitutes a real temperature for the attic in summer — `cooling.attic_temp_f` if declared, else a sol-air estimate — so an unvented attic can carry a cooling factor above 1. On Refrhus it is 0.50 in winter and 3.66 in summer.
- **That asymmetry is physics, not a bug.** An unvented attic *helps* in winter (stale air does not track outdoor temperature) and *hurts* in summer (superheated air has nowhere to go). Do not "fix" an unvented attic by declaring it vented to match a professional report — model the house you have, and record the divergence.

Only the attic currently gets the hot-space summer substitution. **The garage does not**, and an attached unventilated garage with a sun-facing door genuinely runs hot in summer — a known gap, not a modelled decision.

## The operating loop

```bash
# 1. edit in Sweet Home 3D, then re-explode
bash realms/realm-siliconsaga/sweethome3d/unpack.sh \
    hoards/refrhus/Refrhus.sh3d hoards/refrhus/sh3d-internals

# 2. run the engine (it reads a packed .sh3d or an exploded Home.xml)
PYTHONPATH=components/eldr components/eldr/.venv/bin/python -m eldr.cli \
    hoards/refrhus/Refrhus.sh3d hoards/refrhus/eldr-sidecar.yaml

# 3. archive the run before changing anything else
#    hoards/refrhus/hvac/eldr-runs/<date>-<what-changed>.md
```

**Read the *Assumptions behind these numbers* section before the totals.** Five blocks disclose what the engine decided quietly: *Level heights*, *Buffer spaces*, *Assembly coverage*, *Borrowed U-values*, *Schematic gaps*. A borrowed U-value or an unexpected space name there explains more than the bottom line ever will.

**Archive every run.** Totals lie by cancellation: between two Refrhus runs the whole-house heating figure moved 0.7% while four components underneath it moved by thousands in opposite directions. Anyone comparing only bottom lines would have concluded nothing changed. `hoards/refrhus/hvac/README.md` carries that table as the standing argument for the practice.

## Comparing against a professional Manual J

- **Their construction-details page is the real document.** Page 3 of an ACCA progression lists every assembly with area, U-value and HTM. Divide HTM by U to recover the ΔT they applied — that is how you learn their conventions rather than guessing them.
- **Below grade, they load the full outdoor ΔT** and carry the soil path inside the U-value. That is why a bare masonry wall appears at U-0.293 rather than ~1.0. Eldr follows this. Declaring a bare-assembly U here silently overstates the load, and nothing will complain.
- **Expect deliberate divergences and record them.** On Refrhus: the crawlspace runs at an *observed* 32°F rather than their full-outdoor treatment, and the attic stays unvented because it is. Both are better data than the standard assumption. Write the reasoning into the side-car comment beside the value, where the next reader will actually meet it.
- **Match areas before arguing about U-values.** A gap in floor area or ceiling area is geometry and belongs in the model; a gap with matching areas is thermal and belongs in the side-car. Eldr's ceiling area of 984 ft² against a professional 1,547 ft² is a geometry problem (sloped and knee-wall surfaces), not an assembly one.

## Where a wrong number actually lives

| Symptom | Lives in | Fix |
|---|---|---|
| Area disagrees with a measured or professional figure | the model | draw it in Sweet Home 3D |
| Area is right, load is wrong | the side-car | correct the assembly U-value |
| One part of a category differs from the rest | the model **and** the side-car | declare a variant, tag the surfaces |
| Surface counted that should not be | the model | it is outside the envelope — delete or reclassify |
| A whole category is missing a U-value | the side-car | declare it; the *Borrowed U-values* block is telling you |
| A wall is exterior/interior/buffer wrongly | the side-car | `walls: {<id>: {boundary: …}}` — geometry cannot infer buffer |
