# Eldr Manual J — Phase 1a (heating walking skeleton) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Eldr engine's walking skeleton — read a Sweet Home 3D `Home.xml` (read-only) plus a YAML side-car, and produce a whole-house **heating load** (BTU/hr) and the corresponding supply-air **CFM**, rendered as a readable Markdown report. This is **Phase 1a** — the first slice of the design doc's Phase 1; cooling (solar/latent) is **1b** and per-room zoning is **1c**, each its own follow-up plan.

**Architecture:** A small, UI-agnostic Python package (`eldr/`) with focused modules: `units` (conversions), `sidecar` (thermal inputs), `geometry` (parse the model into envelope surfaces), `loads` (the heating math), `report` (render), `cli` (glue). Each module is independently testable; the engine never mutates the model. Cooling, per-room zoning, lat/long climate lookup, the interview skill, and the `.sh3p` plugin are deliberately out of scope here — see the design doc's phasing.

**Tech Stack:** Python 3.11+ (stdlib `xml.etree.ElementTree` for read-only parsing; `dataclasses`), PyYAML for the side-car, pytest for tests. No network, no other runtime deps.

**Design doc:** `realms/realm-siliconsaga/docs/plans/2026-07-15-eldr-manual-j-design.md`.

## Global Constraints

- **Python 3.11+**; standard library only except **PyYAML** (side-car) and **pytest** (tests).
- **Read-only on `Home.xml`.** Eldr parses the model; it never writes it. (ElementTree is fine for *reading*; the "no ElementTree" gotcha in `sh3d-scripts` is about *editing*.)
- **Units:** SH3D stores lengths in **centimetres**. Manual J is imperial. Convert at the geometry boundary; the engine works in **feet, ft², ft³, °F, BTU/hr** internally. U-values are **BTU/(hr·ft²·°F)**.
- **The 1.08 factor:** sensible heat `Q = 1.08 × CFM × ΔT` (BTU/hr), where `1.08 = 0.24 × 60 × 0.075`. Used for both infiltration load and supply-air CFM (with the appropriate ΔT each).
- **Determinism:** no randomness, no network. Design temperatures come from the side-car in Phase 1 (a lat/long → design-station lookup is a later task).
- **Prose in docs is not hard-wrapped** — one paragraph per line.
- **Location:** the package lives at `realms/realm-siliconsaga/sweethome3d/eldr/`; tests under `eldr/tests/`. **Run pytest from `realms/realm-siliconsaga/sweethome3d/`** (the parent of `eldr/`) so the top-level `eldr` package imports cleanly — e.g. `python -m pytest eldr/tests`. Every task's commands already use this working directory.

---

### Task 1: Package scaffold + units module

**Files:**
- Create: `realms/realm-siliconsaga/sweethome3d/eldr/__init__.py`
- Create: `realms/realm-siliconsaga/sweethome3d/eldr/units.py`
- Test: `realms/realm-siliconsaga/sweethome3d/eldr/tests/test_units.py`
- Create: `realms/realm-siliconsaga/sweethome3d/eldr/tests/__init__.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `units.sqcm_to_sqft(area_cm2: float) -> float`, `units.cm_to_ft(length_cm: float) -> float`, `units.SENSIBLE_FACTOR: float` (= 1.08).

- [ ] **Step 1: Write the failing test**

```python
# eldr/tests/test_units.py
from eldr import units


def test_cm_to_ft():
    assert units.cm_to_ft(30.48) == 1.0


def test_sqcm_to_sqft():
    # 1 ft = 30.48 cm, so 1 ft^2 = 929.0304 cm^2
    assert abs(units.sqcm_to_sqft(929.0304) - 1.0) < 1e-9


def test_sensible_factor():
    assert units.SENSIBLE_FACTOR == 1.08
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd realms/realm-siliconsaga/sweethome3d && python -m pytest eldr/tests/test_units.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'eldr'` / `AttributeError`.

- [ ] **Step 3: Write minimal implementation**

```python
# eldr/__init__.py
"""Eldr — Manual J heat-load engine for Sweet Home 3D (read-only)."""
```

```python
# eldr/units.py
"""Unit conversions. SH3D stores centimetres; Eldr works in imperial."""

CM_PER_FT = 30.48
SQCM_PER_SQFT = CM_PER_FT * CM_PER_FT  # 929.0304

# Q_sensible (BTU/hr) = SENSIBLE_FACTOR * CFM * deltaT(F); 0.24 * 60 * 0.075.
SENSIBLE_FACTOR = 1.08


def cm_to_ft(length_cm: float) -> float:
    return length_cm / CM_PER_FT


def sqcm_to_sqft(area_cm2: float) -> float:
    return area_cm2 / SQCM_PER_SQFT
