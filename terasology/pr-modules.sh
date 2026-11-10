#!/usr/bin/env bash
# The module tree's generated files. A module is not allowed its own
# build.gradle: the harness copies templates/build.gradle into each one, and
# every module ignores it. `groovyw module get` does that copy for the
# modules it fetches; a module a bay seeded from the parent's checkout is a
# git clone, which brings nothing ignored, so Gradle skips it ("Found a module
# without a build.gradle, corrupt dir?") and the game runs without it.
#
#   pr-modules.sh ensure     copy the template into every module that lacks it
#
# cwd: the engine checkout. Says which modules it touched; nothing when none.
set -euo pipefail

cmd_ensure() {
  local template="templates/build.gradle" m
  [ -f "$template" ] || { echo "pr-modules: no $template in $PWD; is this the engine checkout?" >&2; return 1; }
  for m in modules/*/; do
    [ -f "$m/module.txt" ] || continue
    [ -f "$m/build.gradle" ] && continue
    cp "$template" "$m/build.gradle"
    echo "pr-modules: ${m%/} had no build.gradle; the template is in place"
  done
}

case "${1:-}" in
  ensure) cmd_ensure ;;
  *) echo "usage: pr-modules.sh ensure" >&2; exit 2 ;;
esac
