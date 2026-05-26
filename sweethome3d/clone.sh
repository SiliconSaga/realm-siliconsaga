#!/usr/bin/env bash
# (Re-)clone Sweet Home 3D SVN trunk into components/sweethome3d as a git-svn mirror.
# Faithful SOURCE only — assets, junk, installers, jars, natives, demo homes excluded (config.sh).
# Usage: bash clone.sh [--force]    (--force replaces an existing clone; it is fully regenerable)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

if [ -e "$COMPONENT_DIR" ]; then
  if [ "${1:-}" = "--force" ] || [ "${FORCE:-}" = "1" ]; then
    # Safety guard: never let an empty/misderived path feed `rm -rf`.
    case "$COMPONENT_DIR" in
      "" | "/" | "$HOME")
        echo "error: refusing to rm unsafe COMPONENT_DIR='$COMPONENT_DIR'" >&2
        exit 1 ;;
    esac
    case "$COMPONENT_DIR" in
      "$WORKSPACE_ROOT"/components/*) ;;  # expected location — ok
      *)
        echo "error: COMPONENT_DIR '$COMPONENT_DIR' is not under '$WORKSPACE_ROOT/components/' — refusing rm" >&2
        exit 1 ;;
    esac
    echo ">> removing existing $COMPONENT_DIR (regenerable)"
    rm -rf "$COMPONENT_DIR"
  else
    echo "error: $COMPONENT_DIR already exists. Re-run with --force to replace it." >&2
    exit 1
  fi
fi

echo ">> git svn clone --stdlayout (via $GIT_BIN)"
echo "   ignoring: $IGNORE_PATHS"
"$GIT_BIN" svn clone \
  --stdlayout \
  --authors-file="$AUTHORS_FILE" \
  --ignore-paths="$IGNORE_PATHS" \
  "$SVN_URL" "$COMPONENT_DIR"

echo ">> branches: '$UPSTREAM_BRANCH' (mirror) + '$MAIN_BRANCH' (fork)"
"$GIT_BIN" -C "$COMPONENT_DIR" branch -m "$UPSTREAM_BRANCH"   # rename clone's default branch
"$GIT_BIN" -C "$COMPONENT_DIR" branch "$MAIN_BRANCH"          # main at upstream HEAD

echo ">> done — on '$UPSTREAM_BRANCH'; '$MAIN_BRANCH' ready for fork work."
"$GIT_BIN" -C "$COMPONENT_DIR" log -1 --format='   HEAD %h  %an  %ad  %s'