```

Also create an empty `eldr/tests/__init__.py`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd realms/realm-siliconsaga/sweethome3d && python -m pytest eldr/tests/test_units.py -v`
Expected: PASS (3 passed).

- [ ] **Step 5: Commit**

```bash
git add eldr/__init__.py eldr/units.py eldr/tests/__init__.py eldr/tests/test_units.py
git commit -m "feat(eldr): package scaffold + unit conversions"
```

---

### Task 2: Side-car schema + loader

**Files:**
- Create: `realms/realm-siliconsaga/sweethome3d/eldr/sidecar.py`
- Create: `realms/realm-siliconsaga/sweethome3d/eldr/example-sidecar.yaml`
- Test: `realms/realm-siliconsaga/sweethome3d/eldr/tests/test_sidecar.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `sidecar.DesignConditions` dataclass: `indoor_heating_f: float`, `outdoor_heating_99_f: float`, `supply_air_rise_f: float`; property `heating_delta_t -> float` (= indoor − outdoor).
  - `sidecar.SideCar` dataclass: `assemblies: dict[str, float]` (category → U-value), `design: DesignConditions`, `infiltration_ach: float`.
  - `sidecar.load_sidecar(path: str) -> SideCar` — raises `ValueError` on a missing required key **or an unphysical value** (non-positive ΔT or supply-air rise, negative ACH or U-value), naming the offending field.

- [ ] **Step 1: Write the failing test**

```python
# eldr/tests/test_sidecar.py
import textwrap
import pytest
from eldr import sidecar


def _write(tmp_path, body):
    p = tmp_path / "sc.yaml"
    p.write_text(textwrap.dedent(body))
    return str(p)


def test_load_sidecar_ok(tmp_path):
    path = _write(tmp_path, """
        design:
          indoor_heating_f: 70
          outdoor_heating_99_f: 15
          supply_air_rise_f: 50
        infiltration:
          ach: 0.5
        assemblies:
          exterior_wall: 0.09
          window: 0.30
    """)
    sc = sidecar.load_sidecar(path)
    assert sc.design.heating_delta_t == 55
    assert sc.infiltration_ach == 0.5
    assert sc.assemblies["window"] == 0.30


def test_load_sidecar_missing_key(tmp_path):
    path = _write(tmp_path, "design:\n  indoor_heating_f: 70\n")
    with pytest.raises(ValueError):
        sidecar.load_sidecar(path)


def test_load_sidecar_rejects_bad_values(tmp_path):
    base = """
        design:
          indoor_heating_f: 70
          outdoor_heating_99_f: {outdoor}
          supply_air_rise_f: {rise}
        infiltration:
          ach: {ach}
        assemblies:
          exterior_wall: {u}
    """
    # zero supply-air rise would divide by zero when sizing CFM
    with pytest.raises(ValueError):
        sidecar.load_sidecar(_write(tmp_path, base.format(outdoor=15, rise=0, ach=0.5, u=0.09)))
    # non-positive heating delta (outdoor >= indoor)
    with pytest.raises(ValueError):
        sidecar.load_sidecar(_write(tmp_path, base.format(outdoor=70, rise=50, ach=0.5, u=0.09)))
    # negative ACH
    with pytest.raises(ValueError):
        sidecar.load_sidecar(_write(tmp_path, base.format(outdoor=15, rise=50, ach=-0.1, u=0.09)))
    # negative U-value
    with pytest.raises(ValueError):
        sidecar.load_sidecar(_write(tmp_path, base.format(outdoor=15, rise=50, ach=0.5, u=-0.09)))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd realms/realm-siliconsaga/sweethome3d && python -m pytest eldr/tests/test_sidecar.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'eldr.sidecar'`.

- [ ] **Step 3: Write minimal implementation**

```python
# eldr/sidecar.py
"""The thermal layer SH3D can't hold: assemblies, design conditions, infiltration."""
from __future__ import annotations
from dataclasses import dataclass
import yaml


@dataclass(frozen=True)
class DesignConditions:
    indoor_heating_f: float
    outdoor_heating_99_f: float
    supply_air_rise_f: float

    @property
    def heating_delta_t(self) -> float:
        return self.indoor_heating_f - self.outdoor_heating_99_f


@dataclass(frozen=True)
class SideCar:
    assemblies: dict[str, float]
    design: DesignConditions
    infiltration_ach: float


def _require(d: dict, key: str, ctx: str):
    if key not in d:
        raise ValueError(f"side-car missing required key '{ctx}.{key}'")
    return d[key]


