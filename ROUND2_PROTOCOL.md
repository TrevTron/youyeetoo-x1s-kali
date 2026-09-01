# Round 2 protocol, limits, and next-run checklist

This file records the protocol and known limits behind the published Round 2
article. The same-request plan described below was later completed. Its final
method is in [`MATCHED_RETEST_PROTOCOL.md`](MATCHED_RETEST_PROTOCOL.md), and the
results are in [`RUNTIME_COMPARISON.md`](RUNTIME_COMPARISON.md).

## Completed run

- Ollama: original deterministic request, 96-token cap, 4,096-token context, temperature 0, seed 42; one cold and two warm requests for the original six models.
- llama.cpp: commit `9a286ac`, four threads, `llama-bench` synthetic `pp128/tg96`, two repetitions, CPU (`-ngl 0`) and Vulkan (`-ngl 99`) configurations.
- Safety controls present in the original runner: package-temperature sampler every two seconds, 85 C session guard, and 10-minute cap per llama.cpp run. Guards stayed stock.
- Intended GPU rule: any reset, process loss, device loss, or hang should end the Vulkan phase. The original runner checked the kernel only after the full Vulkan matrix, so that rule was not actually enforced between runs. This is a recorded protocol defect, not a clean stop-rule claim.

## Limits that must travel with the results

This completed matrix does not support an Ollama-versus-llama.cpp winner. Do
not describe either runtime as faster from these rows.

1. `llama-bench` did not consume the natural-language Ollama request. It generated 96 tokens after a synthetic 128-token prompt. Treat its generation throughput as a controlled microbenchmark, not a same-prompt end-to-end comparison.
2. Ollama's `num_predict=96` was a ceiling. Qwen3 0.6B, 1.7B, and 8B stopped after 54, 56, and 84 generated tokens. Do not describe the two harnesses as using the same output length.
3. The original main llama-bench matrix did not explicitly pass `-c 4096`; do not state that all llama.cpp rows used a frozen 4,096-token context. The later patched Gemma CPU/Vulkan investigation did pass `-c 4096` and is a separate compatibility result.
4. The original public package did not retain the CMake command, cache, or complete build log. The private record was later recovered and showed a Release/O3, OpenMP, SSE4.2, Vulkan build with conservative `GGML_NATIVE=OFF`.
5. Two-second sampling supports the reported peaks and guard behavior, not a claim of per-second telemetry.
6. New requested-model results are single observations. `lfm2.5:latest` is mutable and must be pinned to a digest before a future comparison.
7. X1S, Pi 5, Nova, and N100 results remain non-comparable until the same model artifact, runtime, settings, cooling disclosure, and timing definition are collected on each machine.
8. A zero `llama-bench` exit status did not prove a clean Vulkan run. Qwen3 4B, Phi-4 Mini, and Qwen3 8B returned rows while their telemetry windows contained i915 reset or hang events. Treat those values as diagnostic observations only.

## Clean follow-up protocol, later completed

The planned comparison saved the raw prompt, matched context, thread and batch
settings, seed, sampler, model SHA-256, cache behavior, and 96-token output. It
used the Ollama and llama.cpp server APIs, retained three measured repetitions
per backend, and saved build, request, output, timing, temperature, artifact,
exit-status, and per-run kernel records. See
[`MATCHED_RETEST_PROTOCOL.md`](MATCHED_RETEST_PROTOCOL.md) for the method that
actually ran.
