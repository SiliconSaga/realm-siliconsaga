#!/usr/bin/env bash
# Realm-side Terasology helper tests, on the workspace-vendored bats.
set -euo pipefail
cd "$(dirname "$0")/../.."                      # realm root
WS_ROOT="$(cd ../.. && pwd)"
BATS="$(command -v bats || true)"
BATS="${BATS:-$WS_ROOT/tests/vendor/bats-core/bin/bats}"
exec bash "$BATS" "${1:-terasology/tests/}"
