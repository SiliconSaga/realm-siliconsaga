# Eldr — Manual J heat-load engine for Sweet Home 3D

**Status:** Design + Phase-1a implementation plan written (2026-07-15); code parked pending house measurements. Companion to the Refrhus house-modeling work and the `refrhus-ducting` arc. Implementation plan: `2026-07-15-eldr-manual-j-phase1-plan.md`.

**Name:** *Eldr* — Old Norse "fire." Also reads as "Elder": a quiet, helpful support tool. Framing for the intro — Manual J reckons heat crossing the inside↔outside temperature difference: heat flowing from **Muspelheim** (fire) toward **Niflheim** (ice). Eldr measures that flow.

## 1. Purpose & phasing

Eldr turns a Sweet Home 3D house model into HVAC load numbers. Origin: the owner's Refrhus heat-pump + duct redo needs real load figures, and a partnering HVAC company (DK Mechanical) can put ACCA-grade output to use on this project and potentially beyond — so **certifiability is an explicit end goal, not a toy**. Start concrete against a house we know intimately; generalize later.

Phasing:

- **Phase 1 (this design):** whole-house + room-by-room **heating and cooling loads** (BTU/hr) via a transparent engineering method (`Σ U·A·ΔT` + infiltration + solar/internal/latent) — good-enough now, structured so ACCA Manual J 8th-edition tables slot in without a rewrite. Emits per-room **CFM targets** (`load ÷ 1.08·ΔT`), the bridge to duct design. **Phase 1 ships in slices, each testable on its own:** **1a** = the whole-house *heating* walking skeleton (the current implementation plan); **1b** = cooling (solar-by-orientation + latent); **1c** = per-room zoning + per-room CFM. This design describes the full Phase-1 target; the plan builds 1a first.
- **Phase 2:** **Manual D** — size the ducts the owner is already modeling in SH3D (the "squid," the trunk, the wall-stack risers) against the Phase-1 CFM within a static-pressure / friction budget.
- **Later:** ACCA-certifiable output; before/after insulation scenarios (especially the knee-wall/attic insulation redo); scan-data ingestion.

## 2. Architecture

Three cleanly separated pieces so the same core survives from CLI to plugin:

- **Engine** (UI-agnostic core): parsed geometry + thermal inputs → loads → structured results. Deterministic and testable against hand-worked cases and published examples. This is the reusable heart; everything else is a front door.
- **Interview skill** (the smart front door): an agent skill that reads the model, works out what's missing, and interviews the owner for it (assembly types, envelope boundary, infiltration, occupancy, window/attic specifics), then assembles the side-car and runs the engine. Mirrors the workspace convention — deterministic script + a skill that gathers the human data.
- **Side-car** (the thermal layer SH3D can't hold): a human-editable file (likely YAML) carrying assembly→U-value rules, the per-zone envelope boundary, climate/design conditions, infiltration, internal gains, and any geometry the model can't express (sloped attic / knee-wall areas).

Boundary discipline: the engine never talks to SH3D directly — it consumes a parsed geometry model + the side-car. A later **`.sh3p` plugin** wraps the same engine (assemblies assigned in-app, a "Compute load" action, a results panel); the load math never moves. Engine stays put, only the front door changes.

## 3. Inputs — and where each comes from

The organizing principle: **SH3D owns geometry; the side-car owns thermal.**

| Input | Source |
|---|---|
| Surface areas, volumes, window/door areas | SH3D geometry (walls, rooms, doorOrWindow, levels) |
| Wall exterior/interior classification | derived geometrically (existing `classify_walls.py` approach) |
| True orientation of each surface | SH3D **compass `northDirection`** + the surface's in-plan angle (see §4) |
| Assembly U-values (walls, windows, roof, floor) | side-car rules, matched to SH3D categories (thickness, level, room name, window catalog type) |
| Thermal-envelope boundary per zone | declared in the side-car (esp. knee-wall attic: roof-deck vs knee-wall+ceiling) |
| Attic / roof / sloped-ceiling areas SH3D can't model cleanly | side-car escape hatch (owner-supplied areas) |
| Design temperatures (99% heating / 1% cooling), daily range | derived from the compass **lat/long** → nearest ASHRAE/ACCA design station |
| Infiltration (ACH / construction tightness) | side-car input/estimate; blower-door number later |
| Internal gains (occupants, appliances, lighting) | side-car estimate from room types/areas |
| Solar / SHGC (cooling) | window area × true orientation × SHGC × shading (side-car) |
| Duct losses/gains | Phase 2, from the modeled duct runs |

Key freeing consequence: a window does **not** need a catalog-perfect match — it needs an accurate hole (area + true facing) plus a U-value/SHGC in the side-car. That decouples "make the schematic realistic" from "make the calc accurate."

## 4. Orientation — fix the compass, don't rotate the house

The Refrhus plan was drawn axis-aligned assuming true-south at the bottom, but the house sits slightly off-cardinal (indicated on the survey). Manual J cooling is orientation-sensitive, so true facing matters.

**Decision: do not rotate the geometry.** Set the SH3D **compass `northDirection`** to the true angle read off the survey's north arrow. The plan stays orthogonal (easy to edit) while north points at the real off-cardinal angle. Eldr computes each surface's true compass facing from `northDirection` + the surface's in-plan angle. Bonus: this also corrects SH3D's own 3D sun/shadow rendering. Rotating all walls and furniture would introduce float drift and make the model painful to edit for zero benefit.

This is both a one-time schematic fix (set `northDirection` from the survey) and a documented Eldr input.

## 5. The load math (Phase 1)

- **Heating:** `Q_heat = Σ(U·A·ΔT) over the envelope + infiltration load`, with `ΔT = indoor setpoint − 99% outdoor design temp`. Conservative — no solar or internal-gain credit — per Manual J heating practice.
- **Cooling:** sensible = conductive `Σ U·A·ΔT_cool` + **solar gain** (window area × true orientation × SHGC × shading) + internal gains; latent from infiltration + occupancy humidity. Orientation- and daily-range-aware.
- **Per-room CFM:** heating `Q_room ÷ (1.08 × supply ΔT)`; cooling `sensible_room ÷ (1.08 × supply ΔT)`. Take the larger → the room's design airflow. This is the handoff to Phase 2 / Manual D.
- **Fidelity knobs:** Phase 1 uses transparent coefficients; ACCA HTM/CLTD tables, construction-class infiltration, and room-by-room rules are **pluggable data** that replace the simplified pieces on the path to certifiable — no engine rewrite.

## 6. Outputs

- A **room-by-room table**: sensible / latent / total heating + cooling loads, and design CFM.
- A **whole-house summary**: total loads → equipment-sizing target (Manual S, later).
- A **readable report** for the HVAC partner. Exact format is deliberately TBD — Markdown/PDF vs spreadsheet vs an export into their own ACCA software — decided once we see what they consume. The engine emits structured data; the report is a thin renderer over it.

## 7. Later: the SH3D plugin

The engine is designed to be wrapped as a `.sh3p` plugin: assign assemblies to walls/rooms in-app (custom properties or a side-panel), a "Compute Eldr load" action, and a results panel / exported report. The plugin provides only UI + assembly assignment; the math stays in the shared engine. As of 2026-07 no existing SH3D plugin does HVAC/energy (the ecosystem is furniture/roof/wirings/export tools), so this is greenfield — a genuine differentiator. See the SH3D plugin developer's guide for the `.sh3p` API.

## 8. Open questions / deferred

- **Certifiability:** which ACCA tables/rules are strictly required, and what output a permit office / contractor will accept.
- **Manual D (Phase 2):** friction rate, fitting equivalent-lengths, reading duct segments from the model.
- **Before/after insulation scenarios** (the knee-wall/attic redo) — a side-car variant per scenario, so Eldr can quantify the upgrade.
- **Scan-data ingestion** — sharpen geometry + assemblies from the incoming 3D scan.
- **Engine language/runtime** — likely Python (matches the existing `components/langr/sh3d-scripts/`); decide at planning time.

## 9. Dependency — the schematic true-up

Eldr's accuracy tracks the model's accuracy. The parallel **schematic true-up** (a Thalamus checklist, not its own doc) feeds it: re-measured joists / basement posts, the two main-floor void walls, window sizing, the compass `northDirection`, and — highest Manual-J leverage — the **2nd-floor knee walls + sloped ceilings + top attic ("devil's triangle")**, which are both incomplete in the model and exactly where the insulation money goes. Roof angles can be measured from the 2nd-floor door onto the garage roof (including the original-house vs kitchen-extension slope change, which softens the pitch toward the backyard). Until modeled, those areas ride in Eldr's side-car — Eldr is never blocked on wrestling SH3D into perfect slopes.
