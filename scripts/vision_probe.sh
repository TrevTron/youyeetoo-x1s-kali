#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${1:-$HOME/x1s-lab/evidence/2026-07-16-15-x1s-live-desktop.png}"
OUT_DIR="${2:-$HOME/x1s-lab/logs/vision-probe-$(date +%F-%H%M%S)}"
API="${OLLAMA_HOST:-http://127.0.0.1:11434}"
MAX_TEMP_C="${MAX_TEMP_C:-85}"

mkdir -p "$OUT_DIR"
sha256sum "$IMAGE" > "$OUT_DIR/input-image.sha256"
file "$IMAGE" > "$OUT_DIR/input-image.txt"
base64 -w 0 "$IMAGE" | jq -Rs '{model:"gemma3:4b",prompt:"Describe this desktop screenshot in exactly three short sentences without bullets. Identify the operating system if visible, the dominant color palette, and the visible desktop icons. State uncertainty instead of inventing details.",images:[.],stream:false,think:false,keep_alive:"2m",options:{num_ctx:4096,num_predict:128,temperature:0,seed:42}}' > "$OUT_DIR/payload.json"

pkg_temp_c() {
  local path
  for path in /sys/class/thermal/thermal_zone*/temp; do
    if [[ -r "$path" ]] && [[ "$(cat "${path%/temp}/type" 2>/dev/null || true)" == "x86_pkg_temp" ]]; then
      awk '{printf "%.1f", $1/1000}' "$path"
      return
    fi
  done
}

printf '%s\n' 'timestamp,pkg_temp_c' > "$OUT_DIR/telemetry.csv"
timeout 20m curl --fail --silent --show-error -H 'Content-Type: application/json' \
  --data-binary @"$OUT_DIR/payload.json" "$API/api/generate" > "$OUT_DIR/response.json" &
request_pid=$!
peak=0
while kill -0 "$request_pid" 2>/dev/null; do
  temp="$(pkg_temp_c)"
  printf '%s,%s\n' "$(date --iso-8601=seconds)" "$temp" >> "$OUT_DIR/telemetry.csv"
  if [[ -n "$temp" ]] && awk -v t="$temp" -v max="$MAX_TEMP_C" 'BEGIN {exit !(t>=max)}'; then
    kill -TERM "$request_pid" 2>/dev/null || true
    wait "$request_pid" 2>/dev/null || true
    printf '%s THERMAL_ABORT temp_c=%s\n' "$(date --iso-8601=seconds)" "$temp" | tee "$OUT_DIR/THERMAL_ABORT"
    exit 2
  fi
  if [[ -n "$temp" ]] && awk -v t="$temp" -v p="$peak" 'BEGIN {exit !(t>p)}'; then peak="$temp"; fi
  sleep 1
done
wait "$request_pid"

jq --arg peak "$peak" '{model,response,done_reason,prompt_eval_count,eval_count,total_s:(.total_duration/1000000000),load_s:(.load_duration/1000000000),generation_tps:(.eval_count*1000000000/.eval_duration),peak_pkg_temp_c:($peak|tonumber)}' "$OUT_DIR/response.json" > "$OUT_DIR/summary.json"
systemctl --failed --no-pager > "$OUT_DIR/final-health.txt"
printf 'finished=%s\n' "$(date --iso-8601=seconds)" > "$OUT_DIR/COMPLETE"
