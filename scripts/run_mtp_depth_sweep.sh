#!/usr/bin/env bash
set -Eeuo pipefail

RUNNER="${HOME}/x1s-lab/scripts/benchmark_ollama_mtp_guarded.sh"
LOG_ROOT="${HOME}/x1s-lab/logs/retest-2026-08-24"
STAMP="$(date +%F-%H%M%S)"
CONTROLLER_LOG="${LOG_ROOT}/mtp-depth-sweep-${STAMP}.log"

[[ -x "${RUNNER}" ]] || { echo "Runner is not executable: ${RUNNER}" >&2; exit 69; }

exec > >(tee -a "${CONTROLLER_LOG}") 2>&1
echo "started=$(date --iso-8601=seconds)"

for depth in 1 2 3; do
  for case_id in qwen35-0.8b qwen35-2b gemma4-e2b; do
    echo "starting depth=${depth} case=${case_id} utc=$(date -u +%FT%TZ)"
    DRAFT_N="${depth}" CASE_FILTER="${case_id}" PROMPT_LIMIT=1 \
      bash "${RUNNER}"
  done
done

for case_id in qwen35-0.8b qwen35-2b gemma4-e2b; do
  echo "starting depth=4 case=${case_id} utc=$(date -u +%FT%TZ)"
  DRAFT_N=4 CASE_FILTER="${case_id}" PROMPT_LIMIT=5 \
    bash "${RUNNER}"
done

echo "complete=$(date --iso-8601=seconds)"
