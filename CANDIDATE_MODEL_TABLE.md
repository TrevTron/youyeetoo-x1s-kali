# Follow-up model candidates

This is a planning table, not a benchmark claim. The board has 16 GB installed RAM and limited NVMe capacity. Any new model download or device benchmark requires a separate approval.

| Candidate | Status in round 2 | Next requirement |
| --- | --- | --- |
| Gemma 3n E2B | Measured as `gemma3n:e2b`, 3.24 tok/s | Pin digest before rerunning; this is not Gemma 4 E2B |
| Gemma 4 E2B and E4B | Not measured | Official Ollama tags exist; each requires a separate download and guarded CPU run |
| Granite 4 Tiny-H, 7B-A1B | Measured as `granite4:tiny-h`, 5.43 tok/s | Repeat with a pinned digest |
| Granite 4 Micro-H | Not measured | Pull only after approval |
| LFM2.5 | Measured as `lfm2.5:latest`, 4.95 tok/s | Identify and pin the exact variant |
| Qwen3.5 0.8B | Measured as official Ollama Q8_0 tag, 10.44 tok/s warm average | Completed; blob digest and raw rows retained |
| Qwen3.5 2B | Measured as official Ollama Q8_0 tag, 4.89 tok/s warm average | Completed; blob digest and raw rows retained |
| Ling-mini-2.0 IQ4_XS | Not measured | Manual GGUF source, license, hash, and fit check |
| BitCPM 1B or ternary 8B | Not measured | Verify runtime support and model license first |
| Stitched-Qwen MoE | Not measured | Identify a maintained artifact and record active-parameter behavior |
| Nanbeige4.1 3B | Not measured | Pin one licensed Q4 artifact before pulling |
| Awa 1.5B | Not measured | Identify the exact requested repository and supported artifact |

Do not rank model quality from the round-2 throughput observations. The study did not include a task-quality evaluation.
