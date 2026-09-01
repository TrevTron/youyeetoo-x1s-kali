# X1S community follow-up results

Updated: 2026-08-31

These are the model requests I could answer cleanly after the first X1S post.
I kept unlike prompts, runtimes, and quantizations out of one fake leaderboard.
The table tells you what each number actually is.

## Official Ollama model runs

The first four rows used one cold request followed by two warm requests with the
same natural-language prompt, 4,096-token context, 96-token cap, temperature 0,
seed 42, and standard 85 C guard. The Qwen3.5 9B row used five controlled
prompts and is reported separately as their average.

| Official tag | Quantization | Published generation rate | Peak package | What the number means |
| --- | --- | ---: | ---: | --- |
| `qwen3.5:0.8b` | Q8_0 | 10.44 tok/s | 70 C | Average of warm requests 2 and 3 |
| `qwen3.5:2b` | Q8_0 | 4.89 tok/s | 75 C | Average of warm requests 2 and 3 |
| `gemma4:e2b` | Q4_K_M | 3.38 tok/s | 77 C | Average of warm requests 2 and 3 |
| `gemma4:e4b` | Q4_K_M | 1.78 tok/s | 78 C | Average of warm requests 2 and 3 |
| `qwen3.5:9b` | Q4_K_M | 1.110 tok/s | 82 C | Five-prompt average, no MTP |

The response was deterministic across the three requests for each of the first
four models. The 0.8B tag is the fastest text-generation result in this X1S
work, but throughput does not answer which model gives the best response.

## Ling-mini-2.0 IQ4_XS

I used the exact file requested in the thread: Bartowski's IQ4_XS quantization
from revision `8be84a0f472797118167aac86b56ca903561a73b`. The 8,803,304,640-byte GGUF
has SHA-256
`a72d86d4cb4fedd940e34c08d008bb5cda42db80ce5c6bc5f9494e854a3d742d`.

| Threads | Prompt processing | Generation | Peak package | Guard | Result |
| ---: | ---: | ---: | ---: | ---: | --- |
| 3 | 4.375 tok/s | 3.091 tok/s | 74 C | 85 C | Clean, five repetitions |
| 4 | 5.817 tok/s | 4.083 tok/s | 85 C | 90 C | Clean, five repetitions |

The first four-thread attempt stopped at the standard 85 C guard. I repeated
only that missing setting with a 90 C abort, a 5.9% increase. It completed at
an 85 C sampled peak with a clean
kernel window. The timeout and kernel-error checks were unchanged. The
four-thread result is 32.1% faster in generation than the clean three-thread
row, so it is the selected Ling result.

## MTP did not help this N5095

I tested draft depths 1 through 4 on Qwen3.5 0.8B, Qwen3.5 2B, and Gemma 4 E2B.
The collector explicitly disabled thinking, verified Ollama's `draft-mtp`
runner and nonzero draft tokens in the service journal, and required matching
token counts and output hashes between MTP off and on.

Every tested depth was slower with MTP enabled. Depth 1 was the least costly,
but it still reduced generation throughput by 46.7% on Qwen3.5 0.8B, 22.8% on
Qwen3.5 2B, and 30.7% on Gemma 4 E2B. Increasing the draft depth made the loss
larger. The full table and method are in [`MTP_RESULTS.md`](MTP_RESULTS.md).

This is an N5095 result for Ollama 0.32.1 and these artifacts. It is not a claim
that MTP is useless on newer CPUs or GPUs.

## BitCPM and Gemma 3 compatibility

OpenBMB's official `bitcpm4-1b-tq2_0.gguf` has SHA-256
`2394c15cbea2181b72bfb4215d8417d8d1f2f6214069da2d01fde32ce3b13fce`.
Ollama 0.32.1 rejected it before inference with a tensor-size overflow. The same
file completed a true-CPU llama.cpp pp128/tg96 test at 13.013 prompt tok/s and
8.584 generation tok/s, with five repetitions and a 76 C peak.

The older Gemma 3 Ollama artifact required a separate text-only compatibility
copy before current llama.cpp would load it. The original file was left
untouched. The derived copy has SHA-256
`510408e8043ca1c741fe9a16088d47e8fa0d016033c6acf0c50c50c7c93b6530`
and completed the same true-CPU workload at 2.172 prompt tok/s and 1.624
generation tok/s, with five repetitions and an 81 C peak. That patch is a model
conversion aid, not a Vulkan fix.

## Earlier requested-model observations

These single Ollama observations came from the first follow-up pass:

| Model | Generation | Peak package | Note |
| --- | ---: | ---: | --- |
| Granite 4 Tiny-H | 5.43 tok/s | 79 C | Ollama tag used during the pass |
| LFM2.5 | 4.95 tok/s | 80 C | Mutable `latest` tag was not content-pinned |
| Gemma 3n E2B | 3.24 tok/s | 80 C | This is not Gemma 4 E2B |

## Requests I did not turn into claims

I did not produce trustworthy measurements for Granite 4 Micro-H, BitCPM
ternary 8B, stitched-Qwen MoE variants, Nanbeige4.1 3B, or Awa 1.5B. A matched
N100, N150, Raspberry Pi 5, or IndieDroid Nova comparison also still needs the
same artifact and method on each physical board.

Those gaps are listed in [`CANDIDATE_MODEL_TABLE.md`](CANDIDATE_MODEL_TABLE.md)
instead of being filled with guesses.
