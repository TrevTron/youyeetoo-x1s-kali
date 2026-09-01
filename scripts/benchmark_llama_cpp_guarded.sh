#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 2 || $# -gt 4 ]]; then
  echo "Usage: $0 MODEL_GGUF MODE [GPU_LAYERS] [OUTPUT_DIRECTORY]" >&2
  echo "Modes: pure-cpu, mixed-host-op, full-vulkan" >&2
  echo "Example CPU: $0 model.gguf pure-cpu 0" >&2
  echo "Example mixed zero-layer mode: $0 model.gguf mixed-host-op 0" >&2
  echo "Example Vulkan: $0 model.gguf full-vulkan 99" >&2
  exit 64
fi

MODEL_PATH="$1"
MODE="$2"
GPU_LAYERS="${3:-0}"
OUT_DIR="${4:-$PWD/llama-bench-$(date +%F-%H%M%S)}"
LLAMA_BENCH="${LLAMA_BENCH:-llama-bench}"
MAX_TEMP_C="${MAX_TEMP_C:-85}"
BASELINE_MAX_C="${BASELINE_MAX_C:-65}"
TIME_LIMIT="${TIME_LIMIT:-10m}"
PROMPT_TOKENS="${PROMPT_TOKENS:-128}"
GENERATED_TOKENS="${GENERATED_TOKENS:-96}"
REPETITIONS="${REPETITIONS:-2}"
THREADS="${THREADS:-4}"
BATCH_SIZE="${BATCH_SIZE:-512}"
MICROBATCH_SIZE="${MICROBATCH_SIZE:-512}"
LLAMA_BIN_DIR="$(dirname "$(realpath "$LLAMA_BENCH")")"
LLAMA_SOURCE_DIR="$(realpath "${LLAMA_BIN_DIR}/../..")"

[[ -r "$MODEL_PATH" ]] || { echo "Model is not readable: $MODEL_PATH" >&2; exit 66; }
command -v "$LLAMA_BENCH" >/dev/null 2>&1 || { echo "llama-bench not found: $LLAMA_BENCH" >&2; exit 69; }
[[ "$GPU_LAYERS" =~ ^[0-9]+$ ]] || { echo "GPU_LAYERS must be a nonnegative integer" >&2; exit 64; }
[[ "$BATCH_SIZE" =~ ^[1-9][0-9]*$ ]] || { echo "BATCH_SIZE must be a positive integer" >&2; exit 64; }
[[ "$MICROBATCH_SIZE" =~ ^[1-9][0-9]*$ ]] || { echo "MICROBATCH_SIZE must be a positive integer" >&2; exit 64; }
(( MICROBATCH_SIZE <= BATCH_SIZE )) || { echo "MICROBATCH_SIZE must not exceed BATCH_SIZE" >&2; exit 64; }

case "$MODE" in
  pure-cpu)
    (( GPU_LAYERS == 0 )) || { echo "pure-cpu requires GPU_LAYERS=0" >&2; exit 64; }
    DEVICE_VISIBLE=0
    HOST_OP_OFFLOAD=0
    ;;
  mixed-host-op)
    (( GPU_LAYERS == 0 )) || { echo "mixed-host-op requires GPU_LAYERS=0" >&2; exit 64; }
    DEVICE_VISIBLE=1
    HOST_OP_OFFLOAD=1
    ;;
  full-vulkan)
    (( GPU_LAYERS > 0 )) || { echo "full-vulkan requires GPU_LAYERS greater than zero" >&2; exit 64; }
    DEVICE_VISIBLE=1
    HOST_OP_OFFLOAD=1
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    exit 64
    ;;
esac

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

