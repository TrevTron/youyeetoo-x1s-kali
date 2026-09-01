# Additional model status

Updated: 2026-09-01

This table tracks the additional model candidates considered for the X1S. It
is not a quality ranking. Rows with different prompts, runtimes, or
quantizations are not treated as a head-to-head model comparison.

## Completed

| Model | Exact artifact used | Measured outcome |
| --- | --- | --- |
| Qwen3.5 0.8B | Official Ollama Q8_0 tag | 10.44 tok/s in the original warm pair; 11.16 tok/s across the five MTP-off control prompts |
| Qwen3.5 2B | Official Ollama Q8_0 tag | 4.89 tok/s in the original warm pair; 5.12 tok/s across the five MTP-off control prompts |
| Qwen3.5 9B | Official Ollama Q4_K_M tag, blob SHA-256 `dec52a44569a2a25341c4e4d3fee25846eed4f6f0b936278e3a3c900bb99d37c` | 1.110 tok/s five-prompt average, 82 C maximum |
| Gemma 4 E2B | Official Ollama Q4_K_M tag | 3.38 tok/s in the original warm pair; MTP depths 1 through 4 were all slower than MTP off |
| Gemma 4 E4B | Official Ollama Q4_K_M tag | 1.78 tok/s original warm average |
| Ling-mini-2.0 IQ4_XS | Bartowski revision `8be84a0f472797118167aac86b56ca903561a73b`, SHA-256 `a72d86d4cb4fedd940e34c08d008bb5cda42db80ce5c6bc5f9494e854a3d742d` | 4.083 generation tok/s at four threads, pp128/tg96, five repetitions; 85 C peak under the disclosed 90 C guard |
| Granite 4 Tiny-H | Ollama tag used during the original follow-up | 5.43 tok/s single observation |
| LFM2.5 | Mutable `lfm2.5:latest` tag used during the original follow-up | 4.95 tok/s single observation; the tag was not content-pinned in that pass |
| Gemma 3n E2B | `gemma3n:e2b` | 3.24 tok/s single observation; this is not Gemma 4 E2B |
| BitCPM-CANN 1B TQ2_0 | Official OpenBMB GGUF, SHA-256 `2394c15cbea2181b72bfb4215d8417d8d1f2f6214069da2d01fde32ce3b13fce` | Ollama 0.32.1 rejected the file with a tensor-size overflow; true-CPU llama.cpp measured 13.013 prompt and 8.584 generation tok/s, 76 C peak |

## Not run

The following suggestions did not receive a trustworthy result in this round:

- Granite 4 Micro-H
- BitCPM ternary 8B
- stitched-Qwen MoE variants
- Nanbeige4.1 3B
- Awa 1.5B

They are listed so the original requests are not silently erased. No
performance or compatibility claim is made for them.
