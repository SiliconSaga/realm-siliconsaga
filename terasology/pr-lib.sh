#!/usr/bin/env bash
# Shared by pr-headless.sh and pr-smoke.sh. Sourced.
PR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Poll <file> for <text> until <timeout> seconds pass or <pid> exits. The
# marker counts only while <pid> is still alive: a game that logs the line and
# dies a moment later did not boot.
wait_for_marker() { # <file> <text> <timeout-seconds> [<pid>]
  local file="$1" text="$2" timeout="$3" pid="${4:-}" waited=0
  while [ "$waited" -lt "$timeout" ]; do
    if [ -f "$file" ] && grep -qF -- "$text" "$file"; then
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
        echo "process $pid exited right after '$text' appeared; last lines:" >&2
        tail -n 5 "$file" >&2 2>/dev/null || true
        return 1
      fi
      return 0
    fi
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

# Terasology JVMs on this machine, by pid, optionally only those whose main
# arguments contain <match>. jps ships with the JDK on every OS; -lm shows the
# main class and its arguments, which is how a naust boot is told apart from a
# game a human is playing in a ready bay.
terasology_jvms() { # [<match>]
  local match="${1:-}"
  ${NAUST_JPS_CMD:-jps -lm} 2>/dev/null | awk -v m="$match" '$2 ~ /org\.terasology\.engine\.Terasology$/ && (m == "" || index($0, m)) { print $1 }' || true
}

# The JVMs in <all> that are not in <before>, one per line.
new_jvms() { # <before> <all>
  local p
  for p in $2; do
    case " $1 " in *" $p "*) ;; *) printf '%s\n' "$p" ;; esac
  done
}

# Stop what a boot started. The gradlew wrapper execs the Gradle client, so
# killing <pid> disconnects the client and the daemon cancels the build, which
# kills its JavaExec child. If a Terasology JVM that this boot started is still
# there after that, it is killed by pid; an orphaned game would hold the GPU
# for every later job. Only JVMs matching <match> that did not exist before
# the boot (<before>, pids separated by spaces) are candidates, so a game a
# human runs in another bay is never touched.
stop_game() { # <gradlew pid> [<match>] [<before>]
  local pid="$1" match="${2:-}" before="${3:-}" waited=0 p
  kill "$pid" 2>/dev/null || true
  while [ "$waited" -lt 30 ]; do
    if ! kill -0 "$pid" 2>/dev/null && [ -z "$(new_jvms "$before" "$(terasology_jvms "$match")")" ]; then return 0; fi
    sleep 2; waited=$((waited + 2))
  done
  kill -9 "$pid" 2>/dev/null || true
  for p in $(new_jvms "$before" "$(terasology_jvms "$match")"); do
    echo "stopping a lingering Terasology JVM this boot started, pid $p" >&2
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
