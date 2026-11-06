#!/usr/bin/env bash
# GLM-4.7 REAP apples-to-apples campaign against a live OpenAI-compatible endpoint.
# Prefer homelab-k3s JARVIS wake/lease; fall back to an already-running OPENAI_BASE_URL.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"
HOMELAB_K3S="${HOMELAB_K3S:-${HOME}/Projects/homelab-k3s}"
JARVIS_UP="${HOMELAB_K3S}/scripts/jarvis-up.sh"
JARVIS_DOWN="${HOMELAB_K3S}/scripts/jarvis-down.sh"
JARVIS_LEASE="${HOMELAB_K3S}/scripts/jarvis-lease.sh"
LEASE_HOLDER="${JARVIS_LEASE_HOLDER:-alpha-lab}"
LEASE_MINUTES="${JARVIS_LEASE_MINUTES:-180}"
MODEL="${BENCH_MODEL:-glm47-reap}"
PRESET="${BENCH_PRESET:-${MODEL}}"

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a && source .env && set +a
fi
export OPENAI_BASE_URL="${OPENAI_BASE_URL:-http://127.0.0.1:8080/v1}"

echo "=== Running ${MODEL} Apples-to-Apples Suite ==="
echo "OPENAI_BASE_URL=${OPENAI_BASE_URL}"
date -u

cleanup() {
  if [[ -x "${JARVIS_LEASE}" ]]; then
    "${JARVIS_LEASE}" release || true
  fi
  if [[ "${ALPHA_JARVIS_DOWN_AFTER:-1}" == "1" && -x "${JARVIS_DOWN}" ]]; then
    echo "--- Scaling JARVIS down ---"
    "${JARVIS_DOWN}" --force || "${JARVIS_DOWN}" || true
  fi
}
trap cleanup EXIT

if [[ -x "${JARVIS_UP}" ]]; then
  echo "--- Waking JARVIS ---"
  "${JARVIS_UP}"
  if [[ -x "${JARVIS_LEASE}" ]]; then
    "${JARVIS_LEASE}" acquire "${LEASE_HOLDER}" "${LEASE_MINUTES}"
  fi
else
  echo "WARN: ${JARVIS_UP} not found; assuming inference is already reachable at ${OPENAI_BASE_URL}"
fi

run_and_qualify() {
  local scenario="$1"
  shift
  echo "--- Running ${MODEL}: ${scenario} $* ---"
  date -u
  # Refresh lease activity between long scenarios when JARVIS is in use.
  if [[ -x "${JARVIS_LEASE}" ]]; then
    "${JARVIS_LEASE}" acquire "${LEASE_HOLDER}" "${LEASE_MINUTES}" || true
  fi
  mise exec -- bin/alpha run --scenario "${scenario}" --model "${MODEL}" --preset "${PRESET}" "$@" || true
  local run_id
  run_id="$(ls -td "${ROOT}/results/runs/"*-"${scenario}" 2>/dev/null | head -n 1 | xargs -n 1 basename || true)"
  if [[ -n "${run_id}" ]]; then
    echo "RUN_ID=${run_id}"
    mise exec -- bin/alpha qualify --run "${run_id}" || true
  else
    echo "WARN: no run directory found for ${scenario}"
  fi
}

run_and_qualify pii-scrubbing
run_and_qualify ocr-extraction
run_and_qualify scoped-coding --repair --no-gate-halt
run_and_qualify qwen36-daily --repair --no-gate-halt

echo "=== ${MODEL} Suite execution finished! ==="
date -u
