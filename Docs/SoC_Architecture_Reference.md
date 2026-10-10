# SoC Data Logger — Architecture, Dataflow & Address Path Reference

**File:** `Docs/SoC_Architecture_Reference.md`  
**Project:** Secure RISC-V SoC Data Logger for Mission-Critical Telemetry (Kavach/TCAS)  
**Top Module:** `veer2_dma_aes_wdt_uart_gpio_timer`  
**Date:** October 2026

---

## 1. System Overview

This SoC is a hardware-accelerated, tamper-resistant data logger built around the open-source **VeeR EL2** RISC-V core. Its purpose is to ingest sensor telemetry (train speed, brake pressure, signal aspects) via UART, encrypt it autonomously in hardware using AES-128/256, and log it — all while a watchdog ensures the pipeline never silently stalls.

The CPU does not poll, copy, or encrypt data. It only initialises registers at boot. The rest is fully autonomous hardware.

---

## 2. Complete IP Inventory

| # | Block | File(s) | Bus Role | Address |
|---|-------|---------|----------|---------|
| 1 | VeeR EL2 Core | `el2_veer_wrapper` | AXI4 Master 1 (LSU) | — |
| 2 | 64→32 Dwidth Adapter | `axi_dwidth_converter_64to32` | Bridge | — |
| 3 | 2×6 AXI4 Crossbar | `axi_interconnect_wrap_2x6` | Interconnect | — |
| 4 | UART | `axi_uart_top` via `axi4_to_axilite_bridge` | AXI4-Lite Slave | `0x4000_0000` |
| 5 | System Timer | `timer_axi_wrapper` → `timer_core` | AXI4 Slave | `0x4000_1000` |
| 6 | AES Engine | `aes_veer_adapter` | AXI4 Slave | `0x4000_2000` |
| 7 | DMA Controller | `dma_axi_wrapper` | AXI4 Master 2 + Slave | `0x4000_3000` |
| 8 | Watchdog Timer | `ef_wdt32_axi_wrapper` → `EF_WDT32` | AXI4 Slave | `0x4000_4000` |
| 9 | GPIO | `gpio_axi_wrapper` → `gpio` | AXI4 Slave | `0x4000_5000` |

---

## 3. Full Address Map

```
0x4000_0000 – 0x4000_0FFF   UART          (4 KB)
0x4000_1000 – 0x4000_1FFF   System Timer  (4 KB)
0x4000_2000 – 0x4000_2FFF   AES Engine    (4 KB)
0x4000_3000 – 0x4000_3FFF   DMA CSRs      (4 KB)
0x4000_4000 – 0x4000_4FFF   Watchdog      (4 KB)
0x4000_5000 – 0x4000_5FFF   GPIO          (4 KB)
```

The interconnect enforces a minimum 12-bit (4 KB) aperture per slave. Any access to an unmapped address returns `SLVERR`.

---

## 4. Bus Topology

```
                          ┌────────────────────────────────────────────┐
  VeeR LSU (64-bit) ─────►│  axi_dwidth_converter_64to32               │
                          │  (lane-select, awsize clamp 64→32)         │──► s00
                          └────────────────────────────────────────────┘

  DMA Master (32-bit) ─────────────────────────────────────────────────────► s01

                          ┌────────────────────────────────────────────────────┐
                          │   axi_interconnect_wrap_2x6  (2 masters × 6 slaves)│
                          │                                                    │
                          │  s00 ◄─ VeeR LSU (via adapter)                    │
                          │  s01 ◄─ DMA Master                                │
                          │                                                    │
                          │  m00 ──► UART bridge ──► axi_uart_top             │
                          │  m01 ──► timer_axi_wrapper ──► timer_core         │
                          │  m02 ──► aes_veer_adapter                         │
                          │  m03 ──► dma_axi_wrapper (CSR slave)              │
                          │  m04 ──► ef_wdt32_axi_wrapper                     │
                          │  m05 ──► gpio_axi_wrapper ──► gpio                │
                          └────────────────────────────────────────────────────┘
```

