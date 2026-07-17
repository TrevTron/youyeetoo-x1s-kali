#!/usr/bin/env bash
set -Eeuo pipefail

OUT_DIR="${1:-$HOME/x1s-lab/logs/model-pull-$(date +%F-%H%M%S)}"
mkdir -p "$OUT_DIR"
exec > >(tee -a "$OUT_DIR/pull.log") 2>&1

MODELS=(
  "qwen3:0.6b"
  "qwen3:1.7b"
  "qwen3:4b-instruct"
  "phi4-mini"
  "gemma3:4b"
  "qwen3:8b"
)

printf 'started=%s\n' "$(date --iso-8601=seconds)"
printf 'hostname=%s\n' "$(hostname)"
printf 'ollama_version=%s\n' "$(ollama --version 2>&1)"
lscpu | sed -n '/Model name:/p;/^Flags:/p'
df -h /

for model in "${MODELS[@]}"; do
  printf '\n[%s] pulling %s\n' "$(date --iso-8601=seconds)" "$model"
  if ! timeout 3h ollama pull "$model"; then
    printf '[%s] PULL_FAILED %s\n' "$(date --iso-8601=seconds)" "$model" | tee "$OUT_DIR/PULL_FAILED"
    exit 1
  fi
  safe="${model//[:\/]/_}"
  show_payload="$(jq -n --arg model "$model" '{model:$model}')"
  curl --fail --silent --show-error -H 'Content-Type: application/json' \
    --data-binary "$show_payload" http://127.0.0.1:11434/api/show > "$OUT_DIR/${safe}-model.json"
  ollama list > "$OUT_DIR/models-after-${safe}.txt"
  df -h / > "$OUT_DIR/disk-after-${safe}.txt"
done

ollama list | tee "$OUT_DIR/final-model-list.txt"
df -h / | tee "$OUT_DIR/final-disk.txt"
printf 'finished=%s\n' "$(date --iso-8601=seconds)" | tee "$OUT_DIR/COMPLETE"
