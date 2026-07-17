# X1S CPU Inference Results

## Test conditions

- Date: 2026-07-16 PDT.
- Runtime: Ollama 0.32.1, CPU backend, one model at a time.
- Host: Youyeetoo X1S, Intel N5095, 4 cores / 4 threads, 15 GiB RAM.
- Context: 4,096 tokens.
- Prompt: identical deterministic four-sentence explanation task.
- Generation cap: 96 tokens.
- Runs: one cold and two warm requests per model.
- Sampling: one-second CPU, memory, CPU package, and NVMe telemetry.
- Safety: 15-minute request timeout and 85 C package-temperature abort.

## Throughput and latency

| Model | Cold load | Cold total | Mean warm total | Mean warm generation | Completion |
| --- | ---: | ---: | ---: | ---: | --- |
| `qwen3:0.6b` | 3.00 s | 14.82 s | 8.43 s | 6.788 tok/s | Stopped naturally at 54 tokens |
| `qwen3:1.7b` | 3.97 s | 32.87 s | 18.56 s | 3.129 tok/s | Stopped naturally at 56 tokens |
| `qwen3:4b-instruct` | 6.02 s | 76.27 s | 53.52 s | 1.824 tok/s | Reached 96-token cap |
| `phi4-mini` | 6.64 s | 69.96 s | 49.13 s | 1.991 tok/s | Reached 96-token cap |
| `gemma3:4b` | 8.23 s | 73.92 s | 50.86 s | 1.995 tok/s | Reached 96-token cap |
| `qwen3:8b` | 11.35 s | 151.59 s | 92.29 s | 0.924 tok/s | Stopped naturally at 84 tokens |

Every model produced the same response hash across all three runs. That proves
the fixed seed, zero temperature, prompt, and runtime produced repeatable output
within each model.

## Thermal and memory envelope

| Model | Peak CPU package | Peak NVMe | Minimum available RAM | Maximum sampled CPU |
| --- | ---: | ---: | ---: | ---: |
| `qwen3:0.6b` | 74 C | 35.9 C | 13,601.3 MiB | 100% |
| `qwen3:1.7b` | 77 C | 35.9 C | 12,795.1 MiB | 100% |
| `qwen3:4b-instruct` | 77 C | 35.9 C | 11,504.9 MiB | 100% |
| `phi4-mini` | 77 C | 35.9 C | 11,613.9 MiB | 100% |
| `gemma3:4b` | 77 C | 35.9 C | 11,049.4 MiB | 100% |
| `qwen3:8b` | 80 C | 35.9 C | 8,976.3 MiB | 100% |

The NVMe remained exactly at its 35.9 C idle value throughout inference. The
CPU never crossed the 85 C abort threshold, no request failed, no OOM or thermal
kernel error appeared, and no systemd unit failed. After the run, package
temperature fell from the load range back to 49 C.

The Ollama runner uses memory-mapped model data, so process RSS by itself
understates the working set. Available system RAM and `ollama ps` allocation are
the more useful signals here. Even the 8B run retained almost 9 GiB available
RAM and did not touch a memory-pressure stop condition.

## Instruction-following observation

The 96-token hardware cap also acts as a functional signal:

- 0.6B stopped cleanly but produced only two sentences instead of four.
- 1.7B produced exactly four concise sentences but omitted the requested word
  `memory`.
- Qwen3 4B, Phi-4 Mini, and Gemma 3 4B were cut off by the 96-token cap, so each
  received one 160-token-cap follow-up using the same prompt and settings.
- 8B stopped naturally, produced exactly four sentences, and included
  quantization, memory, tokens per second, and temperature.

The larger-cap follow-up resolved the truncation:

| Model | Tokens | Generation | Peak package | Result |
| --- | ---: | ---: | ---: | --- |
| `qwen3:4b-instruct` | 115 | 1.867 tok/s | 73 C | Natural stop; four complete sentences and all required concepts |
| `phi4-mini` | 134 | 1.997 tok/s | 75 C | Natural stop; four complete sentences and all required concepts |
| `gemma3:4b` | 110 | 2.008 tok/s | 76 C | Natural stop; four complete sentences and all required concepts |

The first 96-token pass remains the fair hardware comparison. The follow-up is
only an instruction-completion check and does not replace the three-run table.

## Vision probe boundary

Gemma 3 4B was also given a 1,920 x 1,080 PNG of the live Kali desktop and a
fixed three-sentence description prompt. Image preprocessing on this CPU did
not finish within the guarded 20-minute request window. The request returned no
text, the cancelled API call ended with HTTP 500, and the model was explicitly
unloaded afterward.

This is a negative result, not a stability failure. Across 1,089 one-second
samples, package temperature averaged 76.69 C and peaked at 80 C without
crossing the 85 C guard. No systemd unit failed, and the CPU cooled to 49 C
after the model was stopped. The result shows that full-resolution vision with
this model is not practical on the N5095 under the tested settings, even though
the same system handles text-only 4B inference at about 2 tokens/second.

The first vision attempt exceeded the shell argument-length limit when the
base64 image was placed directly on the command line. The corrected attempt
wrote the JSON payload to a file and used `curl --data-binary`, preserving both
the failure and the remediation as reproducible evidence.

## Synthetic all-core thermal evaluation

The separate supervised thermal test used `stress-ng 0.21.03` with four CPU
workers, the `matrixprod` method, verification enabled, a fixed 15-minute
duration, and the same 85 C automatic-abort threshold.

| Signal | Result |
| --- | ---: |
| Starting CPU package temperature | 43 C |
| Stress samples | 760 |
| Average / maximum sampled CPU | 100% / 100% |
| Average / minimum / maximum sampled frequency | 2,800 / 2,800 / 2,800 MHz |
| Average / peak CPU package temperature | 74.66 / 77 C |
| Peak NVMe temperature | 35.9 C |
| Minimum available memory | 14,609 MiB |
| Core and package throttle counters | 0 before / 0 after on all four CPUs |
| `stress-ng` result | 4 passed, 0 failed, 0 skipped |

The workload ended normally with return code zero and no thermal abort. There
was no frequency decline during sampled load, no relevant kernel event, and no
failed systemd unit. Package temperature dropped to 47-49 C within seconds of
the workload ending, and the 55 C cooldown target was reached in five seconds.

This establishes stable sustained operation under this 15-minute CPU workload
with the supplied heatsink and active fan. It is not a certification for every
ambient temperature, enclosure, workload, or multi-hour duty cycle.

## Practical first conclusion

- `qwen3:1.7b` is the strongest plausible interactive starting tier on this
  CPU, at about 3.1 generated tokens/second.
- The 4B-class models are usable for patient local batch tasks at roughly 2
  tokens/second. Phi-4 Mini and Gemma 3 4B were about 9 percent faster than the
  Qwen3 4B instruction artifact in this prompt.
- `qwen3:8b` fits comfortably and follows the instruction best, but 0.924
  tokens/second makes it an offline-quality tier rather than an interactive
  assistant on the N5095 CPU.
- The system was thermally stable both for real inference and for the separate
  supervised 15-minute all-core soak. The synthetic peak was 77 C with zero
  recorded throttle events and no frequency decline.

Raw request JSON, model manifests, response hashes, per-second telemetry, and
health logs are preserved under `logs/inference-2026-07-16/`.
Longer-cap completion evidence is under `logs/inference-followup-2026-07-16/`.
Vision evidence is under `logs/vision-probe-2026-07-16/`; the preserved first
attempt is under `logs/vision-probe-2026-07-16-attempt1/`.
Synthetic thermal evidence is under `logs/thermal-final-20260716/`.
