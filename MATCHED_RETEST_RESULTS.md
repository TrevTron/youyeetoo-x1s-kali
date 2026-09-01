# Youyeetoo X1S matched retest results

Updated: 2026-08-31

Round 2 started with a simple question from my first LocalLLaMA thread: what
happens if I build llama.cpp myself and use the N5095's Intel GPU?

The answer needed more work than my first draft admitted. I initially compared
an Ollama API request with a synthetic `llama-bench` job. Both sets of numbers
were real, but they were not the same job. I deleted that Reddit post and reran
the CPU comparison with the same prompt, GGUF, context, sampler, thread count,
batch settings, and output length in both runtimes.

The system under test was one open-bench Youyeetoo X1S with a Celeron N5095,
16 GB RAM, the supplied heatsink and fan, Kali 2025.4, kernel
`6.16.8+kali-amd64`, Ollama 0.32.1, and llama.cpp commit
`9a286ac98d2cab74231bd3f1fc3f2b8bdf05422e`. I did not measure ambient
temperature or wall power.

## Ollama and llama.cpp, corrected CPU comparison

I recovered and audited the original llama.cpp build. It was a Release build
with `-O3`, OpenMP, SSE4.2, and Vulkan. It was conservative because
`GGML_NATIVE=OFF`, but it was not a debug or unoptimized build. For the corrected
comparison I rebuilt the same commit with `GGML_NATIVE=ON` and saved the full
build record and hashes.

The corrected run used the same raw prompt and content-addressed Q4_K_M GGUF,
a 4,096-token context, four CPU threads, batch and microbatch 512, deterministic
sampler settings, disabled prompt-cache reuse, and exactly 96 generated tokens.
Each runtime received one warmup and three measured requests per model.

| Exact GGUF | Native llama.cpp | Ollama 0.32.1 | Difference |
| --- | ---: | ---: | ---: |
| Qwen3 0.6B Q4_K_M | 6.725 tok/s | 7.809 tok/s | Ollama +16.1% |
| Qwen3 1.7B Q4_K_M | 2.852 tok/s | 3.321 tok/s | Ollama +16.5% |
| Qwen3 4B Instruct Q4_K_M | 1.484 tok/s | 2.002 tok/s | Ollama +34.9% |
| Phi-4 Mini Q4_K_M | 1.570 tok/s | 2.072 tok/s | Ollama +32.0% |

All 24 measured requests completed, produced the required token counts, stayed
within the thermal guard, and had clean kernel windows. The prompt counts
matched at 71 tokens for Qwen and 70 for Phi. Output was deterministic within
each runtime. The runtimes did not produce identical greedy text, and that fact
is retained in the parity record.

This result is narrower than the deleted headline. On this board, with these
four files and these controls, Ollama's bundled CPU runner reported higher
internal generation throughput. This is not a universal Ollama-versus-llama.cpp
rule. It is what Ollama 0.32.1 and source commit `9a286ac` did on this X1S.

Ollama unloaded after each request while the standalone llama.cpp server stayed
resident for its three-request block. I therefore compare the internal prompt
and generation rates, not total wall-clock latency. The complete method is in
[`RUNTIME_COMPARISON.md`](RUNTIME_COMPARISON.md).

## What zero GPU layers actually did

The first CPU-versus-Vulkan table hid another important detail. With Vulkan
visible, `--n-gpu-layers 0` still allowed llama.cpp to move host operations to
the GPU. That is not pure CPU and it is not conventional layer-split offload.

I reran Qwen3 0.6B and 1.7B in three explicit modes with one native binary and
one pp128/tg96 workload:

| Model | Mode | Prompt processing | Generation | Peak package |
| --- | --- | ---: | ---: | ---: |
| Qwen3 0.6B | True CPU | 10.666 tok/s | 7.397 tok/s | 81 C |
| Qwen3 0.6B | Zero-layer mixed host-op | 34.586 tok/s | 7.425 tok/s | 80 C |
| Qwen3 0.6B | Full Vulkan | 37.350 tok/s | 8.593 tok/s | 57 C |
| Qwen3 1.7B | True CPU | 3.893 tok/s | 2.986 tok/s | 84 C |
| Qwen3 1.7B | Zero-layer mixed host-op | 12.366 tok/s | 2.997 tok/s | 83 C |
| Qwen3 1.7B | Full Vulkan | 12.879 tok/s | 3.462 tok/s | 58 C |

Full Vulkan processed the prompt 3.50 and 3.31 times faster than true CPU.
Generation improved 16.2% and 15.9%, and the recorded package peaks were 24 C
and 26 C lower. The mixed mode delivered most of the prompt-processing gain but
almost none of the generation gain.

## The larger Vulkan failures were real

The larger-model rows are diagnostic results, not clean benchmark wins:

| Model | What happened |
| --- | --- |
| Qwen3 4B | Reached an i915 reset timeout during its run window |
| Phi-4 Mini | Coincided with an i915 GPU hang even though `llama-bench` returned 0 |
| Qwen3 8B | Coincided with an i915 GPU hang even though `llama-bench` returned 0 |
| Gemma 3 4B | Fence and preemption timeouts, an i915 reset, then `vk::DeviceLostError` |

The kernel recovered the GPU. I did not disable the watchdog or forced-timeout
recovery to make the table look cleaner, and I stopped before attempting a
larger split-offload matrix. These events happened in the recorded run windows
and are backed by retained kernel evidence. I did not run enough controlled
repetitions to publish a failure rate, so I do not call the hangs formally
reproducible.

Gemma exposed a separate compatibility problem before the Vulkan failure. The
older Ollama multimodal conversion was rejected by current llama.cpp. The
included patch utility creates a new text-only derivative by adding required
metadata, padding the vocabulary row, and removing vision tensors. It never
overwrites the source file. The derived file completed a true-CPU pp128/tg96
run at 2.172 prompt tok/s and 1.624 generation tok/s. That conversion is not a
fix for the later GPU device loss.

## Community follow-up

The requests from the first thread now have their own audited result set. It
includes Qwen3.5 0.8B, 2B, and 9B, Gemma 4 E2B and E4B, Ling-mini-2.0 IQ4_XS,
Granite 4 Tiny-H, LFM2.5, Gemma 3n E2B, BitCPM-CANN 1B TQ2_0, and an MTP depth
sweep. Models I could not identify or test cleanly remain listed as not run.

See [`FOLLOWUP_RESULTS.md`](FOLLOWUP_RESULTS.md),
[`MTP_RESULTS.md`](MTP_RESULTS.md), and
[`CANDIDATE_MODEL_TABLE.md`](CANDIDATE_MODEL_TABLE.md).

## Evidence map

- [`results/corrected/matched-runtime-summary.csv`](results/corrected/matched-runtime-summary.csv)
  contains the corrected CPU runtime aggregates.
- [`results/corrected/three-mode-summary.csv`](results/corrected/three-mode-summary.csv)
  contains true CPU, mixed host-op, and full Vulkan results.
- [`results/corrected/compatibility-summary.csv`](results/corrected/compatibility-summary.csv)
  contains the true-CPU BitCPM and derived Gemma rows.
- [`results/round2/gemma3-vulkan-devicelost-dmesg.txt`](results/round2/gemma3-vulkan-devicelost-dmesg.txt)
  preserves the sanitized Gemma kernel failure.
- [`MATCHED_RETEST_PROTOCOL.md`](MATCHED_RETEST_PROTOCOL.md) records the final controls and
  safety rules.

Youyeetoo supplied the X1S and 128 GB NVMe. The testing and conclusions are my
own.