def load_sidecar(path: str) -> SideCar:
    with open(path) as f:
        raw = yaml.safe_load(f) or {}
    design = _require(raw, "design", "root")
    infil = _require(raw, "infiltration", "root")
    sc = SideCar(
        assemblies={k: float(v) for k, v in _require(raw, "assemblies", "root").items()},
        design=DesignConditions(
            indoor_heating_f=float(_require(design, "indoor_heating_f", "design")),
            outdoor_heating_99_f=float(_require(design, "outdoor_heating_99_f", "design")),
            supply_air_rise_f=float(_require(design, "supply_air_rise_f", "design")),
        ),
        infiltration_ach=float(_require(infil, "ach", "infiltration")),
    )
    _validate(sc)
    return sc


def _validate(sc: SideCar) -> None:
    if sc.design.supply_air_rise_f <= 0:
        raise ValueError("design.supply_air_rise_f must be > 0 (it sizes CFM)")
    if sc.design.heating_delta_t <= 0:
        raise ValueError("design: indoor_heating_f must exceed outdoor_heating_99_f")
    if sc.infiltration_ach < 0:
        raise ValueError("infiltration.ach must be >= 0")
    for name, u in sc.assemblies.items():
        if u < 0:
            raise ValueError(f"assemblies.{name}: U-value must be >= 0")
```

```yaml
# eldr/example-sidecar.yaml — Refrhus starting point; refine as the house is measured.
design:
  indoor_heating_f: 70        # winter setpoint
  outdoor_heating_99_f: 15    # 99% heating design temp (NJ-ish placeholder; verify by location)
  supply_air_rise_f: 50       # supply-air temperature rise over room, for CFM sizing
infiltration:
  ach: 0.5                    # whole-house air changes/hour (estimate; blower-door later)
assemblies:                   # U-value, BTU/(hr*ft^2*F), per surface category
  exterior_wall: 0.09         # 2x4 + R-13-ish
  basement_wall: 0.20         # 8in cinderblock, partly below grade
  window: 0.30                # double-pane
  door: 0.40
  ceiling: 0.026              # attic floor, well insulated
  floor: 0.05                 # over unconditioned / slab edge
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd realms/realm-siliconsaga/sweethome3d && python -m pytest eldr/tests/test_sidecar.py -v`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add eldr/sidecar.py eldr/example-sidecar.yaml eldr/tests/test_sidecar.py
git commit -m "feat(eldr): side-car schema + loader"
```

---

### Task 3: Geometry — parse Home.xml into envelope surfaces

**Files:**
- Create: `realms/realm-siliconsaga/sweethome3d/eldr/geometry.py`
- Test: `realms/realm-siliconsaga/sweethome3d/eldr/tests/test_geometry.py`

**Interfaces:**
- Consumes: `units.sqcm_to_sqft`, `units.cm_to_ft`.
- Produces:
  - `geometry.Surface` dataclass: `category: str`, `area_ft2: float`.
  - `geometry.Envelope` dataclass: `surfaces: list[Surface]`, `volume_ft3: float`.
  - `geometry.extract_envelope(home_xml_path: str) -> Envelope`.

**Notes for the implementer (MVP geometry model, single-zone):**
- Categories emitted: `exterior_wall`, `window`, `door`, `ceiling`, `floor`, `basement_wall`.
- **Walls:** a wall is treated as **exterior** when it lies on its level's outer perimeter — i.e. its midpoint x is within 1 cm of the level's min or max wall-x, OR its midpoint y is within 1 cm of the level's min/max wall-y. (This is the same perimeter idea as `sh3d-scripts/sh3d_walls.py`; good enough for the whole-house skeleton, and refined later.) Wall gross area = `length × height`. Basement-level exterior walls emit `basement_wall`; other levels emit `exterior_wall`.
- **Windows/doors:** an opening counts toward the envelope **only if it sits on an exterior/basement wall** — its perpendicular distance to that wall segment is within the wall's half-thickness plus a small tolerance. Such an opening emits a `window` (catalogId or name containing "window") or `door` surface of `width × height`, and its area is **subtracted from that host wall** so walls are net-of-openings. **Interior doors/windows sit on interior walls, find no envelope host, and are ignored** — they neither add openings nor shrink exterior walls.
- **Ceiling / floor:** MVP uses the **footprint** of the highest and lowest levels — approximate the level footprint as the bounding rectangle of that level's walls (`(max_x−min_x) × (max_y−min_y)`). Highest level → one `ceiling`; lowest level → one `floor`.
- **Volume:** Σ over levels of `level_footprint × level_height`.
- Ignore furniture entirely.

- [ ] **Step 1: Write the failing test**

