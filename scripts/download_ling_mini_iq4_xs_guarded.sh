#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${HOME}/x1s-lab"
REVISION="8be84a0f472797118167aac86b56ca903561a73b"
FILE="inclusionAI_Ling-mini-2.0-IQ4_XS.gguf"
EXPECTED_BYTES=8803304640
EXPECTED_SHA256="a72d86d4cb4fedd940e34c08d008bb5cda42db80ce5c6bc5f9494e854a3d742d"
DEST="${ROOT}/models/${FILE}"
PART="${DEST}.part"
LOG_DIR="${ROOT}/logs/retest-2026-08-24/ling-mini-prepare"
URL="https://huggingface.co/bartowski/inclusionAI_Ling-mini-2.0-GGUF/resolve/${REVISION}/${FILE}"

mkdir -p "$(dirname "${DEST}")" "${LOG_DIR}"
exec > >(tee -a "${LOG_DIR}/download.log") 2>&1

free_bytes="$(df -PB1 "${ROOT}" | awk 'NR==2 {print $4}')"
required_bytes=$((EXPECTED_BYTES + 2 * 1024 * 1024 * 1024))
if (( free_bytes < required_bytes )); then
  echo "refusing: ${free_bytes} bytes free, ${required_bytes} required"
  exit 2
fi

curl --fail --location --retry 8 --retry-delay 10 --continue-at - \
  --output "${PART}" "${URL}"

actual_bytes="$(stat -c %s "${PART}")"
if (( actual_bytes != EXPECTED_BYTES )); then
  echo "size mismatch: expected ${EXPECTED_BYTES}, got ${actual_bytes}"
  exit 3
fi

printf '%s  %s\n' "${EXPECTED_SHA256}" "${PART}" | sha256sum --check
mv -- "${PART}" "${DEST}"
sha256sum "${DEST}" > "${LOG_DIR}/artifact.sha256"
printf '%s\n' \
  "repository=bartowski/inclusionAI_Ling-mini-2.0-GGUF" \
  "revision=${REVISION}" \
  "filename=${FILE}" \
  "bytes=${EXPECTED_BYTES}" \
  "sha256=${EXPECTED_SHA256}" \
  > "${LOG_DIR}/artifact.txt"
printf 'complete\n' > "${LOG_DIR}/status.txt"
echo "complete: ${DEST}"
