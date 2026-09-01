#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${HOME}/x1s-lab"
SOURCE="${HOME}/llama.cpp"
REVISION="2d874ef7d29f9a30599a1e4b3c1cbc9595f005df"
MODEL_DIR="${ROOT}/models/google-gemma-4-E2B-it-assistant-${REVISION}"
OUT_GGUF="${ROOT}/models/gemma-4-E2B-it-assistant-${REVISION}-F16.gguf"
EXPECTED_GGUF_SHA256="0641fbd619ff0f53f17ceb25694c2c0cd307d4d3e390e77378b1a9e175f5bb7c"
VENV="${ROOT}/private/venv-llama-convert"
LOG_DIR="${ROOT}/logs/retest-2026-08-24/gemma4-e2b-mtp-prepare"
TAG="gemma4:e2b-mtp-x1s"
BASE_URL="https://huggingface.co/google/gemma-4-E2B-it-assistant/resolve/${REVISION}"

mkdir -p "${MODEL_DIR}" "${LOG_DIR}" "$(dirname "${VENV}")"
exec > >(tee -a "${LOG_DIR}/prepare.log") 2>&1

free_kb="$(df -Pk "${ROOT}" | awk 'NR==2 {print $4}')"
if (( free_kb < 3 * 1024 * 1024 )); then
  echo "refusing: less than 3 GiB free"
  exit 2
fi

download() {
  local file="$1"
  curl --fail --location --retry 5 --retry-delay 5 --continue-at - \
    --output "${MODEL_DIR}/${file}" "${BASE_URL}/${file}"
}

for file in \
  config.json \
  generation_config.json \
  model.safetensors \
  tokenizer.json \
  tokenizer_config.json; do
  download "${file}"
done

printf '%s  %s\n' \
  '93682eb1c97639d18f007704dc880bd74cbe530adaf7b1bb561213863fdad2a6' \
  "${MODEL_DIR}/model.safetensors" \
  | sha256sum --check
printf '%s  %s\n' \
  '75a6583c1a418e2bbd79c60d95d28e0f5bf549ad3f2990b5bdb5238c6c2bf70c' \
  "${MODEL_DIR}/tokenizer.json" \
  | sha256sum --check

if [[ ! -x "${VENV}/bin/python" ]]; then
  python3 -m venv "${VENV}"
fi
"${VENV}/bin/python" -m pip install --upgrade pip
"${VENV}/bin/python" -m pip install \
  --requirement "${SOURCE}/requirements/requirements-convert_hf_to_gguf.txt"

"${VENV}/bin/python" "${SOURCE}/convert_hf_to_gguf.py" \
  "${MODEL_DIR}" \
  --outfile "${OUT_GGUF}" \
  --outtype f16

printf '%s  %s\n' "${EXPECTED_GGUF_SHA256}" "${OUT_GGUF}" \
  | sha256sum --check
sha256sum "${OUT_GGUF}" > "${LOG_DIR}/assistant-gguf.sha256"

printf '%s\n' \
  'FROM gemma4:e2b' \
  "DRAFT ${OUT_GGUF}" \
  'PARAMETER draft_num_predict 4' \
  > "${LOG_DIR}/Modelfile"

timeout --signal=TERM --kill-after=15 900 \
  ollama create "${TAG}" --file "${LOG_DIR}/Modelfile"

ollama show --modelfile "${TAG}" > "${LOG_DIR}/ollama-modelfile.txt"
ollama show --verbose "${TAG}" > "${LOG_DIR}/ollama-show-verbose.txt"
printf 'complete\n' > "${LOG_DIR}/status.txt"
echo "complete: ${TAG}"
