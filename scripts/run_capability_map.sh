#!/usr/bin/env bash
# Parameterized capability-map campaign driver (Watchtower Job graded suites only).
#
# Modes (ALPHA_CAMPAIGN_MODE):
#   full  — chat + vault + crm + coding + web ladder + manifest (legacy v2)
#   ops   — chat + vault + crm + manifest (non-coding ops only)
#
# Lab-owned scenarios (ikigai-dot) always run with:
#   ALPHA_ROOT="${ALPHA_LAB_ROOT:-$HOME/Projects/alpha-lab}"
#
# Graded execution belongs on a Watchtower campaign Job. Laptops may submit or
# monitor only; do not treat this script as a laptop graded runner.
#
# Compat wrappers:
#   scripts/run_capability_map_v2.sh  → MODE=full
#   scripts/run_ops_capability_map.sh → MODE=ops
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"
LAB="${ALPHA_LAB_ROOT:-${HOME}/Projects/alpha-lab}"
HOMELAB_K3S="${HOMELAB_K3S:-${HOME}/Projects/homelab-k3s}"
JARVIS_UP="${HOMELAB_K3S}/scripts/jarvis-up.sh"
JARVIS_DOWN="${HOMELAB_K3S}/scripts/jarvis-down.sh"
JARVIS_LEASE="${HOMELAB_K3S}/scripts/jarvis-lease.sh"
MODE="${ALPHA_CAMPAIGN_MODE:-full}"
ARTIFACT_ROOT="${ALPHA_ARTIFACT_ROOT:-${ROOT}}"
PROMOTE_LAB="${ALPHA_PROMOTE_LAB:-1}"
FROM="${ALPHA_CAMPAIGN_FROM:-all}"
# When set by the Watchtower Job entrypoint, jarvis-session owns begin/heartbeat/end.
SESSION_OWNED=0
if [[ -n "${JARVIS_SESSION_RUN_ID:-}" ]]; then
  SESSION_OWNED=1
fi

case "${MODE}" in
  full)
    LEASE_HOLDER="${JARVIS_LEASE_HOLDER:-alpha-lab}"
    LEASE_MINUTES="${JARVIS_LEASE_MINUTES:-240}"
    LOG_PREFIX="capability-map-v2"
    ;;
  ops)
    LEASE_HOLDER="${JARVIS_LEASE_HOLDER:-alpha-campaign}"
    LEASE_MINUTES="${JARVIS_LEASE_MINUTES:-480}"
    LOG_PREFIX="ops-capability-map"
    ;;
  *)
    echo "fail: unknown ALPHA_CAMPAIGN_MODE=${MODE} (expected full|ops)" >&2
    exit 2
    ;;
esac

# Preserve in-cluster / Job-injected inference URL over laptop-oriented .env.
_PRESERVED_OPENAI_BASE_URL="${OPENAI_BASE_URL:-}"
_PRESERVED_OPENAI_API_BASE="${OPENAI_API_BASE:-}"
_PRESERVED_LLAMA_SERVER_URL="${LLAMA_SERVER_URL:-}"
_PRESERVED_LLAMA_BASE_URL="${LLAMA_BASE_URL:-}"
if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a && source .env && set +a
fi
if [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]]; then
  _CLUSTER_URL="${_PRESERVED_OPENAI_BASE_URL:-http://jarvis.jarvis.svc.cluster.local:8080/v1}"
  export OPENAI_BASE_URL="${_CLUSTER_URL}"
  export OPENAI_API_BASE="${_PRESERVED_OPENAI_API_BASE:-${_CLUSTER_URL}}"
  export LLAMA_SERVER_URL="${_PRESERVED_LLAMA_SERVER_URL:-${_CLUSTER_URL%/v1}}"
  export LLAMA_BASE_URL="${_PRESERVED_LLAMA_BASE_URL:-${_CLUSTER_URL%/v1}}"
elif [[ -n "${_PRESERVED_OPENAI_BASE_URL}" ]]; then
  export OPENAI_BASE_URL="${_PRESERVED_OPENAI_BASE_URL}"
  export OPENAI_API_BASE="${_PRESERVED_OPENAI_API_BASE:-${_PRESERVED_OPENAI_BASE_URL}}"
