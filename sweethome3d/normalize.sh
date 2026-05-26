#!/usr/bin/env bash
# Normalize an exploded Home.xml for clean git diffs: strip editor window/session-state
# <property> elements (frame geometry, pane dividers, plan viewport, screen size, column
# widths, photo-dialog geometry, ...). These are machine/session chrome the app regenerates
# on open/save — not house design — so after normalizing, a no-op open->save->unpack diffs
# to nothing and real edits show as pure signal.
# Usage: normalize.sh <exploded-dir>
set -euo pipefail
dir="${1:?usage: normalize.sh <exploded-dir>}"
xml="$dir/Home.xml"
[ -f "$xml" ] || { echo "error: '$xml' not found" >&2; exit 1; }

before=$(wc -l < "$xml")
# Strip editor-state property lines (the SweetHome3D.* and swing.* UI namespaces only;
# any other <property> is left intact in case it carries real metadata).
grep -Ev "<property name='com\.eteks\.sweethome3d\.(SweetHome3D|swing)\." "$xml" > "$xml.norm"
mv "$xml.norm" "$xml"
after=$(wc -l < "$xml")
echo "normalized Home.xml: stripped $(( before - after )) editor-state property line(s)"
