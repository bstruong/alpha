#!/bin/bash

MODELS=(
  "gemma4:e4b"
  "phi4:14b"
)

PROMPTS_DIR="prompts"
RESULTS_DIR="results"

# --- Argument handling ---
PROMPT_FILE="${1}"

if [[ -z "$PROMPT_FILE" ]]; then
  echo "Usage: ./bench.sh <prompt-filename>"
  echo ""
  echo "Available prompts:"
  for f in "$PROMPTS_DIR"/*.md; do
    echo "  $(basename "$f")"
  done
  exit 1
fi

PROMPT_PATH="${PROMPTS_DIR}/${PROMPT_FILE}"

if [[ ! -f "$PROMPT_PATH" ]]; then
  echo "Error: '$PROMPT_PATH' not found"
  echo ""
  echo "Available prompts:"
  for f in "$PROMPTS_DIR"/*.md; do
    echo "  $(basename "$f")"
  done
  exit 1
fi

LABEL=$(basename "$PROMPT_FILE" .md | sed 's/^prompt-//')
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="${RESULTS_DIR}/bench_${LABEL}_${TIMESTAMP}.txt"

PROMPT=$(<"$PROMPT_PATH")

{
  echo "=============================="
  echo "HTC Benchmark — $(date)"
  echo "Prompt: $PROMPT_PATH"
  echo "Output: $OUTPUT_FILE"
  echo "=============================="

  for MODEL in "${MODELS[@]}"; do
    echo ""
    echo "--- $MODEL ---"

    RESULT=$(curl -s http://localhost:11434/api/generate \
      -d "{
        \"model\": \"$MODEL\",
        \"prompt\": $(echo "$PROMPT" | jq -Rs .),
        \"stream\": false
      }")

    echo "$RESULT" | jq '{
      tokens_generated: .eval_count,
      duration_seconds: (.eval_duration / 1e9),
      tokens_per_second: (.eval_count / (.eval_duration / 1e9)),
      time_to_first_token_seconds: (.prompt_eval_duration / 1e9)
    }'

    echo ""
    echo "Response:"
    echo "$RESULT" | jq -r '.response'
    echo "=============================="
  done
} 2>&1 | tee "$OUTPUT_FILE"

echo ""
echo "Results saved to: $OUTPUT_FILE"
