#!/usr/bin/env bash
# Compat wrapper → parameterized driver (ops / non-coding capability map).
# Lab-owned ikigai-dot runs with ALPHA_ROOT=${ALPHA_LAB_ROOT:-$HOME/Projects/alpha-lab}.
set -euo pipefail
export ALPHA_CAMPAIGN_MODE=ops
exec "$(cd "$(dirname "$0")" && pwd)/run_capability_map.sh" "$@"
