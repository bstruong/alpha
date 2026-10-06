#!/bin/bash
set -e

# Dedicated monitored runner for Pi Local Harness
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/pi-up.sh" "$@"
