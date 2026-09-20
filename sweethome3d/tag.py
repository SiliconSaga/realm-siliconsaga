#!/usr/bin/env python3
"""Read and write Eldr assembly tags on the walls and rooms of a Sweet Home 3D Home.xml.

Sweet Home 3D's own UI cannot edit custom properties, and walls carry no editable name,
so this is how a wall gets told which assembly it is. Windows, doors and anything else in
the furniture list do NOT need this tool — they have a `name` you can type a
`[window/single]` tag into inside the application, where you can see which one you are
naming. This tool deliberately refuses them for that reason.

Usage (from the workspace root, against an EXPLODED tree):

    python3 realms/realm-siliconsaga/sweethome3d/tag.py list hoards/refrhus/sh3d-internals
    python3 realms/realm-siliconsaga/sweethome3d/tag.py set  hoards/refrhus/sh3d-internals \\
        wall 7 exterior_wall/r0
    python3 realms/realm-siliconsaga/sweethome3d/tag.py clear hoards/refrhus/sh3d-internals room 2

Indices come from the IMMEDIATELY PRECEDING `list` and are not stable across edits in
Sweet Home 3D. List, set, verify — do not save an index for later.

Why this edits text rather than reparsing: a full XML parse-and-rewrite would renormalise
attribute order, quoting and whitespace across the whole document, which would bury the
one-line change in a file-wide diff and break the no-op-save invariant that `normalize.sh`
exists to protect. So the element is located and spliced in place, and every byte outside
the tag is left exactly as Sweet Home 3D wrote it.
"""
from __future__ import annotations

import math
import os
import re
import sys
import xml.etree.ElementTree as ET

PROPERTY = "eldr.assembly"

# Categories a tag may name. Kept in step with eldr/sidecar.py CATEGORIES — duplicated
# rather than imported because this tool must run standalone in the realm, with no
# dependency on the eldr component being cloned beside it.
CATEGORIES = {
    "exterior_wall", "basement_wall", "window", "door",
    "ceiling", "floor", "buffer_wall", "buffer_floor", "exposed_floor",
}

COMPASS = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
           "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]


def home_xml_path(target: str) -> str:
    """Accept either the exploded directory or the Home.xml inside it."""
    if os.path.isdir(target):
        return os.path.join(target, "Home.xml")
    return target


def _f(elem, name, default=0.0):
    try:
        return float(elem.get(name))
    except (TypeError, ValueError):
        return default


def _bearing(x1, y1, x2, y2, north_dir_rad: float) -> str:
    """The 16-point compass label for a wall's outward run, honouring the model compass.

    Plan +y runs SOUTH in Sweet Home 3D, so a wall drawn left-to-right along the top of
    the plan runs east. `northDirection` rotates the whole plan against true north, which
    on a model set from a survey is rarely zero — Refrhus sits at ~318 degrees, so plan
    north is not true north and a label computed without it would be wrong by that much.
    """
    ang = math.degrees(math.atan2(x2 - x1, -(y2 - y1)))     # 0 = plan north, clockwise
    ang = (ang + math.degrees(north_dir_rad)) % 360.0
    return COMPASS[int((ang + 11.25) % 360.0 / 22.5)]


def _centroid(points):
    n = len(points)
    return (sum(p[0] for p in points) / n, sum(p[1] for p in points) / n)


def _tags_of(elem) -> list[str]:
    for p in elem.findall("property"):
        if p.get("name") == PROPERTY:
            return (p.get("value") or "").split()
    return []


