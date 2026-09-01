#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${HOME}/x1s-lab"
BIN="${HOME}/llama.cpp/build-native/bin/llama-bench"
MODEL="${ROOT}/models/inclusionAI_Ling-mini-2.0-IQ4_XS.gguf"
EXPECTED_SHA256="a72d86d4cb4fedd940e34c08d008bb5cda42db80ce5c6bc5f9494e854a3d742d"
STAMP="$(date +%F-%H%M%S)"
THREADS="${THREADS:-3}"
THERMAL_LIMIT_MC="${THERMAL_LIMIT_MC:-85000}"
OUT="${ROOT}/logs/retest-2026-08-24/ling-mini-iq4-xs-t${THREADS}-final-${STAMP}"
TIMEOUT_SECONDS=1800

[[ "${THREADS}" =~ ^[1-4]$ ]] || { echo "THREADS must be from 1 through 4"; exit 2; }
[[ "${THERMAL_LIMIT_MC}" =~ ^[0-9]+$ ]] || { echo "THERMAL_LIMIT_MC must be an integer"; exit 2; }
(( THERMAL_LIMIT_MC >= 85000 && THERMAL_LIMIT_MC <= 90000 )) \
  || { echo "THERMAL_LIMIT_MC must be from 85000 through 90000"; exit 2; }

mkdir -p "${OUT}"
exec > >(tee -a "${OUT}/controller.log") 2>&1

max_temp_mc() {
  local value max=0
  for sensor in /sys/class/thermal/thermal_zone*/temp; do
    [[ -r "${sensor}" ]] || continue
    read -r value < "${sensor}" || true
    [[ "${value}" =~ ^[0-9]+$ ]] || continue
    (( value > max )) && max="${value}"
  done
  printf '%s\n' "${max}"
}

wait_for_baseline() {
  local current attempt
  for attempt in $(seq 1 180); do
    current="$(max_temp_mc)"
    if (( current < 65000 )); then
      echo "baseline_ok,temp_mc=${current},attempt=${attempt}"
      return 0
    fi
    sleep 2
  done
  echo "baseline_timeout,temp_mc=$(max_temp_mc)"
  return 1
}

[[ -x "${BIN}" ]] || { echo "missing ${BIN}"; exit 2; }
[[ -f "${MODEL}" ]] || { echo "missing ${MODEL}"; exit 2; }
journalctl -k -n 1 --no-pager >/dev/null 2>&1 \
  || { echo "kernel journal is unreadable"; exit 2; }
printf '%s  %s\n' "${EXPECTED_SHA256}" "${MODEL}" | sha256sum --check

printf 'utc,run_id,exit_code,thermal_abort,kernel_error\n' > "${OUT}/status.csv"
{
  echo "utc=$(date -u +%FT%TZ)"
  echo "kernel=$(uname -r)"
  echo "model=$(sha256sum "${MODEL}")"
  echo "model_bytes=$(stat -c %s "${MODEL}")"
  echo "bench=$(sha256sum "${BIN}")"
  echo "cpu_backend=$(sha256sum "${HOME}/llama.cpp/build-native/bin/libggml-cpu.so")"
  echo "commit=$(git -C "${HOME}/llama.cpp" rev-parse HEAD)"
  echo "selection=explicit_guarded_thread_count"
  echo "workload=pp128_tg96_threads${THREADS}_batch512_ubatch512_repetitions5"
  echo "thermal_limit_mc=${THERMAL_LIMIT_MC}"
  echo "gpu_layers=0"
  echo "host_op_offload=disabled"
  echo "vulkan_devices=hidden_for_benchmark_process"
  awk '/MemTotal:|SwapTotal:/ {printf "memory_%s=%s%s\n", $1, $2, $3}' /proc/meminfo
  echo "cpu=$(lscpu | awk -F: '/Model name/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}')"
} > "${OUT}/environment.txt"

wait_for_baseline
started="$(date --iso-8601=seconds)"
printf 'utc,temp_mc,avg_cpu_freq_khz,mem_available_kb,load1\n' > "${OUT}/telemetry.csv"

timeout --signal=TERM --kill-after=15 "${TIMEOUT_SECONDS}" \
  env GGML_VK_VISIBLE_DEVICES= "${BIN}" \
    --model "${MODEL}" \
    --n-gpu-layers 0 \
    --no-op-offload 1 \
    --batch-size 512 \
    --ubatch-size 512 \
    --n-prompt 128 \
    --n-gen 96 \
    --threads "${THREADS}" \
    --repetitions 5 \
    --output jsonl \
    --output-err jsonl \
    > "${OUT}/result.jsonl" 2> "${OUT}/stderr.log" &
job_pid=$!
killed=0

while kill -0 "${job_pid}" 2>/dev/null; do
  current="$(max_temp_mc)"
  printf '%s,%s,%s,%s,%s\n' \
    "$(date -u +%FT%TZ)" \
    "${current}" \
    "$(awk '{sum+=$1; n++} END {if (n) printf "%.0f", sum/n; else print 0}' /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null)" \
    "$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)" \
    "$(awk '{print $1}' /proc/loadavg)" >> "${OUT}/telemetry.csv"
  if (( current >= THERMAL_LIMIT_MC )); then
    echo "thermal_abort,run=standardized-t${THREADS},temp_mc=${current}"
    killed=1
    kill -TERM "${job_pid}" 2>/dev/null || true
    break
  fi
  sleep 2
done

set +e
wait "${job_pid}"
rc=$?
set -e

journalctl -k --since "${started}" --no-pager > "${OUT}/kernel.log"
serious=0
if grep -Eaiq \
  'GPU HANG|reset timeout|fence.*timeout|preempt.*timeout|i915.*(error|hang|reset)|drm.*(error|hang|reset)|DeviceLost|oom-kill|out of memory|segfault|machine check|hardware error' \
  "${OUT}/kernel.log"; then
  serious=1
fi
printf '%s,%s,%s,%s,%s\n' \
  "$(date -u +%FT%TZ)" "standardized-t${THREADS}" "${rc}" "${killed}" "${serious}" \
  >> "${OUT}/status.csv"

if (( killed != 0 || rc != 0 || serious != 0 )); then
  echo "run_failed,run=standardized-t${THREADS},rc=${rc},thermal_abort=${killed},kernel_error=${serious}"
  exit 1
fi

[[ "$(wc -l < "${OUT}/result.jsonl")" -eq 2 ]] \
  || { echo "expected one prompt and one generation row"; exit 1; }
jq -e 'select(.n_prompt == 128 or .n_gen == 96) | .samples_ts | length == 5' \
  "${OUT}/result.jsonl" >/dev/null

printf 'complete\n' > "${OUT}/status.txt"
echo "complete: ${OUT}"