```python
# eldr/tests/test_geometry.py
import textwrap
from eldr import geometry

# A one-level box: 4 exterior walls forming a 1000cm x 500cm room, height 300cm;
# one 100cm x 100cm window on the south (exterior) wall; plus an interior partition
# wall carrying an interior door that must NOT count toward the envelope.
FIXTURE = textwrap.dedent("""\
<?xml version='1.0'?>
<home version='7400' name='t' wallHeight='300'>
  <level id='L1' name='Main' elevation='0.0' floorThickness='12.0' height='300' elevationIndex='0'/>
  <wall id='w-n' level='L1' xStart='0' yStart='0' xEnd='1000' yEnd='0' height='300' thickness='10'/>
  <wall id='w-s' level='L1' xStart='0' yStart='500' xEnd='1000' yEnd='500' height='300' thickness='10'/>
  <wall id='w-w' level='L1' xStart='0' yStart='0' xEnd='0' yEnd='500' height='300' thickness='10'/>
  <wall id='w-e' level='L1' xStart='1000' yStart='0' xEnd='1000' yEnd='500' height='300' thickness='10'/>
  <wall id='w-int' level='L1' xStart='500' yStart='0' xEnd='500' yEnd='500' height='300' thickness='10'/>
  <doorOrWindow id='win1' level='L1' catalogId='eTeks#window' name='Window' x='500' y='500' width='100' height='100'/>
  <doorOrWindow id='door-int' level='L1' catalogId='eTeks#doorFrame' name='Door frame' x='500' y='250' width='90' height='200'/>
</home>
""")


def _by_cat(env):
    out = {}
    for s in env.surfaces:
        out[s.category] = out.get(s.category, 0.0) + s.area_ft2
    return out


def test_extract_envelope_areas(tmp_path):
    p = tmp_path / "Home.xml"
    p.write_text(FIXTURE)
    env = geometry.extract_envelope(str(p))
    cats = _by_cat(env)
    from eldr import units
    # 4 exterior walls: two 1000x300 + two 500x300 = (2*300000 + 2*150000) cm^2 gross
    gross_wall = units.sqcm_to_sqft(2 * 1000 * 300 + 2 * 500 * 300)
    window = units.sqcm_to_sqft(100 * 100)
    assert abs(cats["window"] - window) < 1e-6
    # exterior wall area is net of the window
    assert abs(cats["exterior_wall"] - (gross_wall - window)) < 1e-6
    # ceiling & floor each = footprint 1000x500
    foot = units.sqcm_to_sqft(1000 * 500)
    assert abs(cats["ceiling"] - foot) < 1e-6
    assert abs(cats["floor"] - foot) < 1e-6
    # volume = 1000 x 500 x 300 cm^3 -> ft^3
    assert abs(env.volume_ft3 - (units.cm_to_ft(1000) * units.cm_to_ft(500) * units.cm_to_ft(300))) < 1e-6
    # the interior door is ignored (no envelope door surface, exterior walls unchanged)
    assert "door" not in cats
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd realms/realm-siliconsaga/sweethome3d && python -m pytest eldr/tests/test_geometry.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'eldr.geometry'`.

- [ ] **Step 3: Write minimal implementation**

