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

# Inference engine URLs (OPENAI_BASE_URL wins over checked-in localhost defaults)
export LLAMA_SERVER_URL="${LLAMA_SERVER_URL:-http://127.0.0.1:8080}"
export LLAMA_BASE_URL="${LLAMA_BASE_URL:-http://127.0.0.1:8080}"
export OPENAI_BASE_URL="${OPENAI_BASE_URL:-http://127.0.0.1:8080/v1}"
export OPENAI_API_BASE="${OPENAI_API_BASE:-${OPENAI_BASE_URL}}"
export OPENAI_API_KEY="${OPENAI_API_KEY:-ignored}"

ROOT_URL="${OPENAI_BASE_URL%/v1}"

# Runtime harness overlay so models.json / settings.json match OPENAI_BASE_URL.
RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/alpha-pi-up.XXXXXX")"
cleanup_runtime() { rm -rf "${RUNTIME_DIR}"; }
trap cleanup_runtime EXIT

for entry in node_modules SYSTEM.md package.json package-lock.json auth.json bin; do
  if [[ -e "${HARNESS_DIR}/${entry}" ]]; then
    ln -s "${HARNESS_DIR}/${entry}" "${RUNTIME_DIR}/${entry}"
  fi
done

python3 - "${HARNESS_DIR}" "${RUNTIME_DIR}" "${OPENAI_BASE_URL}" "${ROOT_URL}" <<'PY'
import json, pathlib, sys
harness = pathlib.Path(sys.argv[1])
runtime = pathlib.Path(sys.argv[2])
base = sys.argv[3]
root = sys.argv[4]
models = json.loads((harness / "models.json").read_text())
models.setdefault("providers", {}).setdefault("openai-compatible", {})
models["providers"]["openai-compatible"]["baseUrl"] = base
(runtime / "models.json").write_text(json.dumps(models, indent=2) + "\n")
settings = json.loads((harness / "settings.json").read_text())
servers = settings.setdefault("llamaSettings", {}).setdefault("servers", [])
if not servers:
    servers.append({"url": root, "id": "alpha-runtime", "name": "Alpha runtime"})
else:
    for server in servers:
        server["url"] = root
(runtime / "settings.json").write_text(json.dumps(settings, indent=2) + "\n")
PY

export PI_CODING_AGENT_DIR="${RUNTIME_DIR}"
export PI_BIN="${PI_BIN}"
exec ruby "${SCRIPT_DIR}/pi-monitor.rb" "$@"
