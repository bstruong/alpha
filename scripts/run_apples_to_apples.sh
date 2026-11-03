#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== Running GLM-4.7 Flash REAP Apples-to-Apples Suite ==="
date

# 1. Switch preset to GLM-4.7 Flash REAP
echo "--- Switching preset to GLM-4.7 Flash REAP ---"
bin/alpha engine down || true
sleep 3
bin/alpha engine up --preset glm47-reap

# 2. Run pii-scrubbing
echo "--- Running GLM-4.7: pii-scrubbing ---"
bin/alpha run --scenario pii-scrubbing --model glm47-reap --preset glm47-reap || true
RUN_ID=$(ls -td results/runs/*-pii-scrubbing 2>/dev/null | head -n 1 | xargs -n 1 basename || true)
if [ -n "$RUN_ID" ]; then
  bin/alpha qualify --run "$RUN_ID" || true
fi

# 3. Run ocr-extraction
echo "--- Running GLM-4.7: ocr-extraction ---"
bin/alpha run --scenario ocr-extraction --model glm47-reap --preset glm47-reap || true
RUN_ID=$(ls -td results/runs/*-ocr-extraction 2>/dev/null | head -n 1 | xargs -n 1 basename || true)
if [ -n "$RUN_ID" ]; then
  bin/alpha qualify --run "$RUN_ID" || true
fi

# 4. Run scoped-coding (decomposed tasks with self-repair)
echo "--- Running GLM-4.7: scoped-coding ---"
bin/alpha run --scenario scoped-coding --model glm47-reap --preset glm47-reap --repair --no-gate-halt || true

# 5. Run qwen36-daily (canonical 9 tasks with self-repair)
echo "--- Running GLM-4.7: qwen36-daily ---"
bin/alpha run --scenario qwen36-daily --model glm47-reap --preset glm47-reap --repair --no-gate-halt || true
RUN_ID=$(ls -td results/runs/*-qwen36-daily 2>/dev/null | head -n 1 | xargs -n 1 basename || true)
if [ -n "$RUN_ID" ]; then
  bin/alpha qualify --run "$RUN_ID" || true
fi

# 6. Scale engine down to zero
echo "--- Scaling engine to zero ---"
bin/alpha engine down
bin/alpha engine status || true

echo "=== GLM-4.7 Suite execution finished! ==="
date
