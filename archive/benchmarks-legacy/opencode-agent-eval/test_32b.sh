#!/usr/bin/env bash
# 32B validation: does bigger model fix tool-call FORMAT and edit COMPETENCE?
# Runs slow on a 12GB card (heavy CPU offload) — that's expected; we only care about correctness.
set -uo pipefail
M=qwen2.5-coder:32b
REPO=/home/user/odysseus
SP=/tmp/claude-1000/-home-user-odysseus/2fae7a02-ebad-43fa-a859-96726b4ebf02/scratchpad
OUT=$SP/results_32b; mkdir -p "$OUT"

echo "################ 1) NATIVE tool_calls reliability (format) ################"
read_test() {
curl -s http://localhost:11434/api/chat -d "{\"model\":\"$M\",\"stream\":false,\"options\":{\"temperature\":0.2},\"messages\":[{\"role\":\"user\",\"content\":\"Read the file src/foo.py using the read tool.\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"read\",\"parameters\":{\"type\":\"object\",\"properties\":{\"filePath\":{\"type\":\"string\"}},\"required\":[\"filePath\"]}}}]}" 2>/dev/null | python3 -c "import sys,json;m=json.load(sys.stdin).get('message',{});print('  read  tool_calls:', 'YES' if m.get('tool_calls') else 'NONE(text)')"
}
edit_test() {
curl -s http://localhost:11434/api/chat -d "{\"model\":\"$M\",\"stream\":false,\"options\":{\"temperature\":0.2},\"messages\":[{\"role\":\"user\",\"content\":\"Use the edit tool on src/foo.py to add a docstring line after the def.\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"edit\",\"parameters\":{\"type\":\"object\",\"properties\":{\"filePath\":{\"type\":\"string\"},\"oldString\":{\"type\":\"string\"},\"newString\":{\"type\":\"string\"}},\"required\":[\"filePath\",\"oldString\",\"newString\"]}}}]}" 2>/dev/null | python3 -c "import sys,json;m=json.load(sys.stdin).get('message',{});tc=m.get('tool_calls');print('  edit  tool_calls:', 'YES' if tc else 'NONE(text)', ('args_ok='+str(bool(tc and tc[0]['function']['arguments'].get('oldString'))) if tc else ''))"
}
for i in 1 2; do read_test; edit_test; done

echo; echo "################ 2) OpenCode headless COMPETENCE — tB + tA ################"
run_task() { # tid file setup testcmd prompt
  local tid=$1 file=$2 setup=$3 testcmd=$4 prompt=$5
  cd "$REPO"; git checkout -- . 2>/dev/null
  [ -n "$setup" ] && eval "$setup"
  echo "---- $tid ($M) ----"
  local t0=$(date +%s)
  timeout 1500 opencode run --auto --model "ollama/$M" "$prompt" >"$OUT/$tid.log" 2>&1
  local secs=$(( $(date +%s) - t0 ))
  git diff >"$OUT/$tid.diff"
  echo "  secs=$secs edited=[$(git diff --name-only|tr '\n' ',')] difflines=$(wc -l <"$OUT/$tid.diff"|tr -d ' ')"
  echo -n "  test: "; bash -c "cd '$REPO' && $testcmd" 2>&1 | tail -1
  git checkout -- . 2>/dev/null
}
run_task tB "src/markitdown_runtime.py" "git apply $SP/taskB_before.patch" \
  "python -m pytest tests/test_markitdown_format_nonstring.py -q" \
  "In src/markitdown_runtime.py, the function is_markitdown_format currently raises when given a non-string path. Make it return False for a non-string path such as None, an int, or a list, before it calls os.path.splitext. Keep valid extensions working."
run_task tA "services/youtube/youtube_handler.py" "" \
  "python -m pytest tests/test_is_youtube_url_nonstring_svc.py -q" \
  "In services/youtube/youtube_handler.py, add a one-line docstring to the function is_youtube_url describing that it returns True for youtube.com or youtu.be URLs and False for anything else including non-strings. Do not change any logic."
echo; echo "################ DONE ################"
