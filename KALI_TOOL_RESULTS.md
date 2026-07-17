# Kali Professional Tool Compatibility Results

## Purpose and safety boundary

This matrix tests the original native-x86 claim at the compatibility layer:
whether representative Kali tools are installed, start correctly, and can use
the X1S CPU and local interfaces. It is not a claim that x86 makes every tool
faster than ARM, and it is not an offensive test.

The only network scan was a TCP connect scan of `127.0.0.1` ports 22 and 11434.
No external target, exploitation, credential attack, password-cracking target,
wireless capture, or injection was used.

## Results

| Tool or check | Version / observed result | Outcome |
| --- | --- | --- |
| Nmap | 7.95, x86_64; loopback scan completed in 0.04 s | Pass |
| Metasploit Framework | Console 6.4.99-dev started and exited in 3.591 s | Pass |
| TShark / dumpcap | Wireshark 4.6.0; enumerated Ethernet, VPN, loopback, Bluetooth-monitor, netfilter, and D-Bus capture sources | Pass |
| John the Ripper | Four OpenMP threads; Raw-SHA256 built-in benchmark at 16.652M c/s real | Pass |
| Hashcat | 7.1.2; PoCL OpenCL detected the N5095 as a four-processor CPU device | Pass |
| Aircrack-ng | 1.7 help/startup path loaded | Pass |
| SQLmap | 1.9.11 stable printed its version | Pass with upstream-version warning |
| Hydra | 9.6 printed full version and help output | Pass; help exits 255 by CLI convention |
| Nikto | 2.5.0 printed its version | Pass |
| Gobuster | 3.8 amd64 printed version and build information | Pass |
| ffuf | 2.1.0-dev printed its version | Pass |
| NetExec | 1.4.0 completed first-run database/config initialization and printed its version | Pass; version command exits 1 by CLI convention |

Both `kali-linux-default` and `kali-tools-top10` were installed. All tested
tool packages were present. Twelve of fourteen raw checks exited zero. Hydra
and NetExec produced the intended valid output with their nonzero CLI exit
conventions; neither crashed or timed out.

No relevant OOM, thermal, throttling, segmentation-fault, or NVMe-critical
kernel event appeared during the matrix, and no systemd unit was failed after
it completed.

## What this does and does not establish

The result supports the practical part of the native-x86 proposition: a stock
Kali amd64 installation provides the common professional toolchain without an
architecture workaround, and CPU-oriented tools can see all four cores through
OpenMP or OpenCL.

This matrix does not benchmark exploit throughput, wireless monitor mode,
packet injection, GPU acceleration, or performance against a Raspberry Pi 5.
Those require authorized targets, compatible radios or accelerators, and a
matched cross-platform method. The public article should keep those boundaries
explicit.

Raw results, package versions, command output, and health checks are preserved
under `logs/kali-tools-final-20260716/`.
