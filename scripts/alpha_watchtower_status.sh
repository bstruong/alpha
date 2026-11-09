#!/usr/bin/env bash
# Show Alpha campaign Job status on Watchtower (read-only).
#
# Lease source of truth: coordination.k8s.io/v1 Lease jarvis/jarvis-gpu
# (homelab-k3s PR #41). ConfigMap jarvis-lease is cutover dual-read only.
set -euo pipefail

NS="${ALPHA_K8S_NAMESPACE:-alpha}"
WATCHTOWER_SSH="${WATCHTOWER_SSH:-watchtower}"
CONTEXT="${KUBE_CONTEXT:-}"
LEASE_NS="${JARVIS_K8S_NAMESPACE:-jarvis}"
LEASE_NAME="${JARVIS_LEASE_NAME:-jarvis-gpu}"

k() {
  if [[ -n "${CONTEXT}" ]]; then
    kubectl --context="${CONTEXT}" "$@"
  elif [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]] || [[ "$(hostname 2>/dev/null || true)" == "watchtower" ]]; then
    kubectl "$@"
  else
    ssh "${WATCHTOWER_SSH}" kubectl "$(printf '%q ' "$@")"
  fi
}

echo "=== Alpha Jobs (${NS}) ==="
k -n "${NS}" get jobs -l app.kubernetes.io/name=alpha-runner -o wide 2>/dev/null \
  || k -n "${NS}" get jobs -o wide

echo ""
echo "=== Latest pods ==="
k -n "${NS}" get pods -l app.kubernetes.io/name=alpha-runner -o wide 2>/dev/null \
  || k -n "${NS}" get pods -o wide

echo ""
echo "=== JARVIS lease (${LEASE_NS}/${LEASE_NAME}) ==="
if ! k -n "${LEASE_NS}" get lease "${LEASE_NAME}" \
  -o jsonpath='holder={.spec.holderIdentity} renew={.spec.renewTime} durationSeconds={.spec.leaseDurationSeconds} run-id={.metadata.annotations.jarvis\.watchtower/run-id} last-activity={.metadata.annotations.jarvis\.watchtower/last-activity-at}{"\n"}' \
  2>/dev/null; then
  echo "(lease/${LEASE_NAME} unavailable — deploy homelab-k3s PR #41)"
fi

replicas="$(k -n "${LEASE_NS}" get deployment jarvis -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")"
echo "jarvis.replicas=${replicas}"

echo ""
echo "=== Artifacts on Watchtower ==="
ssh "${WATCHTOWER_SSH}" 'ls -lt /mnt/appdata/alpha/artifacts/reports 2>/dev/null | head -10; echo; ls -lt /mnt/appdata/alpha/artifacts/results/logs 2>/dev/null | head -8' \
  || echo "(ssh ${WATCHTOWER_SSH} failed — check hostPath manually)"

active="$(k -n "${NS}" get pods -l app.kubernetes.io/name=alpha-runner \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "${active}" ]]; then
  echo ""
  echo "Follow logs: kubectl -n ${NS} logs -f ${active}"
  echo "         or: ssh ${WATCHTOWER_SSH} kubectl -n ${NS} logs -f ${active}"
fi
