# Round 2 protocol, limits, and next-run checklist

## Completed run

- Ollama: original deterministic request, 96-token cap, 4,096-token context, temperature 0, seed 42; one cold and two warm requests for the original six models.
- llama.cpp: commit `9a286ac`, four threads, `llama-bench` synthetic `pp128/tg96`, two repetitions, CPU (`-ngl 0`) and Vulkan (`-ngl 99`) configurations.
- Safety: package-temperature sampler every two seconds, 85 C session guard, 10-minute cap per llama.cpp run. Any GPU reset, process loss, device loss, or hang ended the Vulkan phase. Guards stayed stock.

## Limits that must travel with the results

1. `llama-bench` did not consume the natural-language Ollama request. It generated 96 tokens after a synthetic 128-token prompt. Treat its generation throughput as a controlled microbenchmark, not a same-prompt end-to-end comparison.
2. The original main llama-bench matrix did not explicitly pass `-c 4096`; do not state that all llama.cpp rows used a frozen 4,096-token context. The later patched Gemma CPU/Vulkan investigation did pass `-c 4096` and is a separate compatibility result.
3. Two-second sampling supports the reported peaks and guard behavior, not a claim of per-second telemetry.
4. New requested-model results are single observations. `lfm2.5:latest` is mutable and must be pinned to a digest before a future comparison.
5. X1S, Pi 5, Nova, and N100 results remain non-comparable until the same model artifact, runtime, settings, cooling disclosure, and timing definition are collected on each machine.

## Clean follow-up protocol

For a future same-request runtime comparison, use an explicit `llama-cli` invocation with the exact rendered prompt and chat template recorded beside the Ollama request. Pass `-c 4096`, `-n 96`, `-t 4`, the seed, temperature, model SHA-256, and runtime commit. Run at least three warm repetitions per backend. Save the request body, raw output, timing log, temperature telemetry, model digest, and exit status. A new run must keep the 85 C guard and stop on any GPU reset or device loss.
