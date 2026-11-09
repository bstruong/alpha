#!/usr/bin/env bash
# Submission-only Alpha campaign launcher for Watchtower.
#
# Creates a self-contained campaign Job from the CronJob template, prints the
# run/Job name, then exits. Safe to power off / disconnect afterward — the Job
# owns Lease, wake, heartbeat, graded execution, and GPU release via
# homelab-k3s `scripts/jarvis-session.sh` (begin → heartbeat-loop → end).
#
# Deploy dependency: merge + deploy homelab-k3s PR #41 (native Lease session
# interface + campaign entrypoint) before relying on this cutover.
#
# Usage:
#   ./scripts/alpha_watchtower_kick.sh
#   ALPHA_CAMPAIGN_FROM=ruby ./scripts/alpha_watchtower_kick.sh
#   ALPHA_CAMPAIGN_SCRIPT=scripts/run_ops_capability_map.sh ./scripts/alpha_watchtower_kick.sh
set -euo pipefail

NS="${ALPHA_K8S_NAMESPACE:-alpha}"
TEMPLATE="${ALPHA_CRONJOB_TEMPLATE:-alpha-campaign}"
FROM="${ALPHA_CAMPAIGN_FROM:-ruby}"
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

# Apply a local manifest file (ssh kubectl cannot see laptop temp paths).
k_apply_file() {
  local file="$1"
  if [[ -n "${CONTEXT}" ]]; then
    kubectl --context="${CONTEXT}" apply -f "${file}"
  elif [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]] || [[ "$(hostname 2>/dev/null || true)" == "watchtower" ]]; then
    kubectl apply -f "${file}"
  else
    ssh "${WATCHTOWER_SSH}" kubectl apply -f - <"${file}"
  fi
}

# Job names must be RFC 1123 (lowercase). Avoid %Y%m%dT…Z.
stamp="$(date -u +%Y%m%d-%H%M%S)"
job="alpha-campaign-${stamp}"

running="$(k -n "${NS}" get jobs -l app.kubernetes.io/name=alpha-runner \
  -o jsonpath='{range .items[?(@.status.active>0)]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)"
if [[ -n "${running}" ]]; then
  echo "fail: campaign already running:" >&2
  echo "${running}" >&2
  exit 1
fi

if ! k -n "${NS}" get cronjob "${TEMPLATE}" >/dev/null 2>&1; then
  echo "fail: CronJob ${NS}/${TEMPLATE} missing — deploy homelab-k3s manifests/watchtower/alpha first" >&2
  echo "      (Phase 4 session cutover requires homelab-k3s PR #41 deployed)" >&2
  exit 1
fi

# Optional read-only Lease glance (no acquire / heartbeat / ConfigMap ownership).
lease_holder="$(k -n "${LEASE_NS}" get lease "${LEASE_NAME}" \
  -o jsonpath='{.spec.holderIdentity}' 2>/dev/null || true)"
lease_run="$(k -n "${LEASE_NS}" get lease "${LEASE_NAME}" \
  -o jsonpath='{.metadata.annotations.jarvis\.watchtower/run-id}' 2>/dev/null || true)"
if [[ -n "${lease_holder}" ]]; then
  echo "note: lease/${LEASE_NAME} currently holder=${lease_holder} run-id=${lease_run:-none}"
  echo "      Job entrypoint will CAS-acquire; stale holders expire via Lease TTL + reconciler."
fi

echo "==> creating Job ${NS}/${job} (FROM=${FROM})"

# Job pod templates are immutable after create — bake env into the manifest first.
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
k -n "${NS}" create job "${job}" --from="cronjob/${TEMPLATE}" --dry-run=client -o json >"${tmp}"

JOB_NAME="${job}" FROM="${FROM}" \
ALPHA_CAMPAIGN_SCRIPT="${ALPHA_CAMPAIGN_SCRIPT:-}" \
ALPHA_GIT_REF="${ALPHA_GIT_REF:-}" \
ALPHA_LAB_GIT_REF="${ALPHA_LAB_GIT_REF:-}" \
HOMELAB_GIT_REF="${HOMELAB_GIT_REF:-}" \
python3 - "${tmp}" <<'PY'
import json, os, sys
path = sys.argv[1]
doc = json.load(open(path))
envs = doc["spec"]["template"]["spec"]["containers"][0].setdefault("env", [])
wanted = {
    "ALPHA_CAMPAIGN_FROM": os.environ["FROM"],
    "JOB_NAME": os.environ["JOB_NAME"],
    # Entrypoint sets JARVIS_SESSION_RUN_ID from JOB_NAME when unset; bake it
    # so campaign scripts can detect Job-owned session without racing.
    "JARVIS_SESSION_RUN_ID": os.environ["JOB_NAME"],
    # Entrypoint owns scale-down via jarvis-session end.
    "ALPHA_JARVIS_DOWN_AFTER": "0",
}
for key in ("ALPHA_CAMPAIGN_SCRIPT", "ALPHA_GIT_REF", "ALPHA_LAB_GIT_REF", "HOMELAB_GIT_REF"):
    val = os.environ.get(key) or ""
    if val:
        wanted[key] = val
by_name = {e["name"]: e for e in envs if "name" in e}
for k, v in wanted.items():
    if k in by_name:
        by_name[k]["value"] = v
        by_name[k].pop("valueFrom", None)
    else:
        envs.append({"name": k, "value": v})
json.dump(doc, open(path, "w"))
PY

k_apply_file "${tmp}" >/dev/null

echo ""
echo "ok  Job ${job} created in namespace ${NS}"
echo "    run-id / JARVIS_SESSION_RUN_ID=${job}"
echo "    Safe to power off this machine — campaign runs on Watchtower."
echo "    Job owns jarvis-session begin/heartbeat/end (homelab-k3s PR #41)."
echo "    Phone: subscribe ntfy topic 'alpha-campaigns' (server ntfy.watchtower.local)."
echo "    Status: ./scripts/alpha_watchtower_status.sh"
echo "    Review: ./scripts/alpha_watchtower_review.sh"
echo "JOB=${job}"
echo "RUN_ID=${job}"
