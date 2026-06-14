#!/usr/bin/env bash
# Explode a Sweet Home 3D .sh3d (a ZIP) into a directory for git-diffable tracking, then
# normalize Home.xml (strip editor window/session state) so diffs are pure design signal.
# The exploded dir is the source of truth; the .sh3d is a generated artifact (see pack.sh).
# Usage: unpack.sh <file.sh3d> <dest-dir> [--raw]
#   <dest-dir> is cleared first (so .sh3d deletions are reflected on re-unpack) — point it at
#   a SUBDIR, not a repo/hoard root (guarded). --raw skips normalization (faithful round-trip).
set -euo pipefail
_UNPACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="${1:?usage: unpack.sh <file.sh3d> <dest-dir> [--raw]}"
dest="${2:?usage: unpack.sh <file.sh3d> <dest-dir> [--raw]}"
mode="${3:-}"

[ -f "$src" ] || { echo "error: source '$src' not found" >&2; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo "error: 'unzip' not found" >&2; exit 1; }

# Guard: never clear a repo/hoard root — explode into a subdir of it instead.
if [ -e "$dest/.git" ]; then
  echo "error: '$dest' is a repo root (.git present). Explode into a subdir, e.g. '$dest/<name>'." >&2
  exit 1
fi
# Guard: the clear below (find -delete) is destructive — refuse a symlink so we can't be
# redirected out of the intended tree.
if [ -L "$dest" ]; then
  echo "error: '$dest' is a symlink; point at a real directory." >&2
  exit 1
fi

mkdir -p "$dest"
# Resolve to a physical absolute path and refuse the catastrophic targets (filesystem root,
# $HOME) before deleting — a mistyped or externally-supplied dest must never wipe them.
dest_abs="$(cd "$dest" && pwd -P)" || { echo "error: cannot resolve '$dest'" >&2; exit 1; }
case "$dest_abs" in
  / | "${HOME:-}")
    echo "error: refusing to clear '$dest_abs' — explode into a dedicated subdir." >&2
    exit 1
    ;;
esac
find "$dest_abs" -mindepth 1 -delete      # clean re-unpack: reflect deletions
unzip -q -o "$src" -d "$dest_abs"
echo "unpacked '$src' -> '$dest/' ($(find "$dest" -type f | wc -l | tr -d ' ') files)"

if [ "$mode" = "--raw" ]; then
  echo "(--raw: skipped normalization)"
else
  bash "$_UNPACK_DIR/normalize.sh" "$dest"
fi
