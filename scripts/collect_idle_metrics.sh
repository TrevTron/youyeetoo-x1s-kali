#!/usr/bin/env bash
set -euo pipefail

duration_seconds="${1:-900}"
interval_seconds="${2:-5}"
output_file="${3:-idle-metrics.csv}"

export LC_ALL=C

if ! [[ "$duration_seconds" =~ ^[0-9]+$ ]] || ! [[ "$interval_seconds" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 [duration_seconds] [interval_seconds] [output_file]" >&2
  exit 2
fi

mkdir -p "$(dirname "$output_file")"

find_thermal_zone() {
  local wanted="$1" zone
  for zone in /sys/class/thermal/thermal_zone*; do
    [[ -r "$zone/type" ]] || continue
    if [[ "$(<"$zone/type")" == "$wanted" ]]; then
      printf '%s\n' "$zone"
      return 0
    fi
  done
  return 1
}

find_hwmon() {
  local pattern="$1" hwmon name
  for hwmon in /sys/class/hwmon/hwmon*; do
    [[ -r "$hwmon/name" ]] || continue
    name="$(<"$hwmon/name")"
    if [[ "$name" == $pattern ]]; then
      printf '%s\n' "$hwmon"
      return 0
    fi
  done
  return 1
}

read_cpu_ticks() {
  local label user nice system idle iowait irq softirq steal guest guest_nice
  read -r label user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  CPU_IDLE=$((idle + iowait))
  CPU_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
}

read_millicelsius() {
  local file="${1:-}"
  if [[ -n "$file" && -r "$file" ]]; then
    awk '{ printf "%.1f", $1 / 1000 }' "$file"
  fi
}

package_zone="$(find_thermal_zone 'x86_pkg_temp' || true)"
tcpu_zone="$(find_thermal_zone 'TCPU' || true)"
nvme_hwmon="$(find_hwmon 'nvme' || true)"

fan_input=""
for candidate in /sys/class/hwmon/hwmon*/fan1_input; do
  if [[ -r "$candidate" ]]; then
    fan_input="$candidate"
    break
  fi
done

rapl_energy=""
rapl_max=""
for candidate in /sys/class/powercap/intel-rapl*/energy_uj; do
  if [[ -r "$candidate" ]]; then
    rapl_energy="$candidate"
    rapl_max="${candidate%/energy_uj}/max_energy_range_uj"
    break
  fi
done

printf '%s\n' 'timestamp,cpu_util_percent,load_1m,avg_cpu_mhz,cpu_package_c,tcpu_c,nvme_c,fan_rpm,mem_available_mib,rapl_package_w' > "$output_file"

read_cpu_ticks
previous_idle="$CPU_IDLE"
previous_total="$CPU_TOTAL"
previous_energy=""
previous_epoch=""
if [[ -n "$rapl_energy" ]]; then
  previous_energy="$(<"$rapl_energy")"
  previous_epoch="$(date +%s%N)"
fi

end_epoch=$(( $(date +%s) + duration_seconds ))

while (( $(date +%s) < end_epoch )); do
  sleep "$interval_seconds"
  read_cpu_ticks
  delta_idle=$((CPU_IDLE - previous_idle))
  delta_total=$((CPU_TOTAL - previous_total))
  cpu_util=""
  if (( delta_total > 0 )); then
    cpu_util="$(awk -v idle="$delta_idle" -v total="$delta_total" 'BEGIN { printf "%.2f", 100 * (total - idle) / total }')"
  fi

  avg_cpu_mhz="$(awk '/cpu MHz/ { sum += $4; count += 1 } END { if (count) printf "%.1f", sum / count }' /proc/cpuinfo)"
  load_1m="$(awk '{print $1}' /proc/loadavg)"
  mem_available_mib="$(awk '/MemAvailable:/ { printf "%.1f", $2 / 1024 }' /proc/meminfo)"
  package_temp="$(read_millicelsius "${package_zone:+$package_zone/temp}")"
  tcpu_temp="$(read_millicelsius "${tcpu_zone:+$tcpu_zone/temp}")"
  nvme_temp="$(read_millicelsius "${nvme_hwmon:+$nvme_hwmon/temp1_input}")"
  fan_rpm=""
  [[ -n "$fan_input" ]] && fan_rpm="$(<"$fan_input")"

  rapl_watts=""
  if [[ -n "$rapl_energy" ]]; then
    current_energy="$(<"$rapl_energy")"
    current_epoch="$(date +%s%N)"
    delta_energy=$((current_energy - previous_energy))
    if (( delta_energy < 0 )) && [[ -r "$rapl_max" ]]; then
      delta_energy=$((delta_energy + $(<"$rapl_max")))
    fi
    delta_ns=$((current_epoch - previous_epoch))
    if (( delta_ns > 0 )); then
      rapl_watts="$(awk -v energy="$delta_energy" -v ns="$delta_ns" 'BEGIN { printf "%.3f", (energy / 1000000) / (ns / 1000000000) }')"
    fi
    previous_energy="$current_energy"
    previous_epoch="$current_epoch"
  fi

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$(date -Is)" "$cpu_util" "$load_1m" "$avg_cpu_mhz" "$package_temp" "$tcpu_temp" \
    "$nvme_temp" "$fan_rpm" "$mem_available_mib" "$rapl_watts" >> "$output_file"

  previous_idle="$CPU_IDLE"
  previous_total="$CPU_TOTAL"
done

echo "Wrote $(($(wc -l < "$output_file") - 1)) samples to $output_file"
