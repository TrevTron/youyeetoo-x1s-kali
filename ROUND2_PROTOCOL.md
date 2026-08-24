# Round 2 protocol, limits, and next-run checklist

## Completed run

- Ollama: original deterministic request, 96-token cap, 4,096-token context, temperature 0, seed 42; one cold and two warm requests for the original six models.
- llama.cpp: commit `9a286ac`, four threads, `llama-bench` synthetic `pp128/tg96`, two repetitions, CPU (`-ngl 0`) and Vulkan (`-ngl 99`) configurations.
- Safety controls present in the original runner: package-temperature sampler every two seconds, 85 C session guard, and 10-minute cap per llama.cpp run. Guards stayed stock.
- Intended GPU rule: any reset, process loss, device loss, or hang should end the Vulkan phase. The original runner checked the kernel only after the full Vulkan matrix, so that rule was not actually enforced between runs. This is a recorded protocol defect, not a clean stop-rule claim.

## Limits that must travel with the results

1. `llama-bench` did not consume the natural-language Ollama request. It generated 96 tokens after a synthetic 128-token prompt. Treat its generation throughput as a controlled microbenchmark, not a same-prompt end-to-end comparison.
2. The original main llama-bench matrix did not explicitly pass `-c 4096`; do not state that all llama.cpp rows used a frozen 4,096-token context. The later patched Gemma CPU/Vulkan investigation did pass `-c 4096` and is a separate compatibility result.
3. Two-second sampling supports the reported peaks and guard behavior, not a claim of per-second telemetry.
4. New requested-model results are single observations. `lfm2.5:latest` is mutable and must be pinned to a digest before a future comparison.
5. X1S, Pi 5, Nova, and N100 results remain non-comparable until the same model artifact, runtime, settings, cooling disclosure, and timing definition are collected on each machine.
6. A zero `llama-bench` exit status did not prove a clean Vulkan run. Qwen3 4B, Phi-4 Mini, and Qwen3 8B returned rows while their telemetry windows contained i915 reset or hang events. Treat those values as diagnostic observations only.

## Clean follow-up protocol

For a future same-request runtime comparison, use an explicit `llama-cli` invocation with the exact rendered prompt and chat template recorded beside the Ollama request. Pass `-c 4096`, `-n 96`, `-t 4`, the seed, temperature, model SHA-256, and runtime commit. Run at least three warm repetitions per backend. Save the request body, raw output, timing log, temperature telemetry, model digest, exit status, and per-run kernel delta. A new GPU run must keep the 85 C guard, monitor the kernel while that individual process is active, and stop the whole GPU phase on the first reset, hang, or device loss.
