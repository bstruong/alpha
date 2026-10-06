#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "=== go-merge-intervals ==="
go run main.go
echo "=== go-merge-intervals: PASS ==="
