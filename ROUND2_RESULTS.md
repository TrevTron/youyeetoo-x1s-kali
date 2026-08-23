# X1S Round 2: Ollama, llama.cpp CPU, and Vulkan

Date: 2026-08-21, with the Gemma compatibility investigation completed on 2026-08-23.

This is a measurement report for one open-bench Youyeetoo X1S: Celeron N5095 (4 cores and 4 threads, SSE4.2, no AVX, AVX2, F16C, or BMI2), 16 GB installed RAM, Kali 2025.4, Mesa 25.2.6, Ollama 0.32.1, and llama.cpp commit `9a286ac` built locally with SSE4.2 and Vulkan enabled. The supplied heatsink and active fan were fitted. Ambient temperature and wall power were not instrumented.

## What is directly comparable

The six original tags use the exact Q4_K_M GGUF blobs recorded in `results/round2/ollama-blob-map.txt`. Ollama used the original deterministic request with a 96-token cap, temperature 0, seed 42, and a 4,096-token context. llama.cpp used `llama-bench` with a synthetic 128-token prompt and 96 generated tokens, four threads, and two repetitions.

The weights and token-generation length align, but the Ollama requests and `llama-bench` are different harnesses. The Ollama-versus-llama.cpp figures below are generation-throughput observations, not end-to-end same-prompt latency or a claim that the prompt-evaluation numbers are interchangeable.

Temperature sampling was every two seconds. The stop rules were an 85 C package-temperature guard and a 10-minute per-run cap. No GPU timeout, watchdog, driver, firmware, or kernel safety setting was weakened.

## Original six-model matrix

| Model | Ollama warm generation | llama.cpp CPU generation | llama.cpp Vulkan generation | Vulkan prompt processing | Outcome |
| --- | ---: | ---: | ---: | ---: | --- |
| Qwen3 0.6B | 7.81 tok/s | 7.42 tok/s | 8.56 tok/s | 37.29 tok/s | completed |
| Qwen3 1.7B | 3.47 tok/s | 2.98 tok/s | 3.48 tok/s | 12.86 tok/s | completed |
| Qwen3 4B Instruct | 1.98 tok/s | 1.58 tok/s | 1.46 tok/s | 6.39 tok/s | completed |
| Phi-4 Mini | 2.10 tok/s | 1.64 tok/s | 1.48 tok/s | 6.40 tok/s | completed |
| Gemma 3 4B | 2.13 tok/s | 1.64 tok/s, patched text-only artifact | GPU hang | 5.54 tok/s before the hang | preserved failure |
| Qwen3 8B | 0.98 tok/s | 10-minute cap | 0.84 tok/s | 6.40 tok/s | Vulkan completed |

On this system, Vulkan made prompt processing much faster and reduced recorded package peaks to 53 to 61 C. Generation throughput improved only for the two smaller Qwen models, and was lower for the 4B-class models and Qwen3 8B. The GPU path allowed the 8B benchmark to complete where the CPU benchmark reached the 10-minute cap.

## Vulkan access and failure boundary

Mesa ANV initially exposed only llvmpipe because the bench account could not access `/dev/dri/renderD128`. Adding the account to the existing `render` group allowed Intel UHD Graphics (Jasper Lake) to enumerate. No driver or safety-control change was made.

Gemma 3 4B exposed two separate issues. The Ollama GGUF was an older multimodal conversion that current llama.cpp rejected. A local text-only compatibility copy added the missing epsilon metadata, padded the vocabulary row, and removed embedded vision tensors; it produced the CPU value above. The corresponding Vulkan run then ended with fence timeouts, an i915 preemption reset, and `vk::DeviceLostError`. The system recovered and the raw kernel excerpt is retained in `results/round2/gemma3-vulkan-devicelost-dmesg.txt`.

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
- `ROUND2_PROTOCOL.md`: exact boundaries, limitations, and a clean next-run checklist.