else
  export OPENAI_BASE_URL="${OPENAI_BASE_URL:-http://ai.watchtower.local/v1}"
  export OPENAI_API_BASE="${OPENAI_API_BASE:-${OPENAI_BASE_URL}}"
fi
unset _PRESERVED_OPENAI_BASE_URL _PRESERVED_OPENAI_API_BASE _PRESERVED_LLAMA_SERVER_URL _PRESERVED_LLAMA_BASE_URL _CLUSTER_URL

mkdir -p "${ARTIFACT_ROOT}/results/logs" "${ARTIFACT_ROOT}/reports" "${ARTIFACT_ROOT}/qualifications"
mkdir -p results/logs reports qualifications
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="${ARTIFACT_ROOT}/results/logs/${LOG_PREFIX}-${STAMP}.log"

CHAT_MODELS=(gemma4-4b gemma4-12b gemma4-27b qwen25-coder-14b qwen36-coder-hybrid glm47-reap)
EXTRACT_MODELS=(qwen25-coder-14b qwen36-coder-hybrid glm47-reap)
CODING_MODELS=(qwen25-coder-14b qwen36-coder-hybrid glm47-reap)
CRM_MODELS=(gemma4-4b gemma4-12b qwen25-coder-14b)
WEB_EARLY_MODELS=(qwen36-coder-hybrid glm47-reap)
WEB_LATE_MODELS=(qwen36-coder-hybrid glm47-reap)
OPS_MODELS=(glm47-reap qwen36-coder-hybrid qwen25-coder-14b gemma4-4b gemma4-12b gemma4-27b)

alpha_exec() {
  if command -v mise >/dev/null 2>&1; then
    mise exec -- "$@"
  else
    "$@"
  fi
}

echo "=== Capability-map campaign (${MODE}) ===" | tee "$LOG"
echo "OPENAI_BASE_URL=${OPENAI_BASE_URL}" | tee -a "$LOG"
echo "ALPHA_CAMPAIGN_MODE=${MODE}" | tee -a "$LOG"
echo "ALPHA_CAMPAIGN_FROM=${FROM}" | tee -a "$LOG"
echo "ALPHA_ARTIFACT_ROOT=${ARTIFACT_ROOT}" | tee -a "$LOG"
echo "ALPHA_PROMOTE_LAB=${PROMOTE_LAB}" | tee -a "$LOG"
echo "ALPHA_LAB_ROOT=${LAB}" | tee -a "$LOG"
echo "JARVIS_SESSION_RUN_ID=${JARVIS_SESSION_RUN_ID:-}" | tee -a "$LOG"
echo "LOG=${LOG}" | tee -a "$LOG"
date -u | tee -a "$LOG"

stage_at_or_after() {
  local want="$1"
  local from_i=-1 want_i=-1 i
  local order
  if [[ "${MODE}" == "ops" ]]; then
    order=(all chat vault crm manifest)
  else
    order=(all chat vault crm coding ruby frontend hotwire manifest)
  fi
  for i in "${!order[@]}"; do
    [[ "${order[$i]}" == "${FROM}" ]] && from_i=$i
    [[ "${order[$i]}" == "${want}" ]] && want_i=$i
  done
  [[ $from_i -lt 0 || "${FROM}" == "all" ]] && return 0
  case "${FROM}" in
    chat) [[ $want_i -ge 1 ]] && return 0 ;;
    vault) [[ $want_i -ge 2 ]] && return 0 ;;
    crm) [[ $want_i -ge 3 ]] && return 0 ;;
    coding) [[ "${MODE}" == "full" && $want_i -ge 4 ]] && return 0 ;;
    ruby) [[ "${MODE}" == "full" && $want_i -ge 5 ]] && return 0 ;;
    frontend) [[ "${MODE}" == "full" && $want_i -ge 6 ]] && return 0 ;;
    hotwire) [[ "${MODE}" == "full" && $want_i -ge 7 ]] && return 0 ;;
    manifest)
      if [[ "${MODE}" == "ops" ]]; then
        [[ $want_i -ge 4 ]] && return 0
      else
        [[ $want_i -ge 8 ]] && return 0
      fi
      ;;
  esac
  return 1
}

