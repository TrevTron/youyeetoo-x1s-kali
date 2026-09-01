#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${HOME}/x1s-lab"
STAMP="$(date +%F-%H%M%S)"
DRAFT_N="${DRAFT_N:-4}"
OUT="${ROOT}/logs/retest-2026-08-24/ollama-mtp-d${DRAFT_N}-${STAMP}"
THERMAL_LIMIT_MC="${THERMAL_LIMIT_MC:-85000}"
TIMEOUT_SECONDS=600
OLLAMA_API="http://127.0.0.1:11434/api/generate"
CASE_FILTER="${CASE_FILTER:-all}"
PROMPT_LIMIT="${PROMPT_LIMIT:-5}"

mkdir -p "${OUT}"
exec > >(tee -a "${OUT}/controller.log") 2>&1

prompts=(
  'Armadillo7Z. Continue a numbered field log from item 1 through at least item 80. Make each item one short plain sentence about testing a small computer. Begin with item 1 and do not summarize.'
  'Kestrel9Q. Continue a numbered field log from item 1 through at least item 80. Make each item one short plain sentence about testing a small computer. Begin with item 1 and do not summarize.'
  'Nimbus4V. Continue a numbered field log from item 1 through at least item 80. Make each item one short plain sentence about testing a small computer. Begin with item 1 and do not summarize.'
  'Copper8X. Continue a numbered field log from item 1 through at least item 80. Make each item one short plain sentence about testing a small computer. Begin with item 1 and do not summarize.'
  'Juniper6W. Continue a numbered field log from item 1 through at least item 80. Make each item one short plain sentence about testing a small computer. Begin with item 1 and do not summarize.'
)

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

