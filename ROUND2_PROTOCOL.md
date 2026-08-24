# Round 2 protocol, limits, and next-run checklist

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
4. The package does not retain the original CMake command, CMake cache, or complete build log. It cannot prove that the local llama.cpp build was optimized or configuration-matched.
5. Two-second sampling supports the reported peaks and guard behavior, not a claim of per-second telemetry.
6. New requested-model results are single observations. `lfm2.5:latest` is mutable and must be pinned to a digest before a future comparison.
7. X1S, Pi 5, Nova, and N100 results remain non-comparable until the same model artifact, runtime, settings, cooling disclosure, and timing definition are collected on each machine.
8. A zero `llama-bench` exit status did not prove a clean Vulkan run. Qwen3 4B, Phi-4 Mini, and Qwen3 8B returned rows while their telemetry windows contained i915 reset or hang events. Treat those values as diagnostic observations only.

## Clean follow-up protocol

For a future same-request runtime comparison, first save the exact rendered prompt and chat template. Use an explicit `llama-cli` invocation and an Ollama request that consume that same input. Match context, thread count, batch settings, seed, temperature, model SHA-256, runtime commit, and warm-state procedure. Record actual prompt and generated-token counts plus stop reasons. If the test forces a fixed token count by ignoring EOS, do so symmetrically and label it a synthetic throughput test. Otherwise allow natural EOS on both and compare repeated same-request observations without claiming the outputs had equal length. Run at least three warm repetitions per backend. Save the build command and CMake cache, request body, raw output, timing log, temperature telemetry, model digest, exit status, and per-run kernel delta. A new GPU run must keep the 85 C guard, monitor the kernel while that individual process is active, and stop the whole GPU phase on the first reset, hang, or device loss.
