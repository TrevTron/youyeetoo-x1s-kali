# Follow-up model candidates

This is a planning table, not a benchmark claim. The board has 16 GB installed RAM and limited NVMe capacity. Any new model download or device benchmark requires a separate approval.

| Candidate | Status in round 2 | Next requirement |
| --- | --- | --- |
| Gemma 3n E2B | Measured as `gemma3n:e2b`, 3.24 tok/s | Pin digest before rerunning; this is not Gemma 4 E2B |
| Gemma 4 E2B | Measured as official Ollama Q4_K_M tag, 3.38 tok/s warm average | Completed; blob digest and raw rows retained |
| Gemma 4 E4B | Measured as official Ollama Q4_K_M tag, 1.78 tok/s warm average | Completed; blob digest and raw rows retained |
| Granite 4 Tiny-H, 7B-A1B | Measured as `granite4:tiny-h`, 5.43 tok/s | Repeat with a pinned digest |
| Granite 4 Micro-H | Not measured | Pull only after approval |
| LFM2.5 | Measured as `lfm2.5:latest`, 4.95 tok/s | Identify and pin the exact variant |
| Qwen3.5 0.8B | Measured as official Ollama Q8_0 tag, 10.44 tok/s warm average | Completed; blob digest and raw rows retained |
| Qwen3.5 2B | Measured as official Ollama Q8_0 tag, 4.89 tok/s warm average | Completed; blob digest and raw rows retained |
| Ling-mini-2.0 IQ4_XS | Not measured | Manual GGUF source, license, hash, and fit check |
| BitCPM-CANN 1B TQ2_0 | llama.cpp CPU: 13.30 prompt tok/s and 8.63 generation tok/s | Official Apache-2.0 GGUF; Ollama 0.32.1 rejected the same file with a tensor size overflow |
| BitCPM ternary 8B | Not measured | Separate 2.4 GB artifact; do not infer its performance from the 1B-class result |
| Stitched-Qwen MoE | Not measured | Identify a maintained artifact and record active-parameter behavior |
| Nanbeige4.1 3B | Not measured | Pin one licensed Q4 artifact before pulling |
| Awa 1.5B | Not measured | Identify the exact requested repository and supported artifact |

Do not rank model quality from the round-2 throughput observations. The study did not include a task-quality evaluation.
