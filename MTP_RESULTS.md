# MTP on the Celeron N5095

Updated: 2026-09-01

I tested whether Ollama's multi-token prediction path could give the newer
Qwen3.5 and Gemma 4 models a useful speed boost on the X1S. The sweep covers
draft depths 1 through 4 instead of treating one default depth as representative.

## What I tested

The Qwen3.5 0.8B and 2B tags use their Ollama-provided MTP path. Gemma 4 E2B
used Google's official `gemma-4-E2B-it-assistant` model converted to GGUF and
registered as a local assistant model. The assistant source revision is
`2d874ef7d29f9a30599a1e4b3c1cbc9595f005df`, and the resulting GGUF SHA-256 is
`0641fbd619ff0f53f17ceb25694c2c0cd307d4d3e390e77378b1a9e175f5bb7c`.

Each pair used the same prompt, 4,096-token context, four CPU threads, batch and
microbatch 512, deterministic sampler settings, and exactly 96 generated
tokens. Thinking was explicitly disabled. The collector records both response
fields and hashes the canonical `[thinking, response]` pair. Every completed
MTP-on row matched its MTP-off token count and output hash.

The Ollama journal proves that the on rows launched with
`--spec-type draft-mtp`, the requested draft depth, and nonzero generated draft
tokens. This was real MTP activity, not a model-name or API-option assumption.

## Depth sweep

| Model | Draft depth | MTP off | MTP on | Change | Peak with MTP | Result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Qwen3.5 0.8B | 1 | 11.34 tok/s | 6.04 tok/s | -46.7% | 75 C | clean |
| Qwen3.5 0.8B | 2 | 11.49 tok/s | 4.02 tok/s | -65.0% | 79 C | clean |
| Qwen3.5 0.8B | 3 | 11.21 tok/s | 3.13 tok/s | -72.1% | 77 C | clean |
| Qwen3.5 0.8B | 4 | 11.16 tok/s | 2.62 tok/s | -76.5% | 79 C | five-prompt average, clean |
| Qwen3.5 2B | 1 | 4.89 tok/s | 3.78 tok/s | -22.8% | 77 C | clean |
| Qwen3.5 2B | 2 | 5.15 tok/s | 2.85 tok/s | -44.7% | 79 C | clean |
| Qwen3.5 2B | 3 | 4.85 tok/s | 2.60 tok/s | -46.5% | 80 C | clean |
| Qwen3.5 2B | 4 | 5.12 tok/s | 1.52 tok/s | -70.3% | 79 C | five-prompt average, clean |
| Gemma 4 E2B | 1 | 3.27 tok/s | 2.27 tok/s | -30.7% | 84 C | clean |
| Gemma 4 E2B | 2 | 3.36 tok/s | 1.96 tok/s | -41.6% | 84 C | clean at 90 C guard |
| Gemma 4 E2B | 3 | 3.35 tok/s | 1.47 tok/s | -56.0% | 86 C | clean at 90 C guard |
| Gemma 4 E2B | 4 | 3.40 tok/s | 1.33 tok/s | -60.8% | 84 C | five-prompt average, clean |

Depth 4 received five measured prompts per variant. Depths 1 through 3 were a
bounded one-prompt sweep using the same first prompt. The one-prompt rows are
configuration screening results, not a five-prompt performance distribution.

Gemma depths 2 and 3 first reached the standard 85 C guard. I repeated those
two missing configurations once at a 90 C abort, a 5.9% increase. Intel
specifies 105 C Tjunction for the N5095. Both rows completed, the kernel
windows were clean, and the relaxed ceiling is
shown rather than blended into the standard protocol.

## What I conclude

MTP did not help these models on this N5095 setup. Depth 1 was the least costly
setting for all three, but it was still 22.8 to 46.7 percent slower than MTP
off. Increasing the depth made generation progressively slower. The draft path
was active and accepted tokens, so the result points to draft overhead
outweighing the saved target work on this four-core CPU.

That conclusion is limited to Ollama 0.32.1, these model artifacts, this board,
and this short deterministic workload. It does not establish that MTP is slow
on newer CPUs or GPUs.

The official Qwen3.5 9B Q4_K_M control also completed without MTP at a
five-prompt average of 1.110 tok/s, with an 82 C maximum. It is a fit and
throughput result, not part of the MTP on/off table.

The preparation script downloads, converts, verifies, and registers the Gemma
assistant. The registration script reuses that verified converted file without
downloading it again. The collector, full depth-sweep controller, exact
aggregate rows, and guard events are in this repository:

- [`scripts/benchmark_ollama_mtp_guarded.sh`](scripts/benchmark_ollama_mtp_guarded.sh)
- [`scripts/run_mtp_depth_sweep.sh`](scripts/run_mtp_depth_sweep.sh)
- [`scripts/prepare_gemma4_e2b_mtp_guarded.sh`](scripts/prepare_gemma4_e2b_mtp_guarded.sh)
- [`scripts/register_gemma4_e2b_mtp_guarded.sh`](scripts/register_gemma4_e2b_mtp_guarded.sh)
- [`results/corrected/mtp-depth-summary.csv`](results/corrected/mtp-depth-summary.csv)
- [`results/corrected/mtp-guard-events.csv`](results/corrected/mtp-guard-events.csv)