# Copy only when src/dst resolve to different paths (ALPHA_ROOT=LAB otherwise aborts under set -e).
safe_cp() {
  local src="$1" dst="$2"
  [[ -f "${src}" ]] || return 0
  mkdir -p "$(dirname "${dst}")"
  local src_r dst_r
  src_r="$(realpath -m "${src}")"
  dst_r="$(realpath -m "${dst}")"
  if [[ "${src_r}" == "${dst_r}" ]]; then
    echo "REPORT_ALREADY_IN_LAB $(basename "${src}")" | tee -a "$LOG"
    return 0
  fi
  cp -f "${src}" "${dst}"
}

cleanup() {
  if [[ "${SESSION_OWNED}" -eq 1 ]]; then
    return 0
  fi
  if [[ -x "${JARVIS_LEASE}" ]]; then
    "${JARVIS_LEASE}" release || true
  fi
  if [[ "${ALPHA_JARVIS_DOWN_AFTER:-1}" == "1" && -x "${JARVIS_DOWN}" ]]; then
    echo "--- Scaling JARVIS down ---" | tee -a "$LOG"
    "${JARVIS_DOWN}" --force || "${JARVIS_DOWN}" || true
  fi
}
trap cleanup EXIT

touch_lease() {
  if [[ "${SESSION_OWNED}" -eq 1 ]]; then
    return 0
  fi
  if [[ -x "${JARVIS_LEASE}" ]]; then
    "${JARVIS_LEASE}" acquire "${LEASE_HOLDER}" "${LEASE_MINUTES}" || true
  fi
}

jarvis_healthy() {
  local url
  for url in \
    "${OPENAI_BASE_URL%/v1}/health" \
    "http://jarvis.jarvis.svc.cluster.local:8080/health" \
    "http://127.0.0.1:8080/health"
  do
    [[ -n "${url}" ]] || continue
    if curl -fsS --max-time 3 "${url}" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

if [[ "${SESSION_OWNED}" -eq 1 ]]; then
  echo "--- JARVIS session owned by Watchtower Job (run-id=${JARVIS_SESSION_RUN_ID}); skipping local wake/lease ---" | tee -a "$LOG"
  if ! jarvis_healthy; then
    echo "fail: JARVIS unhealthy after Job session begin" | tee -a "$LOG"
    exit 1
  fi
elif jarvis_healthy; then
  echo "--- JARVIS already healthy at ${OPENAI_BASE_URL} ---" | tee -a "$LOG"
  touch_lease
elif [[ -x "${JARVIS_UP}" ]]; then
  echo "--- Waking JARVIS (local diagnostic path; not graded evidence) ---" | tee -a "$LOG"
  if ! "${JARVIS_UP}" 2>&1 | tee -a "$LOG"; then
    if jarvis_healthy; then
      echo "WARN: jarvis-up failed but health OK; continuing" | tee -a "$LOG"
    else
      echo "fail: JARVIS unreachable after wake" | tee -a "$LOG"
      exit 1
    fi
  fi
  touch_lease
else
  echo "WARN: jarvis-up missing; assuming ${OPENAI_BASE_URL} is up" | tee -a "$LOG"
fi

promote_report() {
  local run_id="$1" src_root="${2:-${ROOT}}"
  [[ -n "${run_id}" && -f "${src_root}/reports/${run_id}.md" ]] || return 0
  safe_cp "${src_root}/reports/${run_id}.md" "${ARTIFACT_ROOT}/reports/${run_id}.md"
  if [[ "${PROMOTE_LAB}" == "1" ]]; then
    safe_cp "${src_root}/reports/${run_id}.md" "${LAB}/reports/${run_id}.md"
  fi
  echo "REPORT->${run_id}" | tee -a "$LOG"
}

promote_qual() {
  local model="$1" role="$2" src_root="${3:-${ROOT}}"
  local qpath="${src_root}/qualifications/${model}__${role}__shipping.json"
  if [[ -f "${qpath}" ]] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('qualified') is True and d.get('schema')=='alpha.qualification.v2' else 1)" "${qpath}"; then
    safe_cp "${qpath}" "${ARTIFACT_ROOT}/qualifications/$(basename "${qpath}")"
    if [[ "${PROMOTE_LAB}" == "1" ]]; then
      safe_cp "${qpath}" "${LAB}/qualifications/$(basename "${qpath}")"
      echo "PROMOTED $(basename "${qpath}")" | tee -a "$LOG"
    else
      echo "QUAL_ON_PVC $(basename "${qpath}") (ALPHA_PROMOTE_LAB=0)" | tee -a "$LOG"
    fi
  else
    echo "NOT_PROMOTED ${model} ${role}" | tee -a "$LOG"
  fi
}

