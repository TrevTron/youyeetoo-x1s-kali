#!/usr/bin/env bash
set -Eeuo pipefail

OUT_DIR="${1:-$HOME/x1s-lab/logs/inference-$(date +%F-%H%M%S)}"
MAX_TEMP_C="${MAX_TEMP_C:-85}"
NUM_PREDICT="${NUM_PREDICT:-96}"
NUM_CTX="${NUM_CTX:-4096}"
API="${OLLAMA_HOST:-http://127.0.0.1:11434}"

if [[ -n "${MODEL_LIST:-}" ]]; then
  read -r -a MODELS <<< "$MODEL_LIST"
else
  MODELS=(
    "qwen3:0.6b"
    "qwen3:1.7b"
    "qwen3:4b-instruct"
    "phi4-mini"
    "gemma3:4b"
    "qwen3:8b"
  )
fi

PROMPT='Without using markdown, explain in exactly four short sentences what CPU-only local language-model inference is. Mention quantization, tokens per second, memory, and temperature. Do not claim that this machine has a GPU.'

mkdir -p "$OUT_DIR"
RESULTS="$OUT_DIR/results.jsonl"
SUMMARY="$OUT_DIR/summary.csv"
EVENTS="$OUT_DIR/events.log"

printf '%s\n' 'model,run,total_s,load_s,prompt_tokens,prompt_tps,generated_tokens,generation_tps,done_reason,response_sha256' > "$SUMMARY"

pkg_temp_c() {
  local path
  for path in /sys/class/thermal/thermal_zone*/temp; do
    if [[ -r "$path" ]] && [[ "$(cat "${path%/temp}/type" 2>/dev/null || true)" == "x86_pkg_temp" ]]; then
      awk '{printf "%.1f", $1/1000}' "$path"
      return
    fi
  done
  printf ''
}

nvme_temp_c() {
  local h
  for h in /sys/class/hwmon/hwmon*; do
    if [[ -r "$h/name" ]] && [[ "$(cat "$h/name")" == "nvme" ]] && [[ -r "$h/temp1_input" ]]; then
      awk '{printf "%.1f", $1/1000}' "$h/temp1_input"
      return
    fi
  done
  if command -v nvme >/dev/null 2>&1; then
    sudo -n nvme smart-log /dev/nvme0 2>/dev/null | awk '/^temperature[[:space:]]*:/ {print $3; exit}'
  fi
}

cpu_use() {
  local _cpu user nice system idle iowait irq softirq steal _rest
  read -r _cpu user nice system idle iowait irq softirq steal _rest < /proc/stat
  local total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
  local idle1=$((idle + iowait))
  sleep 1
  read -r _cpu user nice system idle iowait irq softirq steal _rest < /proc/stat
  local total2=$((user + nice + system + idle + iowait + irq + softirq + steal))
  local idle2=$((idle + iowait))
  awk -v t="$((total2-total1))" -v i="$((idle2-idle1))" 'BEGIN {if (t>0) printf "%.2f", 100*(t-i)/t; else printf "0.00"}'
}

sampler() {
  local model="$1" csv="$2" stop_file="$3" request_pid="$4"
  printf '%s\n' 'timestamp,model,cpu_pct,load1,pkg_temp_c,nvme_temp_c,mem_available_mib,ollama_rss_mib' > "$csv"
  while [[ ! -e "$stop_file" ]]; do
    local now cpu load temp nvme_temp mem rss
    now="$(date --iso-8601=seconds)"
    cpu="$(cpu_use)"
    load="$(awk '{print $1}' /proc/loadavg)"
    temp="$(pkg_temp_c)"
    nvme_temp="$(nvme_temp_c || true)"
    mem="$(awk '/MemAvailable:/ {printf "%.1f", $2/1024}' /proc/meminfo)"
    rss="$(ps -C ollama -o rss= 2>/dev/null | awk '{s+=$1} END {printf "%.1f", s/1024}')"
    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' "$now" "$model" "$cpu" "$load" "$temp" "$nvme_temp" "$mem" "$rss" >> "$csv"
    if [[ -n "$temp" ]] && awk -v t="$temp" -v max="$MAX_TEMP_C" 'BEGIN {exit !(t>=max)}'; then
      printf '%s THERMAL_ABORT model=%s package_temp_c=%s threshold_c=%s\n' "$now" "$model" "$temp" "$MAX_TEMP_C" | tee -a "$EVENTS"
      touch "$OUT_DIR/THERMAL_ABORT"
      kill -TERM "$request_pid" 2>/dev/null || true
      return
    fi
  done
}

