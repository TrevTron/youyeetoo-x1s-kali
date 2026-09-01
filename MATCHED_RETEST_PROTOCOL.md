# X1S matched retest protocol

Updated: 2026-08-31

This is the protocol behind the corrected CPU, Vulkan, Ling-mini, Qwen3.5,
Gemma 4, MTP, BitCPM, and Gemma 3 compatibility results.

## System under test

- Youyeetoo X1S review unit
- Intel Celeron N5095, four cores and four threads
- 16 GB RAM
- Supplied heatsink and active fan, open bench
- Kali Linux 2025.4 amd64, kernel `6.16.8+kali-amd64`
- Ollama 0.32.1
- llama.cpp commit `9a286ac98d2cab74231bd3f1fc3f2b8bdf05422e`

Ambient temperature and wall power were not instrumented. These results do not
support temperature-over-ambient or performance-per-watt claims.

## Build record

The original llama.cpp build was recovered and audited. It used Release mode,
`-O3`, OpenMP, SSE4.2, Vulkan, and a conservative `GGML_NATIVE=OFF` CPU build.
It was not a debug build. The corrected same-prompt CPU comparison used a new
build of the same commit with `GGML_NATIVE=ON`.

The build collector saves the commit, CMake command and cache values, compiler
flags, binary hashes, CPU-backend hash, instruction flags, and kernel version.
See [`scripts/build_llama_cpp_native_guarded.sh`](scripts/build_llama_cpp_native_guarded.sh).

## Matched CPU runtime comparison

Ollama 0.32.1's bundled CPU runner and the pinned native llama.cpp server
received the same:

- content-addressed GGUF;
- raw prompt, without a chat template;
- 4,096-token context;
- four CPU threads;
- batch and microbatch size 512;
- 96 generated tokens;
- seed 42, temperature 0, top-k 1, top-p 1, min-p 0, repeat-last-n 0,
  repeat penalty 1;
- disabled prompt-cache reuse;
- one warmup and three measured requests per runtime.

The collector requires matching prompt-token counts and exactly 96 generated
tokens. Output must be deterministic within each runtime. Cross-runtime output
equality is recorded but is not a pass condition because revision and kernel
differences can produce different greedy paths.

Ollama unloads after every request. The standalone llama.cpp server remains
resident for its three-request block. The comparison therefore uses each
server's internal prompt and generation durations, not total wall-clock latency.
See [`scripts/benchmark_matched_runtime_guarded.sh`](scripts/benchmark_matched_runtime_guarded.sh).

## True CPU, mixed host-op, and full Vulkan

`--n-gpu-layers 0` is not a pure-CPU guarantee when a Vulkan device remains
visible. llama.cpp can still move host operations to the device. The corrected
small-model matrix used one native binary, pp128, tg96, four threads, batch and
microbatch 512, and five repetitions in each explicit mode:

- Pure CPU: `GGML_VK_VISIBLE_DEVICES=`, zero GPU layers, and
  `--no-op-offload 1`.
- Mixed host-op: Vulkan visible, zero GPU layers, and default operation
  offload.
- Full Vulkan: Vulkan visible and 99 GPU layers.

The original larger-model Vulkan rows remain diagnostic only. Qwen3 4B reached
a reset timeout. Phi-4 Mini and Qwen3 8B coincided with i915 GPU hangs even
though their processes returned zero. Gemma 3 later ended with fence timeouts,
an i915 reset, and `vk::DeviceLostError`.

See [`scripts/benchmark_three_mode_final_guarded.sh`](scripts/benchmark_three_mode_final_guarded.sh).

## Ling-mini

The requested artifact is Bartowski's Ling-mini-2.0 IQ4_XS GGUF from revision
`8be84a0f472797118167aac86b56ca903561a73b`, SHA-256
`a72d86d4cb4fedd940e34c08d008bb5cda42db80ce5c6bc5f9494e854a3d742d`.

A one-through-four thread sweep found that four threads reached the standard
85 C guard. I repeated that one missing setting with a 90 C abort, a 5.9%
increase. It completed cleanly with an 85 C peak. The selected final row used
four threads, pp128, tg96, batch and
microbatch 512, and five repetitions in true CPU mode. The earlier clean
three-thread row is retained beside it.

See [`scripts/download_ling_mini_iq4_xs_guarded.sh`](scripts/download_ling_mini_iq4_xs_guarded.sh)
and [`scripts/benchmark_ling_mini_final_guarded.sh`](scripts/benchmark_ling_mini_final_guarded.sh).

## MTP

The MTP pairs use the same prompt, context, four CPU threads, batch settings,
sampler settings, and 96-token output. Thinking is explicitly false. The
collector records both `thinking` and `response` lengths and hashes the
canonical `[thinking, response]` pair.

An on row must prove all of the following:

- Ollama launched with `--spec-type draft-mtp` and the requested draft depth;
- the journal recorded nonzero generated draft tokens;
- off and on produced 96 tokens;
- the combined output hashes matched;
- no thermal or kernel guard fired.

Depths 1 through 3 use one paired screening prompt. Depth 4 uses five measured
prompts per variant. A single depth is not generalized to MTP as a whole.

The standard thermal abort is 85 C. Gemma depths 2 and 3 first reached that
guard. I repeated only those two missing configurations with a 90 C abort, a
5.9% increase. Intel specifies 105 C Tjunction for the N5095. The i915
recovery behavior, kernel-error checks, and 10-minute
request timeout were unchanged.

See [`scripts/benchmark_ollama_mtp_guarded.sh`](scripts/benchmark_ollama_mtp_guarded.sh)
and [`MTP_RESULTS.md`](MTP_RESULTS.md).

## Safety and evidence rules

- Ordinary runs begin below 65 C and stop at 85 C.
- The two disclosed Gemma MTP repeats and one Ling-mini repeat stop at 90 C.
- Temperature is sampled every two seconds.
- Every request or benchmark receives its own kernel-journal window.
- A matched GPU hang, reset, device loss, OOM, segmentation fault, machine
  check, or hardware error invalidates the row.
- A process return code of zero does not override a kernel failure.
- Timeouts and thermal stops are published as stops, not converted into speed
  scores.
- Model, binary, and evidence hashes are retained.
- The original source model is never overwritten by a compatibility patch.

No GPU watchdog, forced timeout restart, firmware protection, or kernel safety
control was disabled.

## Original matrix boundary

The first Round 2 CPU matrix used exact matching GGUFs but not the same job.
Ollama answered a natural-language request, while `llama-bench` used a synthetic
128-token prompt. Output length, context handling, cache behavior, repetitions,
and timing path differed. Those rows are historical measurements only. They do
not support a runtime winner claim.

The corrected comparison is documented in
[`RUNTIME_COMPARISON.md`](RUNTIME_COMPARISON.md).

## Comparisons this project does not make

- Throughput is not a quality score.
- Different quantizations are not ranked as if they were equal artifacts.
- The Pi 5, IndieDroid Nova, N100, and N150 are not compared without the same
  model, runtime, prompt, settings, cooling disclosure, and timing definition.
- Mixed host-operation offload is not renamed conventional layer-split offload.
