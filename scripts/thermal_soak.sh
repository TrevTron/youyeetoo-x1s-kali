#!/usr/bin/env bash
set -Eeuo pipefail

OUT_DIR="${1:-$HOME/x1s-lab/logs/thermal-$(date +%F-%H%M%S)}"
DURATION="${DURATION:-15m}"
WORKERS="${WORKERS:-$(nproc)}"
MAX_TEMP_C="${MAX_TEMP_C:-85}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-120}"

mkdir -p "$OUT_DIR"
METRICS="$OUT_DIR/metrics.csv"
EVENTS="$OUT_DIR/events.log"
STOP_FILE="$OUT_DIR/.stop-sampler"
STRESS_PID_FILE="$OUT_DIR/.stress-pid"

pkg_temp_c() {
  local path
  for path in /sys/class/thermal/thermal_zone*/temp; do
    if [[ -r "$path" ]] && [[ "$(cat "${path%/temp}/type" 2>/dev/null || true)" == "x86_pkg_temp" ]]; then
      awk '{printf "%.1f", $1/1000}' "$path"
      return
    fi
  done
  printf ''
}

nvme_temp_c() {
  local h
  for h in /sys/class/hwmon/hwmon*; do
    if [[ -r "$h/name" ]] && [[ "$(cat "$h/name")" == "nvme" ]] && [[ -r "$h/temp1_input" ]]; then
      awk '{printf "%.1f", $1/1000}' "$h/temp1_input"
      return
    fi
  done
  printf ''
}

cpu_use() {
  local _cpu user nice system idle iowait irq softirq steal _rest
  read -r _cpu user nice system idle iowait irq softirq steal _rest < /proc/stat
  local total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
  local idle1=$((idle + iowait))
  sleep 1
  read -r _cpu user nice system idle iowait irq softirq steal _rest < /proc/stat
  local total2=$((user + nice + system + idle + iowait + irq + softirq + steal))
  local idle2=$((idle + iowait))
  awk -v t="$((total2-total1))" -v i="$((idle2-idle1))" 'BEGIN {if (t>0) printf "%.2f", 100*(t-i)/t; else printf "0.00"}'
}

snapshot_throttle_counters() {
  local output="$1" f
  : > "$output"
  while IFS= read -r f; do
    printf '%s,%s\n' "$f" "$(cat "$f" 2>/dev/null || printf unreadable)" >> "$output"
  done < <(find /sys/devices/system/cpu -type f \
    \( -name core_throttle_count -o -name package_throttle_count \) 2>/dev/null | sort)
  [[ -s "$output" ]] || printf 'unavailable,unavailable\n' > "$output"
}

sampler() {
  printf '%s\n' 'timestamp,phase,cpu_pct,load1,avg_mhz,pkg_temp_c,nvme_temp_c,mem_available_mib' > "$METRICS"
  while [[ ! -e "$STOP_FILE" ]]; do
    local now phase cpu load mhz pkg nvme mem
    now="$(date --iso-8601=seconds)"
    phase="idle"
    [[ -s "$STRESS_PID_FILE" ]] && kill -0 "$(cat "$STRESS_PID_FILE")" 2>/dev/null && phase="stress"
    cpu="$(cpu_use)"
    load="$(awk '{print $1}' /proc/loadavg)"
    mhz="$(awk -F: '/cpu MHz/ {s+=$2; n++} END {if(n) printf "%.1f",s/n}' /proc/cpuinfo)"
    pkg="$(pkg_temp_c)"
    nvme="$(nvme_temp_c)"
    mem="$(awk '/MemAvailable:/ {printf "%.1f", $2/1024}' /proc/meminfo)"
    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' "$now" "$phase" "$cpu" "$load" "$mhz" "$pkg" "$nvme" "$mem" >> "$METRICS"

    if [[ "$phase" == "stress" && -n "$pkg" ]] && awk -v t="$pkg" -v max="$MAX_TEMP_C" 'BEGIN {exit !(t>=max)}'; then
      printf '%s THERMAL_ABORT package_temp_c=%s threshold_c=%s\n' "$now" "$pkg" "$MAX_TEMP_C" | tee -a "$EVENTS"
      touch "$OUT_DIR/THERMAL_ABORT"
      kill -TERM "$(cat "$STRESS_PID_FILE")" 2>/dev/null || true
    fi
  done
}

