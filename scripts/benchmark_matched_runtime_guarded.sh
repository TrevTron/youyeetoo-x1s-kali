#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${HOME}/x1s-lab"
LLAMA_SERVER="${HOME}/llama.cpp/build-native/bin/llama-server"
OLLAMA_API="http://127.0.0.1:11434/api/generate"
SERVER_API="http://127.0.0.1:18080/completion"
SERVER_HEALTH="http://127.0.0.1:18080/health"
STAMP="$(date +%F-%H%M%S)"
BATCH_SIZE="${BATCH_SIZE:-512}"
REPETITIONS="${REPETITIONS:-3}"
MODEL_FILTER="${MODEL_FILTER:-}"
THERMAL_LIMIT_MC=85000
TIMEOUT_SECONDS=600
PROMPT='Armadillo7Z. Continue a numbered field log from item 1 through at least item 80. Make each item one short plain sentence about testing CPU-only local language-model inference. Mention quantization, tokens per second, memory, and temperature in different items. Begin with item 1, do not summarize, and do not stop early.'
OUT="${ROOT}/logs/retest-2026-08-24/matched-runtime-b${BATCH_SIZE}-${STAMP}"
SERVER_PID=""

models=(
  "qwen3-0.6b|qwen3:0.6b|${ROOT}/gguf/qwen3-0.6b.gguf"
  "qwen3-1.7b|qwen3:1.7b|${ROOT}/gguf/qwen3-1.7b.gguf"
  "qwen3-4b-instruct|qwen3:4b-instruct|${ROOT}/gguf/qwen3-4b-instruct.gguf"
  "phi4-mini|phi4-mini:latest|${ROOT}/gguf/phi4-mini-latest.gguf"
)

mkdir -p "${OUT}"
exec > >(tee -a "${OUT}/controller.log") 2>&1

stop_server() {
  if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill -TERM "${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
  SERVER_PID=""
}
trap stop_server EXIT

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
      printf '%s\n' "baseline_ok,temp_mc=${current},attempt=${attempt}" \
        | tee -a "${OUT}/thermal-events.csv"
      return 0
    fi
    sleep 2
  done
  printf '%s\n' "baseline_timeout,temp_mc=$(max_temp_mc)" \
    | tee -a "${OUT}/thermal-events.csv"
  return 1
}

avg_cpu_freq_khz() {
  awk '{sum+=$1; n++} END {if (n) printf "%.0f", sum/n; else print 0}' \
    /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null
}

write_ollama_payload() {
  local tag="$1" prompt="$2" predict="$3" dest="$4"
  jq -n \
    --arg model "${tag}" \
    --arg prompt "${prompt}" \
    --argjson num_predict "${predict}" \
    --argjson batch "${BATCH_SIZE}" \
    '{
      model: $model,
      prompt: $prompt,
      raw: true,
      stream: false,
      keep_alive: 0,
      options: {
        num_ctx: 4096,
        num_batch: $batch,
        num_gpu: 0,
        num_thread: 4,
        use_mmap: true,
        num_predict: $num_predict,
        seed: 42,
        temperature: 0,
        top_k: 1,
        top_p: 1,
        min_p: 0,
        repeat_last_n: 0,
        repeat_penalty: 1
      }
    }' > "${dest}"
}

write_llama_payload() {
  local prompt="$1" predict="$2" dest="$3"
  jq -n \
    --arg prompt "${prompt}" \
    --argjson n_predict "${predict}" \
    '{
      prompt: $prompt,
      n_predict: $n_predict,
      stream: false,
      cache_prompt: false,
      seed: 42,
      temperature: 0,
      top_k: 1,
      top_p: 1,
      min_p: 0,
      repeat_last_n: 0,
      repeat_penalty: 1
    }' > "${dest}"
}

