# Youyeetoo X1S Kali lab and local LLM benchmarks

![Youyeetoo X1S running as a compact Kali Linux workbench](images/x1s-kali-workbench.webp)

This repository contains my installation notes, guarded scripts, selected raw
evidence, and benchmark results for the Youyeetoo X1S. The board has a Celeron
N5095, 16 GB RAM, Intel UHD graphics, and a 128 GB NVMe. I tested it as both a
small Kali workstation and a low-cost local LLM box.

The work is split across three articles. Each article stays tied to the testing
stage it reported:

- [Testing the Youyeetoo X1S for a Budget Kali Cyberdeck](https://unland.dev/blog/budget-cyberdeck-youyeetoo-x1s-kali)
  covers the NVMe installation, thermals, Kali tools, loopback lab, and first
  CPU-only model pass.
- [Youyeetoo X1S Round 2: Ollama, llama.cpp, and Intel Vulkan](https://unland.dev/blog/youyeetoo-x1s-ollama-llamacpp-vulkan-benchmarks)
  covers the first from-source llama.cpp, Vulkan, and requested-model pass,
  including the later correction that its CPU jobs were not matched.
- [I Reran Ollama vs llama.cpp on the Youyeetoo X1S](https://unland.dev/blog/youyeetoo-x1s-ollama-llamacpp-matched-retest)
  is the new matched retest: same-prompt CPU results, explicit device modes,
  Ling-mini, Qwen3.5 9B, MTP depths 1 through 4, and compatibility reruns.

## What the X1S completed

| Area | Result |
| --- | --- |
| Kali installation | Reliable amd64 Kali boot from the supplied NVMe |
| Thermal soak | 15 minutes, four workers, 77 C peak, no recorded throttling |
| Kali checks | 14 of 14 representative commands produced the intended output |
| Local security workflow | Nmap, Metasploit, Nikto, Gobuster, ffuf, SQLmap, and TShark completed together on loopback |
| Round 1 local LLM range | Qwen3 0.6B at 6.788 warm tok/s through Qwen3 8B at 0.924 warm tok/s |

The security workflow only targets a deliberately vulnerable service bound to
`127.0.0.1`. It does not scan or attack a third-party system.

## Corrected Ollama and llama.cpp CPU comparison

My first Round 2 draft compared an Ollama API request with a synthetic
`llama-bench` job. Those were real measurements, but not a fair head-to-head
test. I reran the comparison with the same raw prompt, content-addressed GGUF,
4,096-token context, four threads, batch and microbatch 512, deterministic
sampler, disabled prompt-cache reuse, and exactly 96 generated tokens.

The llama.cpp side used a native Release build of commit
`9a286ac98d2cab74231bd3f1fc3f2b8bdf05422e`. The build command, CMake values,
binary hashes, and CPU-backend hash are retained.

| Exact Q4_K_M GGUF | Native llama.cpp | Ollama 0.32.1 | Difference |
| --- | ---: | ---: | ---: |
| Qwen3 0.6B | 6.725 tok/s | 7.809 tok/s | Ollama +16.1% |
| Qwen3 1.7B | 2.852 tok/s | 3.321 tok/s | Ollama +16.5% |
| Qwen3 4B Instruct | 1.484 tok/s | 2.002 tok/s | Ollama +34.9% |
| Phi-4 Mini | 1.570 tok/s | 2.072 tok/s | Ollama +32.0% |

All 24 measured requests completed cleanly and produced the required token
counts. This is what these two pinned runtimes did on this X1S. It is not a
universal claim that Ollama is always faster. Ollama unloaded after each
request, so the table compares internal generation rates rather than total
wall-clock latency. See [`RUNTIME_COMPARISON.md`](RUNTIME_COMPARISON.md).

## True CPU, mixed host-op, and full Vulkan

`--n-gpu-layers 0` did not guarantee pure CPU when Vulkan was visible. llama.cpp
could still move host operations to the Intel GPU. I reran the two small models
in three explicit modes with one binary and one pp128/tg96 workload.

| Model | True CPU pp/tg | Mixed host-op pp/tg | Full Vulkan pp/tg | Full Vulkan peak |
| --- | ---: | ---: | ---: | ---: |
| Qwen3 0.6B | 10.666 / 7.397 | 34.586 / 7.425 | 37.350 / 8.593 | 57 C |
| Qwen3 1.7B | 3.893 / 2.986 | 12.366 / 2.997 | 12.879 / 3.462 | 58 C |

Full Vulkan processed prompts 3.50 and 3.31 times faster than true CPU,
improved generation 16.2% and 15.9%, and peaked 24 C and 26 C cooler. The mixed
zero-layer mode delivered most of the prompt gain but almost no generation
gain. It is not conventional layer-split offload.

The larger full-Vulkan tests crossed a reliability boundary. Qwen3 4B reached a
reset timeout. Phi-4 Mini and Qwen3 8B coincided with i915 GPU hangs even though
their processes returned zero. Gemma 3 ended with fence timeouts, an i915 reset,
and `vk::DeviceLostError`. The kernel recovered each time. I did not disable
the watchdog or forced-timeout recovery, and I stopped before a larger split
matrix. See [`MATCHED_RETEST_RESULTS.md`](MATCHED_RETEST_RESULTS.md).

## Community-requested models

| Request | Audited result |
| --- | --- |
| Qwen3.5 0.8B Q8_0 | 10.44 warm tok/s |
| Qwen3.5 2B Q8_0 | 4.89 warm tok/s |
| Qwen3.5 9B Q4_K_M | 1.110 tok/s across five prompts, 82 C peak |
| Gemma 4 E2B Q4_K_M | 3.38 warm tok/s |
| Gemma 4 E4B Q4_K_M | 1.78 warm tok/s |
| Ling-mini-2.0 IQ4_XS | 4.083 generation tok/s at four threads, 85 C peak under the disclosed 90 C guard |
| Granite 4 Tiny-H | 5.43 tok/s single observation |
| LFM2.5 | 4.95 tok/s single observation; mutable tag was not pinned |
| Gemma 3n E2B | 3.24 tok/s single observation |

MTP draft depths 1 through 4 were slower than MTP off on Qwen3.5 0.8B,
Qwen3.5 2B, and Gemma 4 E2B. Depth 1 was the least costly and still reduced
generation by 22.8% to 46.7%. The service journal proves the draft path was
active. See [`MTP_RESULTS.md`](MTP_RESULTS.md).

OpenBMB's official BitCPM-CANN 1B TQ2_0 file exposed a runtime compatibility
difference. Ollama 0.32.1 rejected it with a tensor-size overflow. The same file
completed a true-CPU llama.cpp run at 13.013 prompt tok/s and 8.584 generation
tok/s. A derived text-only Gemma 3 compatibility copy completed true CPU at
2.172 prompt tok/s and 1.624 generation tok/s. The patch script leaves the
original multimodal GGUF untouched and is not a Vulkan workaround. See
[`FOLLOWUP_RESULTS.md`](FOLLOWUP_RESULTS.md).

## Run the guarded collectors

Read each script before running it. The scripts create new result directories,
start below a defined package temperature, monitor the kernel, and stop on their
documented limits.

The collectors also clean up their child processes and stop Ollama models when
a run finishes or is interrupted. The matched runtime collector uses
`keep_alive: 0`, so Ollama unloads the model after every request.

```bash
# All-core thermal soak
MAX_TEMP_C=85 DURATION=15m ./scripts/thermal_soak.sh

# CPU-only Ollama model matrix
MAX_TEMP_C=85 ./scripts/benchmark_ollama.sh

# One true-CPU llama.cpp microbenchmark
LLAMA_BENCH=$HOME/llama.cpp/build-native/bin/llama-bench \
  ./scripts/benchmark_llama_cpp_guarded.sh /path/to/model.gguf pure-cpu 0

# Matched Ollama and llama.cpp server comparison
./scripts/benchmark_matched_runtime_guarded.sh

# True CPU, zero-layer mixed host-op, and full Vulkan
./scripts/benchmark_three_mode_final_guarded.sh
```

The normal thermal abort is 85 C. I repeated two incomplete Gemma MTP settings
and one Ling four-thread setting with a 90 C abort, a 5.9% increase.
Intel lists 105 C Tjunction for the N5095. The affected rows disclose the
changed ceiling. Kernel-error checks, i915 recovery, and request timeouts stayed
enabled.

## Repository map

- [`INSTALLATION.md`](INSTALLATION.md) records the Kali NVMe installation.
- [`METHODOLOGY.md`](METHODOLOGY.md) defines workloads, guards, and comparison
  boundaries.
- [`BENCHMARK_RESULTS.md`](BENCHMARK_RESULTS.md) contains Round 1 results.
- [`ROUND2_RESULTS.md`](ROUND2_RESULTS.md) stays with the measurements behind
  the published Round 2 article.
- [`MATCHED_RETEST_RESULTS.md`](MATCHED_RETEST_RESULTS.md) contains the new
  matched runtime, explicit device-mode, Vulkan, and compatibility findings.
- [`RUNTIME_COMPARISON.md`](RUNTIME_COMPARISON.md) documents the matched CPU
  comparison.
- [`FOLLOWUP_RESULTS.md`](FOLLOWUP_RESULTS.md) covers requested models and
  compatibility results.
- [`MTP_RESULTS.md`](MTP_RESULTS.md) contains the depth sweep.
- [`ROUND2_PROTOCOL.md`](ROUND2_PROTOCOL.md) records the published Round 2
  protocol and its known limits.
- [`MATCHED_RETEST_PROTOCOL.md`](MATCHED_RETEST_PROTOCOL.md) freezes the new
  matched retest protocol.
- [`CANDIDATE_MODEL_TABLE.md`](CANDIDATE_MODEL_TABLE.md) lists completed and
  untested community requests.
- [`results/corrected/`](results/corrected/) contains public aggregate rows and
  evidence-manifest hashes.
- [`results/round2/`](results/round2/) contains sanitized original Round 2 rows
  and GPU-hang evidence.
- [`scripts/`](scripts/) contains the guarded collectors and conversion tools.

## Boundaries

These results describe one open-bench X1S with the supplied heatsink and fan.
I did not instrument ambient temperature or wall power. Throughput is not a
quality score. Different quantizations and prompts are not ranked as if they
were matched. My Raspberry Pi and IndieDroid Nova work is useful context, but it
is not a direct three-board benchmark without the same artifact and method on
each device.

Use Kali tools only on systems you own or are explicitly authorized to test.

## Disclosure and license

Youyeetoo supplied the X1S review unit and 128 GB NVMe. The testing and
conclusions are my own.

Executable scripts are available under the [MIT License](LICENSE). Photographs,
written benchmark material, and result artifacts remain copyright Trevor
Unland unless a file says otherwise.