cleanup() {
  touch "$STOP_FILE"
  jobs -pr | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT INT TERM

{
  printf 'started=%s\n' "$(date --iso-8601=seconds)"
  printf 'hostname=%s\n' "$(hostname)"
  printf 'kernel=%s\n' "$(uname -r)"
  printf 'stress_ng=%s\n' "$(stress-ng --version)"
  printf 'duration=%s\nworkers=%s\nmax_temp_c=%s\n' "$DURATION" "$WORKERS" "$MAX_TEMP_C"
  printf 'governors=%s\n' "$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u | paste -sd, -)"
  printf 'initial_pkg_temp_c=%s\ninitial_nvme_temp_c=%s\n' "$(pkg_temp_c)" "$(nvme_temp_c)"
} > "$OUT_DIR/metadata.txt"

systemctl --failed --no-legend > "$OUT_DIR/failed-units-before.txt" || true
journalctl -k --since '10 minutes ago' --no-pager > "$OUT_DIR/kernel-before.log" || true
snapshot_throttle_counters "$OUT_DIR/throttle-before.csv"

sampler &
SAMPLER_PID=$!
sleep 2

printf '%s STRESS_START duration=%s workers=%s method=matrixprod\n' "$(date --iso-8601=seconds)" "$DURATION" "$WORKERS" | tee -a "$EVENTS"
set +e
stress-ng --cpu "$WORKERS" --cpu-method matrixprod --verify --timeout "$DURATION" --metrics-brief \
  > "$OUT_DIR/stress-ng.log" 2>&1 &
STRESS_PID=$!
printf '%s\n' "$STRESS_PID" > "$STRESS_PID_FILE"
wait "$STRESS_PID"
STRESS_RC=$?
set -e
rm -f "$STRESS_PID_FILE"
printf '%s STRESS_END rc=%s\n' "$(date --iso-8601=seconds)" "$STRESS_RC" | tee -a "$EVENTS"

cooldown_start=$(date +%s)
while (( $(date +%s) - cooldown_start < COOLDOWN_SECONDS )); do
  pkg="$(pkg_temp_c)"
  if [[ -n "$pkg" ]] && awk -v t="$pkg" 'BEGIN {exit !(t<=55)}'; then
    printf '%s COOLDOWN_TARGET_REACHED package_temp_c=%s\n' "$(date --iso-8601=seconds)" "$pkg" | tee -a "$EVENTS"
    break
  fi
  sleep 5
done

touch "$STOP_FILE"
wait "$SAMPLER_PID" 2>/dev/null || true
snapshot_throttle_counters "$OUT_DIR/throttle-after.csv"
systemctl --failed --no-legend > "$OUT_DIR/failed-units-after.txt" || true
journalctl -k --since "$(awk -F= '/^started=/{print $2}' "$OUT_DIR/metadata.txt")" --no-pager > "$OUT_DIR/kernel-after.log" || true

awk -F, 'NR>1 && $2=="stress" {
  n++; cpu+=$3; if($3>maxcpu)maxcpu=$3; if($6>maxt)maxt=$6; if(minmem==0||$8<minmem)minmem=$8;
  if($7>maxnvme)maxnvme=$7
} END {
  printf "samples=%d\navg_cpu_pct=%.2f\nmax_cpu_pct=%.2f\nmax_pkg_temp_c=%.1f\nmax_nvme_temp_c=%.1f\nmin_mem_available_mib=%.1f\n", n, (n?cpu/n:0), maxcpu, maxt, maxnvme, minmem
}' "$METRICS" > "$OUT_DIR/summary.txt"
printf 'stress_rc=%s\nthermal_abort=%s\nfinished=%s\n' "$STRESS_RC" "$([[ -e "$OUT_DIR/THERMAL_ABORT" ]] && printf yes || printf no)" "$(date --iso-8601=seconds)" >> "$OUT_DIR/summary.txt"

cat "$OUT_DIR/summary.txt"
[[ ! -e "$OUT_DIR/THERMAL_ABORT" ]]
