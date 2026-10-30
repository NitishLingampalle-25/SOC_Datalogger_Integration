<<<<<<< HEAD
<div align="center">

# Secure RISC-V SoC Data Logger for Mission-Critical Telemetry
### Kavach / TCAS — Train Collision Avoidance System

[![RISC-V](https://img.shields.io/badge/ISA-RV32IMC-blue)](https://riscv.org/technical/specifications/)
[![Core](https://img.shields.io/badge/Core-VeeR%20EL2-informational)](https://github.com/chipsalliance/Cores-VeeR-EL2)
[![Bus](https://img.shields.io/badge/Bus-AXI4--Lite-orange)](https://developer.arm.com/documentation/ihi0022/latest/)
[![Sim](https://img.shields.io/badge/Simulator-VCS%20%2F%20Verdi-lightgrey)]()
[![Status](https://img.shields.io/badge/Status-In%20Progress-yellow)]()

</div>

---

## Table of Contents

1. [Motivation](#1-motivation)
2. [Block Diagram](#2-block-diagram)
3. [System Architecture & IPs Used](#3-system-architecture--ips-used)
4. [References](#4-references)
5. [Repository Structure](#5-repository-structure)
6. [Register Map](#6-register-map)
7. [How to Build & Run](#7-how-to-build--run)
8. [Verification Status](#8-verification-status)
9. [Challenges & Debugging](#9-challenges--debugging)
10. [Skills & Tools Demonstrated](#10-skills--tools-demonstrated)
11. [Author](#11-author)


## 1. Motivation

Modern safety-critical transportation systems — most notably India's **Train Collision Avoidance System (TCAS/Kavach)** — depend on continuous, real-time logging of operational telemetry: train speed, signal aspect, brake pipe pressure, braking commands, and driver inputs. This data is the backbone of incident forensics, regulatory compliance, and post-accident investigation.

### Why this matters in real time

- Handling continuous high-rate sensor streams purely in software forces the CPU to repeatedly service interrupts and run memory-copy/crypto routines, causing pipeline stalls and jitter — and in the worst case, dropped telemetry during exactly the burst of activity (e.g. a hard brake) that investigators need most.
- Telemetry stored without hardware-level cryptographic protection is tamper-able, which undermines its value as forensic evidence.
- A firmware hang or bus deadlock, if undetected, can silently stop logging altogether with no operator awareness.

### How this project addresses it

This SoC offloads memory transfer, encryption, and health-monitoring to dedicated autonomous hardware blocks, so the control processor never becomes the bottleneck:

- **Zero telemetry loss** under sustained sensor throughput — hardware handshaking, not CPU polling
- **Constant-time, tamper-resistant cryptography** on every logged block — hardware AES, not a software library exposed to cache-timing side channels
- **Autonomous fault isolation** — a watchdog that can force recovery even if the CPU or DMA has completely locked up, with zero software involvement

> The direct benefit: a data logger that keeps recording accurately and securely exactly when the system is under the most stress — which is when the log matters most.

---

## 2. Block Diagram

[→ Open the full architecture diagram] (https://app.diagrams.net/#G1E4_oNCy5_rBY-oTDDtPXRc-Tu5abfEbk#%7B%22pageId%22%3A%22CIzeiW2PUjdxlhk8X_p7%22%7D)



## 3. System Architecture & IPs Used

### Core Processor

**RISC-V Processor Core — VeeR EL2** (Western Digital / CHIPS Alliance)
Open-source, dual-issue 32-bit core implementing **RV32IMC**, with 32 KB ICCM and 64 KB DCCM. It is the control-plane master — configuring peripheral registers and handling top-level interrupts/fault vectors — while the closely-coupled memories let it run control code at deterministic, single-cycle latency without contending for the shared AXI bus. This is what makes non-blocking CPU execution possible even while DMA is saturating the bus.

### Bus Fabric

**Dual-Master AXI4-Lite Interconnect**
Crossbar with round-robin arbitration between Master 1 (RISC-V core) and Master 2 (DMA). Chosen for low area overhead and standardized handshaking; the round-robin arbiter is what gives the zero-starvation guarantee — high-bandwidth DMA traffic can never lock the CPU out of its control registers.

### The Six Integrated Peripheral IPs

| 1 | **AES Encryption Engine** (AXI4-Lite slave) | Hardware-accelerated AES-128/256 (ECB/CBC) over staged sensor blocks. Removes the latency and cache-timing side-channel risk of software crypto; its completion pulse doubles as the hardware "system alive" heartbeat for the watchdog. 

| 2 | **Bus-Mastering DMA Controller** (AXI4-Lite slave + master) | Moves UART telemetry into staging SRAM autonomously once a FIFO threshold is crossed — no CPU polling, no programmatic I/O. Its completion pulse triggers the AES engine directly. 

| 3 | **Watchdog Timer (WDT)** | Autonomous supervisor with an early-warning IRQ, an NMI line, and a hard reset line, all independent of software. Auto-kicked on every AES completion, so any hang anywhere in the pipeline is detected and recovered from without firmware intervention. 

| 4 | **UART** | Sensor ingest interface; asserts a hardware DMA request the moment its RX FIFO crosses a watermark, starting the autonomous pipeline with zero CPU involvement. 

| 5 | **GPIO / Timer** | Board-level I/O and timing references (baud generation, peripheral clocking) supporting the rest of the pipeline. 

| 6 | **Programmable Interrupt Controller (PIC)** | Aggregates and priority-encodes interrupts from DMA, AES, UART, and WDT-warning into a single vectored line to the core, keeping CPU-side interrupt handling simple despite multiple autonomous blocks running in parallel. 

**Supporting element:** a 32 KB dual-port staging SRAM (Port A → AES, Port B → DMA/CPU) that decouples ingest from cryptographic processing, avoiding bus contention between the two.

### Key Architectural Guarantees

- **Hardware-synchronized autonomous pipeline:** UART → DMA → SRAM → AES → WDT kick, entirely in hardware, no software intervention.
- **Zero-starvation arbiter:** transaction-boundary round-robin locking bounds CPU wait time regardless of DMA load.
- **Non-blocking CPU execution:** the core only stalls if it explicitly issues an off-chip AXI transaction; otherwise it runs at full speed from ICCM/DCCM.
- **Privilege and bus protection:** Master 2 (DMA) is hardware-blocked from writing to CPU-only registers (AES keys, WDT control); unaligned accesses return SLVERR.
- 
## 4. References

- RISC-V VeeR EL2 core (Western Digital / CHIPS Alliance), open-source RTL — [github.com/chipsalliance/Cores-VeeR-EL2](https://github.com/chipsalliance/Cores-VeeR-EL2)
- RISC-V Instruction Set Manual, Vol. I: Unprivileged ISA — [riscv.org/technical/specifications](https://riscv.org/technical/specifications/)
- Arm AMBA AXI and ACE Protocol Specification (AXI4 / AXI4-Lite) — [developer.arm.com/documentation/ihi0022](https://developer.arm.com/documentation/ihi0022/latest/)
- FIPS 197, Advanced Encryption Standard — NIST — [nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.197.pdf](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.197.pdf)
- AMBA AXI4-Lite UART reference behavior (register map / FIFO conventions used as baseline for `axi_uart_top`) — consistent with LogiCORE AXI UART Lite v2.0 — [docs.amd.com/v/u/en-US/pg142-axi-uartlite](https://docs.amd.com/v/u/en-US/pg142-axi-uartlite)
- Synopsys VCS / Verdi User Guides — simulation and waveform debug tooling used for verification


---

## 5. Repository Structure

```text
SOC_Datalogger_project/
├── Docs/                           # Spec doc, session log, error log
├── RTL_files/                      # Top-level integration RTL (bridge, wrapper, timescale stub)
├── TB_files/                       # SystemVerilog testbenches
├── Scripts/                        # Build/utility scripts
├── run/                            # Filelists and run scripts (VCS compile/sim)
├── axi-lite_uart-ipcore-develop/   # UART IP core source (RTL + docs)
└── README.md
```

## 6. Register Map

### UART — base `0x4000_0000`, 32 B aperture

| Offset | Register  | Description                                          |
|--------|-----------|-------------------------------------------------------|
| 0x00   | RBR / THR | RX buffer / TX holding                                |
| 0x04   | IER       | Interrupt enable                                       |
| 0x08   | BAUD      | Baud divisor                                            |
| 0x0C   | LCR       | Line control (8N1 = `0x03`)                            |
| 0x14   | LSR       | Line status (TEMT = bit6, THRE = bit5, DATA_READY = bit0) |

### DMA Controller — base `0x4000_3000`

| Offset | Register     | Description                                       |
|--------|--------------|-----------------------------------------------------|
| 0x00   | DMA_SRC_ADDR | Source address pointer                              |
| 0x04   | DMA_DST_ADDR | Destination address pointer (SRAM Port B)           |
| 0x08   | DMA_XFER_LEN | Transaction length in bytes                          |
| 0x0C   | DMA_CTRL     | START (bit0), IRQ_EN (bit1), MODE_SEL (bit2)         |
| 0x10   | DMA_STATUS   | BUSY (bit0), DONE (bit1), ERROR (bit2)               |

### AES Engine — base `0x4000_2000`

| Offset      | Register     | Description                                              |
|-------------|--------------|------------------------------------------------------------|
| 0x00        | AES_CTRL     | START (bit0), MODE (bit1), DIR (bit2), SRAM_AUTO_FETCH (bit3) |
| 0x04        | AES_STATUS   | IDLE / PROCESSING / COMPLETE                                |
| 0x10–0x2C   | AES_KEY_0..7 | 128/256-bit key words                                       |

### Watchdog Timer — base `0x4000_4000`

| Offset | Register       | Description                                        |
|--------|----------------|-------------------------------------------------------|
| 0x00   | WDT_MAX_LIMIT  | Timeout threshold (cycles)                            |
| 0x04   | WDT_CTRL       | Auto-kick enable, NMI mode, hard-reset config          |
| 0x08   | WDT_PING_REG   | Manual software ping (CPU ISR fallback)                |

---

## 7. How to Build & Run

cd run

# Compile (recommended, with log capture)
vcs -full64 -sverilog -l compile.log -f run_interconnect_uart.f -o simv_ic_uart

# Simulate
./simv_ic_uart

# With Verdi waveforms
vcs -full64 -sverilog -debug_access+all -kdb -f run_interconnect_uart.f -o simv_ic_uart
./simv_ic_uart -verdi


## 8. Verification Status

The AXI-interconnect ↔ UART integration is verified with a directed 7-step test sequence. 

| 1 | Reset | Hold `rst_n` low for 20 clocks |
| 2 | LCR config | Write `0x03` (8N1) |
| 3 | BAUD config | Write `SIM_BAUD_DIV = 10` |
| 4 | THR write | Write `0x55` to transmit register |
| 5 | LSR poll TEMT | Wait for TX FIFO drain |
| 6 | RX injection | Drive byte `0xA5` on `uart_rx` (NRZ, LSB-first) |
| 7 | RBR read | Verify received byte equals `0xA5` |

**All 7 tests currently pass.**

This verified interconnect–UART block has since been **integrated into the RISC-V wrapper (VeeR EL2)**, and verification of that integrated block is **currently in progress**.

AES, DMA, WDT, and PIC integration into the full top-level SoC is planned next and not yet covered by any testbench — this section will be updated as each stage's verification lands.

---

## 9. Challenges & Debugging

| 1 | `NTSFM` — missing `` `timescale `` (1st attempt) | A shared `timescale.v` stub listed first in the filelist looked correct but doesn't propagate across file boundaries in VCS | — |
| 2 | `SVS` — SystemVerilog-only syntax | `rd = '0;` rejected outside full SV mode | Replaced with `{DATA_W{1'b0}}` |
| 3 | `NTSFM` — real root cause | VCS resets timescale context at every file boundary | Embedded `` `timescale `` inside each of the 6 UART source files individually |
| 4 | `TFIPC` — too few port connections | Tie-off logic for unused master ports (m01–m05) wired only the input side; 32 output ports per master were missing | Tied outputs to `()`, drove inputs with literals in the instantiation |
| 5 | `SIOB` + `NMCM` — OOB slice / negative replication | ID-width conversion assumed interconnect ID width ≥ UART's fixed 12-bit ID; it was actually 8-bit | Reversed conversion direction (zero-pad 8→12 in, truncate 12→8 out) |
| 6 | `UST` — undefined system task | `` `ifdef VCS `` always selected the FSDB dump branch (VCS defines that macro by default), but the Verdi/Novas PLI library wasn't loaded | Replaced with unconditional `$dumpfile` / `$dumpvars` |
| 7 | Runtime `$finish` — address width violation | Interconnect enforces a minimum 12-bit (4 KB) slave address aperture; UART's real footprint is 5 bits (32 B) | Set `M00_ADDR_WIDTH = 12`, unused address space returns SLVERR |
| 8 | Stale-binary false negative | Runtime error persisted post-fix because `simv_ic_uart` was a stale compiled binary | `build_ic_uart.sh` clears prior build artifacts before every recompile |

> **Recurring lesson:** several issues looked fixed after the first pass but weren't — the actual root cause in both the timescale bug and the stale-binary bug was *tool behavior* (per-file timescale reset, cached binaries), not the RTL itself.


## 10. Skills & Tools Demonstrated

- RTL design in Verilog / SystemVerilog
- AXI4 and AXI4-Lite protocol implementation (interconnect, bridge, peripheral slaves)
- RISC-V SoC integration (VeeR EL2 core)
- Testbench development and directed verification methodology
- Synopsys VCS (compilation, simulation) and Verdi (FSDB waveform debug)
- Systematic root-cause debugging across compile-time (`NTSFM`, `SVS`, `TFIPC`, `SIOB`, `NMCM`, `UST`) and runtime errors
- Hardware security: AES-128/256 cryptographic acceleration
- Fault-tolerant system design: autonomous watchdog-based recovery

---

## 11. Author

**Nitish**
Final-year B.E. Electronics and Communication Engineering, Vasavi College of Engineering (VCE), Hyderabad
Trained in Semiconductor Device Fabrication at CENSE, IISc Bangalore · Samsung SSIR Fellow · ISWDP certified (IISc, Synopsys, Samsung)

📧 [nitishlingampalle@ieee.org](mailto:nitishlingampalle@ieee.org)
🔗 [linkedin.com/in/nitishlingampalle25](https://www.linkedin.com/in/nitishlingampalle25/)
=======
# SOC_Datalogger_Integration
>>>>>>> fde64a9f7b2928fa8d30e19dbba01e81e3f96e1b