guarded_request() {
  local runtime="$1" tag="$2" run_id="$3" url="$4" payload="$5"
  local response="${OUT}/${run_id}.json"
  local curl_err="${OUT}/${run_id}.curl.log"
  local wall="${OUT}/${run_id}.wall-seconds.txt"
  local telemetry="${OUT}/${run_id}.telemetry.csv"
  local kernel="${OUT}/${run_id}.kernel.log"
  local started current killed=0 rc serious=0

  wait_for_baseline
  started="$(date --iso-8601=seconds)"
  printf 'utc,temp_mc,avg_cpu_freq_khz,mem_available_kb,load1\n' > "${telemetry}"

  timeout --signal=TERM --kill-after=15 "${TIMEOUT_SECONDS}" \
    curl --silent --show-error --fail-with-body \
      --header 'Content-Type: application/json' \
      --data-binary "@${payload}" \
      --output "${response}" \
      --write-out '%{time_total}\n' \
      "${url}" \
      > "${wall}" 2> "${curl_err}" &
  local job_pid=$!

  while kill -0 "${job_pid}" 2>/dev/null; do
    current="$(max_temp_mc)"
    printf '%s,%s,%s,%s,%s\n' \
      "$(date -u +%FT%TZ)" \
      "${current}" \
      "$(avg_cpu_freq_khz)" \
      "$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)" \
      "$(awk '{print $1}' /proc/loadavg)" >> "${telemetry}"
    if (( current >= THERMAL_LIMIT_MC )); then
      printf '%s\n' "thermal_abort,run=${run_id},temp_mc=${current}" \
        | tee -a "${OUT}/thermal-events.csv"
      killed=1
      kill -TERM "${job_pid}" 2>/dev/null || true
      if [[ "${runtime}" == "ollama" ]]; then
        ollama stop "${tag}" >/dev/null 2>&1 || true
      else
        stop_server
      fi
      break
    fi
    sleep 2
  done

  set +e
  wait "${job_pid}"
  rc=$?
  set -e

  journalctl -k --since "${started}" --no-pager > "${kernel}"
  if [[ "${runtime}" == "ollama" ]]; then
    journalctl -u ollama --since "${started}" --no-pager \
      > "${OUT}/${run_id}.ollama-journal.log"
  fi
  if grep -Eaiq \
    'GPU HANG|reset timeout|fence.*timeout|preempt.*timeout|i915.*(error|hang|reset)|drm.*(error|hang|reset)|DeviceLost|oom-kill|out of memory|segfault|machine check|hardware error' \
    "${kernel}"; then
    serious=1
  fi

  printf '%s,%s,%s,%s,%s,%s\n' \
    "$(date -u +%FT%TZ)" "${run_id}" "${runtime}" "${rc}" "${killed}" "${serious}" \
    >> "${OUT}/status.csv"

  if (( killed != 0 || rc != 0 || serious != 0 )); then
    printf '%s\n' \
      "request_failed,run=${run_id},rc=${rc},thermal_abort=${killed},kernel_error=${serious}" \
      | tee -a "${OUT}/failures.log"
    return 1
  fi
}

start_server() {
  local label="$1" model="$2"
  local log="${OUT}/${label}-llama-server.log"
  local current attempt

  stop_server
  wait_for_baseline
  env GGML_VK_VISIBLE_DEVICES= "${LLAMA_SERVER}" \
    --model "${model}" \
    --host 127.0.0.1 \
    --port 18080 \
    --ctx-size 4096 \
    --batch-size "${BATCH_SIZE}" \
    --ubatch-size "${BATCH_SIZE}" \
    --threads 4 \
    --n-gpu-layers 0 \
    --no-op-offload \
    --cache-ram 0 \
    --no-webui \
    > "${log}" 2>&1 &
  SERVER_PID=$!

  for attempt in $(seq 1 180); do
    kill -0 "${SERVER_PID}" 2>/dev/null \
      || { echo "llama-server exited during load for ${label}"; return 1; }
    current="$(max_temp_mc)"
    if (( current >= THERMAL_LIMIT_MC )); then
      echo "thermal_abort,run=${label}-server-load,temp_mc=${current}"
      stop_server
      return 1
    fi
    if curl --silent --fail "${SERVER_HEALTH}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "llama-server health timeout for ${label}"
  stop_server
  return 1
}

