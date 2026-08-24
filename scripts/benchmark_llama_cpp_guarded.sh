#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 2 || $# -gt 4 ]]; then
  echo "Usage: $0 MODEL_GGUF BACKEND_LABEL [GPU_LAYERS] [OUTPUT_DIRECTORY]" >&2
  echo "Example CPU: $0 model.gguf cpu 0" >&2
  echo "Example Vulkan: $0 model.gguf vulkan 99" >&2
  exit 64
fi

MODEL_PATH="$1"
BACKEND_LABEL="$2"
GPU_LAYERS="${3:-0}"
OUT_DIR="${4:-$PWD/llama-bench-$(date +%F-%H%M%S)}"
LLAMA_BENCH="${LLAMA_BENCH:-llama-bench}"
MAX_TEMP_C="${MAX_TEMP_C:-85}"
TIME_LIMIT="${TIME_LIMIT:-10m}"
PROMPT_TOKENS="${PROMPT_TOKENS:-128}"
GENERATED_TOKENS="${GENERATED_TOKENS:-96}"
REPETITIONS="${REPETITIONS:-2}"
THREADS="${THREADS:-4}"

[[ -r "$MODEL_PATH" ]] || { echo "Model is not readable: $MODEL_PATH" >&2; exit 66; }
command -v "$LLAMA_BENCH" >/dev/null 2>&1 || { echo "llama-bench not found: $LLAMA_BENCH" >&2; exit 69; }
[[ "$GPU_LAYERS" =~ ^[0-9]+$ ]] || { echo "GPU_LAYERS must be a nonnegative integer" >&2; exit 64; }

mkdir -p "$OUT_DIR"
RESULT_CSV="$OUT_DIR/result.csv"
STDERR_LOG="$OUT_DIR/stderr.log"
TELEMETRY="$OUT_DIR/telemetry.csv"
EVENTS="$OUT_DIR/events.log"
STOP_FILE="$OUT_DIR/.stop"
KERNEL_FIFO="$OUT_DIR/.kernel-fifo"
rm -f "$STOP_FILE" "$KERNEL_FIFO"

pkg_temp_c() {
  local path
  for path in /sys/class/thermal/thermal_zone*/temp; do
    if [[ -r "$path" ]] && [[ "$(cat "${path%/temp}/type" 2>/dev/null || true)" == "x86_pkg_temp" ]]; then
      awk '{printf "%.1f", $1/1000}' "$path"
      return
    fi
  done
}

stop_benchmark() {
  local reason="$1"
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$reason" | tee -a "$EVENTS"
  touch "$STOP_FILE"
  if [[ -n "${BENCH_PID:-}" ]]; then
    kill -TERM "$BENCH_PID" 2>/dev/null || true
  fi
}

sampler() {
  printf '%s\n' 'timestamp,package_temp_c' > "$TELEMETRY"
  while [[ ! -e "$STOP_FILE" ]]; do
    local temp
    temp="$(pkg_temp_c)"
    printf '%s,%s\n' "$(date --iso-8601=seconds)" "$temp" >> "$TELEMETRY"
    if [[ -n "$temp" ]] && awk -v t="$temp" -v max="$MAX_TEMP_C" 'BEGIN {exit !(t>=max)}'; then
      stop_benchmark "THERMAL_ABORT package_temp_c=$temp threshold_c=$MAX_TEMP_C"
      return
    fi
    sleep 2
  done
}

kernel_monitor() {
  local line
  while IFS= read -r line; do
    [[ -e "$STOP_FILE" ]] && return
    if grep -Eqi 'i915.*(GPU HANG|reset request timed out|Resetting .*preemption time out|stopped heartbeat)' <<< "$line"; then
      printf '%s\n' "$line" >> "$OUT_DIR/kernel-events.txt"
      stop_benchmark "GPU_ABORT i915 reset-or-hang detected"
      return
    fi
  done < "$KERNEL_FIFO"
}

cleanup() {
  touch "$STOP_FILE"
  local pid
  for pid in "${SAMPLER_PID:-}" "${KERNEL_PID:-}" "${JOURNAL_PID:-}"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  rm -f "$KERNEL_FIFO"
}
trap cleanup EXIT INT TERM

{
  printf 'started=%s\n' "$(date --iso-8601=seconds)"
  printf 'model=%s\nbackend=%s\ngpu_layers=%s\n' "$MODEL_PATH" "$BACKEND_LABEL" "$GPU_LAYERS"
  printf 'prompt_tokens=%s\ngenerated_tokens=%s\nrepetitions=%s\nthreads=%s\n' "$PROMPT_TOKENS" "$GENERATED_TOKENS" "$REPETITIONS" "$THREADS"
  printf 'max_temp_c=%s\ntime_limit=%s\n' "$MAX_TEMP_C" "$TIME_LIMIT"
  sha256sum "$MODEL_PATH"
  "$LLAMA_BENCH" --version 2>&1 | head -2
} > "$OUT_DIR/environment.txt"

if (( GPU_LAYERS > 0 )); then
  if ! sudo -n journalctl -k -n 1 --no-pager >/dev/null 2>&1; then
    echo "GPU runs require passwordless read access to the kernel journal so resets can stop the run immediately." >&2
    exit 77
  fi
  mkfifo "$KERNEL_FIFO"
  kernel_monitor &
  KERNEL_PID=$!
  sudo -n journalctl -kf -o short-iso > "$KERNEL_FIFO" &
  JOURNAL_PID=$!
fi

timeout "$TIME_LIMIT" "$LLAMA_BENCH" \
  -m "$MODEL_PATH" -t "$THREADS" -p "$PROMPT_TOKENS" \
  -n "$GENERATED_TOKENS" -r "$REPETITIONS" -ngl "$GPU_LAYERS" -o csv \
  > "$RESULT_CSV" 2> "$STDERR_LOG" &
BENCH_PID=$!
if [[ -e "$STOP_FILE" ]]; then
  kill -TERM "$BENCH_PID" 2>/dev/null || true
fi
sampler &
SAMPLER_PID=$!

set +e
wait "$BENCH_PID"
BENCH_RC=$?
set -e
touch "$STOP_FILE"
wait "$SAMPLER_PID" 2>/dev/null || true

if [[ -s "$OUT_DIR/kernel-events.txt" ]]; then
  printf 'status=gpu-kernel-failure\nexit_code=%s\n' "$BENCH_RC" > "$OUT_DIR/status.txt"
  exit 70
fi
if [[ -n "$(grep -Ei 'DeviceLost|ErrorDeviceLost' "$STDERR_LOG" || true)" ]]; then
  printf 'status=gpu-device-lost\nexit_code=%s\n' "$BENCH_RC" > "$OUT_DIR/status.txt"
  exit 70
fi
if [[ "$BENCH_RC" -ne 0 ]]; then
  printf 'status=process-failure\nexit_code=%s\n' "$BENCH_RC" > "$OUT_DIR/status.txt"
  exit "$BENCH_RC"
fi

printf 'status=clean\nexit_code=0\nfinished=%s\n' "$(date --iso-8601=seconds)" > "$OUT_DIR/status.txt"
echo "Clean benchmark artifacts: $OUT_DIR"