# Run shipping + measurement for one model/scenario, then qualify with ceiling pairing.
# Optional 4th arg: ALPHA_ROOT override (lab-owned scenarios must pass "${LAB}").
run_pair() {
  local model="$1" scenario="$2" role="$3"
  local alpha_root="${4:-}"
  local extra_env=()
  if [[ -n "${alpha_root}" ]]; then
    extra_env=(env "ALPHA_ROOT=${alpha_root}")
  fi

  echo "" | tee -a "$LOG"
  echo "===== ${model} / ${scenario} (${role}) @ $(date -u) =====" | tee -a "$LOG"
  touch_lease

  local results_root="${alpha_root:-${ROOT}}/results/runs"

  find_run() {
    local profile="$1"
    RESULTS_ROOT="${results_root}" SCENARIO="${scenario}" MODEL="${model}" PROFILE="${profile}" python3 - <<'PY'
import json, glob, os
root=os.environ["RESULTS_ROOT"]
scenario=os.environ["SCENARIO"]
model=os.environ["MODEL"]
profile=os.environ["PROFILE"]
cands=[]
for p in glob.glob(f"{root}/*-{scenario}/summary.json"):
    try:
        d=json.load(open(p))
    except Exception:
        continue
    if d.get("model_id")==model and d.get("prompt_preset")==profile:
        cands.append((os.path.getmtime(p), d.get("run_id") or os.path.basename(os.path.dirname(p))))
cands.sort(reverse=True)
print(cands[0][1] if cands else "")
PY
  }

  echo "--- shipping ---" | tee -a "$LOG"
  "${extra_env[@]}" alpha_exec bin/alpha run \
    --scenario "${scenario}" --model "${model}" --preset "${model}" --profile shipping \
    2>&1 | tee -a "$LOG" || true
  local ship_id
  ship_id="$(find_run shipping)"
  echo "SHIP_RUN=${ship_id}" | tee -a "$LOG"
  promote_report "${ship_id}" "${alpha_root:-${ROOT}}"

  touch_lease
  echo "--- measurement ---" | tee -a "$LOG"
  "${extra_env[@]}" alpha_exec bin/alpha run \
    --scenario "${scenario}" --model "${model}" --preset "${model}" --profile measurement \
    2>&1 | tee -a "$LOG" || true
  local meas_id
  meas_id="$(find_run measurement)"
  echo "MEAS_RUN=${meas_id}" | tee -a "$LOG"
  promote_report "${meas_id}" "${alpha_root:-${ROOT}}"

  if [[ -n "${ship_id}" ]]; then
    if [[ -n "${meas_id}" ]]; then
      "${extra_env[@]}" alpha_exec bin/alpha qualify --run "${ship_id}" --measurement-run "${meas_id}" --role "${role}" \
        2>&1 | tee -a "$LOG" || true
    else
      "${extra_env[@]}" alpha_exec bin/alpha qualify --run "${ship_id}" --role "${role}" \
        2>&1 | tee -a "$LOG" || true
    fi
    promote_qual "${model}" "${role}" "${alpha_root:-${ROOT}}"
  fi
}

if stage_at_or_after chat; then
  if [[ "${MODE}" == "ops" ]]; then
    for m in "${OPS_MODELS[@]}"; do
      run_pair "$m" email-triage triager
      run_pair "$m" pii-scrubbing sanitizer
      run_pair "$m" ocr-extraction extractor
    done
  else
    for m in "${CHAT_MODELS[@]}"; do
      run_pair "$m" email-triage triager
    done
    for m in "${EXTRACT_MODELS[@]}"; do
      run_pair "$m" pii-scrubbing sanitizer
      run_pair "$m" ocr-extraction extractor
    done
  fi
fi

if stage_at_or_after vault; then
  if [[ "${MODE}" == "ops" ]]; then
    for m in "${OPS_MODELS[@]}"; do
      run_pair "$m" vault-extract vault_extractor
      run_pair "$m" vault-sanitize vault_sanitizer
      run_pair "$m" vault-reconcile recon_ops
    done
  else
    for m in "${EXTRACT_MODELS[@]}"; do
      run_pair "$m" vault-extract vault_extractor
      run_pair "$m" vault-sanitize vault_sanitizer
      run_pair "$m" vault-reconcile recon_ops
    done
  fi