record_ollama_result() {
  local label="$1" run="$2" run_id="$3"
  local response="${OUT}/${run_id}.json"
  local response_hash peak avg_freq
  jq -e '.done == true and (.error == null) and .eval_count == 96' "${response}" >/dev/null \
    || { echo "Ollama did not produce the required 96 tokens for ${run_id}"; return 1; }
  response_hash="$(jq -r '.response' "${response}" | sha256sum | awk '{print $1}')"
  peak="$(awk -F, 'NR>1 && $2+0>m {m=$2} END {print m+0}' "${OUT}/${run_id}.telemetry.csv")"
  avg_freq="$(awk -F, 'NR>1 && $3+0>0 {s+=$3; n++} END {if(n) printf "%.0f",s/n; else print 0}' "${OUT}/${run_id}.telemetry.csv")"
  jq -r \
    --arg model "${label}" \
    --argjson run "${run}" \
    --arg response_sha256 "${response_hash}" \
    --argjson wall_seconds "$(cat "${OUT}/${run_id}.wall-seconds.txt")" \
    --argjson peak_temp_mc "${peak}" \
    --argjson avg_cpu_freq_khz "${avg_freq}" \
    '[
      $model, "ollama", $run,
      .prompt_eval_count, .eval_count,
      (if .prompt_eval_duration > 0 then (.prompt_eval_count * 1000000000 / .prompt_eval_duration) else null end),
      (if .eval_duration > 0 then (.eval_count * 1000000000 / .eval_duration) else null end),
      .prompt_eval_duration, .eval_duration, .load_duration, .total_duration,
      .done_reason, $wall_seconds, $peak_temp_mc, $avg_cpu_freq_khz, $response_sha256
    ] | @csv' "${response}" >> "${OUT}/results.csv"
}

record_llama_result() {
  local label="$1" run="$2" run_id="$3"
  local response="${OUT}/${run_id}.json"
  local response_hash peak avg_freq
  jq -e '.stop == true and (.error == null) and .tokens_predicted == 96' "${response}" >/dev/null \
    || { echo "llama.cpp did not produce the required 96 tokens for ${run_id}"; return 1; }
  response_hash="$(jq -r '.content' "${response}" | sha256sum | awk '{print $1}')"
  peak="$(awk -F, 'NR>1 && $2+0>m {m=$2} END {print m+0}' "${OUT}/${run_id}.telemetry.csv")"
  avg_freq="$(awk -F, 'NR>1 && $3+0>0 {s+=$3; n++} END {if(n) printf "%.0f",s/n; else print 0}' "${OUT}/${run_id}.telemetry.csv")"
  jq -r \
    --arg model "${label}" \
    --argjson run "${run}" \
    --arg response_sha256 "${response_hash}" \
    --argjson wall_seconds "$(cat "${OUT}/${run_id}.wall-seconds.txt")" \
    --argjson peak_temp_mc "${peak}" \
    --argjson avg_cpu_freq_khz "${avg_freq}" \
    '[
      $model, "llama.cpp-native", $run,
      .tokens_evaluated, .tokens_predicted,
      .timings.prompt_per_second, .timings.predicted_per_second,
      (.timings.prompt_ms * 1000000), (.timings.predicted_ms * 1000000), null, null,
      .stop_type, $wall_seconds, $peak_temp_mc, $avg_cpu_freq_khz, $response_sha256
    ] | @csv' "${response}" >> "${OUT}/results.csv"
}

run_ollama() {
  local label="$1" tag="$2"
  local payload run_id run

  payload="${OUT}/${label}-ollama-warmup.payload.json"
  write_ollama_payload "${tag}" 'Warm the model with one short sentence about a computer test.' 16 "${payload}"
  guarded_request ollama "${tag}" "${label}-ollama-warmup" "${OLLAMA_API}" "${payload}"

  for run in $(seq 1 "${REPETITIONS}"); do
    run_id="${label}-ollama-run${run}"
    payload="${OUT}/${run_id}.payload.json"
    write_ollama_payload "${tag}" "${PROMPT}" 96 "${payload}"
    guarded_request ollama "${tag}" "${run_id}" "${OLLAMA_API}" "${payload}"
    record_ollama_result "${label}" "${run}" "${run_id}"
  done
}

