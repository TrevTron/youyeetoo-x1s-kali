# X1S community follow-up results

Date: 2026-08-23

These are CPU Ollama measurements added after the round-2 evidence audit. They
use the same natural-language prompt, 4,096-token context, 96-token generation
cap, temperature 0, seed 42, and 85 C package-temperature guard as the round-2
Ollama rerun. Each model received one cold request followed by two warm
requests. The published warm figure is the arithmetic mean of runs 2 and 3.

## Qwen3.5 results

| Official Ollama tag | Quantization | Cold generation | Warm run 2 | Warm run 3 | Warm average | Peak package |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `qwen3.5:0.8b` | Q8_0 | 10.43 tok/s | 10.37 tok/s | 10.51 tok/s | 10.44 tok/s | 70 C |
| `qwen3.5:2b` | Q8_0 | 4.97 tok/s | 4.91 tok/s | 4.87 tok/s | 4.89 tok/s | 75 C |

The response hash was identical across all three requests for each model. The
0.8B tag is the fastest text-generation result measured in this X1S work. That
does not make it a quality winner. These are throughput measurements, and the
Q8_0 weights are not a quantization-matched comparison with every older tag.

Raw per-run timings and response hashes are in
`results/followup/qwen3.5-ollama.csv`. The exact Ollama model blob digests are
in `results/followup/model-artifacts.txt`.

## Requests that remain separate

- Gemma 4 E2B and E4B are different models from the measured `gemma3n:e2b`.
- Split Vulkan offload was not run after the audit reconstructed i915 resets
  and hangs in the larger full-offload rows. The safety boundary takes priority.
- Ling-mini-2.0 IQ4_XS is an 8.8 GB third-party quantization and was not pulled
  without a completed artifact and time-to-shutdown fit check.
- BitCPM, a stitched-Qwen MoE, and Awa require an exact maintained artifact,
  license, and runtime-support check before a benchmark claim.
- A matched N100, Raspberry Pi 5, and Nova comparison still requires the same
  model artifact and method on each physical board.

These statuses are not failures disguised as measurements. They define exactly
what the published result package does and does not answer.
