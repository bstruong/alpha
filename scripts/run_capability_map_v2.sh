#!/usr/bin/env bash
# Compat wrapper → parameterized driver (full capability map).
set -euo pipefail
export ALPHA_CAMPAIGN_MODE="${ALPHA_CAMPAIGN_MODE:-full}"
exec "$(cd "$(dirname "$0")" && pwd)/run_capability_map.sh" "$@"
