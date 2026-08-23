# Follow-up model candidates

This is a planning table, not a benchmark claim. The board has 16 GB installed RAM and limited NVMe capacity. Any new model download or device benchmark requires a separate approval.

| Candidate | Status in round 2 | Next requirement |
| --- | --- | --- |
| Gemma 3n E2B | Measured as `gemma3n:e2b`, 3.24 tok/s | Pin digest before rerunning |
| Gemma 3n E4B | Not measured | Confirm storage and exact tag |
| Granite 4 Tiny-H, 7B-A1B | Measured as `granite4:tiny-h`, 5.43 tok/s | Repeat with a pinned digest |
| Granite 4 Micro-H | Not measured | Pull only after approval |
| LFM2.5 | Measured as `lfm2.5:latest`, 4.95 tok/s | Identify and pin the exact variant |
| Qwen3.5 0.8B and 2B | Not measured | Official Qwen releases exist; obtain a supported, pinned local artifact before any claim |
| Ling-mini-2.0 IQ4_XS | Not measured | Manual GGUF source, license, hash, and fit check |
| BitCPM 1B or ternary 8B | Not measured | Verify runtime support and model license first |
| Stitched-Qwen MoE | Not measured | Identify a maintained artifact and record active-parameter behavior |

Do not rank model quality from the round-2 throughput observations. The study did not include a task-quality evaluation.
