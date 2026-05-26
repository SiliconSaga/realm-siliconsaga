#!/usr/bin/env bash
# Normalize an exploded Sweet Home 3D dir for clean git diffs:
#   - drop the serialized 'Home' blob — redundant with Home.xml (read in priority since v5.3),
#     re-added on every save; stripping it each unpack keeps the house fully text-diffable.
#   - strip volatile view/session state from Home.xml so a no-op open->save->unpack diffs to
#     nothing and real edits are pure signal:
#       * editor window/session <property> elements (frame/panes/viewport/screen/...)
#       * the default view cameras <observerCamera> and <camera attribute='topCamera'> —
#         their coords move as you navigate. Matched by attribute= so any NAMED/stored
#         viewpoints (<camera name='...'>) are preserved. SH3D recreates defaults on open.
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

# Strip volatile lines: editor-state properties + the two default view cameras.
before=$(wc -l < "$xml")
grep -Ev "<property name='com\.eteks\.sweethome3d\.(SweetHome3D|swing)\.|<(observerCamera|camera) attribute='(observerCamera|topCamera)'" "$xml" > "$xml.norm"
mv "$xml.norm" "$xml"
after=$(wc -l < "$xml")
echo "normalized Home.xml: stripped $(( before - after )) volatile line(s) (UI state + default cameras)"