Arbitration is **round-robin** between s00 (VeeR) and s01 (DMA), ensuring neither master can starve the other regardless of burst length.

---

## 5. Detailed Dataflow — The Autonomous Telemetry Pipeline

This is the core value of the SoC. Once initialised by firmware, the following pipeline runs entirely in hardware with zero CPU involvement:

```
Sensor ──► [UART RX FIFO] ──► [DMA] ──► [Staging SRAM] ──► [AES] ──► [WDT kick]
                │                                                          │
          FIFO threshold                                            auto-reload
          fires DMA request                                       prevents timeout
```

### Step-by-step:

**1. UART Ingest (`0x4000_0000`)**  
- Sensor sends NRZ serial data (e.g., 115200 baud, 8N1).  
- `axi_uart_top` shifts bits into its RX FIFO.  
- When the FIFO crosses its watermark, `read_interrupt_o` asserts — this is the hardware DMA request signal.  
- No CPU involvement: the interrupt fires DMA directly (hardware handshake).

**2. DMA Transfer (`0x4000_3000` CSRs, `0x4000_3000`–`0x4000_3FFF`)**  
- The DMA Controller (`dma_axi_wrapper`) is pre-programmed at boot:  
  - `DMA_SRC_ADDR` = UART RX buffer address  
  - `DMA_DST_ADDR` = Staging SRAM base (e.g., some DCCM region)  
  - `DMA_XFER_LEN` = block size in bytes  
  - `DMA_CTRL[START]` = 1 (armed, waits for request)  
- On the UART watermark signal, DMA issues AXI4 burst transactions on **s01** (Master 2).  
- The crossbar routes these through **m00** (UART) and to the destination SRAM.  
- On completion, `dma_done_o` asserts → `dma_irq_o` fires → optionally wakes CPU.

**3. AES Encryption (`0x4000_2000`)**  
- `aes_veer_adapter` is armed by firmware with:  
  - 128/256-bit key in `AES_KEY_0..7`  
  - `AES_CTRL[SRAM_AUTO_FETCH]` = 1 (auto-reads from staging SRAM)  
  - `AES_CTRL[START]` triggered by DMA completion pulse (hardware wiring)  
- AES operates over the staged block, producing ciphertext.  
- On completion, `aes_done_pulse_o` fires a **1-cycle pulse** wired directly to the WDT.  
- `aes_irq_o` also fires → CPU can log metadata if desired, but is not required.

**4. Watchdog Auto-Kick (`0x4000_4000`)**  
- `ef_wdt32_axi_wrapper` wraps `EF_WDT32`.  
- `WDT_CTRL[AUTO_KICK_EN]` (bit 1) enables hardware kick on `aes_done_pulse_i`.  
- Every AES completion automatically reloads the watchdog counter, proving the pipeline is alive.  
- If AES stops completing (DMA stall, bus deadlock, CPU hang), the watchdog times out and:  
  - Issues `wdt_irq_o` (early warning, maskable) → PIC → CPU  
  - Escalates to `wdt_nmi_o` → directly OR'd into VeeR's `nmi_int` pin (bypasses PIC)  
  - Final escalation: `wdt_reset_o` → hard system reset

**Hardware guarantee:** The system self-recovers from any pipeline stall without any firmware intervention.

---

## 6. Control Path — What Firmware Does

Firmware only runs at boot to configure registers. Typical boot sequence:

```c
// 1. Configure UART: 115200 baud, 8N1
UART[LCR]  = 0x03;          // 8N1
UART[BAUD] = baud_divisor;  // clock / baudrate

// 2. Configure DMA: src=UART_RX, dst=SRAM, len=128 bytes
DMA[SRC]   = 0x40000000;    // UART RX
DMA[DST]   = sram_base;
DMA[LEN]   = 128;
DMA[CTRL]  = 0x07;          // START | IRQ_EN | MODE_STREAM

// 3. Load AES key and arm engine
AES[KEY_0..7] = key_words;
AES[CTRL]  = 0x0B;          // START | CBC | ENC | SRAM_AUTO_FETCH

// 4. Configure Watchdog: 1M cycle timeout, auto-kick from AES
WDT[LOAD]  = 1_000_000;
WDT[CTRL]  = 0x03;          // WDT_EN | AUTO_KICK_EN

// 5. Configure System Timer: prescaler for 1 µs tick
TIMER[CFG0]    = (prescaler << 8) | step;
TIMER[CMP_LO]  = 0xFFFFFFFF;  // set far deadline initially
TIMER[CMP_HI]  = 0xFFFFFFFF;
TIMER[CTRL]    = 0x01;         // enable

// 6. Configure GPIO: set output enables, interrupt masks
GPIO[GPIO_EN]  = 0x0000_00FF;  // lower 8 pins = output
GPIO[GPIO_OUT] = 0x00;

// 7. Enable interrupts in VeeR PIC and go idle / run application
```

After this, the hardware pipeline runs autonomously. The CPU only wakes on:
- `dma_irq_o` — DMA done (metadata logging, optional)
- `aes_irq_o` — AES done (ciphertext ready for off-chip write)
- `wdt_irq_o` — Watchdog early warning (investigate stall)
- `wdt_nmi_o` — Watchdog NMI (emergency recovery ISR)
- `timer_irq_o` — Timer compare match (scheduling, timestamping)
- `gpio_irq_o` — GPIO edge/level interrupt (external event)
- `uart_read_irq_o` — UART RX data ready (fallback polled mode)

---

## 7. Register Maps

### 7.1 UART — base `0x4000_0000`

| Offset | Register | Description |
|--------|----------|-------------|
| `0x00` | RBR/THR | RX buffer read / TX holding write |
| `0x04` | IER | Interrupt enable |
| `0x08` | BAUD | Baud divisor |
| `0x0C` | LCR | Line control (8N1 = `0x03`) |
| `0x14` | LSR | Line status: TEMT=bit6, THRE=bit5, DATA_READY=bit0 |

### 7.2 System Timer — base `0x4000_1000`

| Offset | Register | Description |
|--------|----------|-------------|
| `0x000` | CTRL | `[0]` = timer enable |
| `0x100` | INTR_ENABLE0 | `[0]` = interrupt enable |
| `0x104` | INTR_STATE0 | `[0]` = interrupt pending (W1C) |
| `0x108` | INTR_TEST0 | `[0]` = force interrupt (write-only) |
| `0x10C` | CFG0 | `[19:8]` = prescaler, `[7:0]` = step |
| `0x110` | TIMER_V_LOWER0 | `mtime[31:0]` — RW, updated each tick |
| `0x114` | TIMER_V_UPPER0 | `mtime[63:32]` — RW, updated each tick |
| `0x118` | COMPARE_LOWER0 | `mtimecmp[31:0]` |
| `0x11C` | COMPARE_UPPER0 | `mtimecmp[63:32]` |

Timer fires `timer_irq_o` when `mtime >= mtimecmp` and `INTR_ENABLE0[0]=1`.  
Tick period = `(prescaler + 1)` clock cycles; mtime increments by `step` each tick.

### 7.3 AES Engine — base `0x4000_2000`

| Offset | Register | Description |
|--------|----------|-------------|
| `0x00` | AES_CTRL | `[0]`=START, `[1]`=MODE(CBC/ECB), `[2]`=DIR(enc/dec), `[3]`=SRAM_AUTO_FETCH |
| `0x04` | AES_STATUS | IDLE / PROCESSING / COMPLETE |
| `0x10–0x2C` | AES_KEY_0..7 | 128 or 256-bit key words |

### 7.4 DMA Controller — base `0x4000_3000`