run_llama() {
  local label="$1" model="$2"
  local payload run_id run

  start_server "${label}" "${model}"
  payload="${OUT}/${label}-llama-warmup.payload.json"
  write_llama_payload 'Warm the model with one short sentence about a computer test.' 16 "${payload}"
  guarded_request llama.cpp "" "${label}-llama-warmup" "${SERVER_API}" "${payload}"

  for run in $(seq 1 "${REPETITIONS}"); do
    run_id="${label}-llama-run${run}"
    payload="${OUT}/${run_id}.payload.json"
    write_llama_payload "${PROMPT}" 96 "${payload}"
    guarded_request llama.cpp "" "${run_id}" "${SERVER_API}" "${payload}"
    record_llama_result "${label}" "${run}" "${run_id}"
  done
  stop_server
}

verify_exact_artifact() {
  local label="$1" tag="$2" model="$3"
  local modelfile="${OUT}/${label}-ollama-modelfile.txt"
  local blob model_hash blob_hash verification_method

  ollama show --modelfile "${tag}" > "${modelfile}"
  blob="$(sed -n 's/^FROM[[:space:]]\+//p' "${modelfile}" | head -n 1)"
  blob="${blob%\"}"
  blob="${blob#\"}"
  model_hash="$(sha256sum "${model}" | awk '{print $1}')"
  if [[ -r "${blob}" ]]; then
    blob_hash="$(sha256sum "${blob}" | awk '{print $1}')"
    verification_method="readable_blob_sha256"
  elif [[ "$(basename "${blob}")" =~ ^sha256-([0-9a-f]{64})$ ]]; then
    # Ollama stores verified layers under their content digest. The service-owned
    # blob directory is intentionally not traversable by the benchmark account.
    blob_hash="${BASH_REMATCH[1]}"
    verification_method="ollama_content_address"
  else
    echo "cannot verify Ollama blob identity for ${tag}: ${blob}"
    return 1
  fi
  printf '%s,%s,%s,%s,%s,%s,%s\n' \
    "${label}" "${tag}" "${model}" "${model_hash}" "${blob}" "${blob_hash}" "${verification_method}" \
    >> "${OUT}/artifact-map.csv"
  [[ "${model_hash}" == "${blob_hash}" ]] \
    || { echo "artifact mismatch for ${label}"; return 1; }
}

[[ -x "${LLAMA_SERVER}" ]] || { echo "missing ${LLAMA_SERVER}"; exit 2; }
curl --silent --fail http://127.0.0.1:11434/api/version >/dev/null \
  || { echo "Ollama API is unavailable"; exit 2; }
journalctl -k -n 1 --no-pager >/dev/null 2>&1 \
  || { echo "kernel journal is unreadable"; exit 2; }

printf 'utc,run_id,runtime,exit_code,thermal_abort,kernel_error\n' > "${OUT}/status.csv"
printf 'event\n' > "${OUT}/thermal-events.csv"
printf 'model,ollama_tag,gguf_path,gguf_sha256,ollama_blob_path,ollama_blob_sha256,verification_method\n' \
  > "${OUT}/artifact-map.csv"
printf '%s\n' \
  'model,runtime,run,prompt_tokens,generated_tokens,prompt_tps,generation_tps,prompt_duration_ns,generation_duration_ns,load_duration_ns,total_duration_ns,stop_reason,wall_seconds,peak_temp_mc,avg_cpu_freq_khz,response_sha256' \
  > "${OUT}/results.csv"

