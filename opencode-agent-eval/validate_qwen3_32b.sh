#!/usr/bin/env bash
# FINAL validation: qwen3:32b (big + reliable NATIVE tool_calls, no template patch needed)
# on all 3 tasks headless. Answers: does big-model + reliable-format = working agentic edits?
set -uo pipefail
M=qwen3:32b
REPO=/home/brian/odysseus
SP=/tmp/claude-1000/-home-brian-odysseus/2fae7a02-ebad-43fa-a859-96726b4ebf02/scratchpad
OUT=$SP/results_qwen3_32b; mkdir -p "$OUT"

run_task() { # tid file setup testcmd prompt
  local tid=$1 file=$2 setup=$3 testcmd=$4 prompt=$5
  cd "$REPO"; git checkout -- . 2>/dev/null
  [ -n "$setup" ] && eval "$setup"
  echo "---- $tid ($M) ----"
  local t0=$(date +%s)
  timeout 1800 opencode run --auto --model "ollama/$M" "$prompt" >"$OUT/$tid.log" 2>&1
  local secs=$(( $(date +%s) - t0 ))
  git diff >"$OUT/$tid.diff"
  echo "  secs=$secs edited=[$(git diff --name-only|tr '\n' ',')] difflines=$(wc -l <"$OUT/$tid.diff"|tr -d ' ')"
  echo -n "  test: "; bash -c "cd '$REPO' && $testcmd" 2>&1 | tail -1
  git checkout -- . 2>/dev/null
}
run_task tB "src/markitdown_runtime.py" "git apply $SP/taskB_before.patch" \
  "python -m pytest tests/test_markitdown_format_nonstring.py -q" \
  "In src/markitdown_runtime.py, the function is_markitdown_format currently raises when given a non-string path. Make it return False for a non-string path such as None, an int, or a list, before it calls os.path.splitext. Keep valid extensions working."
run_task tC "src/url_safety.py" "git apply $SP/taskC_before.patch" \
  "python -m pytest tests/test_url_safety.py -q" \
  "In src/url_safety.py, the function check_outbound_url currently crashes when the resolver returns non-IP or non-string values. Update it so that when the resolver returns a mix of unparseable values and at least one valid IP, it skips the junk entries and still validates the real IP. If none of the returned values parse as an IP address, it must fail closed and return False with the reason that the host does not resolve to an IP."
run_task tA "services/youtube/youtube_handler.py" "" \
  "python -m pytest tests/test_is_youtube_url_nonstring_svc.py -q" \
  "In services/youtube/youtube_handler.py, add a one-line docstring to the function is_youtube_url describing that it returns True for youtube.com or youtu.be URLs and False for anything else including non-strings. Do not change any logic."
echo "################ DONE ################"
