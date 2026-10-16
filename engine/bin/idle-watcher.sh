#!/usr/bin/env bash
# =============================================================================
# alpha / engine / bin / idle-watcher.sh
# Checks /slots and /metrics on llama-server (port 8080).
# If alpha-llama is running but has had 0 inference activity for 30 minutes,
# scales the deployment back to 0 replicas to reclaim RAM and VRAM.
# =============================================================================
set -euo pipefail

STATE_FILE="/tmp/alpha-llama-idle.state"
IDLE_TIMEOUT_SECONDS=1800  # 30 minutes
SERVER_URL="http://127.0.0.1:8080"
NAMESPACE="alpha"
DEPLOYMENT="alpha-llama"

# 1. Check if deployment is currently scaled up
REPLICAS=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)
if [[ "${REPLICAS}" -eq 0 ]]; then
  # Already scaled to zero, clean up state
  rm -f "${STATE_FILE}"
  exit 0
fi

# 2. Check if server endpoint is responding
if ! SLOTS=$(curl -s --connect-timeout 3 "${SERVER_URL}/slots" 2>/dev/null); then
  # Pod might be starting or restarting; don't terminate immediately
  echo "alpha-llama is scaled to ${REPLICAS} but ${SERVER_URL}/slots is not responding. Skipping."
  exit 0
fi

# 3. Check if any slot is actively processing
IS_PROCESSING=$(echo "${SLOTS}" | jq -r '[.[] | .is_processing] | any' 2>/dev/null || echo "false")
if [[ "${IS_PROCESSING}" == "true" ]]; then
  echo "alpha-llama is currently processing a request. Updating activity timestamp."
  echo "LAST_ACTIVE=$(date +%s)" > "${STATE_FILE}"
  exit 0
fi

# 4. Check total decodes from /metrics
METRICS=$(curl -s --connect-timeout 3 "${SERVER_URL}/metrics" 2>/dev/null || true)
TOTAL_DECODES=$(echo "${METRICS}" | grep '^llamacpp:n_decode_total' | awk '{print $2}' || echo "0")
CURRENT_TASK_IDS=$(echo "${SLOTS}" | jq -r '[.[] | .id_task // 0] | sort | join(",")' 2>/dev/null || echo "")

NOW=$(date +%s)

if [[ -f "${STATE_FILE}" ]]; then
  # Load previous state
  # Format: LAST_ACTIVE=<ts> LAST_DECODES=<num> LAST_TASKS=<tasks>
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
  LAST_ACTIVE=${LAST_ACTIVE:-${NOW}}
  LAST_DECODES=${LAST_DECODES:-""}
  LAST_TASKS=${LAST_TASKS:-""}

  # If decodes or tasks changed, activity occurred
  if [[ "${TOTAL_DECODES}" != "${LAST_DECODES}" || "${CURRENT_TASK_IDS}" != "${LAST_TASKS}" ]]; then
    echo "Activity detected (decodes: ${LAST_DECODES} -> ${TOTAL_DECODES}). Resetting idle timer."
    cat <<EOF > "${STATE_FILE}"
LAST_ACTIVE=${NOW}
LAST_DECODES=${TOTAL_DECODES}
LAST_TASKS=${CURRENT_TASK_IDS}
EOF
    exit 0
  fi

  # No activity detected. Check idle duration
  IDLE_SECONDS=$(( NOW - LAST_ACTIVE ))
  echo "alpha-llama idle for ${IDLE_SECONDS}s (threshold: ${IDLE_TIMEOUT_SECONDS}s, decodes: ${TOTAL_DECODES})"

  if [[ ${IDLE_SECONDS} -ge ${IDLE_TIMEOUT_SECONDS} ]]; then
    echo "Alpha engine idle threshold reached (${IDLE_SECONDS}s >= ${IDLE_TIMEOUT_SECONDS}s). Scaling ${DEPLOYMENT} to 0..."
    kubectl scale deployment "${DEPLOYMENT}" --replicas=0 -n "${NAMESPACE}"
    rm -f "${STATE_FILE}"
    echo "✓ Scaled ${DEPLOYMENT} to 0 replicas."
  fi
else
  # Initialize state
  cat <<EOF > "${STATE_FILE}"
LAST_ACTIVE=${NOW}
LAST_DECODES=${TOTAL_DECODES}
LAST_TASKS=${CURRENT_TASK_IDS}
EOF
  echo "Initialized idle tracking at ${NOW} (decodes: ${TOTAL_DECODES})."
fi