```python
# eldr/geometry.py
"""Parse a Home.xml (read-only) into a single-zone envelope of Surfaces."""
from __future__ import annotations
from dataclasses import dataclass
import xml.etree.ElementTree as ET
from eldr import units


@dataclass(frozen=True)
class Surface:
    category: str
    area_ft2: float


@dataclass(frozen=True)
class Envelope:
    surfaces: list[Surface]
    volume_ft3: float


def _f(el, attr):
    return float(el.get(attr))


def _wall_midpoint(w):
    return ((_f(w, "xStart") + _f(w, "xEnd")) / 2.0,
            (_f(w, "yStart") + _f(w, "yEnd")) / 2.0)


def _wall_length_cm(w):
    dx = _f(w, "xEnd") - _f(w, "xStart")
    dy = _f(w, "yEnd") - _f(w, "yStart")
    return (dx * dx + dy * dy) ** 0.5


def _point_seg_dist_cm(px, py, w):
    """Perpendicular distance (cm) from a point to a wall segment."""
    ax, ay = _f(w, "xStart"), _f(w, "yStart")
    bx, by = _f(w, "xEnd"), _f(w, "yEnd")
    dx, dy = bx - ax, by - ay
    seg2 = dx * dx + dy * dy
    if seg2 == 0.0:
        return ((px - ax) ** 2 + (py - ay) ** 2) ** 0.5
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / seg2))
    cx, cy = ax + t * dx, ay + t * dy
    return ((px - cx) ** 2 + (py - cy) ** 2) ** 0.5


def extract_envelope(home_xml_path: str) -> Envelope:
    root = ET.parse(home_xml_path).getroot()

    levels = {lv.get("id"): lv for lv in root.findall("level")}
    walls_by_level: dict[str, list] = {}
    for w in root.findall("wall"):
        walls_by_level.setdefault(w.get("level"), []).append(w)

    surfaces: list[Surface] = []
    # Track net exterior wall area per (level, category) so we can subtract openings.
    wall_area_cm2: dict[str, float] = {}      # key: wall id -> net gross area (cm^2)
    wall_category: dict[str, str] = {}         # wall id -> category
    level_extent: dict[str, tuple] = {}        # level -> (minx,maxx,miny,maxy)
    volume_ft3 = 0.0

    for level_id, walls in walls_by_level.items():
        xs = [x for w in walls for x in (_f(w, "xStart"), _f(w, "xEnd"))]
        ys = [y for w in walls for y in (_f(w, "yStart"), _f(w, "yEnd"))]
        minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
        level_extent[level_id] = (minx, maxx, miny, maxy)
        lv = levels[level_id]
        is_basement = (lv.get("name") or "").lower().startswith("basement")
        for w in walls:
            mx, my = _wall_midpoint(w)
            exterior = (abs(mx - minx) < 1.0 or abs(mx - maxx) < 1.0
                        or abs(my - miny) < 1.0 or abs(my - maxy) < 1.0)
            if not exterior:
                continue
            area = _wall_length_cm(w) * _f(w, "height")
            wall_area_cm2[w.get("id")] = area
            wall_category[w.get("id")] = "basement_wall" if is_basement else "exterior_wall"
        # volume from footprint x height
        footprint = (maxx - minx) * (maxy - miny)
        volume_ft3 += (units.cm_to_ft(maxx - minx) * units.cm_to_ft(maxy - miny)
                       * units.cm_to_ft(_f(lv, "height")))

    # An opening belongs to the envelope only if it actually sits on an exterior/
    # basement wall (perp distance within that wall's half-thickness + tolerance).
    # Interior doors/windows sit on interior walls -> no envelope host -> ignored.
    OPENING_TOL_CM = 20.0

    def host_envelope_wall(dw):
        lid = dw.get("level")
        dx, dy = _f(dw, "x"), _f(dw, "y")
        best, best_d = None, None
        for w in walls_by_level.get(lid, []):
            wid = w.get("id")
            if wid not in wall_area_cm2:            # only envelope walls are candidates
                continue
            d = _point_seg_dist_cm(dx, dy, w)
            if d > _f(w, "thickness") / 2.0 + OPENING_TOL_CM:
                continue                            # opening isn't on this wall
            if best_d is None or d < best_d:
                best, best_d = wid, d
        return best

    for dw in root.findall("doorOrWindow"):
        host = host_envelope_wall(dw)
        if host is None:
            continue                                # interior opening -> not an envelope surface
        area_cm2 = _f(dw, "width") * _f(dw, "height")
        label = (dw.get("catalogId", "") + " " + (dw.get("name") or "")).lower()
        category = "window" if "window" in label else "door"
        surfaces.append(Surface(category, units.sqcm_to_sqft(area_cm2)))
        wall_area_cm2[host] = max(0.0, wall_area_cm2[host] - area_cm2)

    for wid, area_cm2 in wall_area_cm2.items():
        surfaces.append(Surface(wall_category[wid], units.sqcm_to_sqft(area_cm2)))

    # Ceiling on the highest level, floor on the lowest (by elevation).
    def level_elev(lid):
        return float(levels[lid].get("elevation"))

    if level_extent:
        levels_present = list(level_extent.keys())
        top = max(levels_present, key=level_elev)
        bot = min(levels_present, key=level_elev)
        for lid, cat in ((top, "ceiling"), (bot, "floor")):
            minx, maxx, miny, maxy = level_extent[lid]
            surfaces.append(Surface(cat, units.sqcm_to_sqft((maxx - minx) * (maxy - miny))))

    return Envelope(surfaces=surfaces, volume_ft3=volume_ft3)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd realms/realm-siliconsaga/sweethome3d && python -m pytest eldr/tests/test_geometry.py -v`
Expected: PASS (1 passed).

- [ ] **Step 5: Commit**

```bash
git add eldr/geometry.py eldr/tests/test_geometry.py
git commit -m "feat(eldr): parse Home.xml into a single-zone envelope"
```

---

### Task 4: Heating load + CFM

**Files:**
- Create: `realms/realm-siliconsaga/sweethome3d/eldr/loads.py`
- Test: `realms/realm-siliconsaga/sweethome3d/eldr/tests/test_loads.py`

