#!/usr/bin/env bash
# The smoke boot's seed save. `--create-last-game` needs a latest game manifest
# to exist, and the engine treats any directory under saves/ holding a titled
# manifest.json as a save. The manifest names every module with a version, so
# the template carries @Name@ placeholders and `generate` fills them from the
# checkout's own descriptors; shipping versions would go stale with the next
# SNAPSHOT bump. The result lives in the bay's .tmp/, which git ignores and a
# reset never touches.
#
#   pr-seed.sh generate   cwd: the engine checkout. Writes $NAUST_BAY_DIR/.tmp/naust/seed/manifest.json.
#   pr-seed.sh restore    copies it to saves/naust-seed/manifest.json (after every reset).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$HERE/seed-manifest.template.json"
SEED_DIR="${NAUST_BAY_DIR:?pr-seed: NAUST_BAY_DIR is required}/.tmp/naust/seed"

module_version() { # <module name>
  local f
  if [ "$1" = engine ]; then
    f="engine/src/main/resources/org/terasology/engine/module.txt"
  else
    f="modules/$1/module.txt"
  fi
  [ -f "$f" ] || { echo "pr-seed: no module descriptor for $1 at $PWD/$f" >&2; return 1; }
  # Not anchored: the engine's descriptor is one line, a module's is pretty-printed.
  sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$f" | head -n1
}

cmd_generate() {
  local out="$SEED_DIR/manifest.json" name version
  mkdir -p "$SEED_DIR"
  cp "$TEMPLATE" "$out"
  for name in $(grep -oE '@[A-Za-z0-9]+@' "$TEMPLATE" | tr -d '@' | sort -u); do
    version="$(module_version "$name")" || exit 1
    [ -n "$version" ] || { echo "pr-seed: $name has no version in its descriptor" >&2; exit 1; }
    sed -i "s/@$name@/$version/g" "$out"
  done
  echo "pr-seed: wrote $out"
}

cmd_restore() {
  [ -f "$SEED_DIR/manifest.json" ] || { echo "pr-seed: no seed at $SEED_DIR/manifest.json; run 'pr-seed.sh generate' in the engine checkout first" >&2; exit 1; }
  mkdir -p saves/naust-seed
  cp "$SEED_DIR/manifest.json" saves/naust-seed/manifest.json
  touch saves/naust-seed/manifest.json
  echo "pr-seed: restored saves/naust-seed/manifest.json"
}

case "${1:-}" in
  generate) cmd_generate ;;
  restore)  cmd_restore ;;
  *) echo "usage: pr-seed.sh {generate|restore}" >&2; exit 2 ;;
esac
