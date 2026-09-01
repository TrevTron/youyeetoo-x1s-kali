#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${HOME}/x1s-lab"
REVISION="2d874ef7d29f9a30599a1e4b3c1cbc9595f005df"
ASSISTANT="${ASSISTANT:-${ROOT}/models/gemma-4-E2B-it-assistant-${REVISION}-F16.gguf}"
EXPECTED_SHA256="0641fbd619ff0f53f17ceb25694c2c0cd307d4d3e390e77378b1a9e175f5bb7c"
TAG="gemma4:e2b-mtp-x1s"
LOG_DIR="${ROOT}/logs/retest-2026-08-24/gemma4-e2b-mtp-register"

mkdir -p "${LOG_DIR}"
exec > >(tee -a "${LOG_DIR}/register.log") 2>&1

[[ -f "${ASSISTANT}" ]] || { echo "missing ${ASSISTANT}"; exit 2; }
printf '%s  %s\n' "${EXPECTED_SHA256}" "${ASSISTANT}" | sha256sum --check
ollama show gemma4:e2b >/dev/null

{
  echo 'FROM gemma4:e2b'
  echo "DRAFT ${ASSISTANT}"
  echo 'PARAMETER draft_num_predict 4'
} > "${LOG_DIR}/Modelfile"

timeout --signal=TERM --kill-after=15 900 \
  ollama create "${TAG}" --file "${LOG_DIR}/Modelfile"

ollama show --modelfile "${TAG}" > "${LOG_DIR}/ollama-modelfile.txt"
ollama show --verbose "${TAG}" > "${LOG_DIR}/ollama-show-verbose.txt"

grep -q '^DRAFT ' "${LOG_DIR}/ollama-modelfile.txt" \
  || { echo "registered model does not retain a DRAFT artifact"; exit 3; }
grep -Eq '^PARAMETER[[:space:]]+draft_num_predict[[:space:]]+4$' \
  "${LOG_DIR}/ollama-modelfile.txt" \
  || { echo "registered model does not retain draft_num_predict=4"; exit 3; }

printf 'complete\n' > "${LOG_DIR}/status.txt"
echo "complete: ${TAG}"