**Interfaces:**
- Consumes: `geometry.Envelope`, `geometry.Surface`, `sidecar.SideCar`, `units.SENSIBLE_FACTOR`.
- Produces:
  - `loads.HeatingResult` dataclass: `conduction_btuh: float`, `infiltration_btuh: float`, `total_btuh: float`, `cfm: float`, `by_category: dict[str, float]`.
  - `loads.heating_load(env: geometry.Envelope, sc: sidecar.SideCar) -> HeatingResult` — raises `KeyError` if a surface category has no assembly U-value in the side-car.

- [ ] **Step 1: Write the failing test**

```python
# eldr/tests/test_loads.py
import pytest
from eldr import loads, geometry, sidecar


def _sc():
    return sidecar.SideCar(
        assemblies={"exterior_wall": 0.1, "window": 0.3},
        design=sidecar.DesignConditions(indoor_heating_f=70, outdoor_heating_99_f=20,
                                        supply_air_rise_f=50),
        infiltration_ach=0.5,
    )


def test_heating_load_math():
    env = geometry.Envelope(
        surfaces=[geometry.Surface("exterior_wall", 1000.0),
                  geometry.Surface("window", 100.0)],
        volume_ft3=12000.0,
    )
    r = loads.heating_load(env, _sc())
    dt = 50.0
    conduction = 0.1 * 1000 * dt + 0.3 * 100 * dt      # 5000 + 1500 = 6500
    infil_cfm = 0.5 * 12000 / 60.0                       # 100 CFM
    infiltration = 1.08 * infil_cfm * dt                 # 5400
    assert abs(r.conduction_btuh - conduction) < 1e-6
    assert abs(r.infiltration_btuh - infiltration) < 1e-6
    assert abs(r.total_btuh - (conduction + infiltration)) < 1e-6
    # CFM sized on supply-air rise, not the design delta-T
    assert abs(r.cfm - r.total_btuh / (1.08 * 50)) < 1e-6
    assert abs(r.by_category["window"] - 1500) < 1e-6


def test_heating_load_missing_assembly():
    env = geometry.Envelope(surfaces=[geometry.Surface("mystery", 10.0)], volume_ft3=100.0)
    with pytest.raises(KeyError):
        loads.heating_load(env, _sc())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd realms/realm-siliconsaga/sweethome3d && python -m pytest eldr/tests/test_loads.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'eldr.loads'`.

- [ ] **Step 3: Write minimal implementation**

```python
# eldr/loads.py
"""Phase 1 heating load: conduction (sum U*A*dT) + infiltration, and supply CFM."""
from __future__ import annotations
from dataclasses import dataclass
from eldr import geometry, sidecar, units


@dataclass(frozen=True)
class HeatingResult:
    conduction_btuh: float
    infiltration_btuh: float
    total_btuh: float
    cfm: float
    by_category: dict[str, float]


def heating_load(env: geometry.Envelope, sc: sidecar.SideCar) -> HeatingResult:
    dt = sc.design.heating_delta_t
    by_category: dict[str, float] = {}
    conduction = 0.0
    for s in env.surfaces:
        if s.category not in sc.assemblies:
            raise KeyError(f"no assembly U-value for category '{s.category}' in side-car")
        q = sc.assemblies[s.category] * s.area_ft2 * dt
        by_category[s.category] = by_category.get(s.category, 0.0) + q
        conduction += q

    infil_cfm = sc.infiltration_ach * env.volume_ft3 / 60.0
    infiltration = units.SENSIBLE_FACTOR * infil_cfm * dt

    total = conduction + infiltration
    cfm = total / (units.SENSIBLE_FACTOR * sc.design.supply_air_rise_f)
    return HeatingResult(conduction, infiltration, total, cfm, by_category)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd realms/realm-siliconsaga/sweethome3d && python -m pytest eldr/tests/test_loads.py -v`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add eldr/loads.py eldr/tests/test_loads.py
git commit -m "feat(eldr): heating load (conduction + infiltration) + supply CFM"
```

---

### Task 5: Report renderer

**Files:**
- Create: `realms/realm-siliconsaga/sweethome3d/eldr/report.py`
- Test: `realms/realm-siliconsaga/sweethome3d/eldr/tests/test_report.py`

**Interfaces:**
- Consumes: `loads.HeatingResult`, `sidecar.SideCar`.
- Produces: `report.render_heating(result: loads.HeatingResult, sc: sidecar.SideCar) -> str` (Markdown).

- [ ] **Step 1: Write the failing test**

```python
# eldr/tests/test_report.py
from eldr import report, loads, sidecar


