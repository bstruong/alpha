#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "=== python-token-bucket ==="
python3 token_bucket.py
echo "=== python-token-bucket: PASS ==="
