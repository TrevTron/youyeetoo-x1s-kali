# X1S Idle Baseline Summary

- Window: 2026-07-16 17:44:22 through 17:59:19 PDT.
- Duration: 14 minutes 57 seconds.
- Interval: 5 seconds.
- Samples: 179 complete samples.

| Metric | Minimum | Mean | 95th percentile | Maximum |
| --- | ---: | ---: | ---: | ---: |
| CPU utilization | 0.95% | 1.69% | 3.47% | 9.69% |
| 1-minute load | 0.00 | 0.02 | 0.10 | 0.16 |
| Average CPU frequency | 766.0 MHz | 950.64 MHz | 1564.8 MHz | 2800.1 MHz |
| CPU package temperature | 40.0 C | 42.22 C | 43.0 C | 44.0 C |
| TCPU temperature | 35.0 C | 38.54 C | 42.0 C | 44.0 C |
| NVMe temperature | 35.9 C | 35.9 C | 35.9 C | 35.9 C |
| Available memory | 14699.4 MiB | 14747.07 MiB | 14761.7 MiB | 14764.4 MiB |

Fan RPM and RAPL package watts were not exposed by the current kernel/sysfs
interfaces. Their empty CSV fields mean “sensor unavailable,” not zero RPM or
zero watts.

Interpretation: the rebuilt X1S is cool and quiet at idle, with negligible CPU
load, no memory pressure, and a stable NVMe temperature. This is the reference
against which model-load and inference telemetry will be compared.

