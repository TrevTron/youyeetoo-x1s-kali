#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${HOME}/x1s-lab"
BIN="${HOME}/llama.cpp/build/bin/llama-bench"
STAMP="$(date +%F-%H%M%S)"
OUT="${ROOT}/logs/retest-2026-08-24/three-mode-final-${STAMP}"
THERMAL_LIMIT_MC=85000
TIMEOUT_SECONDS=900

models=(
  "qwen3-0.6b|${ROOT}/gguf/qwen3-0.6b.gguf"
  "qwen3-1.7b|${ROOT}/gguf/qwen3-1.7b.gguf"
)

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
  for attempt in $(seq 1 120); do
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

run_one() {
  local label="$1" model="$2" mode="$3"
  local run_id="${label}-${mode}"
  local raw="${OUT}/${run_id}.jsonl"
  local err="${OUT}/${run_id}.stderr.log"
  local telemetry="${OUT}/${run_id}.telemetry.csv"
  local kernel="${OUT}/${run_id}.kernel.log"
  local started killed=0 current rc serious=0
  local -a command

  command=(
    "${BIN}"
    --model "${model}"
    --n-prompt 128
    --n-gen 96
    --threads 4
    --batch-size 512
    --ubatch-size 512
    --repetitions 5
    --output jsonl
    --output-err jsonl
  )
  case "${mode}" in
    pure-cpu)
      command=(env GGML_VK_VISIBLE_DEVICES= "${command[@]}" --n-gpu-layers 0 --no-op-offload 1)
      ;;
    mixed-host-op)
      command+=(--n-gpu-layers 0)
      ;;
    full-vulkan)
      command+=(--n-gpu-layers 99)
      ;;
    *)
      echo "unknown mode: ${mode}"
      return 2
      ;;
  esac

  wait_for_baseline
  started="$(date --iso-8601=seconds)"
  printf 'utc,temp_mc,avg_cpu_freq_khz,mem_available_kb,load1\n' > "${telemetry}"

  timeout --signal=TERM --kill-after=15 "${TIMEOUT_SECONDS}" \
    "${command[@]}" > "${raw}" 2> "${err}" &
  local job_pid=$!

  while kill -0 "${job_pid}" 2>/dev/null; do
    current="$(max_temp_mc)"
    printf '%s,%s,%s,%s,%s\n' \
      "$(date -u +%FT%TZ)" \
      "${current}" \
      "$(awk '{sum+=$1; n++} END {if (n) printf "%.0f", sum/n; else print 0}' /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null)" \
      "$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)" \
      "$(awk '{print $1}' /proc/loadavg)" >> "${telemetry}"
    if (( current >= THERMAL_LIMIT_MC )); then
      echo "thermal_abort,run=${run_id},temp_mc=${current}"
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

  journalctl -k --since "${started}" --no-pager > "${kernel}"
  if grep -Eaiq \
    'GPU HANG|reset timeout|fence.*timeout|preempt.*timeout|i915.*(error|hang|reset)|drm.*(error|hang|reset)|DeviceLost|oom-kill|out of memory|segfault|machine check|hardware error' \
    "${kernel}"; then
    serious=1
  fi
  printf '%s,%s,%s,%s,%s,%s,%s\n' \
    "$(date -u +%FT%TZ)" "${label}" "${mode}" "${rc}" "${killed}" "${serious}" "${run_id}" \
    >> "${OUT}/status.csv"

  if (( killed != 0 || rc != 0 || serious != 0 )); then
    echo "run_failed,run=${run_id},rc=${rc},thermal_abort=${killed},kernel_error=${serious}"
    return 1
  fi
}

[[ -x "${BIN}" ]] || { echo "missing ${BIN}"; exit 2; }
journalctl -k -n 1 --no-pager >/dev/null 2>&1 \
  || { echo "kernel journal is unreadable"; exit 2; }

printf 'utc,model,mode,exit_code,thermal_abort,kernel_error,run_id\n' > "${OUT}/status.csv"
{
  echo "utc=$(date -u +%FT%TZ)"
  echo "kernel=$(uname -r)"
  echo "commit=$(git -C "${HOME}/llama.cpp" rev-parse HEAD)"
  echo "bench=$(sha256sum "${BIN}")"
  echo "cpu_backend=$(sha256sum "${HOME}/llama.cpp/build/bin/libggml-cpu.so")"
  echo "vulkan_backend=$(sha256sum "${HOME}/llama.cpp/build/bin/libggml-vulkan.so")"
  echo "workload=pp128_tg96_threads4_batch512_ubatch512_repetitions5"
  echo "pure_cpu=Vulkan_hidden_n_gpu_layers_0_no_op_offload_1"
  echo "mixed_host_op=Vulkan_visible_n_gpu_layers_0_default_host_op_offload"
  echo "full_vulkan=Vulkan_visible_n_gpu_layers_99_default_host_op_offload"
} > "${OUT}/environment.txt"

for entry in "${models[@]}"; do
  IFS='|' read -r label model <<< "${entry}"
  if [[ "${label}" == "qwen3-0.6b" ]]; then
    modes=(pure-cpu mixed-host-op full-vulkan)
  else
    modes=(full-vulkan mixed-host-op pure-cpu)
  fi
  for mode in "${modes[@]}"; do
    run_one "${label}" "${model}" "${mode}"
  done
done

printf 'complete\n' > "${OUT}/status.txt"
echo "complete: ${OUT}"
