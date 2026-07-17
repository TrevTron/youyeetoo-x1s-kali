#!/usr/bin/env bash
set -Eeuo pipefail

OUT_DIR="${1:-$HOME/x1s-lab/logs/kali-tools-$(date +%F-%H%M%S)}"
mkdir -p "$OUT_DIR/output"
RESULTS="$OUT_DIR/results.csv"

printf '%s\n' 'check,tool,installed,exit_code,elapsed_ms,scope,output_file' > "$RESULTS"

run_check() {
  local check="$1" tool="$2" scope="$3"
  shift 3
  local output="$OUT_DIR/output/${check}.txt" start end rc

  if ! command -v "$tool" >/dev/null 2>&1; then
    printf '%s,%s,no,127,0,%s,%s\n' "$check" "$tool" "$scope" "output/${check}.txt" >> "$RESULTS"
    printf 'NOT INSTALLED: %s\n' "$tool" > "$output"
    return 0
  fi

  start="$(date +%s%3N)"
  set +e
  timeout --signal=TERM 120s "$tool" "$@" > "$output" 2>&1
  rc=$?
  set -e
  end="$(date +%s%3N)"
  printf '%s,%s,yes,%s,%s,%s,%s\n' "$check" "$tool" "$rc" "$((end-start))" "$scope" "output/${check}.txt" >> "$RESULTS"
}

{
  printf 'started=%s\n' "$(date --iso-8601=seconds)"
  printf 'hostname=%s\n' "$(hostname)"
  printf 'os=%s\n' "$(. /etc/os-release && printf '%s %s' "$PRETTY_NAME" "$VERSION_ID")"
  printf 'kernel=%s\n' "$(uname -r)"
  printf 'policy=Version and startup checks plus a TCP connect scan of loopback only. No external target. No exploitation. No password cracking target. No wireless capture or injection.\n'
} > "$OUT_DIR/metadata.txt"

systemctl --failed --no-legend > "$OUT_DIR/failed-units-before.txt" || true

run_check nmap_version nmap version --version
run_check nmap_loopback nmap loopback-only -sT -Pn -p 22,11434 127.0.0.1
run_check metasploit_startup msfconsole startup-only -q -x 'version; exit -y'
run_check tshark_version tshark version --version
run_check dumpcap_interfaces dumpcap local-interface-enumeration -D
run_check john_benchmark john synthetic-built-in-benchmark --test=5 --format=raw-sha256
run_check hashcat_devices hashcat local-compute-device-enumeration -I
run_check aircrack_help aircrack-ng help-only --help
run_check sqlmap_version sqlmap version --version
run_check hydra_help hydra help-only -h
run_check nikto_version nikto version -Version
run_check gobuster_version gobuster version --version
run_check ffuf_version ffuf version -V
run_check netexec_version netexec version --version

for package in kali-linux-default kali-tools-top10 nmap metasploit-framework wireshark tshark john hashcat aircrack-ng sqlmap hydra nikto gobuster ffuf netexec; do
  dpkg-query -W -f='${Package},${Status},${Version}\n' "$package" 2>/dev/null || printf '%s,not-installed,\n' "$package"
done > "$OUT_DIR/package-inventory.csv"

systemctl --failed --no-legend > "$OUT_DIR/failed-units-after.txt" || true
journalctl -k --since "$(awk -F= '/^started=/{print $2}' "$OUT_DIR/metadata.txt")" --no-pager \
  | grep -Ei 'oom|out of memory|thermal|thrott|segfault|nvme.*(error|critical)' \
  > "$OUT_DIR/relevant-kernel-events.log" || true

printf 'finished=%s\n' "$(date --iso-8601=seconds)" >> "$OUT_DIR/metadata.txt"
column -s, -t "$RESULTS" 2>/dev/null || cat "$RESULTS"
