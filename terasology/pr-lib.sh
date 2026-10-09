#!/usr/bin/env bash
# Shared by pr-headless.sh and pr-smoke.sh. Sourced.
PR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Poll <file> for <text> until <timeout> seconds pass or <pid> exits.
wait_for_marker() { # <file> <text> <timeout-seconds> [<pid>]
  local file="$1" text="$2" timeout="$3" pid="${4:-}" waited=0
  while [ "$waited" -lt "$timeout" ]; do
    if [ -f "$file" ] && grep -qF -- "$text" "$file"; then return 0; fi
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      echo "process $pid exited before '$text' appeared; last lines:" >&2
      tail -n 5 "$file" >&2 2>/dev/null || true
      return 1
    fi
    sleep 2; waited=$((waited + 2))
  done
  echo "timeout after ${timeout}s waiting for '$text' in $file" >&2
  return 1
}

# Terasology JVMs on this machine, by pid. jps ships with the JDK on every OS.
terasology_jvms() {
  ${NAUST_JPS_CMD:-jps -l} 2>/dev/null | awk '$2 ~ /org\.terasology\.engine\.Terasology$/ { print $1 }' || true
}

# Stop what a boot started. The gradlew wrapper execs the Gradle client, so
# killing <pid> disconnects the client and the daemon cancels the build, which
# kills its JavaExec child. If a Terasology JVM is still there after that, it is
# killed by pid; an orphaned game would hold the GPU for every later job.
stop_game() { # <gradlew pid>
  local pid="$1" waited=0 p
  kill "$pid" 2>/dev/null || true
  while [ "$waited" -lt 30 ]; do
    if ! kill -0 "$pid" 2>/dev/null && [ -z "$(terasology_jvms)" ]; then return 0; fi
    sleep 2; waited=$((waited + 2))
  done
  kill -9 "$pid" 2>/dev/null || true
  for p in $(terasology_jvms); do
    echo "stopping a lingering Terasology JVM, pid $p" >&2
    case "$(uname -s)" in
      MINGW*|MSYS*|CYGWIN*) taskkill //PID "$p" //F >/dev/null 2>&1 || kill -9 "$p" 2>/dev/null || true ;;
      *) kill -9 "$p" 2>/dev/null || true ;;
    esac
  done
}

# Capture the primary display to <out.png> with whatever this OS has.
screenshot() { # <out.png>
  if [ -n "${NAUST_SCREENSHOT_CMD:-}" ]; then $NAUST_SCREENSHOT_CMD "$1"; return; fi
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$PR_LIB_DIR/screenshot.ps1")" "$(cygpath -w "$1")" ;;
    Darwin) screencapture -x "$1" ;;
    *)
      if command -v import >/dev/null 2>&1; then import -window root "$1"
      elif command -v gnome-screenshot >/dev/null 2>&1; then gnome-screenshot -f "$1"
      else echo "no screenshot tool (install ImageMagick or gnome-screenshot)" >&2; return 1; fi ;;
  esac
}
