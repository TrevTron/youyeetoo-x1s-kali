# Matched retest result set

This directory contains the public aggregate rows from the corrected X1S work.
The full private archive also retains every request body, response, telemetry
trace, kernel window, controller log, and SHA-256 manifest.

- `matched-runtime-summary.csv` is the same-prompt, same-GGUF CPU comparison
  between Ollama 0.32.1 and the native llama.cpp server at commit `9a286ac`.
- `three-mode-summary.csv` separates true CPU, zero-layer mixed host-operation
  offload, and full Vulkan.
- `ling-mini-iq4-xs-summary.csv` contains the pinned Ling-mini result and the
  disclosed thread and thermal settings used for the final comparison.
- `mtp-depth-summary.csv` contains every completed MTP depth.
- `mtp-guard-events.csv` preserves the configurations that first stopped at
  the standard 85 C guard before the authorized 90 C repeats.
- `compatibility-summary.csv` contains the final true-CPU BitCPM and derived
  Gemma 3 compatibility rows.

The files in this directory are not interchangeable tables. Each row belongs
to the method named in its companion documentation. Read
[`RUNTIME_COMPARISON.md`](../../RUNTIME_COMPARISON.md),
[`METHODOLOGY.md`](../../METHODOLOGY.md), and
[`MATCHED_RETEST_PROTOCOL.md`](../../MATCHED_RETEST_PROTOCOL.md) before comparing values.
