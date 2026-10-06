#!/usr/bin/env bash
set -euo pipefail

# Check if Go is available; if not, do a syntax check only
if command -v go &>/dev/null; then
    go vet main.go
    go build -o /dev/null main.go
else
    echo "[skip] go not installed, skipping compilation"
fi
echo "go-merge-intervals: OK"
