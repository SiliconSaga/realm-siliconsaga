#!/usr/bin/env bash
# Shared configuration for the Sweet Home 3D git-svn mirror tooling.
# Sourced by clone.sh and sync.sh — the single source of truth for URL, exclusions, authors.

# Homebrew git carries git-svn (Apple's git does not). CI can override with: GIT_BIN=git
GIT_BIN="${GIT_BIN:-/opt/homebrew/bin/git}"

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

# Resolve paths from this file's location (realms/realm-siliconsaga/sweethome3d/).
_SH3D_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$_SH3D_DIR/../../.." && pwd)"
COMPONENT_DIR="$WORKSPACE_ROOT/components/sweethome3d"
AUTHORS_FILE="$_SH3D_DIR/authors.txt"

# Branch roles (see the upstream<->main model in 2026-05-25-sh3d-mirror-design.md):
UPSTREAM_BRANCH="upstream"   # machine-only, tracks SVN trunk; never hand-edited
MAIN_BRANCH="main"           # our fork line (improvements, CI, resolve-libs)
