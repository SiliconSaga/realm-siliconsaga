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
#       * the <home ... selectedLevel='...'> attribute — the last-edited level, pure editor
#         churn. An inline attribute (not its own line), so stripped via sed s/// below;
#         SH3D just defaults to a level on open.
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
# Use sed, not `grep -Ev`: grep exits 1 when it filters out *every* line, which under
# `set -e` would abort the script before the mv (and a bare `|| true` would instead mask a
# real read error and clobber Home.xml with an empty file). sed deletes matches and exits 0.
sed -E -e "/<property name='com\.eteks\.sweethome3d\.(SweetHome3D|swing)\.|<(observerCamera|camera) attribute='(observerCamera|topCamera)'/d" -e "s/ selectedLevel='[^']*'//" "$xml" > "$xml.norm"
# Never replace Home.xml with nothing — guard against a future pattern that empties the file.
[ -s "$xml.norm" ] || { echo "error: normalization produced an empty Home.xml — aborting" >&2; rm -f "$xml.norm"; exit 1; }
mv "$xml.norm" "$xml"
after=$(wc -l < "$xml")
echo "normalized Home.xml: stripped $(( before - after )) volatile line(s) (UI state + cameras) + selectedLevel attribute"
