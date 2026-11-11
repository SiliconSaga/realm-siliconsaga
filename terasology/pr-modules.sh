#!/usr/bin/env bash
# The module tree's generated files, the ones `groovyw module get` copies in
# after its clone (config/groovy/module.groovy, refreshGradle): a module is not
# allowed its own build.gradle, so the harness copies templates/build.gradle
# into each one and every module ignores it, and a module's tests get
# templates/module.logback-test.xml as src/test/resources/logback-test.xml
# when they have none. A module a bay seeded from the parent's checkout is a
# plain git clone, which brings nothing ignored and skips that step, so
# Gradle skips the module ("Found a module without a build.gradle, corrupt
# dir?") and the game runs without it.
#
#   pr-modules.sh ensure     copy what groovyw would have into every module that lacks it
#
# cwd: the engine checkout. Says which modules it touched; nothing when none.
set -euo pipefail

cmd_ensure() {
  local template="templates/build.gradle" logback="templates/module.logback-test.xml" m
  [ -f "$template" ] || { echo "pr-modules: no $template in $PWD; is this the engine checkout?" >&2; return 1; }
  for m in modules/*/; do
    [ -f "$m/module.txt" ] || continue
    if [ ! -f "$m/build.gradle" ]; then
      cp "$template" "$m/build.gradle"
      echo "pr-modules: ${m%/} had no build.gradle; the template is in place"
    fi
    if [ -f "$logback" ] && [ ! -f "$m/src/test/resources/logback-test.xml" ]; then
      mkdir -p "$m/src/test/resources"
      cp "$logback" "$m/src/test/resources/logback-test.xml"
      echo "pr-modules: ${m%/} had no test logging config; the template is in place"
    fi
  done
}

case "${1:-}" in
  ensure) cmd_ensure ;;
  *) echo "usage: pr-modules.sh ensure" >&2; exit 2 ;;
esac