def _inventory(xml_text: str):
    """(walls, rooms) as display records, in document order — the order `set` indexes."""
    root = ET.fromstring(xml_text)
    level_names = {lv.get("id"): (lv.get("name") or "(unnamed)")
                   for lv in root.findall("level")}
    compass = root.find("compass")
    north = _f(compass, "northDirection", 0.0) if compass is not None else 0.0

    rooms = []
    for r in root.findall("room"):
        pts = [(_f(p, "x"), _f(p, "y")) for p in r.findall("point")]
        if len(pts) < 3:
            continue
        area = abs(sum(pts[i][0] * pts[(i + 1) % len(pts)][1]
                       - pts[(i + 1) % len(pts)][0] * pts[i][1]
                       for i in range(len(pts)))) / 2.0
        rooms.append({
            "id": r.get("id"), "name": r.get("name") or "(unnamed)",
            "level": level_names.get(r.get("level"), "?"),
            "level_id": r.get("level"),
            "area_ft2": area / 929.0304, "centroid": _centroid(pts),
            "tags": _tags_of(r),
        })

    walls = []
    for w in root.findall("wall"):
        x1, y1 = _f(w, "xStart"), _f(w, "yStart")
        x2, y2 = _f(w, "xEnd"), _f(w, "yEnd")
        mid = ((x1 + x2) / 2.0, (y1 + y2) / 2.0)
        lid = w.get("level")
        near = [rm for rm in rooms if rm["level_id"] == lid]
        nearest = min(near, key=lambda rm: math.dist(mid, rm["centroid"])) if near else None
        walls.append({
            "id": w.get("id"),
            "level": level_names.get(lid, "?"),
            "length_ft": math.dist((x1, y1), (x2, y2)) / 30.48,
            "facing": _bearing(x1, y1, x2, y2, north),
            "near": nearest["name"] if nearest else "-",
            "tags": _tags_of(w),
        })
    return walls, rooms


def cmd_list(target: str) -> int:
    with open(home_xml_path(target), encoding="utf-8", newline="") as fh:
        walls, rooms = _inventory(fh.read())

    print(f"WALLS ({len(walls)}) — index, level, length, run, nearest room, tag")
    for i, w in enumerate(walls, 1):
        tag = " ".join(w["tags"]) or "-"
        print(f"  wall {i:>3}  {w['level']:<24} {w['length_ft']:>6.1f} ft  "
              f"{w['facing']:<3}  {w['near']:<20} {tag}")
    print()
    print(f"ROOMS ({len(rooms)}) — index, level, name, area, tag")
    for i, r in enumerate(rooms, 1):
        tag = " ".join(r["tags"]) or "-"
        print(f"  room {i:>3}  {r['level']:<24} {r['name']:<24} "
              f"{r['area_ft2']:>7.1f} ft²  {tag}")
    print()
    print("Indices are valid only until the model is edited. Windows and doors are not "
          "listed:\ntag those by name in Sweet Home 3D, e.g. 'Bedroom window "
          "[window/single]'.")
    return 0


# A variant ends up inside a single-quoted XML attribute, unescaped, so the
# characters that could close it early or open a new one are refused rather
# than encoded. Nothing legitimate needs them: variants are short names like
# r0, r11, single, storm, 2x6+r5.
VARIANT_RE = re.compile(r"\A[A-Za-z0-9][A-Za-z0-9_.+-]*\Z")


def _validate(keys: list[str]) -> None:
    for key in keys:
        category, sep, variant = key.partition("/")
        if not sep or not variant:
            raise SystemExit(
                f"error: '{key}' is not a variant key. Expected '<category>/<name>', "
                f"e.g. exterior_wall/r0. A bare category is the default and needs no tag.")
        if category not in CATEGORIES:
            raise SystemExit(
                f"error: '{key}' names unknown category '{category}'. "
                f"Known: {', '.join(sorted(CATEGORIES))}")
        if not VARIANT_RE.match(variant):
            raise SystemExit(
                f"error: '{variant}' is not a usable variant name. Use letters, "
                f"digits, and _ . + - only, starting with a letter or digit. "
                f"The value is written into an XML attribute as-is.")


def _element_span(xml_text: str, kind: str, obj_id: str) -> tuple[int, int, str, bool]:
    """(start, end, indent, self_closing) of the `kind` element carrying `obj_id`.

    Text-level on purpose — see the module docstring. The id is unique per the DTD
    (`id ID #REQUIRED`), so matching on it cannot hit the wrong element.
    """
    open_re = re.compile(rf"([ \t]*)<{kind}\b[^>]*\bid=['\"]{re.escape(obj_id)}['\"][^>]*?(/?)>")
    m = open_re.search(xml_text)
    if not m:
        raise SystemExit(f"error: no <{kind}> with id {obj_id} found")
    indent = m.group(1)
    if m.group(2) == "/":
        return m.start(), m.end(), indent, True
    close = xml_text.index(f"</{kind}>", m.end()) + len(f"</{kind}>")
    return m.start(), close, indent, False