| Offset | Register | Description |
|--------|----------|-------------|
| `0x00` | DMA_SRC_ADDR | Source address |
| `0x04` | DMA_DST_ADDR | Destination address (SRAM) |
| `0x08` | DMA_XFER_LEN | Length in bytes |
| `0x0C` | DMA_CTRL | `[0]`=START, `[1]`=IRQ_EN, `[2]`=MODE_SEL |
| `0x10` | DMA_STATUS | `[0]`=BUSY, `[1]`=DONE, `[2]`=ERROR |

### 7.5 Watchdog Timer — base `0x4000_4000`

| Offset | Register | Description |
|--------|----------|-------------|
| `0x04` | WDT_LOAD | Timeout threshold (cycles) |
| `0x08` | WDT_CTRL | `[0]`=WDT_EN, `[1]`=AUTO_KICK_EN, `[2]`=NMI_EN, `[3]`=RESET_EN |
| `0x0C` | WDT_PING | Manual software kick |
| `0x10` | WDT_IM | Interrupt mask |
| `0x14` | WDT_RIS | Raw interrupt status |
| `0x18` | WDT_MIS | Masked interrupt status |
| `0x20` | WDT_GCLK | Gated clock enable |

### 7.6 GPIO — base `0x4000_5000`

| Offset | Register | Description |
|--------|----------|-------------|
| `0x000` | INFO | Version / GPIO count (read-only) |
| `0x004` | CFG | Interrupt mode config |
| `0x008–0x00C` | GPIO_MODE_0/1 | Per-pin mode (2 bits each, 16 pins/word) |
| `0x080` | GPIO_EN | Output enable mask (1=output) |
| `0x100` | GPIO_IN | Sampled input values (read-only) |
| `0x180` | GPIO_OUT | Output data register |
| `0x200` | GPIO_SET | Atomic bit-set |
| `0x280` | GPIO_CLEAR | Atomic bit-clear |
| `0x300` | GPIO_TOGGLE | Atomic bit-toggle |
| `0x380` | INTRPT_RISE_EN | Rising-edge interrupt enable |
| `0x400` | INTRPT_FALL_EN | Falling-edge interrupt enable |
| `0x480` | INTRPT_LVL_HIGH_EN | Level-high interrupt enable |
| `0x500` | INTRPT_LVL_LOW_EN | Level-low interrupt enable |
| `0x580` | INTRPT_STATUS | Interrupt pending flags (W1C) |

---

## 8. Address Transaction Path — Step by Step

When firmware writes `0x4000_0000` (UART THR):

1. **VeeR EL2 LSU** issues a 64-bit AXI4 write on its LSU port.
2. **`axi_dwidth_converter_64to32`** inspects `awaddr[2]` to select the correct 32-bit lane; clamps `awsize` from `3'b011` to `3'b010`; drives 32-bit `s00` port of the interconnect.
3. **`axi_interconnect_wrap_2x6`** decodes the address: `0x4000_0000` matches `M00_BASE_ADDR`. Transaction routed to `m00` port.
4. **`axi4_to_axilite_bridge`** strips burst/lock/cache sideband signals, forwards a single-beat AXI4-Lite write to `axi_uart_top`.
5. **`axi_uart_top`** writes the byte to its TX holding register and shifts it out serially.

When DMA reads `0x4000_0000` (UART RBR):

1. **`dma_axi_wrapper`** AXI4 master drives `s01` port.
2. **Round-robin arbiter** in the crossbar grants access (will not starve VeeR on `s00`).
3. Same m00/bridge/UART path as above, but for read channel.

---

## 9. Hardware Handshaking Signals (Out-of-Band)

These signals flow directly between IPs, bypassing the AXI bus entirely:

