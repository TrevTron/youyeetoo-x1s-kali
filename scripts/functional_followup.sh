#!/usr/bin/env bash
set -Eeuo pipefail

OUT_DIR="${1:-$HOME/x1s-lab/logs/inference-followup-$(date +%F-%H%M%S)}"
API="${OLLAMA_HOST:-http://127.0.0.1:11434}"
MAX_TEMP_C="${MAX_TEMP_C:-85}"
MODELS=("qwen3:4b-instruct" "phi4-mini" "gemma3:4b")
PROMPT='Without using markdown, explain in exactly four short sentences what CPU-only local language-model inference is. Mention quantization, tokens per second, memory, and temperature. Do not claim that this machine has a GPU.'

mkdir -p "$OUT_DIR"
printf '%s\n' 'model,total_s,load_s,generated_tokens,generation_tps,done_reason,response_sha256,peak_pkg_temp_c' > "$OUT_DIR/summary.csv"

pkg_temp_c() {
  local path
  for path in /sys/class/thermal/thermal_zone*/temp; do
    if [[ -r "$path" ]] && [[ "$(cat "${path%/temp}/type" 2>/dev/null || true)" == "x86_pkg_temp" ]]; then
      awk '{printf "%.1f", $1/1000}' "$path"
      return
    fi
  done
}

for model in "${MODELS[@]}"; do
  safe="${model//[:\/]/_}"
  response="$OUT_DIR/${safe}.json"
  telemetry="$OUT_DIR/${safe}-telemetry.csv"
  printf '%s\n' 'timestamp,pkg_temp_c' > "$telemetry"
  ollama stop "$model" >/dev/null 2>&1 || true
  sleep 3
  payload="$(jq -n --arg model "$model" --arg prompt "$PROMPT" '{model:$model,prompt:$prompt,stream:false,think:false,keep_alive:"2m",options:{num_ctx:4096,num_predict:160,temperature:0,seed:42}}')"

  timeout 15m curl --fail --silent --show-error -H 'Content-Type: application/json' \
    --data-binary "$payload" "$API/api/generate" > "$response" &
  request_pid=$!
  peak=0
  while kill -0 "$request_pid" 2>/dev/null; do
    temp="$(pkg_temp_c)"
    printf '%s,%s\n' "$(date --iso-8601=seconds)" "$temp" >> "$telemetry"
    if [[ -n "$temp" ]] && awk -v t="$temp" -v max="$MAX_TEMP_C" 'BEGIN {exit !(t>=max)}'; then
      kill -TERM "$request_pid" 2>/dev/null || true
      wait "$request_pid" 2>/dev/null || true
      printf '%s THERMAL_ABORT model=%s temp_c=%s\n' "$(date --iso-8601=seconds)" "$model" "$temp" | tee "$OUT_DIR/THERMAL_ABORT"
      exit 2
    fi
    if [[ -n "$temp" ]] && awk -v t="$temp" -v p="$peak" 'BEGIN {exit !(t>p)}'; then peak="$temp"; fi
    sleep 1
  done
  wait "$request_pid"

  hash="$(jq -r '.response' "$response" | sha256sum | awk '{print $1}')"
  jq -r --arg model "$model" --arg hash "$hash" --arg peak "$peak" '
    [
      $model,
      ((.total_duration // 0) / 1000000000),
      ((.load_duration // 0) / 1000000000),
      (.eval_count // 0),
      (if (.eval_duration // 0) > 0 then (.eval_count * 1000000000 / .eval_duration) else 0 end),
      (.done_reason // ""),
      $hash,
      ($peak | tonumber)
    ] | @csv' "$response" >> "$OUT_DIR/summary.csv"
  ollama stop "$model" >/dev/null 2>&1 || true
done

systemctl --failed --no-pager > "$OUT_DIR/final-health.txt"
printf 'finished=%s\n' "$(date --iso-8601=seconds)" > "$OUT_DIR/COMPLETE"

