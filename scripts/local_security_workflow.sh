#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$HOME/x1s-lab/logs/security-workflow-$(date +%F-%H%M%S)}"
TARGET="http://127.0.0.1:8008"
mkdir -p "$OUT_DIR/output"
RESULTS="$OUT_DIR/results.csv"
printf '%s\n' 'check,tool,exit_code,elapsed_ms,output_file' > "$RESULTS"

run_check() {
  local name="$1" tool="$2"
  shift 2
  local output="$OUT_DIR/output/${name}.txt" start end rc
  start="$(date +%s%3N)"
  set +e
  timeout --signal=TERM 300s "$tool" "$@" > "$output" 2>&1
  rc=$?
  set -e
  end="$(date +%s%3N)"
  printf '%s,%s,%s,%s,%s\n' "$name" "$tool" "$rc" "$((end-start))" "output/${name}.txt" >> "$RESULTS"
}

cleanup() {
  [[ -n "${CAPTURE_PID:-}" ]] && kill -TERM "$CAPTURE_PID" 2>/dev/null || true
  [[ -n "${SERVER_PID:-}" ]] && kill -TERM "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

{
  printf 'started=%s\n' "$(date --iso-8601=seconds)"
  printf 'target=%s\n' "$TARGET"
  printf 'binding=loopback-only\n'
  printf 'authorization=Self-hosted intentionally vulnerable lab on the X1S; no external target.\n'
} > "$OUT_DIR/metadata.txt"

systemctl --failed --no-legend > "$OUT_DIR/failed-units-before.txt" || true
python3 "$SCRIPT_DIR/local_security_lab.py" --host 127.0.0.1 --port 8008 > "$OUT_DIR/server.log" 2>&1 &
SERVER_PID=$!

for _ in {1..20}; do
  curl --silent --fail "$TARGET/" >/dev/null 2>&1 && break
  sleep 0.25
done
curl --silent --fail "$TARGET/" > "$OUT_DIR/output/baseline-root.html"

timeout --signal=TERM 90s tshark -i lo -f 'tcp port 8008' -w "$OUT_DIR/loopback-capture.pcapng" \
  > "$OUT_DIR/output/tshark-capture.txt" 2>&1 &
CAPTURE_PID=$!
sleep 1

run_check nmap_service nmap -sV -Pn -p 8008 127.0.0.1
run_check metasploit_http msfconsole -q -x 'use auxiliary/scanner/http/http_version; set RHOSTS 127.0.0.1; set RPORT 8008; run; exit -y'
run_check nikto_local nikto -h "$TARGET" -maxtime 60s -nointeractive
run_check gobuster_local gobuster dir -u "$TARGET" -w "$SCRIPT_DIR/local_security_wordlist.txt" -q -t 4 --timeout 5s
run_check ffuf_local ffuf -u "$TARGET/FUZZ" -w "$SCRIPT_DIR/local_security_wordlist.txt" -mc all -s -noninteractive -t 4
run_check sqlmap_local sqlmap -u "$TARGET/item?id=1" --batch --level=1 --risk=1 --dbms=SQLite --technique=BE --flush-session --timeout=5 --retries=0 --threads=2

curl --silent "$TARGET/admin/" >/dev/null
curl --silent "$TARGET/item?id=1" >/dev/null
sleep 2
kill -TERM "$CAPTURE_PID" 2>/dev/null || true
wait "$CAPTURE_PID" 2>/dev/null || true
CAPTURE_PID=''

if [[ -s "$OUT_DIR/loopback-capture.pcapng" ]]; then
  tshark -r "$OUT_DIR/loopback-capture.pcapng" -q -z io,phs > "$OUT_DIR/output/tshark-protocol-summary.txt" 2>&1 || true
fi

systemctl --failed --no-legend > "$OUT_DIR/failed-units-after.txt" || true
journalctl -k --since "$(awk -F= '/^started=/{print $2}' "$OUT_DIR/metadata.txt")" --no-pager \
  | grep -Ei 'oom|out of memory|thermal|thrott|segfault|nvme.*(error|critical)' \
  > "$OUT_DIR/relevant-kernel-events.log" || true
printf 'finished=%s\n' "$(date --iso-8601=seconds)" >> "$OUT_DIR/metadata.txt"

column -s, -t "$RESULTS" 2>/dev/null || cat "$RESULTS"
