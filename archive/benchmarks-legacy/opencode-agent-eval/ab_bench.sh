#!/usr/bin/env bash
# A/B benchmark: qwen2.5-coder:7b-q4_K_M (A) vs qwen2.5-coder:14b (B)
# on 3 small, verifiable edit tasks in the Odysseus repo.
# Headless via `opencode run --auto` (auto-approves edit:ask; deny rules still hold).
#
# Usage:
#   ab_bench.sh smoke   # one cell: model A x task tA (fast pipeline check)
#   ab_bench.sh         # full 2x3 matrix
set -uo pipefail

REPO=/home/user/odysseus
SP=/tmp/claude-1000/-home-user-odysseus/2fae7a02-ebad-43fa-a859-96726b4ebf02/scratchpad
RESULTS=$SP/ab-results
TIMEOUT=300

# label + model id
declare -a MODELS=(
  "A|mistral-nemo:12b"
  "B|qwen3:8b"
)

# Parallel task arrays (same index). Prompts use NO single quotes.
declare -a TIDS=( tA tB tC )
declare -a TFILES=(
  "services/youtube/youtube_handler.py"
  "src/markitdown_runtime.py"
  "src/url_safety.py"
)
# setup: shell run before the model, to create a "before" state (empty = none)
declare -a TSETUP=(
  ""
  "git apply $SP/taskB_before.patch"
  "git apply $SP/taskC_before.patch"
)
declare -a TTEST=(
  "python -m pytest tests/test_is_youtube_url_nonstring_svc.py -q"
  "python -m pytest tests/test_markitdown_format_nonstring.py -q"
  "python -m pytest tests/test_url_safety.py -q"
)
declare -a TPROMPT=(
  "In services/youtube/youtube_handler.py, add a one-line docstring to the function is_youtube_url describing that it returns True for youtube.com or youtu.be URLs and False for anything else including non-strings. Do not change any logic."
  "In src/markitdown_runtime.py, the function is_markitdown_format currently raises when given a non-string path. Make it return False for a non-string path such as None, an int, or a list, before it calls os.path.splitext. Keep valid extensions working."
  "In src/url_safety.py, the function check_outbound_url currently crashes when the resolver returns non-IP or non-string values. Update it so that when the resolver returns a mix of unparseable values and at least one valid IP, it skips the junk entries and still validates the real IP. If none of the returned values parse as an IP address, it must fail closed and return False with the reason that the host does not resolve to an IP."
)

clean() { cd "$REPO" && git checkout -- . 2>/dev/null; }

run_one() { # idx label model
  local i=$1 label=$2 model=$3
  local tid=${TIDS[$i]} file=${TFILES[$i]} setup=${TSETUP[$i]} testcmd=${TTEST[$i]} prompt=${TPROMPT[$i]}
  local out=$RESULTS/$label/$tid
  mkdir -p "$out"
  cd "$REPO" || return 1

  clean
  if [ -n "$setup" ]; then
    if ! eval "$setup"; then echo "!! setup failed for $tid" | tee "$out/ERROR"; return 1; fi
  fi
  # pre-run test state (for B/C should be failing; for A passing)
  bash -c "cd '$REPO' && $testcmd" >"$out/pretest.txt" 2>&1; local prerc=$?

  echo ">> [$label $model] $tid  (pre_rc=$prerc)"
  local t0 rc secs
  t0=$(date +%s)
  timeout "$TIMEOUT" opencode run --auto --model "ollama/$model" "$prompt" >"$out/run.log" 2>&1
  rc=$?
  secs=$(( $(date +%s) - t0 ))

  git diff >"$out/change.diff"
  local edited; edited=$(git diff --name-only | tr '\n' ',')
  bash -c "cd '$REPO' && $testcmd" >"$out/posttest.txt" 2>&1; local postrc=$?
  local psum; psum=$(grep -oE '[0-9]+ (passed|failed|error)[a-z]*' "$out/posttest.txt" | tr '\n' ' ')
  [ -z "$psum" ] && psum=$(tail -1 "$out/posttest.txt")

  local line="label=$label model=$model task=$tid run_rc=$rc secs=${secs}s pre_rc=$prerc post_rc=$postrc post=[$psum] edited=[$edited] difflines=$(wc -l <"$out/change.diff"|tr -d ' ')"
  echo "$line" | tee -a "$RESULTS/summary.txt"
  clean
}

main() {
  mkdir -p "$RESULTS"; : >"$RESULTS/summary.txt"; clean
  local mode=${1:-full}
  if [ "$mode" = "smoke" ]; then
    run_one 0 A "qwen2.5-coder:7b-instruct-q4_K_M"
    echo "=== SMOKE DONE ==="; return
  fi
  for m in "${MODELS[@]}"; do
    local label=${m%%|*} model=${m#*|}
    for i in 0 1 2; do run_one "$i" "$label" "$model"; done
  done
  echo; echo "=== SUMMARY ==="; cat "$RESULTS/summary.txt"
}

main "${1:-full}"