| Signal | From → To | Purpose |
|--------|-----------|---------|
| `aes_done_pulse_o` | AES → WDT `aes_done_pulse_i` | Auto-kick watchdog on every AES completion |
| `wdt_nmi_o` | WDT → VeeR `nmi_int` (OR'd) | Escalation: emergency NMI bypasses PIC |
| `wdt_reset_o` | WDT → top-level output | Escalation: hard system reset |
| `wdt_irq_o` | WDT → PIC (via `extintsrc_req`) | Early-warning maskable interrupt |
| `uart_read_irq_o` | UART → PIC | RX data-ready interrupt |
| `dma_done_o` / `dma_irq_o` | DMA → PIC | Transfer completion |
| `aes_irq_o` | AES → PIC | AES operation complete |
| `timer_irq_o` | Timer → PIC | `mtime >= mtimecmp` |
| `gpio_irq_o` | GPIO → PIC | Pin-level edge/level event |

---

## 10. Why Each Design Decision Was Made

| Decision | Reason |
|----------|--------|
| AXI4 bus (not APB/AHB) | Higher throughput, burst support needed for DMA block transfers |
| Round-robin arbitration | Zero-starvation guarantee: DMA bursts cannot lock CPU off its control registers |
| AES hardware, not software | Constant-time, no cache-timing side-channel risk; no CPU cycles consumed |
| WDT auto-kicked by AES | Proves the entire pipeline (UART→DMA→AES) is live; a stall anywhere stops the kick |
| WDT NMI bypass of PIC | NMI reaches the core even if PIC is corrupted or CPU interrupt mask is wrong |
| DMA as AXI Master 2 | Decouples UART ingest from CPU; SRAM writes happen without any CPU instruction |
| 64→32 dwidth adapter | VeeR EL2 LSU is natively 64-bit; all peripherals are 32-bit AXI4-Lite capable |
| `timer_core.sv` only (no TLUL) | rv_timer.sv requires full OpenTitan TLUL stack; timer_axi_wrapper implements only the register logic needed, wrapping the dependency-free timer_core directly |
| `gpio_axi_wrapper` flat structs | gpio_axi_lite_wrap.sv requires pulp-platform macro headers not present in this project; flat struct approach achieves identical functionality without external dependencies |

---

## 11. File Map

```
RTL_files/
├── veer2_dma_aes_wdt_uart_gpio_timer.v   ← CURRENT TOP MODULE (all 9 IPs)
├── veer2_dma_aes_wdt_uart_gpio.v         ← Previous top (without timer)
├── timer_axi_wrapper.v                   ← Self-contained AXI4 timer wrapper
├── gpio_axi_wrapper.v                    ← Self-contained AXI4 GPIO wrapper
├── System_Timer/
│   ├── timer_core.sv                     ← Instantiated by timer_axi_wrapper
│   ├── rv_timer.sv                       ← NOT used (requires OpenTitan TLUL)
│   ├── rv_timer_reg_pkg.sv               ← Register offsets (reference only)
│   └── rv_timer_reg_top.sv               ← NOT used (requires TLUL)
├── GPIO/
│   ├── gpio.sv                           ← Instantiated by gpio_axi_wrapper
│   ├── gpio_reg_pkg.sv                   ← Package (GPIOCount=32)
│   ├── gpio_reg_top.sv                   ← Instantiated by gpio.sv
│   ├── gpio_axi_lite_wrap.sv             ← NOT used (requires pulp macros)
│   └── gpio_input_stage*.sv
└── [AES, DMA, WDT, UART source directories]
```

---

## 12. Integration History (Quick Reference)

| Step | Module Added | Slot Used |
|------|-------------|-----------|
| 1 | UART | m00 @ `0x4000_0000` |
| 2 | AES | m02 @ `0x4000_2000` |
| 3 | DMA | m03 @ `0x4000_3000` + s01 as master |
| 4 | WDT | m04 @ `0x4000_4000` |
| 5 | GPIO | m05 @ `0x4000_5000` |
| 6 | System Timer | m01 @ `0x4000_1000` (was tied-off) |

All 6 slave ports of the `axi_interconnect_wrap_2x6` are now occupied.