def _rewrite(xml_text: str, kind: str, obj_id: str, keys: list[str]) -> str:
    """Return `xml_text` with the object's assembly property set to `keys` (or removed).

    Everything outside the property element is preserved byte for byte, including the
    file's line ending — inserted lines copy whatever the file already uses rather than
    assuming "\n", or a CRLF model comes back with a couple of bare LF in it.
    """
    start, end, indent, self_closing = _element_span(xml_text, kind, obj_id)
    nl = "\r\n" if "\r\n" in xml_text else "\n"
    block = xml_text[start:end]
    prop_re = re.compile(
        rf"[ \t]*<property\s+name=['\"]{re.escape(PROPERTY)}['\"][^>]*/>\r?\n?")
    block = prop_re.sub("", block)                       # drop any existing tag first

    if not keys:                                          # `clear` — nothing to insert
        # An element this tool reopened and has now emptied should go back to being
        # self-closing, so that set-then-clear returns the original bytes rather than
        # leaving `<wall ...></wall>` behind as diff noise.
        empty = re.compile(rf"\A(\s*<{kind}\b[^>]*?)>\s*</{kind}>\Z", re.S)
        m = empty.match(block)
        if m:
            block = f"{m.group(1)}/>"
        return xml_text[:start] + block + xml_text[end:]

    value = " ".join(keys)
    prop = f"{indent}  <property name='{PROPERTY}' value='{value}'/>"
    if self_closing:
        # `<wall ... />` has no children yet: reopen it and give it a body. The DTD puts
        # `property*` first among a wall's children, so a later texture or baseboard
        # written by Sweet Home 3D still lands in a valid order.
        head = block.rstrip()
        assert head.endswith("/>")
        block = f"{head[:-2].rstrip()}>{nl}{prop}{nl}{indent}</{kind}>"
    else:
        # Splice the property in as the first child and leave the existing children
        # exactly as they were — including their own indentation, which is why nothing
        # is stripped or re-added here. Re-indenting the next line is the easy mistake.
        head_end = block.index(">") + 1
        block = block[:head_end] + nl + prop + block[head_end:]
    return xml_text[:start] + block + xml_text[end:]


def cmd_set(target: str, kind: str, index: int, keys: list[str]) -> int:
    if kind not in ("wall", "room"):
        raise SystemExit("error: kind must be 'wall' or 'room'. Windows and doors are "
                         "tagged by name in Sweet Home 3D, not here.")
    _validate(keys)
    path = home_xml_path(target)
    with open(path, encoding="utf-8", newline="") as fh:
        xml_text = fh.read()
    walls, rooms = _inventory(xml_text)
    items = walls if kind == "wall" else rooms
    if not 1 <= index <= len(items):
        raise SystemExit(f"error: {kind} index {index} out of range (1..{len(items)}). "
                         f"Re-run `list` — indices move when the model is edited.")
    obj = items[index - 1]
    if not obj["id"]:
        raise SystemExit(
            f"error: {kind} {index} carries no id, so it cannot be addressed "
            f"safely. The DTD makes id required — re-save the model in Sweet "
            f"Home 3D to have one written, or tag this one by hand.")
    updated = _rewrite(xml_text, kind, obj["id"], keys)
    if updated == xml_text:
        print(f"unchanged: {kind} {index} already carries {' '.join(keys) or '(no tag)'}")
        return 0
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(updated)
    label = obj.get("name") or obj["id"]
    print(f"{kind} {index} ({label}, {obj['level']}) -> {' '.join(keys) or '(cleared)'}")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    cmd, target = argv[1], argv[2]
    if cmd == "list":
        return cmd_list(target)
    if cmd == "set":
        if len(argv) < 6:
            raise SystemExit("usage: tag.py set <dir> <wall|room> <index> <key> [key...]")
        return cmd_set(target, argv[3], int(argv[4]), argv[5:])
    if cmd == "clear":
        if len(argv) < 5:
            raise SystemExit("usage: tag.py clear <dir> <wall|room> <index>")
        return cmd_set(target, argv[3], int(argv[4]), [])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