def test_render_heating_contains_totals():
    sc = sidecar.SideCar(
        assemblies={"exterior_wall": 0.1},
        design=sidecar.DesignConditions(70, 20, 50),
        infiltration_ach=0.5,
    )
    r = loads.HeatingResult(conduction_btuh=6500.0, infiltration_btuh=5400.0,
                            total_btuh=11900.0, cfm=220.4,
                            by_category={"exterior_wall": 6500.0})
    md = report.render_heating(r, sc)
    assert "# Eldr — Heating Load" in md
    assert "11,900" in md          # total, thousands-separated
    assert "220" in md             # CFM
    assert "exterior_wall" in md
    assert "ΔT" in md and "50" in md
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd realms/realm-siliconsaga/sweethome3d && python -m pytest eldr/tests/test_report.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'eldr.report'`.

- [ ] **Step 3: Write minimal implementation**

```python
# eldr/report.py
"""Render a HeatingResult as a readable Markdown report."""
from __future__ import annotations
from eldr import loads, sidecar


def render_heating(result: loads.HeatingResult, sc: sidecar.SideCar) -> str:
    d = sc.design
    lines = [
        "# Eldr — Heating Load (Phase 1, whole-house)",
        "",
        f"- Indoor / 99% outdoor design: **{d.indoor_heating_f:.0f}°F / {d.outdoor_heating_99_f:.0f}°F** "
        f"(ΔT = {d.heating_delta_t:.0f}°F)",
        f"- Infiltration: **{sc.infiltration_ach:.2f} ACH**",
        "",
        "| Component | Load (BTU/hr) |",
        "|---|---:|",
    ]
    for cat, q in sorted(result.by_category.items()):
        lines.append(f"| {cat} | {q:,.0f} |")
    lines.append(f"| infiltration | {result.infiltration_btuh:,.0f} |")
    lines.append(f"| **total** | **{result.total_btuh:,.0f}** |")
    lines += [
        "",
        f"**Supply airflow:** {result.cfm:,.0f} CFM "
        f"(at {d.supply_air_rise_f:.0f}°F supply-air rise)",
        "",
        "_Phase 1 whole-house estimate. Not ACCA-certified. Room-by-room + cooling to follow._",
    ]
    return "\n".join(lines)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd realms/realm-siliconsaga/sweethome3d && python -m pytest eldr/tests/test_report.py -v`
Expected: PASS (1 passed).

- [ ] **Step 5: Commit**

```bash
git add eldr/report.py eldr/tests/test_report.py
git commit -m "feat(eldr): Markdown heating-load report"
```

---

### Task 6: CLI + end-to-end integration test + README

**Files:**
- Create: `realms/realm-siliconsaga/sweethome3d/eldr/cli.py`
- Create: `realms/realm-siliconsaga/sweethome3d/eldr/README.md`
- Test: `realms/realm-siliconsaga/sweethome3d/eldr/tests/test_integration.py`

**Interfaces:**
- Consumes: `geometry.extract_envelope`, `sidecar.load_sidecar`, `loads.heating_load`, `report.render_heating`.
- Produces: `cli.run(home_xml_path: str, sidecar_path: str) -> str` (the report), and a `main()` argparse entry point (`python -m eldr.cli <Home.xml> <sidecar.yaml>`).

- [ ] **Step 1: Write the failing test**

```python
# eldr/tests/test_integration.py
import textwrap
from eldr import cli

FIXTURE = textwrap.dedent("""\
<?xml version='1.0'?>
<home version='7400' name='t' wallHeight='300'>
  <level id='L1' name='Main' elevation='0.0' floorThickness='12.0' height='300' elevationIndex='0'/>
  <wall id='w-n' level='L1' xStart='0' yStart='0' xEnd='1000' yEnd='0' height='300' thickness='10'/>
  <wall id='w-s' level='L1' xStart='0' yStart='500' xEnd='1000' yEnd='500' height='300' thickness='10'/>
  <wall id='w-w' level='L1' xStart='0' yStart='0' xEnd='0' yEnd='500' height='300' thickness='10'/>
  <wall id='w-e' level='L1' xStart='1000' yStart='0' xEnd='1000' yEnd='500' height='300' thickness='10'/>
  <doorOrWindow id='win1' level='L1' catalogId='eTeks#window' name='Window' x='500' y='500' width='100' height='100'/>
</home>
""")

SIDECAR = textwrap.dedent("""\
design:
  indoor_heating_f: 70
  outdoor_heating_99_f: 15
  supply_air_rise_f: 50
infiltration:
  ach: 0.5
assemblies:
  exterior_wall: 0.09
  window: 0.30
  ceiling: 0.026
  floor: 0.05
""")


def test_end_to_end(tmp_path):
    home = tmp_path / "Home.xml"; home.write_text(FIXTURE)
    sc = tmp_path / "sc.yaml"; sc.write_text(SIDECAR)
    md = cli.run(str(home), str(sc))
    assert "# Eldr — Heating Load" in md
    assert "total" in md
    assert "CFM" in md
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd realms/realm-siliconsaga/sweethome3d && python -m pytest eldr/tests/test_integration.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'eldr.cli'`.

- [ ] **Step 3: Write minimal implementation**

```python
# eldr/cli.py
"""Wire the engine together: Home.xml + side-car -> heating-load report."""
from __future__ import annotations
import argparse
from eldr import geometry, sidecar, loads, report


