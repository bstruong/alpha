#!/usr/bin/env bash
# Submission-only Alpha campaign launcher for Watchtower.
#
# Creates a self-contained campaign Job from the CronJob template, prints the
# run/Job name, then exits. Safe to power off / disconnect afterward — the Job
# owns Lease, wake, heartbeat, graded execution, and GPU release via
# homelab-k3s `scripts/jarvis-session.sh` (begin → heartbeat-loop → end).
#
# Phase 5: promotable graded campaigns require immutable pins:
#   ALPHA_RUNNER_IMAGE      image@sha256:... (no :latest)
#   ALPHA_GIT_SHA / ALPHA_LAB_GIT_SHA / HOMELAB_GIT_SHA   full 40-char commits
# Dev/diagnostic submits may set ALPHA_ALLOW_MOVING_REFS=1 (not promotable).
#
# Usage:
#   ALPHA_RUNNER_IMAGE=registry.watchtower.local/alpha-runner@sha256:... \
#   ALPHA_GIT_SHA=... ALPHA_LAB_GIT_SHA=... HOMELAB_GIT_SHA=... \
#     ./scripts/alpha_watchtower_kick.sh
#   ALPHA_CAMPAIGN_FROM=ruby ./scripts/alpha_watchtower_kick.sh
set -euo pipefail

NS="${ALPHA_K8S_NAMESPACE:-alpha}"
TEMPLATE="${ALPHA_CRONJOB_TEMPLATE:-alpha-campaign}"
FROM="${ALPHA_CAMPAIGN_FROM:-ruby}"
WATCHTOWER_SSH="${WATCHTOWER_SSH:-watchtower}"
CONTEXT="${KUBE_CONTEXT:-}"
LEASE_NS="${JARVIS_K8S_NAMESPACE:-jarvis}"
LEASE_NAME="${JARVIS_LEASE_NAME:-jarvis-gpu}"
ALLOW_MOVING="${ALPHA_ALLOW_MOVING_REFS:-0}"

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

is_full_sha() {
  [[ "${1:-}" =~ ^[0-9a-fA-F]{40}$ ]]
}

is_digest_image() {
  local img="${1:-}"
  [[ "${img}" == *"@sha256:"* ]] || [[ "${img}" =~ ^sha256:[0-9a-fA-F]{64}$ ]]
}

require_promotable_pins() {
  local missing=0
  if [[ -z "${ALPHA_RUNNER_IMAGE:-}" ]] || ! is_digest_image "${ALPHA_RUNNER_IMAGE}"; then
    echo "fail: ALPHA_RUNNER_IMAGE must be digest-pinned (image@sha256:...) for graded campaigns" >&2
    missing=1
  fi
  if [[ "${ALPHA_RUNNER_IMAGE:-}" == *":latest"* ]]; then
    echo "fail: ALPHA_RUNNER_IMAGE must not use :latest" >&2
    missing=1
  fi
  for var in ALPHA_GIT_SHA ALPHA_LAB_GIT_SHA HOMELAB_GIT_SHA; do
    local val="${!var:-}"
    if ! is_full_sha "${val}"; then
      echo "fail: ${var} must be a full 40-char commit SHA (got '${val:-empty}')" >&2
      missing=1
    fi
  done
  for var in ALPHA_GIT_REF ALPHA_LAB_GIT_REF HOMELAB_GIT_REF; do
    local val="${!var:-}"
    if [[ -n "${val}" ]] && [[ "${val}" == "main" || "${val}" == "master" || "${val}" == "latest" || "${val}" == "HEAD" ]]; then
      echo "fail: ${var}=${val} is a moving ref — pass the commit SHA via *_GIT_SHA / *_GIT_REF" >&2
      missing=1
    fi
  done
  if [[ "${missing}" -ne 0 ]]; then
    echo "hint: set ALPHA_ALLOW_MOVING_REFS=1 only for non-promotable diagnostics" >&2
    exit 1
  fi
}

if [[ "${ALLOW_MOVING}" != "1" ]]; then
  require_promotable_pins
else
  echo "warn: ALPHA_ALLOW_MOVING_REFS=1 — Job is not promotable (Phase 5)" >&2
fi

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
ALPHA_GIT_REF="${ALPHA_GIT_REF:-${ALPHA_GIT_SHA:-}}" \
ALPHA_LAB_GIT_REF="${ALPHA_LAB_GIT_REF:-${ALPHA_LAB_GIT_SHA:-}}" \
HOMELAB_GIT_REF="${HOMELAB_GIT_REF:-${HOMELAB_GIT_SHA:-}}" \
ALPHA_GIT_SHA="${ALPHA_GIT_SHA:-}" \
ALPHA_LAB_GIT_SHA="${ALPHA_LAB_GIT_SHA:-}" \
HOMELAB_GIT_SHA="${HOMELAB_GIT_SHA:-}" \
ALPHA_RUNNER_IMAGE="${ALPHA_RUNNER_IMAGE:-}" \
ALPHA_RUNNER_IMAGE_DIGEST="${ALPHA_RUNNER_IMAGE_DIGEST:-}" \
ALPHA_ALLOW_MOVING_REFS="${ALLOW_MOVING}" \
python3 - "${tmp}" <<'PY'
import json, os, sys, re
path = sys.argv[1]
doc = json.load(open(path))
container = doc["spec"]["template"]["spec"]["containers"][0]
envs = container.setdefault("env", [])
wanted = {
    "ALPHA_CAMPAIGN_FROM": os.environ["FROM"],
    "JOB_NAME": os.environ["JOB_NAME"],
    "JARVIS_SESSION_RUN_ID": os.environ["JOB_NAME"],
    "ALPHA_JARVIS_DOWN_AFTER": "0",
    "ALPHA_ALLOW_MOVING_REFS": os.environ.get("ALPHA_ALLOW_MOVING_REFS") or "0",
}
for key in (
    "ALPHA_CAMPAIGN_SCRIPT",
    "ALPHA_GIT_REF",
    "ALPHA_LAB_GIT_REF",
    "HOMELAB_GIT_REF",
    "ALPHA_GIT_SHA",
    "ALPHA_LAB_GIT_SHA",
    "HOMELAB_GIT_SHA",
    "ALPHA_RUNNER_IMAGE",
    "ALPHA_RUNNER_IMAGE_DIGEST",
):
    val = os.environ.get(key) or ""
    if val:
        wanted[key] = val

image = os.environ.get("ALPHA_RUNNER_IMAGE") or ""
if image:
    container["image"] = image
    container["imagePullPolicy"] = "IfNotPresent"
    # Prefer digest form already in image; also export digest env for provenance.
    m = re.search(r"@(sha256:[0-9a-fA-F]{64})$", image)
    if m and not wanted.get("ALPHA_RUNNER_IMAGE_DIGEST"):
        wanted["ALPHA_RUNNER_IMAGE_DIGEST"] = m.group(1)

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
echo "    runner_image=${ALPHA_RUNNER_IMAGE:-from-cronjob-template}"
echo "    alpha_sha=${ALPHA_GIT_SHA:-${ALPHA_GIT_REF:-unset}}"
echo "    Safe to power off this machine — campaign runs on Watchtower."
echo "    Job owns jarvis-session begin/heartbeat/end."
echo "    Phone: subscribe ntfy topic 'alpha-campaigns' (server ntfy.watchtower.local)."
echo "    Status: ./scripts/alpha_watchtower_status.sh"
echo "    Review: ./scripts/alpha_watchtower_review.sh"
echo "JOB=${job}"
echo "RUN_ID=${job}"