{
  echo "utc=$(date -u +%FT%TZ)"
  echo "kernel=$(uname -r)"
  echo "ollama=$(ollama --version 2>&1)"
  echo "llama_commit=$(git -C "${HOME}/llama.cpp" rev-parse HEAD)"
  echo "llama_server=$(sha256sum "${LLAMA_SERVER}")"
  echo "llama_cpu_backend=$(sha256sum "${HOME}/llama.cpp/build-native/bin/libggml-cpu.so")"
  echo "prompt_sha256=$(printf '%s' "${PROMPT}" | sha256sum)"
  echo "prompt=${PROMPT}"
  echo "batch_size=${BATCH_SIZE}"
  echo "repetitions=${REPETITIONS}"
  echo "model_filter=${MODEL_FILTER:-all}"
  echo "ctx_size=4096"
  echo "threads=4"
  echo "num_predict=96"
  echo "required_generated_tokens=96_or_run_fails"
  echo "sampling=seed42,temp0,top_k1,top_p1,min_p0,repeat_last_n0,repeat_penalty1"
  echo "ollama_cache_control=keep_alive_0_unload_after_every_request"
  echo "llama_cache_control=server_cache_ram_0_and_request_cache_prompt_false"
  echo "cpu_control=ollama_num_gpu_0_cpu_library_and_llama_no_op_offload_with_Vulkan_hidden"
  echo "mmap_control=enabled_in_both_runtimes"
} > "${OUT}/environment.txt"

for entry in "${models[@]}"; do
  IFS='|' read -r label tag model <<< "${entry}"
  [[ -z "${MODEL_FILTER}" || "${label}" == "${MODEL_FILTER}" ]] || continue
  verify_exact_artifact "${label}" "${tag}" "${model}"
done

for index in "${!models[@]}"; do
  IFS='|' read -r label tag model <<< "${models[$index]}"
  [[ -z "${MODEL_FILTER}" || "${label}" == "${MODEL_FILTER}" ]] || continue
  if (( index % 2 == 0 )); then
    run_ollama "${label}" "${tag}"
    run_llama "${label}" "${model}"
  else
    run_llama "${label}" "${model}"
    run_ollama "${label}" "${tag}"
  fi
done

awk -F, -v expected="${REPETITIONS}" '
  BEGIN {
    print "model,prompt_tokens_match,generated_tokens_match,cross_runtime_response_hash_match_observed,ollama_prompt_tokens,llama_prompt_tokens,ollama_generated_tokens,llama_generated_tokens,ollama_response_sha256,llama_response_sha256"
  }
  NR > 1 {
    for (i = 1; i <= NF; i++) {
      gsub(/^"|"$/, "", $i)
    }
    model = $1
    runtime = $2
    key = model SUBSEP runtime
    models[model] = 1
    count[key]++
    if (!(key in prompt_tokens)) {
      prompt_tokens[key] = $4
      generated_tokens[key] = $5
      response_hash[key] = $16
    } else if (prompt_tokens[key] != $4 || generated_tokens[key] != $5 || response_hash[key] != $16) {
      internal_mismatch[key] = 1
    }
  }
  END {
    failed = 0
    for (model in models) {
      ok = model SUBSEP "ollama"
      lk = model SUBSEP "llama.cpp-native"
      prompt_match = (prompt_tokens[ok] == prompt_tokens[lk])
      generated_match = (generated_tokens[ok] == generated_tokens[lk] && generated_tokens[ok] == 96)
      hash_match = (response_hash[ok] == response_hash[lk])
      print model "," prompt_match "," generated_match "," hash_match "," prompt_tokens[ok] "," prompt_tokens[lk] "," generated_tokens[ok] "," generated_tokens[lk] "," response_hash[ok] "," response_hash[lk]
      # Different llama.cpp revisions and CPU kernels can make different greedy
      # token choices even with the same artifact, prompt, and sampler. Record
      # cross-runtime text equality, but gate the workload on input tokens,
      # output length, repetition count, and within-runtime determinism.
      if (count[ok] != expected || count[lk] != expected || internal_mismatch[ok] || internal_mismatch[lk] || !prompt_match || !generated_match) {
        failed = 1
      }
    }
    exit failed
  }
' "${OUT}/results.csv" > "${OUT}/runtime-parity.csv" \
  || { echo "matched runtime parity check failed"; exit 1; }

journalctl -k --since "$(date -u -d '4 hours ago' '+%F %T')" --no-pager \
  | grep -Eai 'i915|drm|gpu|hang|reset|oom|out of memory|segfault|machine check|hardware error' \
  > "${OUT}/kernel-relevant.log" || true

printf 'complete\n' > "${OUT}/status.txt"
echo "complete: ${OUT}"
