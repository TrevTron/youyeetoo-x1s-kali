#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="${1:-$HOME/llama.cpp}"
OUTPUT_DIR="${2:-$HOME/x1s-lab/logs/retest-$(date +%F)/build-native}"
BUILD_DIR="${BUILD_DIR:-$SOURCE_DIR/build-native}"
EXPECTED_COMMIT="${EXPECTED_COMMIT:-9a286ac98d2cab74231bd3f1fc3f2b8bdf05422e}"
MAX_TEMP_C="${MAX_TEMP_C:-85}"
TIME_LIMIT="${TIME_LIMIT:-30m}"
BUILD_JOBS="${BUILD_JOBS:-4}"
MIN_FREE_KIB="${MIN_FREE_KIB:-4194304}"

mkdir -p "$OUTPUT_DIR"
TELEMETRY="$OUTPUT_DIR/telemetry.csv"
EVENTS="$OUTPUT_DIR/events.log"
STATUS="$OUTPUT_DIR/status.txt"
STOP_FILE="$OUTPUT_DIR/.stop"
rm -f "$STOP_FILE"

pkg_temp_c() {
  local zone type temp
  for zone in /sys/class/thermal/thermal_zone*; do
    [[ -r "$zone/type" && -r "$zone/temp" ]] || continue
    type="$(<"$zone/type")"
    [[ "$type" == "x86_pkg_temp" ]] || continue
    temp="$(<"$zone/temp")"
    awk -v value="$temp" 'BEGIN {printf "%.1f", value / 1000}'
    return 0
  done
  return 1
}

stop_build() {
  local reason="$1"
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$reason" | tee -a "$EVENTS"
  touch "$STOP_FILE"
  if [[ -n "${BUILD_PID:-}" ]]; then
    kill -TERM -- "-$BUILD_PID" 2>/dev/null || true
  fi
}

sampler() {
  printf '%s\n' 'timestamp,package_temp_c' > "$TELEMETRY"
  while [[ ! -e "$STOP_FILE" ]]; do
    local temp
    temp="$(pkg_temp_c || true)"
    printf '%s,%s\n' "$(date --iso-8601=seconds)" "$temp" >> "$TELEMETRY"
    if [[ -n "$temp" ]] && awk -v value="$temp" -v limit="$MAX_TEMP_C" 'BEGIN {exit !(value >= limit)}'; then
      stop_build "THERMAL_ABORT package_temp_c=$temp threshold_c=$MAX_TEMP_C"
      return
    fi
    sleep 2
  done
}

cleanup() {
  touch "$STOP_FILE"
  [[ -n "${SAMPLER_PID:-}" ]] && kill "$SAMPLER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

[[ -d "$SOURCE_DIR/.git" ]] || { echo "Missing llama.cpp source tree: $SOURCE_DIR" >&2; exit 66; }
actual_commit="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
[[ "$actual_commit" == "$EXPECTED_COMMIT" ]] || {
  echo "Commit mismatch: expected $EXPECTED_COMMIT, found $actual_commit" >&2
  exit 65
}

free_kib="$(df -Pk "$SOURCE_DIR" | awk 'NR == 2 {print $4}')"
[[ "$free_kib" =~ ^[0-9]+$ ]] || { echo "Could not determine free disk space" >&2; exit 74; }
(( free_kib >= MIN_FREE_KIB )) || {
  echo "Free disk space is below the ${MIN_FREE_KIB} KiB guard" >&2
  exit 75
}

{
  printf 'started=%s\n' "$(date --iso-8601=seconds)"
  printf 'source_dir=%s\nbuild_dir=%s\ncommit=%s\n' "$SOURCE_DIR" "$BUILD_DIR" "$actual_commit"
  printf 'max_temp_c=%s\ntime_limit=%s\nbuild_jobs=%s\nfree_kib_before=%s\n' "$MAX_TEMP_C" "$TIME_LIMIT" "$BUILD_JOBS" "$free_kib"
  printf '%s\n' 'cmake_options=-DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON -DGGML_VULKAN=ON -DLLAMA_CURL=OFF'
  uname -a
  cmake --version | sed -n '1p'
  cc --version | sed -n '1p'
} > "$OUTPUT_DIR/environment.txt"

sampler &
SAMPLER_PID=$!

set +e
setsid timeout "$TIME_LIMIT" bash -c '
  set -Eeuo pipefail
  cmake -S "$1" -B "$2" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_NATIVE=ON \
    -DGGML_VULKAN=ON \
    -DLLAMA_CURL=OFF
  cmake --build "$2" --config Release -j"$3" \
    --target llama-cli llama-bench llama-server
' _ "$SOURCE_DIR" "$BUILD_DIR" "$BUILD_JOBS" > "$OUTPUT_DIR/build.log" 2>&1 &
BUILD_PID=$!
wait "$BUILD_PID"
BUILD_RC=$?
set -e

touch "$STOP_FILE"
wait "$SAMPLER_PID" 2>/dev/null || true

if grep -q 'THERMAL_ABORT' "$EVENTS" 2>/dev/null; then
  printf 'status=thermal-abort\nexit_code=%s\n' "$BUILD_RC" > "$STATUS"
  exit 70
fi
if [[ "$BUILD_RC" -eq 124 ]]; then
  printf 'status=time-limit\nexit_code=124\n' > "$STATUS"
  exit 124
fi
if [[ "$BUILD_RC" -ne 0 ]]; then
  printf 'status=build-failure\nexit_code=%s\n' "$BUILD_RC" > "$STATUS"
  exit "$BUILD_RC"
fi

for binary in llama-cli llama-bench llama-server; do
  [[ -x "$BUILD_DIR/bin/$binary" ]] || {
    printf 'status=missing-binary\nbinary=%s\n' "$binary" > "$STATUS"
    exit 69
  }
done

{
  grep -E '^(CMAKE_BUILD_TYPE|GGML_NATIVE|GGML_SSE42|GGML_AVX|GGML_AVX2|GGML_FMA|GGML_F16C|GGML_BMI2|GGML_VULKAN):' "$BUILD_DIR/CMakeCache.txt" | sort
  grep -R -h -E '^(C_FLAGS|CXX_FLAGS) = ' "$BUILD_DIR/ggml"/*/CMakeFiles/ggml-cpu.dir/flags.make 2>/dev/null | sort -u
  "$BUILD_DIR/bin/llama-cli" --version 2>&1 | sed -n '1,4p'
  stat -c '%n %y %s' "$BUILD_DIR/bin/llama-cli" "$BUILD_DIR/bin/llama-bench" "$BUILD_DIR/bin/llama-server"
} > "$OUTPUT_DIR/build-evidence.txt"

peak="$(awk -F, 'NR > 1 && $2 != "" {if ($2 > max) max=$2} END {print max}' "$TELEMETRY")"
printf 'status=clean\nexit_code=0\npeak_package_c=%s\nfinished=%s\n' "$peak" "$(date --iso-8601=seconds)" > "$STATUS"
echo "Native llama.cpp build completed: $BUILD_DIR"
