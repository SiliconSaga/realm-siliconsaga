#!/usr/bin/env bash
# Repack an exploded directory into a .sh3d (a ZIP) openable in Sweet Home 3D.
# Inverse of unpack.sh. Usage: pack.sh <exploded-dir> <out.sh3d>
set -euo pipefail
dir="${1:?usage: pack.sh <exploded-dir> <out.sh3d>}"
out="${2:?usage: pack.sh <exploded-dir> <out.sh3d>}"

[ -d "$dir" ] || { echo "error: exploded dir '$dir' not found" >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { echo "error: 'zip' not found" >&2; exit 1; }

mkdir -p "$(dirname "$out")"
out_abs="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
rm -f "$out_abs"
# cd into the dir so entry names are clean (no leading path); -X drops extra attrs.
( cd "$dir" && zip -q -r -X "$out_abs" . )
echo "packed '$dir' -> '$out_abs'"
