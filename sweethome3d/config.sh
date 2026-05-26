#!/usr/bin/env bash
# shellcheck disable=SC2034  # GIT_BIN/SVN_URL/IGNORE_PATHS/COMPONENT_DIR/AUTHORS_FILE/*_BRANCH are consumed by clone.sh & sync.sh after sourcing
# Shared configuration for the Sweet Home 3D git-svn mirror tooling.
# Sourced by clone.sh and sync.sh — the single source of truth for URL, exclusions, authors.

# --- git binary (must support git-svn) ---
# Apple's stock git lacks git-svn; Homebrew's separate `git-svn` formula provides it.
# Prefer whichever git actually has git-svn; override with GIT_BIN.
if [ -z "${GIT_BIN:-}" ]; then
  if command -v git >/dev/null 2>&1 && git svn --version >/dev/null 2>&1; then
    GIT_BIN=git                          # stock git already has git-svn (typical Linux)
  elif [ -x /opt/homebrew/bin/git ] && /opt/homebrew/bin/git svn --version >/dev/null 2>&1; then
    GIT_BIN=/opt/homebrew/bin/git        # Apple Silicon Homebrew
  elif [ -x /usr/local/bin/git ] && /usr/local/bin/git svn --version >/dev/null 2>&1; then
    GIT_BIN=/usr/local/bin/git           # Intel Homebrew
  else
    GIT_BIN=git                          # fall through to the clear error below
  fi
fi
if ! "$GIT_BIN" svn --version >/dev/null 2>&1; then
  echo "error: '$GIT_BIN' has no git-svn. Install it (macOS: 'brew install git-svn subversion')" >&2
  echo "       or set GIT_BIN to a git that does." >&2
  return 1 2>/dev/null || exit 1
fi

SVN_URL="https://svn.code.sf.net/p/sweethome3d/code/"

# Excluded from the mirror. Principle: keep SOURCE, drop DATA/CONTENT & build outputs.
# (rationale: 2026-05-25-sh3d-modernization-and-assets.md)
#   3DModels/, Textures/   bulky standalone asset libraries (content)
#   SweetHome3DJS/other/   dead historical junk (no longer in current trunk)
#   SweetHome3DExample*    realistic demo/sample homes (.sh3d/.zip) = CONTENT.
#                          KEPT (SH3D-maintained SOURCE, not content): crafted edge-case
#                          fixtures (damagedHome*, holes, home1, HomeTest, cube) and the
#                          vendored patched-source for the forked freehep/sunflow deps
#                          (*-src-diff.zip — ~0.5MB total, changes a couple times/year).
#   *.exe/.dmg/.pkg/.msi   built installer binaries (build output)
#   *.jar                  549MB of committed dependency jars
#   *.so/.dll/.dylib/.jnilib  native libs (Java3D/JOGL + the bundled yafaray ray-tracer)
# Jars, natives, and demo homes are restored on `main` (resolve-libs / Artifactory).
# MUST be identical on every clone AND fetch, or git-svn re-imports the excluded paths.
IGNORE_PATHS='(^|/)(3DModels|Textures)(/|$)|(^|/)SweetHome3DJS/other(/|$)|(^|/)SweetHome3DExample[^/]*\.(sh3d|zip)$|\.(exe|dmg|pkg|msi|jar|so|dll|dylib|jnilib)$'

# --- workspace + component paths ---
# Default layout: <workspace>/realms/<realm>/sweethome3d/ → workspace is three levels up.
# Override with SH3D_WORKSPACE_ROOT for standalone/CI checkouts. Validated below so a bad
# derivation can never feed clone.sh's `rm -rf`.
_SH3D_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${SH3D_WORKSPACE_ROOT:-$(cd "$_SH3D_DIR/../../.." && pwd)}"
if [ ! -d "$WORKSPACE_ROOT/components" ] || [ ! -e "$WORKSPACE_ROOT/ecosystem.yaml" ]; then
  echo "error: WORKSPACE_ROOT '$WORKSPACE_ROOT' doesn't look like the yggdrasil workspace" >&2
  echo "       (expected components/ and ecosystem.yaml). Set SH3D_WORKSPACE_ROOT to override." >&2
  return 1 2>/dev/null || exit 1
fi
COMPONENT_DIR="$WORKSPACE_ROOT/components/sweethome3d"
AUTHORS_FILE="$_SH3D_DIR/authors.txt"

# Branch roles (see the upstream<->main model in 2026-05-25-sh3d-mirror-design.md):
UPSTREAM_BRANCH="upstream"   # machine-only, tracks SVN trunk; never hand-edited
MAIN_BRANCH="main"           # our fork line (improvements, CI, resolve-libs)