fi

# ikigai-dot is owned solely by alpha-lab
if stage_at_or_after crm; then
  if [[ "${MODE}" == "ops" ]]; then
    for m in "${OPS_MODELS[@]}"; do
      run_pair "$m" ikigai-dot crm_ops "${LAB}"
    done
  else
    for m in "${CRM_MODELS[@]}"; do
      run_pair "$m" ikigai-dot crm_ops "${LAB}"
    done
  fi
fi

if [[ "${MODE}" == "full" ]]; then
  if stage_at_or_after coding; then
    for m in "${CODING_MODELS[@]}"; do
      run_pair "$m" scoped-coding scoped_coder
      run_pair "$m" ledger-coding ledger_coder
      run_pair "$m" qwen36-daily coder
    done
  fi
  if stage_at_or_after ruby; then
    for m in "${WEB_EARLY_MODELS[@]}"; do
      run_pair "$m" ruby-coding ruby_coder
    done
  fi
  if stage_at_or_after frontend; then
    for m in "${WEB_EARLY_MODELS[@]}"; do
      run_pair "$m" frontend-coding frontend_coder
    done
  fi
  if stage_at_or_after hotwire; then
    for m in "${WEB_LATE_MODELS[@]}"; do
      run_pair "$m" hotwire-coding hotwire_coder
    done
  fi
fi

if stage_at_or_after manifest; then
  map_out="${ARTIFACT_ROOT}/reports/CAPABILITY_MAP_LIVE.md"
  if [[ "${PROMOTE_LAB}" == "1" ]]; then
    echo "=== regenerating alpha-lab manifest ===" | tee -a "$LOG"
    ALPHA_ROOT="${LAB}" alpha_exec bin/alpha qualify --manifest 2>&1 | tee -a "$LOG" || true
    ALPHA_ROOT="${LAB}" alpha_exec bin/alpha qualify --list 2>&1 | tee -a "$LOG" || true
    map_out="${LAB}/reports/CAPABILITY_MAP_LIVE.md"
  else
    echo "=== manifest on PVC (ALPHA_PROMOTE_LAB=0) ===" | tee -a "$LOG"
  fi

  map_runs="$(ROOT="${ROOT}" LAB="${LAB}" ARTIFACT_ROOT="${ARTIFACT_ROOT}" MODE="${MODE}" python3 - <<'PY'
import json, glob, os
ids=[]
seen=set()
mode=os.environ.get("MODE","full")
ops={"email-triage","ocr-extraction","pii-scrubbing","vault-extract","vault-sanitize","vault-reconcile","ikigai-dot"}
limit=120 if mode=="ops" else 80
for root in [os.environ["ROOT"], os.environ["LAB"], os.environ.get("ARTIFACT_ROOT","")]:
    if not root:
        continue
    for p in sorted(glob.glob(f"{root}/results/runs/*/summary.json"), key=lambda x: -os.path.getmtime(x)):
        try:
            d=json.load(open(p))
        except Exception:
            continue
        if d.get("prompt_preset")!="shipping" or d.get("schema")!="alpha.report.v2":
            continue
        if mode=="ops" and d.get("scenario") not in ops:
            continue
        rid=d.get("run_id") or p.split("/")[-2]
        if rid in seen:
            continue
        seen.add(rid)
        ids.append(rid)
        if len(ids)>=limit:
            break
    if len(ids)>=limit:
        break
print(",".join(ids))
PY
)"
  if [[ -n "${map_runs}" ]]; then
    mkdir -p "$(dirname "${map_out}")"
    alpha_exec bin/alpha capability-map --runs "${map_runs}" --out "${map_out}" \
      2>&1 | tee -a "$LOG" || true
    echo "CAPABILITY_MAP=${map_out}" | tee -a "$LOG"
  fi

  # Phase 0/3: never regenerate Own/Unattended OPS_TRUST from Alpha.
  # Active delegation views are Phase 7 and live only in alpha-lab.
  echo "OPS_TRUST_SKIPPED (no Own/Unattended regeneration; see alpha-lab notes/OPS_TRUST.md)" | tee -a "$LOG"
fi

echo "=== DONE ${MODE} capability-map $(date -u) ===" | tee -a "$LOG"
echo "FINISHED_LOG=${LOG}"
