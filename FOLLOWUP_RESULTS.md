# X1S community follow-up results

Date: 2026-08-23

These are CPU Ollama measurements added after the round-2 evidence audit. They
use the same natural-language prompt, 4,096-token context, 96-token generation
cap, temperature 0, seed 42, and 85 C package-temperature guard as the round-2
Ollama rerun. Each model received one cold request followed by two warm
requests. The published warm figure is the arithmetic mean of runs 2 and 3.

## Official candidate results

| Official Ollama tag | Quantization | Cold generation | Warm run 2 | Warm run 3 | Warm average | Peak package |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `qwen3.5:0.8b` | Q8_0 | 10.43 tok/s | 10.37 tok/s | 10.51 tok/s | 10.44 tok/s | 70 C |
| `qwen3.5:2b` | Q8_0 | 4.97 tok/s | 4.91 tok/s | 4.87 tok/s | 4.89 tok/s | 75 C |
| `gemma4:e2b` | Q4_K_M | 3.36 tok/s | 3.38 tok/s | 3.38 tok/s | 3.38 tok/s | 77 C |
| `gemma4:e4b` | Q4_K_M | 1.78 tok/s | 1.78 tok/s | 1.78 tok/s | 1.78 tok/s | 78 C |

The response hash was identical across all three requests for each model. Gemma
4 E2B and E4B stopped naturally after 66 and 82 generated tokens; the Qwen
requests reached the 96-token cap. The 0.8B tag is the fastest text-generation
result measured in this X1S work. That does not make it a quality winner. These
are throughput measurements, and the Q8_0 Qwen weights are not a
quantization-matched comparison with every older tag.

Raw per-run timings and response hashes are in
`results/followup/official-candidates-ollama.csv`. The exact Ollama model blob digests are
in `results/followup/model-artifacts.txt`.

## BitCPM runtime compatibility result

I also tested OpenBMB's official Apache-2.0
[`bitcpm4-1b-tq2_0.gguf`](https://huggingface.co/openbmb/BitCPM-CANN-1B-gguf).
Ollama 0.32.1 downloaded and verified the file, but rejected it before inference
with `tensor "blk.0.attn_k.weight" size overflow`. The same file loaded in
llama.cpp commit `9a286ac` with CPU execution and zero GPU layers.

| Runtime and method | Prompt processing | Generation | Peak package | Status |
| --- | ---: | ---: | ---: | --- |
| llama.cpp, 128 prompt tokens, 96 generated tokens, 2 repetitions | 13.30 tok/s | 8.63 tok/s | 68 C | Clean |
| Ollama 0.32.1 | Not run | Not run | Not applicable | Model-load failure |

llama.cpp reported 1.62B parameters and identified the 550 MB artifact as
TQ2_0 at 2.06 bits per weight. This is a llama.cpp microbenchmark, not the
natural-language Ollama request used in the table above, so it belongs as a
separate compatibility and throughput result. The sanitized raw row is in
`results/followup/bitcpm-1b-tq2_0-llamacpp.csv`.

## What is still untested

- Gemma 4 E2B and E4B are now measured separately. E2B is different from the
  earlier `gemma3n:e2b` result.
- Split Vulkan offload was not run after the audit reconstructed i915 resets
  and hangs in the larger full-offload rows. The safety boundary takes priority.
- The Ling-mini-2.0 IQ4_XS file I found is an 8.8 GB third-party quantization.
  I did not have enough verified provenance and testing time to include it.
- BitCPM 1B TQ2_0 is now tested in llama.cpp. The 8B artifact remains separate.
  A stitched-Qwen MoE and Awa still need an exact maintained artifact, license,
  and runtime-support check before a benchmark claim.
- A matched N100, Raspberry Pi 5, and Nova comparison still requires the same
  model artifact and method on each physical board.

I am leaving these gaps visible because they need their own artifacts, hardware,
or test pass before they can support a benchmark claim.
