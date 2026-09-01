# Matched Ollama and llama.cpp CPU comparison

Updated: 2026-08-31

Ollama, llama.cpp, and Vulkan are not three versions of the same thing. Ollama
is the application and model server I used day to day. llama.cpp is the
standalone implementation I built and pinned for this test. Vulkan is a GPU
backend I tested separately through llama.cpp.

I deleted my first Round 2 Reddit post because I had treated two different jobs
as a head-to-head runtime test. The saved measurements were real, but Ollama had
answered my normal request while `llama-bench` had used a synthetic 128-token
prompt. They also differed in output length, context handling, cache behavior,
and timing path. Those old rows remain useful as historical measurements, but
they cannot decide which CPU runtime was faster.

## The build was not a mystery build

The original build material was recovered from the X1S and audited. It used
llama.cpp commit `9a286ac98d2cab74231bd3f1fc3f2b8bdf05422e`, Release mode,
`-O3`, OpenMP, SSE4.2, and Vulkan. `GGML_NATIVE=OFF` and the unavailable AVX,
AVX2, and FMA paths were disabled deliberately for a conservative N5095 build.
That build was not unoptimized or silently falling back to debug code.

I still rebuilt the same commit with `GGML_NATIVE=ON` before the matched test.
The retained native `llama-server` SHA-256 is
`9fe2b2b0d523981b8f3f3e2d2dcf8e3fad42e53b736b59879c388b930a2f2497`.
Its CPU backend SHA-256 is
`45a4cd0841b06500bc0af216c52f6a6c66bc8d9fae122a608ffd7d718ac6ecfc`.
The guarded build script is
[`scripts/build_llama_cpp_native_guarded.sh`](scripts/build_llama_cpp_native_guarded.sh).

## Matched method

The corrected test compared Ollama 0.32.1's bundled CPU runner with the pinned
native llama.cpp server. For each model I used:

- the exact same content-addressed GGUF;
- the exact same raw prompt, without a chat template;
- a 4,096-token context;
- four CPU threads;
- batch and microbatch size 512;
- temperature 0, seed 42, top-k 1, top-p 1, min-p 0, repeat penalty 1;
- prompt-cache reuse disabled;
- exactly 96 generated tokens;
- one warmup followed by three measured requests in each runtime;
- a starting package temperature below 65 C and an 85 C stop guard;
- a separate temperature trace and kernel window for every request.

The prompt token counts matched at 71 tokens for the three Qwen models and 70
for Phi-4 Mini. Every measured request generated 96 tokens. Each runtime was
deterministic across its own three repetitions. The two runtimes produced
different greedy output, which is recorded rather than hidden. Different
revisions and CPU kernels can choose different paths even with the same model
and sampler settings, so cross-runtime text equality was not a pass condition.

## Results

| Exact GGUF | Native llama.cpp generation | Ollama generation | Ollama difference |
| --- | ---: | ---: | ---: |
| Qwen3 0.6B Q4_K_M | 6.725 tok/s | 7.809 tok/s | +16.1% |
| Qwen3 1.7B Q4_K_M | 2.852 tok/s | 3.321 tok/s | +16.5% |
| Qwen3 4B Instruct Q4_K_M | 1.484 tok/s | 2.002 tok/s | +34.9% |
| Phi-4 Mini Q4_K_M | 1.570 tok/s | 2.072 tok/s | +32.0% |

All 24 measured requests completed without a thermal abort or a matched kernel
failure. The highest sampled package temperature was 83 C.

These are the internal prompt-evaluation and generation rates reported by each
server. They are not an identical end-to-end latency comparison. Ollama was
configured to unload after every request, while the standalone llama.cpp server
remained resident for its three-request block. That difference affects load and
wall time, but not the internal generation rates in the table.

## What I conclude

On this X1S, with Ollama 0.32.1, llama.cpp commit `9a286ac`, these four GGUFs,
and the controls above, Ollama's bundled CPU runner reported higher internal
generation throughput in all four matched rows. That is the result I can defend.
It is not a universal claim that Ollama is faster than llama.cpp, and it does
not compare Vulkan with either CPU path.

The full collector is
[`scripts/benchmark_matched_runtime_guarded.sh`](scripts/benchmark_matched_runtime_guarded.sh).
The public aggregate rows are in
[`results/corrected/matched-runtime-summary.csv`](results/corrected/matched-runtime-summary.csv).
The retained evidence manifest covers the request bodies, responses, artifact
hashes, parity checks, environment record, telemetry, and kernel windows.