def run(home_xml_path: str, sidecar_path: str) -> str:
    env = geometry.extract_envelope(home_xml_path)
    sc = sidecar.load_sidecar(sidecar_path)
    result = loads.heating_load(env, sc)
    return report.render_heating(result, sc)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="eldr", description="Eldr Manual J — Phase 1 heating load.")
    ap.add_argument("home_xml", help="path to an exploded Sweet Home 3D Home.xml")
    ap.add_argument("sidecar", help="path to the Eldr side-car YAML")
    args = ap.parse_args(argv)
    print(run(args.home_xml, args.sidecar))


if __name__ == "__main__":
    main()
```

```markdown
# Eldr — Manual J heat-load engine (Phase 1)

Read-only engine: parses an exploded Sweet Home 3D `Home.xml` + a YAML side-car
and prints a whole-house **heating load** + supply **CFM**.

## Run

```bash
cd realms/realm-siliconsaga/sweethome3d
python -m eldr.cli ../../../hoards/refrhus/sh3d-internals/Home.xml eldr/example-sidecar.yaml
```

## Test

```bash
cd realms/realm-siliconsaga/sweethome3d
python -m pytest eldr/tests -v
```

## Scope

Phase 1 is a whole-house heating skeleton. Cooling (solar-by-orientation +
latent), per-room zoning, lat/long climate lookup, the interview skill, and the
`.sh3p` plugin are follow-ups — see
`docs/plans/2026-07-15-eldr-manual-j-design.md`.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd realms/realm-siliconsaga/sweethome3d && python -m pytest eldr/tests -v`
Expected: PASS (all tests, all files).

- [ ] **Step 5: Smoke-test against the real house (manual, non-blocking)**

Run: `cd realms/realm-siliconsaga/sweethome3d && python -m eldr.cli ../../../hoards/refrhus/sh3d-internals/Home.xml eldr/example-sidecar.yaml`
Expected: a Markdown heating-load report with plausible non-zero totals. (Numbers are rough until the schematic true-up + real assemblies — that's expected.)

- [ ] **Step 6: Commit**

```bash
git add eldr/cli.py eldr/README.md eldr/tests/test_integration.py
git commit -m "feat(eldr): CLI + end-to-end heating-load pipeline"
```

---

## Self-Review

**Spec coverage (against the design doc):**
- Architecture (engine core, UI-agnostic) → Tasks 1–6 build exactly the engine; skill/plugin are explicitly deferred. ✓
- Inputs "SH3D owns geometry, side-car owns thermal" → geometry.py (SH3D) + sidecar.py (thermal). ✓
- Load math (heating `ΣU·A·ΔT` + infiltration; CFM = load ÷ 1.08·ΔT) → loads.py, with the design ΔT for load and supply-air rise for CFM. ✓
- Outputs (readable report; engine emits structured data, report is a thin renderer) → HeatingResult + report.py. ✓
- **Deferred, and clearly marked as such (not gaps):** cooling (solar/latent), per-room zoning, orientation/compass math, lat/long → design-station lookup, rule-based assembly matching (MVP uses category→U). These are named in the design doc's phasing and this plan's scope; each is a follow-up plan.

**Placeholder scan:** every code step contains complete, runnable code; no "TBD"/"add error handling"/"similar to Task N". ✓

**Type consistency:** `Surface(category, area_ft2)`, `Envelope(surfaces, volume_ft3)`, `SideCar(assemblies, design, infiltration_ach)`, `DesignConditions(...).heating_delta_t`, `HeatingResult(...)`, `heating_load(env, sc)`, `render_heating(result, sc)`, `run(home, sidecar)` — names/signatures match across Tasks 1–6. ✓

**Known MVP simplifications (intentional, documented in code + README):** perimeter-heuristic exterior-wall detection; bounding-rectangle ceiling/floor footprint; single-zone (no per-room); category-level U-values. All sound for a whole-house skeleton and flagged for refinement.

## Execution Handoff

Plan complete. Because the owner is parking execution until measurements exist, this plan is **written and ready but not yet executed** — the immediate next step is committing the design + this plan to the realm and opening a review PR.

When ready to build, two options:
1. **Subagent-Driven (recommended)** — a fresh subagent per task, review between tasks (superpowers:subagent-driven-development).
2. **Inline Execution** — tasks in-session with checkpoints (superpowers:executing-plans).