write_payload() {
  local tag="$1" draft_n="$2" prompt="$3" num_predict="$4" dest="$5"
  jq -n \
    --arg model "${tag}" \
    --arg prompt "${prompt}" \
    --argjson draft_n "${draft_n}" \
    --argjson num_predict "${num_predict}" \
    '{
      model: $model,
      prompt: $prompt,
      stream: false,
      think: false,
      keep_alive: 0,
      options: {
        num_ctx: 4096,
        num_batch: 512,
        num_gpu: 0,
        num_thread: 4,
        draft_num_predict: $draft_n,
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

guarded_request() {
  local run_id="$1" payload="$2"
  local response="${OUT}/${run_id}.json"
  local curl_err="${OUT}/${run_id}.curl.log"
  local wall="${OUT}/${run_id}.wall-seconds.txt"
  local telemetry="${OUT}/${run_id}.telemetry.csv"
  local kernel="${OUT}/${run_id}.kernel.log"
  local model_tag started killed=0 current rc serious=0

  model_tag="$(jq -r '.model' "${payload}")"
  wait_for_baseline
  started="$(date --iso-8601=seconds)"
  printf 'utc,temp_mc,avg_cpu_freq_khz,mem_available_kb,load1\n' > "${telemetry}"
  timeout --signal=TERM --kill-after=15 "${TIMEOUT_SECONDS}" \
    curl --silent --show-error --fail-with-body \
      --header 'Content-Type: application/json' \
      --data-binary "@${payload}" \
      --output "${response}" \
      --write-out '%{time_total}\n' \
      "${OLLAMA_API}" \
      > "${wall}" 2> "${curl_err}" &
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
      ollama stop "${model_tag}" >/dev/null 2>&1 || true
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
  printf '%s,%s,%s,%s,%s\n' \
    "$(date -u +%FT%TZ)" "${run_id}" "${rc}" "${killed}" "${serious}" \
    >> "${OUT}/status.csv"

  if (( killed != 0 || rc != 0 || serious != 0 )); then
    ollama stop "${model_tag}" >/dev/null 2>&1 || true
    echo "request_failed,run=${run_id},rc=${rc},thermal_abort=${killed},kernel_error=${serious}"
    return 1
  fi
  jq -e '.done == true and (.error == null)' "${response}" >/dev/null
}

run_variant() {
  local case_id="$1" variant="$2" tag="$3" draft_n="$4"
  local started payload response run_id generated_content_hash peak

  ollama stop "${tag}" >/dev/null 2>&1 || true
  started="$(date --iso-8601=seconds)"

  payload="${OUT}/${case_id}-${variant}-warmup.payload.json"
  write_payload "${tag}" "${draft_n}" \
    'Walrus0M. Write a numbered list of at least twenty short observations about a small computer test.' \
    16 "${payload}"
  guarded_request "${case_id}-${variant}-warmup" "${payload}"

  for index in "${!prompts[@]}"; do
    (( index < PROMPT_LIMIT )) || break
    run_id="${case_id}-${variant}-run$((index + 1))"
    payload="${OUT}/${run_id}.payload.json"
    write_payload "${tag}" "${draft_n}" "${prompts[$index]}" 96 "${payload}"
    guarded_request "${run_id}" "${payload}"
    response="${OUT}/${run_id}.json"
    generated_content_hash="$(jq -c '[.thinking // "", .response // ""]' "${response}" | sha256sum | awk '{print $1}')"
    peak="$(awk -F, 'NR>1 && $2+0>m {m=$2} END {print m+0}' "${OUT}/${run_id}.telemetry.csv")"
    jq -r \
      --arg case_id "${case_id}" \
      --arg variant "${variant}" \
      --arg tag "${tag}" \
      --argjson draft_n "${draft_n}" \
      --argjson run "$((index + 1))" \
      --arg generated_content_sha256 "${generated_content_hash}" \
      --argjson wall_seconds "$(cat "${OUT}/${run_id}.wall-seconds.txt")" \
      --argjson peak_temp_mc "${peak}" \
      '[
        $case_id, $variant, $tag, $draft_n, $run,
        .prompt_eval_count,
        .eval_count,
        (if .prompt_eval_duration > 0 then (.prompt_eval_count / (.prompt_eval_duration / 1000000000)) else null end),
        (if .eval_duration > 0 then (.eval_count / (.eval_duration / 1000000000)) else null end),
        .load_duration,
        .total_duration,
        .done_reason,
        $wall_seconds,
        $peak_temp_mc,
        (.thinking // "" | length),
        (.response // "" | length),
        $generated_content_sha256
      ] | @csv' "${response}" >> "${OUT}/results.csv"
  done

  ollama stop "${tag}" >/dev/null 2>&1 || true
  local journal="${OUT}/${case_id}-${variant}-ollama-journal.log"
  journalctl -u ollama --since "${started}" --no-pager > "${journal}"

  if (( draft_n > 0 )); then
    grep -F -- '--spec-type draft-mtp' "${journal}" \
      > "${OUT}/${case_id}-${variant}-mtp-command-proof.txt" \
      || { echo "MTP command proof missing for ${case_id}-${variant}"; return 1; }
    grep -E 'draft acceptance = .*[0-9]+ accepted / +[1-9][0-9]* generated' "${journal}" \
      > "${OUT}/${case_id}-${variant}-mtp-acceptance-proof.txt" \
      || { echo "MTP generated-draft proof missing for ${case_id}-${variant}"; return 1; }
  elif grep -Fq -- '--spec-type draft-mtp' "${journal}"; then
    echo "MTP unexpectedly active in off variant ${case_id}-${variant}"
    return 1
  fi
}

printf '%s\n' \
  'case_id,variant,tag,draft_num_predict,run,prompt_tokens,generated_tokens,prompt_tps,generation_tps,load_duration_ns,total_duration_ns,done_reason,wall_seconds,peak_temp_mc,thinking_chars,response_chars,generated_content_sha256' \
  > "${OUT}/results.csv"
printf 'utc,run_id,exit_code,thermal_abort,kernel_error\n' > "${OUT}/status.csv"

[[ "${PROMPT_LIMIT}" =~ ^[1-5]$ ]] \
  || { echo "PROMPT_LIMIT must be an integer from 1 through 5"; exit 2; }
[[ "${DRAFT_N}" =~ ^[1-4]$ ]] \
  || { echo "DRAFT_N must be an integer from 1 through 4"; exit 2; }
[[ "${THERMAL_LIMIT_MC}" =~ ^[0-9]+$ ]] \
  || { echo "THERMAL_LIMIT_MC must be an integer"; exit 2; }
(( THERMAL_LIMIT_MC >= 85000 && THERMAL_LIMIT_MC <= 90000 )) \
  || { echo "THERMAL_LIMIT_MC must be from 85000 through 90000"; exit 2; }
case "${CASE_FILTER}" in
  all|qwen35-0.8b|qwen35-2b|qwen35-9b|gemma4-e2b) ;;
  *) echo "unknown CASE_FILTER: ${CASE_FILTER}"; exit 2 ;;
esac

journalctl -k -n 1 --no-pager >/dev/null 2>&1 \
  || { echo "kernel journal is unreadable"; exit 2; }

{
  echo "utc=$(date -u +%FT%TZ)"
  echo "ollama=$(ollama --version 2>&1)"
  echo "kernel=$(uname -r)"
  echo "cpu=$(lscpu | awk -F: '/Model name/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}')"
  echo "case_filter=${CASE_FILTER}"
  echo "prompt_limit=${PROMPT_LIMIT}"
  echo "draft_n=${DRAFT_N}"
  echo "thermal_limit_mc=${THERMAL_LIMIT_MC}"
  ollama list
} > "${OUT}/environment.txt"

for tag in qwen3.5:0.8b qwen3.5:2b qwen3.5:9b gemma4:e2b gemma4:e2b-mtp-x1s; do
  if ollama show "${tag}" >/dev/null 2>&1; then
    safe_tag="${tag//[:\/]/_}"
    ollama show --modelfile "${tag}" > "${OUT}/${safe_tag}-modelfile.txt"
    ollama show --verbose "${tag}" > "${OUT}/${safe_tag}-show-verbose.txt"
  fi
done

if [[ "${CASE_FILTER}" == "all" || "${CASE_FILTER}" == "qwen35-0.8b" ]]; then
  run_variant qwen35-0.8b off qwen3.5:0.8b 0
  run_variant qwen35-0.8b on qwen3.5:0.8b "${DRAFT_N}"
fi

if [[ "${CASE_FILTER}" == "all" || "${CASE_FILTER}" == "qwen35-2b" ]]; then
  run_variant qwen35-2b on qwen3.5:2b "${DRAFT_N}"
  run_variant qwen35-2b off qwen3.5:2b 0
fi

if [[ "${CASE_FILTER}" == "all" || "${CASE_FILTER}" == "qwen35-9b" ]]; then
  if ollama show qwen3.5:9b >/dev/null 2>&1; then
    run_variant qwen35-9b off qwen3.5:9b 0
  else
    echo "qwen3.5:9b is not installed; 9B phase not run" \
      | tee "${OUT}/qwen35-9b-not-run.txt"
  fi
fi

if [[ "${CASE_FILTER}" == "all" || "${CASE_FILTER}" == "gemma4-e2b" ]]; then
  if ollama show gemma4:e2b-mtp-x1s >/dev/null 2>&1; then
    run_variant gemma4-e2b off gemma4:e2b 0
    run_variant gemma4-e2b on gemma4:e2b-mtp-x1s "${DRAFT_N}"
  else
    echo "gemma4:e2b-mtp-x1s is not prepared; Gemma MTP phase not run" \
      | tee "${OUT}/gemma-mtp-not-run.txt"
  fi
fi

awk -F, '
  BEGIN {
    print "case_id,run,generated_tokens_match,generated_content_hash_match,off_generated_tokens,on_generated_tokens,off_generated_content_sha256,on_generated_content_sha256"
  }
  NR > 1 {
    for (i = 1; i <= NF; i++) {
      gsub(/^"|"$/, "", $i)
    }
    key = $1 "|" $5
    if ($2 == "off") {
      off_tokens[key] = $7
      off_hash[key] = $17
    } else if ($2 == "on") {
      on_tokens[key] = $7
      on_hash[key] = $17
    }
  }
  END {
    failed = 0
    for (key in off_hash) {
      if (!(key in on_hash)) {
        continue
      }
      split(key, parts, "|")
      tokens_match = off_tokens[key] == on_tokens[key] ? 1 : 0
      hash_match = off_hash[key] == on_hash[key] ? 1 : 0
      print parts[1] "," parts[2] "," tokens_match "," hash_match "," off_tokens[key] "," on_tokens[key] "," off_hash[key] "," on_hash[key]
      if (!tokens_match || !hash_match) {
        failed = 1
      }
    }
    exit failed
  }
' "${OUT}/results.csv" > "${OUT}/output-parity.csv" \
  || { echo "MTP off/on output parity failed"; exit 1; }

journalctl -k --since "$(date -u -d '3 hours ago' '+%F %T')" --no-pager \
  | grep -Eai 'i915|drm|gpu|hang|reset|oom|out of memory' \
  > "${OUT}/kernel-relevant.log" || true

printf 'complete\n' > "${OUT}/status.txt"
echo "complete: ${OUT}"
