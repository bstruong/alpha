#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "=== ts-semver-compare ==="
node --experimental-strip-types semver.ts
echo "=== ts-semver-compare: PASS ==="