wait_for_baseline() {
  local attempt temp
  for attempt in $(seq 1 120); do
    temp="$(pkg_temp_c)"
    if [[ -n "$temp" ]] && awk -v t="$temp" -v max="$BASELINE_MAX_C" 'BEGIN {exit !(t<max)}'; then
      printf '%s BASELINE_OK package_temp_c=%s attempt=%s\n' \
        "$(date --iso-8601=seconds)" "$temp" "$attempt" >> "$EVENTS"
      return 0
    fi
    sleep 2
  done
  printf '%s BASELINE_TIMEOUT package_temp_c=%s threshold_c=%s\n' \
    "$(date --iso-8601=seconds)" "$(pkg_temp_c)" "$BASELINE_MAX_C" >> "$EVENTS"
  return 1
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
    if grep -Eqi 'GPU HANG|reset timeout|reset request timed out|fence.*timeout|preempt.*timeout|i915.*(error|hang|reset)|drm.*(error|hang|reset)|DeviceLost|oom-kill|out of memory|segfault|machine check|hardware error' <<< "$line"; then
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
  printf 'model=%s\nmode=%s\ngpu_layers=%s\n' "$MODEL_PATH" "$MODE" "$GPU_LAYERS"
  printf 'device_visible=%s\nhost_op_offload=%s\n' "$DEVICE_VISIBLE" "$HOST_OP_OFFLOAD"
  printf 'prompt_tokens=%s\ngenerated_tokens=%s\nrepetitions=%s\nthreads=%s\nbatch_size=%s\nmicrobatch_size=%s\n' \
    "$PROMPT_TOKENS" "$GENERATED_TOKENS" "$REPETITIONS" "$THREADS" "$BATCH_SIZE" "$MICROBATCH_SIZE"
  printf 'baseline_max_c=%s\nmax_temp_c=%s\ntime_limit=%s\n' "$BASELINE_MAX_C" "$MAX_TEMP_C" "$TIME_LIMIT"
  sha256sum "$MODEL_PATH"
  sha256sum "$LLAMA_BENCH"
  if [[ -r "${LLAMA_BIN_DIR}/libggml-cpu.so" ]]; then
    sha256sum "${LLAMA_BIN_DIR}/libggml-cpu.so"
  fi
  if git -C "$LLAMA_SOURCE_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
    printf 'llama_commit=%s\n' "$(git -C "$LLAMA_SOURCE_DIR" rev-parse HEAD)"
  fi
  printf 'kernel=%s\n' "$(uname -r)"
  printf 'cpu=%s\n' "$(lscpu | awk -F: '/Model name/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}')"
} > "$OUT_DIR/environment.txt"

journalctl -k -n 1 --no-pager >/dev/null 2>&1 \
  || { echo "The benchmark account must be able to read the kernel journal." >&2; exit 77; }
wait_for_baseline \
  || { printf 'status=baseline-timeout\nexit_code=78\n' > "$OUT_DIR/status.txt"; exit 78; }
RUN_STARTED="$(date --iso-8601=seconds)"

if (( DEVICE_VISIBLE > 0 )); then
  mkfifo "$KERNEL_FIFO"
  kernel_monitor &
  KERNEL_PID=$!
  journalctl -kf -o short-iso > "$KERNEL_FIFO" &
  JOURNAL_PID=$!
fi

COMMAND=(
  "$LLAMA_BENCH"
  --model "$MODEL_PATH"
  --threads "$THREADS"
  --n-prompt "$PROMPT_TOKENS"
  --n-gen "$GENERATED_TOKENS"
  --repetitions "$REPETITIONS"
  --batch-size "$BATCH_SIZE"
  --ubatch-size "$MICROBATCH_SIZE"
  --n-gpu-layers "$GPU_LAYERS"
  --output csv
)
if [[ "$MODE" == "pure-cpu" ]]; then
  COMMAND=(env GGML_VK_VISIBLE_DEVICES= "${COMMAND[@]}" --no-op-offload 1)
fi

timeout "$TIME_LIMIT" "${COMMAND[@]}" > "$RESULT_CSV" 2> "$STDERR_LOG" &
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
journalctl -k --since "$RUN_STARTED" --no-pager > "$OUT_DIR/kernel.log"

if grep -Eqi \
  'GPU HANG|reset timeout|reset request timed out|fence.*timeout|preempt.*timeout|i915.*(error|hang|reset)|drm.*(error|hang|reset)|DeviceLost|oom-kill|out of memory|segfault|machine check|hardware error' \
  "$OUT_DIR/kernel.log"; then
  printf 'status=kernel-failure\nexit_code=%s\n' "$BENCH_RC" > "$OUT_DIR/status.txt"
  exit 70
fi

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
