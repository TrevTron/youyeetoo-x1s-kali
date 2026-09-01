# Methodology and Limits

## System under test

- Youyeetoo X1S review unit.
- Intel Celeron N5095, four cores / four threads.
- 16 GB installed RAM (approximately 15 GiB visible to Linux).
- 128 GB M.2 2280 NVMe supplied by Youyeetoo.
- Supplied heatsink and connected active fan, open-bench configuration.
- Kali Linux 2025.4 amd64; kernel `6.16.8+kali-amd64`.
- Ollama 0.32.1 CPU backend.

The original Kali, thermal, and Ollama work was recorded on 2026-07-16 PDT.
Round 2 and its corrected follow-up ran from 2026-08-21 through 2026-08-31.
Ambient room temperature and wall power were not instrumented, so I do not make
a temperature-over-ambient or performance-per-watt claim.

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

## Integrated loopback security workflow

The follow-up workflow starts an intentionally vulnerable Python HTTP service
that refuses any host other than `127.0.0.1`. Nmap performs service discovery,
the Metasploit HTTP-version scanner validates framework operation, Nikto checks
the local HTTP surface, Gobuster and ffuf use a five-entry seeded wordlist,
SQLmap validates the deliberately unsafe SQLite query parameter, and TShark
preserves a loopback PCAP. Each tool has a five-minute command timeout.

Systemd failures and relevant OOM, thermal, throttling, segmentation-fault, and
NVMe-critical kernel events are checked before and after. This demonstrates a
reproducible multi-tool workflow without creating an external target or making
a claim about unauthorized systems.

## Round 2 build audit

The original llama.cpp build was recovered and inspected rather than guessed
from a binary name. It used commit
`9a286ac98d2cab74231bd3f1fc3f2b8bdf05422e`, Release mode, `-O3`, OpenMP,
SSE4.2, and Vulkan. `GGML_NATIVE=OFF` made it a conservative N5095 build, but it
was not a debug or unoptimized build. I rebuilt the same commit with
`GGML_NATIVE=ON` for the corrected CPU comparison and saved the build command,
CMake cache values, compile flags, binary hashes, and CPU-backend hash.

## Matched Ollama and llama.cpp CPU method

The first Round 2 CPU rows were not a valid runtime comparison. Ollama had
answered a natural-language request while `llama-bench` had used a synthetic
128-token prompt. Context handling, output length, cache behavior, repetitions,
and timing path also differed. Those original numbers remain historical
measurements, not a winner test.

The corrected test compared Ollama 0.32.1's bundled CPU runner with the native
llama.cpp server from the pinned commit. Both received the same raw prompt,
content-addressed GGUF, 4,096-token context, four threads, batch and microbatch
512, deterministic sampler settings, disabled prompt-cache reuse, and exactly
96 generated tokens. Each runtime received one warmup followed by three
measured requests per model.

Every request began below 65 C and stopped at 85 C. Temperature was sampled
every two seconds, and each request received its own kernel-journal window.
Prompt-token and generated-token counts had to match. Output had to be
deterministic within each runtime. Cross-runtime output equality was recorded,
but it was not required because different revisions and CPU kernels can take
different greedy paths. The test compares internal prompt and generation rates,
not identical wall-clock latency, because Ollama unloaded after every request
while the standalone server remained resident for its three-request block.

## Corrected CPU and Vulkan device modes

On this llama.cpp build, `--n-gpu-layers 0` does not necessarily mean pure CPU
when Vulkan is visible. Default host-operation offload can still use the GPU.
The corrected small-model matrix therefore measured three explicit modes with
one native binary, one workload, batch and microbatch 512, four threads, and
five repetitions:

- Pure CPU hid Vulkan and passed `--no-op-offload 1` with zero GPU layers.
- Mixed host-op left Vulkan visible with zero GPU layers and default operation
  offload.
- Full Vulkan left Vulkan visible and passed 99 GPU layers.

The original larger-model Vulkan rows are diagnostic evidence only. A process
return code of zero did not override a matching i915 reset or GPU hang in its
kernel window. The corrected runner watches the kernel during each run and
stops on the first reset, hang, device loss, OOM, hardware error, or thermal
limit.

## Community model follow-up

Qwen3.5, Gemma 4, Granite 4 Tiny-H, LFM2.5, Gemma 3n, BitCPM, and Ling-mini
were kept as separate model and compatibility questions. Throughput is not a
quality score, and results from different quantizations or prompts are not
presented as direct model rankings.

The requested Ling-mini-2.0 file is Bartowski's IQ4_XS GGUF at pinned revision
`8be84a0f472797118167aac86b56ca903561a73b`. Its SHA-256 is
`a72d86d4cb4fedd940e34c08d008bb5cda42db80ce5c6bc5f9494e854a3d742d`.
I swept one through four CPU threads first. Four threads reached the standard
85 C guard. I repeated that one missing setting with a 90 C abort, a 5.9%
increase. It completed with an 85 C
peak. The final four-thread row used true CPU mode, pp128, tg96, batch and
microbatch 512, and five repetitions. The earlier clean three-thread row remains
in the result file so the effect of the changed ceiling is visible.

The MTP check used Ollama's `draft_num_predict` option with thinking explicitly
disabled. The collector records both `thinking` and `response` lengths and
hashes the canonical pair. An early pilot that hashed only `.response` is
retained privately as invalid because Qwen3.5 had placed its text in
`.thinking`. The corrected run requires equal generated-token counts and equal
combined output hashes between MTP-off and MTP-on. Draft activation and nonzero
draft generation are also proven from the Ollama service journal. Depths 1
through 4 are separate configurations. A result at one depth is not generalized
to MTP as a whole.

The standard ceiling was 85 C. Gemma depth 2 reached that ceiling during
its measured request, and depth 3 reached it during warmup. I repeated only
those two missing configurations with a 90 C abort, a 5.9% increase. Intel lists the
N5095 Tjunction at 105 C, leaving a 15 C margin. Both configurations completed
under the new ceiling, and the result rows record which limit was used. The
i915 reset behavior, kernel-error abort, and request timeout were not changed.
The same authorization covered the otherwise incomplete four-thread Ling-mini
setting. It completed at an 85 C peak under the 90 C abort.
See [Intel's N5095 specifications](https://www.intel.com/content/www/us/en/products/sku/212322/intel-celeron-processor-n5095-4m-cache-up-to-2-90-ghz/specifications.html).

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
