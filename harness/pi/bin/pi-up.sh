#!/bin/bash
set -e

# Resolve Pi Harness root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PI_BIN="${HARNESS_DIR}/node_modules/.bin/pi"

if [[ ! -x "${PI_BIN}" ]]; then
  echo "Error: Pi binary not found at ${PI_BIN}. Run 'npm install' in ${HARNESS_DIR}." >&2
  exit 1
fi

# Bootstrapper for the Pi Local Harness
export PI_CODING_AGENT_DIR="${HARNESS_DIR}"

# Local inference engine URLs
export LLAMA_SERVER_URL="${LLAMA_SERVER_URL:-http://127.0.0.1:8080}"
export LLAMA_BASE_URL="${LLAMA_BASE_URL:-http://127.0.0.1:8080}"
export OPENAI_API_BASE="${OPENAI_API_BASE:-http://127.0.0.1:8080/v1}"

# Route through the Ruby heartbeat monitor. The Python monitor remains beside it.
export PI_BIN="${PI_BIN}"
exec ruby "${SCRIPT_DIR}/pi-monitor.rb" "$@"
