# X1S Round 2: Ollama, llama.cpp CPU, and Vulkan

Date: 2026-08-21, with the Gemma compatibility investigation completed on 2026-08-23.

This is a measurement report for one open-bench Youyeetoo X1S: Celeron N5095 (4 cores and 4 threads, SSE4.2, no AVX, AVX2, F16C, or BMI2), 16 GB installed RAM, Kali 2025.4, Mesa 25.2.6, Ollama 0.32.1, and llama.cpp commit `9a286ac` built locally with SSE4.2 and Vulkan enabled. The supplied heatsink and active fan were fitted. Ambient temperature and wall power were not instrumented.

## What matches, and what does not

Five original tags use the exact Q4_K_M GGUF blobs recorded in `results/round2/ollama-blob-map.txt`. That verifies the model artifacts, not a fair runtime comparison. Gemma required a separate derived text-only compatibility copy for llama.cpp. Ollama used the original deterministic request with a 96-token cap, temperature 0, seed 42, and a 4,096-token context. llama.cpp used `llama-bench` with a synthetic 128-token prompt and 96 generated tokens, four threads, and two repetitions. The main llama.cpp matrix did not explicitly pass the same 4,096-token context.

The weights and token-generation length align, but the prompt, harness, and explicitly recorded context do not. The Ollama and llama.cpp CPU figures below are separate generation-throughput observations. They do not establish that either runtime is faster. A winner claim requires the clean same-request protocol in `ROUND2_PROTOCOL.md`.

Correction, 2026-08-24: an earlier summary treated the first four completed CPU rows as a direct runtime comparison. That interpretation was too strong and has been removed. The raw measurements have not changed.

Temperature sampling was every two seconds. The stop rules were an 85 C package-temperature guard and a 10-minute per-run cap. No GPU timeout, watchdog, driver, firmware, or kernel safety setting was weakened.

## Original six-model matrix

| Model | Ollama warm generation | llama.cpp CPU generation | llama.cpp Vulkan generation | Vulkan prompt processing | Outcome |
| --- | ---: | ---: | ---: | ---: | --- |
| Qwen3 0.6B | 7.81 tok/s | 7.42 tok/s | 8.56 tok/s | 37.29 tok/s | clean Vulkan run |
| Qwen3 1.7B | 3.47 tok/s | 2.98 tok/s | 3.48 tok/s | 12.86 tok/s | clean Vulkan run |
| Qwen3 4B Instruct | 1.98 tok/s | 1.58 tok/s | 1.46 tok/s | 6.39 tok/s | kernel reset timeout during run window |
| Phi-4 Mini | 2.10 tok/s | 1.64 tok/s | 1.48 tok/s | 6.40 tok/s | i915 GPU hang during run window, process returned 0 |
| Gemma 3 4B | 2.12 tok/s | 1.64 tok/s, derived text-only compatibility copy | GPU hang | not reported | preserved failure |
| Qwen3 8B | 0.98 tok/s | 10-minute cap | 0.84 tok/s | 6.40 tok/s | i915 GPU hang during run window, process returned 0 |

Only Qwen3 0.6B and 1.7B completed without a matching kernel reset or hang. In those clean pairs, Vulkan prompt processing ran at 3.3 to 3.5 times the CPU rate, generation improved over CPU, and recorded package peaks were 26 to 27 C lower.

The larger-model processes still wrote benchmark rows, but their run windows contain i915 failures. Qwen3 4B reached a reset request timeout. Phi-4 Mini and Qwen3 8B coincided with explicit GPU hangs even though `llama-bench` returned 0. The Qwen3 8B number is therefore a retained diagnostic observation, not evidence of a clean completion after the CPU time cap.

## Vulkan access and failure boundary

Mesa ANV initially exposed only llvmpipe because the bench account could not access `/dev/dri/renderD128`. Adding the account to the existing `render` group allowed Intel UHD Graphics (Jasper Lake) to enumerate. No driver or safety-control change was made.

The original runner enforced temperature and process timeouts, but it inspected the kernel summary only after the full Vulkan matrix. That implementation did not enforce the intended stop-on-reset rule. The corrected interpretation maps the telemetry windows to the retained kernel log and marks every affected row as unstable. No additional Vulkan or split-offload testing was attempted after this reconstruction.

Gemma 3 4B exposed two separate issues. The Ollama GGUF was an older multimodal conversion that current llama.cpp rejected. A separate text-only compatibility copy added the missing epsilon metadata, padded the vocabulary row, and removed embedded vision tensors; it produced the CPU value above. The corresponding Vulkan run then ended with fence timeouts, an i915 preemption reset, and `vk::DeviceLostError`. It produced no valid prompt or generation score. The system recovered and the raw kernel excerpt is retained in `results/round2/gemma3-vulkan-devicelost-dmesg.txt`.

The compatibility utility is retained as `scripts/patch_gemma3_gguf.py`. It creates a new output file and leaves the source GGUF unchanged. It is not a workaround for the Vulkan failure.

## Community-requested models

These measurements are single Ollama requests using the same request settings as the original six-model rerun. They are throughput observations, not quality rankings or repeated performance distributions.

| Model tag used | Generation | Peak package | Note |
| --- | ---: | ---: | --- |
| `granite4:tiny-h` | 5.43 tok/s | 79 C | 7B-A1B hybrid MoE tag |
| `lfm2.5:latest` | 4.95 tok/s | 80 C | `latest` was not pinned to a public digest in this release package |
| `gemma3n:e2b` | 3.24 tok/s | 80 C | effective-2B variant |

Each result is faster than the 1.824 to 1.995 tok/s 4B-class range measured in round 1. That does not establish broader answer quality or a universal recommendation.

## Retained result files

- `results/round2/ollama-rerun.csv`: complete three-run Ollama summary for the original six tags.
- `results/round2/llama-bench.csv`: sanitized aggregated llama-bench rows.
- `results/round2/new-models.tsv`: the requested-model observations.
- `results/round2/gemma3-vulkan-devicelost-dmesg.txt`: kernel evidence for the recovered GPU failure.
- `results/round2/vulkan-session-kernel-events.txt`: sanitized run-window mapping for the reset and GPU-hang events in the original Vulkan matrix.
- `ROUND2_PROTOCOL.md`: exact boundaries, limitations, and a clean next-run checklist.
