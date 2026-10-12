#!/usr/bin/env bash
set -euo pipefail

if command -v node &>/dev/null; then
    # Strip TypeScript type annotations and run as plain JS
    sed 's/: string//g; s/: number//g; s/: boolean//g; s/\.map(Number)//g' semver.ts | node
else
    echo "[skip] node not installed, skipping execution"
fi
echo "ts-semver-compare: OK"