cleanup() {
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

{
  printf 'started=%s\n' "$(date --iso-8601=seconds)"
  printf 'hostname=%s\n' "$(hostname)"
  printf 'kernel=%s\n' "$(uname -r)"
  printf 'ollama_version=%s\n' "$(ollama --version 2>&1)"
  printf 'num_ctx=%s\nnum_predict=%s\nmax_temp_c=%s\n' "$NUM_CTX" "$NUM_PREDICT" "$MAX_TEMP_C"
  lscpu
  free -h
  ollama list
} > "$OUT_DIR/environment.txt"

for model in "${MODELS[@]}"; do
  if [[ -e "$OUT_DIR/THERMAL_ABORT" ]]; then
    break
  fi

  safe="${model//[:\/]/_}"
  show_payload="$(jq -n --arg model "$model" '{model:$model}')"
  curl --fail --silent --show-error -H 'Content-Type: application/json' \
    --data-binary "$show_payload" "$API/api/show" > "$OUT_DIR/${safe}-model.json"
  ollama stop "$model" >/dev/null 2>&1 || true
  sleep 3

  for run in 1 2 3; do
    stop_file="$OUT_DIR/.stop-${safe}-${run}"
    telemetry="$OUT_DIR/${safe}-run${run}-telemetry.csv"
    response="$OUT_DIR/${safe}-run${run}.json"
    rm -f "$stop_file"
    payload="$(jq -n \
      --arg model "$model" \
      --arg prompt "$PROMPT" \
      --argjson ctx "$NUM_CTX" \
      --argjson predict "$NUM_PREDICT" \
      '{model:$model,prompt:$prompt,stream:false,think:false,keep_alive:"2m",options:{num_ctx:$ctx,num_predict:$predict,temperature:0,seed:42}}')"

    timeout 15m curl --fail --silent --show-error \
      -H 'Content-Type: application/json' \
      --data-binary "$payload" "$API/api/generate" > "$response" &
    request_pid=$!
    sampler "$model" "$telemetry" "$stop_file" "$request_pid" &
    sampler_pid=$!

    if ! wait "$request_pid"; then
      printf '%s REQUEST_FAILED model=%s run=%s\n' "$(date --iso-8601=seconds)" "$model" "$run" | tee -a "$EVENTS"
      touch "$stop_file"
      wait "$sampler_pid" 2>/dev/null || true
      break
    fi

    touch "$stop_file"
    wait "$sampler_pid" 2>/dev/null || true
    jq -c --arg model "$model" --argjson run "$run" '. + {benchmark_model:$model,benchmark_run:$run}' "$response" >> "$RESULTS"

    jq -r --arg model "$model" --arg run "$run" '
      [
        $model,
        $run,
        ((.total_duration // 0) / 1000000000),
        ((.load_duration // 0) / 1000000000),
        (.prompt_eval_count // 0),
        (if (.prompt_eval_duration // 0) > 0 then (.prompt_eval_count * 1000000000 / .prompt_eval_duration) else 0 end),
        (.eval_count // 0),
        (if (.eval_duration // 0) > 0 then (.eval_count * 1000000000 / .eval_duration) else 0 end),
        (.done_reason // ""),
        (.response | @base64)
      ] | @csv' "$response" |
      while IFS= read -r row; do
        prefix="$(printf '%s' "$row" | sed 's/,"[^"]*"$/,/')"
        hash="$(jq -r '.response' "$response" | sha256sum | awk '{print $1}')"
        printf '%s%s\n' "$prefix" "$hash" >> "$SUMMARY"
      done

    if [[ -e "$OUT_DIR/THERMAL_ABORT" ]]; then
      break 2
    fi
  done
  ollama stop "$model" >/dev/null 2>&1 || true
done

{
  printf 'finished=%s\n' "$(date --iso-8601=seconds)"
  systemctl --failed --no-pager || true
  journalctl -k --since "$(date -d '2 hours ago' '+%F %T')" --no-pager | grep -Ei 'oom|out of memory|thermal|thrott|nvme.*(error|critical)' || true
} > "$OUT_DIR/final-health.txt"

printf 'Benchmark artifacts: %s\n' "$OUT_DIR" | tee -a "$EVENTS"
