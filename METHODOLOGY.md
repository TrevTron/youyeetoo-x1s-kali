# Methodology and Limits

## System under test

- Youyeetoo X1S review unit.
- Intel Celeron N5095, four cores / four threads.
- 16 GB installed RAM (approximately 15 GiB visible to Linux).
- 128 GB M.2 2280 NVMe supplied by Youyeetoo.
- Supplied heatsink and connected active fan, open-bench configuration.
- Kali Linux 2025.4 amd64; kernel `6.16.8+kali-amd64`.
- Ollama 0.32.1 CPU backend.

The test date was 2026-07-16 PDT. Ambient room temperature and wall power were
not instrumented, so no temperature-over-ambient or performance-per-watt claim
is made.

## Idle baseline

CPU package and NVMe temperature were sampled for 15 minutes before sustained
workloads. The raw series and summary are in `results/`.

## Text-inference matrix

Six models were tested one at a time with an identical deterministic prompt,
4,096-token context, zero temperature, fixed seed, and 96 generated-token cap.
Each model received one cold and two warm requests. Per-second telemetry
recorded CPU use, load, package temperature, NVMe temperature, available RAM,
and Ollama RSS. Requests had a 15-minute timeout and an 85 C automatic-abort
guard.

The three 4B-class models that hit the 96-token cap received one separate
160-token functional follow-up. These confirm instruction completion and are
not substituted into the fixed hardware comparison.

## Vision boundary probe

Gemma 3 4B received the same 1,920 x 1,080 Kali desktop PNG and a fixed
three-sentence description prompt. The corrected request used a JSON file with
`curl --data-binary`, a 20-minute timeout, and the 85 C guard. It produced no
text before timeout. This negative result is reported as a practical latency
boundary, not as a crash or thermal failure. The public results retain the
input SHA-256 and dimensions, but omit the source screenshot because its panel
contained a private VPN address. The JSON payload containing the base64-encoded
source is omitted for the same reason.

## Synthetic thermal evaluation

`stress-ng 0.21.03` ran four verified CPU workers using `matrixprod` for exactly
15 minutes. Telemetry sampled CPU use, load, average reported frequency,
package temperature, NVMe temperature, and available memory. Core and package
thermal-throttle counters, kernel events, and failed services were captured
before and after. The workload was terminated automatically if package
temperature reached 85 C.

Linux reported the `powersave` scaling governor. Under the workload, every
sample still reported an average 2.8 GHz across the four CPUs; interpretation
therefore uses observed frequency and throttle counters, not the governor name
alone.

## Kali compatibility matrix

The matrix records package versions and bounded startup behavior for Nmap,
Metasploit, TShark/dumpcap, John, Hashcat, Aircrack-ng, SQLmap, Hydra, Nikto,
Gobuster, ffuf, and NetExec. It includes a five-second built-in John benchmark,
Hashcat compute-device enumeration, dumpcap local-interface enumeration, and an
Nmap TCP-connect scan of `127.0.0.1` only.

It does not test exploit success, external scan throughput, real credential
attacks, monitor-mode radios, packet injection, or GPU acceleration.

## Comparison policy

Trevor's existing Nova-versus-Raspberry-Pi work is useful editorial context but
is not merged into the X1S tables. It used different hardware, runtimes,
quantization, and some disclosed third-party Pi data. A direct X1S-versus-Pi 5
performance claim requires the same model artifact, runtime, prompt, settings,
cooling disclosure, and measurement script on both boards.

## General limits

- One X1S sample was tested.
- The board was not enclosed.
- The thermal soak lasted 15 minutes, not multiple hours or days.
- No calibrated ambient-temperature or power meter was used.
- Software versions will change after rolling updates.
- Compatibility proves installation and bounded operation, not superiority for
  every professional security workflow.
