#!/usr/bin/env bash
# Normalize an exploded Sweet Home 3D dir for clean git diffs:
#   - drop the serialized 'Home' blob — redundant with Home.xml (which SH3D reads in priority
#     since v5.3), binary, and re-churned on every save. The packed result is .sh3x-style;
#     SH3D re-adds 'Home' on each save, so we strip it again on every unpack.
#   - strip editor window/session-state <property> elements from Home.xml (frame geometry,
#     pane dividers, plan viewport, screen size, ... — machine/session chrome, app-regenerated).
# After this, a no-op open->save->unpack diffs to nothing and real edits are pure signal.
# Usage: normalize.sh <exploded-dir>
set -euo pipefail
dir="${1:?usage: normalize.sh <exploded-dir>}"
xml="$dir/Home.xml"
[ -f "$xml" ] || { echo "error: '$xml' not found" >&2; exit 1; }

# Drop the redundant serialized blob.
if [ -f "$dir/Home" ]; then
  rm -f "$dir/Home"
  echo "dropped serialized 'Home' blob (Home.xml is authoritative)"
fi

# Strip editor-state property lines (the SweetHome3D.* / swing.* UI namespaces only; any
# other <property> is left intact in case it carries real metadata).
before=$(wc -l < "$xml")
grep -Ev "<property name='com\.eteks\.sweethome3d\.(SweetHome3D|swing)\." "$xml" > "$xml.norm"
mv "$xml.norm" "$xml"
after=$(wc -l < "$xml")
echo "normalized Home.xml: stripped $(( before - after )) editor-state property line(s)"
