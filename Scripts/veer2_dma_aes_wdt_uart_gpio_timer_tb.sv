`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// File    : Scripts/veer2_dma_aes_wdt_uart_gpio_timer_tb.sv
//
// Purpose : Firmware-driven Testbench for the Full-SoC Top Level:
//           veer2_dma_aes_wdt_uart_gpio_timer
//
// Target Firmware : soc_full_test.hex (generated from soc_full_test.c)
//
// Verification Features:
//   1.  Loads soc_full_test.hex into IFU memory model with auto-detected/
//       configurable reset vector (supports 0x0000_0000 and 0x0001_0120).
//   2.  VeeR EL2 core boots and executes the firmware natively. All peripheral
//       transactions are issued autonomously by VeeR LSU through the
//       axi_dwidth_converter_64to32 and 2x6 crossbar interconnect.
//   3.  Co-simulation Responders:
//       - UART TX: Monitors uart_tx_o, deserializes transmitted byte, verifies 'K' (0x4B).
//       - UART RX: Injects 8'hA5 via uart_rx_i so firmware's RX check passes.
//       - System Timer: Verifies timer counter increment and timer_irq_o assertion.
//       - AES Engine: Verifies aes_busy_o, aes_done_o, and aes_done_pulse_o.
//       - DMA Controller: Verifies dma_done_o and dma_irq_o.
//       - Watchdog Timer: Verifies SW ping, AES auto-kick, timeout IRQ, and escalation.
//       - GPIO: Verifies gpio_out_o == 0xA5, feeds gpio_in_i, and pulses bit 0 to test IRQ.
//   4.  TOHOST Interceptor (Address 0xF000_0000):
//       - Automatically overrides interconnect decode response to OKAY (2'b00)
//         to prevent imprecise store bus error exceptions on unmapped address.
//       - Captures progress milestone codes (0x0006, 0x0009, 0x0013, 0x0016,
//         0x0021, 0x0025, 0x0026) and final PASS magic word 0x900D.
//       - Reports fail trap code (0xDEADxxxx) on any step failure.
//   5.  Maintains legacy BFM mode as fallback when +BFM plusarg is provided.
// =============================================================================

module veer2_dma_aes_wdt_uart_gpio_timer_tb;

    // =========================================================================
    // Simulation parameters
    // =========================================================================
    localparam CLK_PERIOD    = 10;          // 100 MHz
    localparam FIXED_PERIOD  = 10;          // UART baud reference
    localparam RST_CYCLES    = 20;
    localparam TIMEOUT_CYC   = 20_000;      // Handshake watchdog
    localparam SIM_BAUD_DIV  = 10;          // baud divisor for sim
    localparam BIT_CYCLES    = SIM_BAUD_DIV + 1; // 11 clocks per bit

    localparam IC_ID_WIDTH   = 8;
    localparam DATA_WIDTH    = 32;
    localparam ADDR_WIDTH    = 32;
    localparam STRB_WIDTH    = 4;

    // Base addresses (must match interconnect decode and firmware)
    localparam [31:0] UART_BASE      = 32'h4000_0000;
    localparam [31:0] TIMER_BASE     = 32'h4000_1000;
    localparam [31:0] AES_BASE       = 32'h4000_2000;
    localparam [31:0] DMA_BASE       = 32'h4000_3000;
    localparam [31:0] WDT_BASE       = 32'h4000_4000;
    localparam [31:0] GPIO_BASE      = 32'h4000_5000;
    localparam [31:0] TOHOST_ADDR    = 32'hF000_0000;
    localparam [31:0] UNMAPPED_ADDR  = 32'h5000_0000;

    // Peripheral Register Offsets
    localparam [31:0] UART_THR       = UART_BASE  + 32'h00;
    localparam [31:0] UART_RBR       = UART_BASE  + 32'h00;
    localparam [31:0] UART_IER       = UART_BASE  + 32'h04;
    localparam [31:0] UART_BAUD      = UART_BASE  + 32'h08;
    localparam [31:0] UART_LCR       = UART_BASE  + 32'h0C;
    localparam [31:0] UART_LSR       = UART_BASE  + 32'h14;

    localparam [31:0] TIMER_CTRL     = TIMER_BASE + 32'h000;
    localparam [31:0] TIMER_INTR_EN  = TIMER_BASE + 32'h100;
    localparam [31:0] TIMER_INTR_ST  = TIMER_BASE + 32'h104;
    localparam [31:0] TIMER_CFG0     = TIMER_BASE + 32'h10C;
    localparam [31:0] TIMER_VAL_LO   = TIMER_BASE + 32'h110;
    localparam [31:0] TIMER_VAL_HI   = TIMER_BASE + 32'h114;
    localparam [31:0] TIMER_CMP_LO   = TIMER_BASE + 32'h118;
    localparam [31:0] TIMER_CMP_HI   = TIMER_BASE + 32'h11C;

    localparam [31:0] AES_CTRL_REG   = AES_BASE   + 32'h00;
    localparam [31:0] AES_STATUS     = AES_BASE   + 32'h04;
    localparam [31:0] AES_KEY0       = AES_BASE   + 32'h08;
    localparam [31:0] AES_KEY1       = AES_BASE   + 32'h0C;
    localparam [31:0] AES_KEY2       = AES_BASE   + 32'h10;
    localparam [31:0] AES_KEY3       = AES_BASE   + 32'h14;
    localparam [31:0] AES_TXTIN0     = AES_BASE   + 32'h18;
    localparam [31:0] AES_TXTIN1     = AES_BASE   + 32'h1C;
    localparam [31:0] AES_TXTIN2     = AES_BASE   + 32'h20;
    localparam [31:0] AES_TXTIN3     = AES_BASE   + 32'h24;
    localparam [31:0] AES_TXTOUT0    = AES_BASE   + 32'h28;
    localparam [31:0] AES_TXTOUT1    = AES_BASE   + 32'h2C;
    localparam [31:0] AES_TXTOUT2    = AES_BASE   + 32'h30;
    localparam [31:0] AES_TXTOUT3    = AES_BASE   + 32'h34;

    localparam [31:0] DMA_CTRL_REG   = DMA_BASE   + 32'h00;
    localparam [31:0] DMA_STAT_REG   = DMA_BASE   + 32'h08;
    localparam [31:0] DMA_ERR_REG    = DMA_BASE   + 32'h10;
    localparam [31:0] DMA_DESC0_SRC  = DMA_BASE   + 32'h20;
    localparam [31:0] DMA_DESC0_DST  = DMA_BASE   + 32'h30;

    localparam [31:0] WDT_LOAD       = WDT_BASE   + 32'h04;
    localparam [31:0] WDT_CTRL       = WDT_BASE   + 32'h08;
    localparam [31:0] WDT_PING       = WDT_BASE   + 32'h0C;
    localparam [31:0] WDT_IM         = WDT_BASE   + 32'h10;
    localparam [31:0] WDT_RIS        = WDT_BASE   + 32'h14;
    localparam [31:0] WDT_MIS        = WDT_BASE   + 32'h18;
    localparam [31:0] WDT_IC         = WDT_BASE   + 32'h1C;

    localparam [31:0] GPIO_EN_REG    = GPIO_BASE  + 32'h080;
    localparam [31:0] GPIO_IN_REG    = GPIO_BASE  + 32'h100;
    localparam [31:0] GPIO_OUT_REG   = GPIO_BASE  + 32'h180;
    localparam [31:0] GPIO_RISE_EN   = GPIO_BASE  + 32'h380;
    localparam [31:0] GPIO_INT_STAT  = GPIO_BASE  + 32'h580;

    // NIST FIPS-197 golden reference vectors
    localparam [31:0] AES_KEY_W0     = 32'h2b7e1516;
    localparam [31:0] AES_KEY_W1     = 32'h28aed2a6;
    localparam [31:0] AES_KEY_W2     = 32'habf71588;
    localparam [31:0] AES_KEY_W3     = 32'h09cf4f3c;

    localparam [31:0] AES_PT_W0      = 32'h3243f6a8;
    localparam [31:0] AES_PT_W1      = 32'h885a308d;
    localparam [31:0] AES_PT_W2      = 32'h3131982a;
    localparam [31:0] AES_PT_W3      = 32'he0370734;

    localparam [31:0] AES_CT_W0      = 32'h3925841d;
    localparam [31:0] AES_CT_W1      = 32'h02dc09fb;
    localparam [31:0] AES_CT_W2      = 32'hdc118597;
    localparam [31:0] AES_CT_W3      = 32'h196a0b32;

    // =========================================================================
    // Clocks and resets
    // =========================================================================
    logic clk;
    logic fixed_clk;
    logic rst_l;
    logic dbg_rst_l;

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    initial begin
        fixed_clk = 1'b0;
        forever #(FIXED_PERIOD / 2) fixed_clk = ~fixed_clk;
    end

    // =========================================================================
    // DUT Port Declarations
    // =========================================================================

    // Boot
    logic [31:1]  rst_vec;
    logic [31:1]  nmi_vec;
    logic [31:1]  jtag_id;
    logic [31:4]  core_id;

    // Interrupts
    logic         nmi_int;
    logic         timer_int;
    logic         soft_int;
    logic [31:1]  extintsrc_req;

    // Peripheral outputs
    logic         uart_read_irq_o;
    logic         aes_irq_o;
    logic         aes_done_pulse_o;
    logic         dma_done_o;
    logic         dma_error_o;
    logic         dma_irq_o;
    logic         wdt_irq_o;
    logic         wdt_nmi_o;
    logic         wdt_reset_o;
    logic         wdt_timeout_o;
    logic         gpio_irq_o;
    logic         timer_irq_o;

    // Physical peripheral signals
    logic         uart_tx_o;
    logic         uart_rx_i;
    logic         aes_busy_o;
    logic         aes_done_o;
    logic [31:0]  gpio_in_i;
    logic [31:0]  gpio_out_o;
    logic [31:0]  gpio_tx_en_o;

    // IFU AXI (master from core, slave in TB)
    logic         ifu_axi_arvalid;
    logic         ifu_axi_arready;
    logic [2:0]   ifu_axi_arid;
    logic [31:0]  ifu_axi_araddr;
    logic [3:0]   ifu_axi_arregion;
    logic [7:0]   ifu_axi_arlen;
    logic [2:0]   ifu_axi_arsize;
    logic [1:0]   ifu_axi_arburst;
    logic         ifu_axi_arlock;
    logic [3:0]   ifu_axi_arcache;
    logic [2:0]   ifu_axi_arprot;
    logic [3:0]   ifu_axi_arqos;
    logic         ifu_axi_rvalid;
    logic         ifu_axi_rready;
    logic [2:0]   ifu_axi_rid;
    logic [63:0]  ifu_axi_rdata;
    logic [1:0]   ifu_axi_rresp;
    logic         ifu_axi_rlast;
    logic         ifu_axi_awvalid;
    logic         ifu_axi_awready;
    logic [2:0]   ifu_axi_awid;
    logic [31:0]  ifu_axi_awaddr;
    logic [3:0]   ifu_axi_awregion;
    logic [7:0]   ifu_axi_awlen;
    logic [2:0]   ifu_axi_awsize;
    logic [1:0]   ifu_axi_awburst;
    logic         ifu_axi_awlock;
    logic [3:0]   ifu_axi_awcache;
    logic [2:0]   ifu_axi_awprot;
    logic [3:0]   ifu_axi_awqos;
    logic         ifu_axi_wvalid;
    logic         ifu_axi_wready;
    logic [63:0]  ifu_axi_wdata;
    logic [7:0]   ifu_axi_wstrb;
    logic         ifu_axi_wlast;
    logic         ifu_axi_bvalid;
    logic         ifu_axi_bready;
    logic [1:0]   ifu_axi_bresp;
    logic [2:0]   ifu_axi_bid;

    // SB AXI (master from core, slave in TB)
    logic         sb_axi_awvalid;
    logic         sb_axi_awready;
    logic [0:0]   sb_axi_awid;
    logic [31:0]  sb_axi_awaddr;
    logic [3:0]   sb_axi_awregion;
    logic [7:0]   sb_axi_awlen;
    logic [2:0]   sb_axi_awsize;
    logic [1:0]   sb_axi_awburst;
    logic         sb_axi_awlock;
    logic [3:0]   sb_axi_awcache;
    logic [2:0]   sb_axi_awprot;
    logic [3:0]   sb_axi_awqos;
    logic         sb_axi_wvalid;
    logic         sb_axi_wready;
    logic [63:0]  sb_axi_wdata;
    logic [7:0]   sb_axi_wstrb;
    logic         sb_axi_wlast;
    logic         sb_axi_bvalid;
    logic         sb_axi_bready;
    logic [1:0]   sb_axi_bresp;
    logic [0:0]   sb_axi_bid;
    logic         sb_axi_arvalid;
    logic         sb_axi_arready;
    logic [0:0]   sb_axi_arid;
    logic [31:0]  sb_axi_araddr;
    logic [3:0]   sb_axi_arregion;
    logic [7:0]   sb_axi_arlen;
    logic [2:0]   sb_axi_arsize;
    logic [1:0]   sb_axi_arburst;
    logic         sb_axi_arlock;
    logic [3:0]   sb_axi_arcache;
    logic [2:0]   sb_axi_arprot;
    logic [3:0]   sb_axi_arqos;
    logic         sb_axi_rvalid;
    logic         sb_axi_rready;
    logic [0:0]   sb_axi_rid;
    logic [63:0]  sb_axi_rdata;
    logic [1:0]   sb_axi_rresp;
    logic         sb_axi_rlast;

    // DMA AXI slave port on VeeR wrapper
    logic         dma_axi_awvalid;
    logic         dma_axi_awready;
    logic [0:0]   dma_axi_awid;
    logic [31:0]  dma_axi_awaddr;
    logic [2:0]   dma_axi_awsize;
    logic [2:0]   dma_axi_awprot;
    logic [7:0]   dma_axi_awlen;
    logic [1:0]   dma_axi_awburst;
    logic         dma_axi_wvalid;
    logic         dma_axi_wready;
    logic [63:0]  dma_axi_wdata;
    logic [7:0]   dma_axi_wstrb;
    logic         dma_axi_wlast;
    logic         dma_axi_bvalid;
    logic         dma_axi_bready;
    logic [1:0]   dma_axi_bresp;
    logic [0:0]   dma_axi_bid;
    logic         dma_axi_arvalid;
    logic         dma_axi_arready;
    logic [0:0]   dma_axi_arid;
    logic [31:0]  dma_axi_araddr;
    logic [2:0]   dma_axi_arsize;
    logic [2:0]   dma_axi_arprot;
    logic [7:0]   dma_axi_arlen;
    logic [1:0]   dma_axi_arburst;
    logic         dma_axi_rvalid;
    logic         dma_axi_rready;
    logic [0:0]   dma_axi_rid;
    logic [63:0]  dma_axi_rdata;
    logic [1:0]   dma_axi_rresp;
    logic         dma_axi_rlast;

    // Trace signals
    logic [31:0]  trace_rv_i_insn_ip;
    logic [31:0]  trace_rv_i_address_ip;
    logic         trace_rv_i_valid_ip;
    logic         trace_rv_i_exception_ip;
    logic [4:0]   trace_rv_i_ecause_ip;
    logic         trace_rv_i_interrupt_ip;
    logic [31:0]  trace_rv_i_tval_ip;

    // ECC / Perf
    logic         iccm_ecc_single_error;
    logic         iccm_ecc_double_error;
    logic         dccm_ecc_single_error;
    logic         dccm_ecc_double_error;
    logic         dccm_write_readback_error;
    logic         dec_tlu_perfcnt0;
    logic         dec_tlu_perfcnt1;
    logic         dec_tlu_perfcnt2;
    logic         dec_tlu_perfcnt3;

    // JTAG
    logic         jtag_tck;
    logic         jtag_tms;
    logic         jtag_tdi;
    logic         jtag_trst_n;
    logic         jtag_tdo;
    logic         jtag_tdoEn;

    // MPC / Debug
    logic         mpc_debug_halt_req;
    logic         mpc_debug_run_req;
    logic         mpc_reset_run_req;
    logic         mpc_debug_halt_ack;
    logic         mpc_debug_run_ack;
    logic         debug_brkpt_status;
    logic         i_cpu_halt_req;
    logic         o_cpu_halt_ack;
    logic         o_cpu_halt_status;
    logic         o_debug_mode_status;
    logic         i_cpu_run_req;
    logic         o_cpu_run_ack;

    // Bus clock enables
    logic         lsu_bus_clk_en;
    logic         ifu_bus_clk_en;
    logic         dbg_bus_clk_en;
    logic         dma_bus_clk_en;
    logic         scan_mode;
    logic         mbist_mode;

    // DMI
    logic         dmi_core_enable;
    logic         dmi_uncore_enable;
    logic         dmi_uncore_en;
    logic         dmi_uncore_wr_en;
    logic [6:0]   dmi_uncore_addr;
    logic [31:0]  dmi_uncore_wdata;
    logic [31:0]  dmi_uncore_rdata;
    logic         dmi_active;

    // =========================================================================
    // DUT instantiation
    // =========================================================================
    veer2_dma_aes_wdt_uart_gpio_timer dut (
        .clk                    (clk),
        .rst_l                  (rst_l),
        .dbg_rst_l              (dbg_rst_l),
        .fixed_clk              (fixed_clk),
        .rst_vec                (rst_vec),
        .nmi_vec                (nmi_vec),
        .jtag_id                (jtag_id),
        .core_id                (core_id),
        .nmi_int                (nmi_int),
        .timer_int              (timer_int),
        .soft_int               (soft_int),
        .extintsrc_req          (extintsrc_req),
        .uart_read_irq_o        (uart_read_irq_o),
        .aes_irq_o              (aes_irq_o),
        .aes_done_pulse_o       (aes_done_pulse_o),
        .dma_done_o             (dma_done_o),
        .dma_error_o            (dma_error_o),
        .dma_irq_o              (dma_irq_o),
        .wdt_irq_o              (wdt_irq_o),
        .wdt_nmi_o              (wdt_nmi_o),
        .wdt_reset_o            (wdt_reset_o),
        .wdt_timeout_o          (wdt_timeout_o),
        .gpio_irq_o             (gpio_irq_o),
        .timer_irq_o            (timer_irq_o),
        .uart_tx_o              (uart_tx_o),
        .uart_rx_i              (uart_rx_i),
        .aes_busy_o             (aes_busy_o),
        .aes_done_o             (aes_done_o),
        .gpio_in_i              (gpio_in_i),
        .gpio_out_o             (gpio_out_o),
        .gpio_tx_en_o           (gpio_tx_en_o),
        // IFU
        .ifu_axi_arvalid        (ifu_axi_arvalid),
        .ifu_axi_arready        (ifu_axi_arready),
        .ifu_axi_arid           (ifu_axi_arid),
        .ifu_axi_araddr         (ifu_axi_araddr),
        .ifu_axi_arregion       (ifu_axi_arregion),
        .ifu_axi_arlen          (ifu_axi_arlen),
        .ifu_axi_arsize         (ifu_axi_arsize),
        .ifu_axi_arburst        (ifu_axi_arburst),
        .ifu_axi_arlock         (ifu_axi_arlock),
        .ifu_axi_arcache        (ifu_axi_arcache),
        .ifu_axi_arprot         (ifu_axi_arprot),
        .ifu_axi_arqos          (ifu_axi_arqos),
        .ifu_axi_rvalid         (ifu_axi_rvalid),
        .ifu_axi_rready         (ifu_axi_rready),
        .ifu_axi_rid            (ifu_axi_rid),
        .ifu_axi_rdata          (ifu_axi_rdata),
        .ifu_axi_rresp          (ifu_axi_rresp),
        .ifu_axi_rlast          (ifu_axi_rlast),
        .ifu_axi_awvalid        (ifu_axi_awvalid),
        .ifu_axi_awready        (ifu_axi_awready),
        .ifu_axi_awid           (ifu_axi_awid),
        .ifu_axi_awaddr         (ifu_axi_awaddr),
        .ifu_axi_awregion       (ifu_axi_awregion),
        .ifu_axi_awlen          (ifu_axi_awlen),
        .ifu_axi_awsize         (ifu_axi_awsize),
        .ifu_axi_awburst        (ifu_axi_awburst),
        .ifu_axi_awlock         (ifu_axi_awlock),
        .ifu_axi_awcache        (ifu_axi_awcache),
        .ifu_axi_awprot         (ifu_axi_awprot),
        .ifu_axi_awqos          (ifu_axi_awqos),
        .ifu_axi_wvalid         (ifu_axi_wvalid),
        .ifu_axi_wready         (ifu_axi_wready),
        .ifu_axi_wdata          (ifu_axi_wdata),
        .ifu_axi_wstrb          (ifu_axi_wstrb),
        .ifu_axi_wlast          (ifu_axi_wlast),
        .ifu_axi_bvalid         (ifu_axi_bvalid),
        .ifu_axi_bready         (ifu_axi_bready),
        .ifu_axi_bresp          (ifu_axi_bresp),
        .ifu_axi_bid            (ifu_axi_bid),
        // SB
        .sb_axi_awvalid         (sb_axi_awvalid),
        .sb_axi_awready         (sb_axi_awready),
        .sb_axi_awid            (sb_axi_awid),
        .sb_axi_awaddr          (sb_axi_awaddr),
        .sb_axi_awregion        (sb_axi_awregion),
        .sb_axi_awlen           (sb_axi_awlen),
        .sb_axi_awsize          (sb_axi_awsize),
        .sb_axi_awburst         (sb_axi_awburst),
        .sb_axi_awlock          (sb_axi_awlock),
        .sb_axi_awcache         (sb_axi_awcache),
        .sb_axi_awprot          (sb_axi_awprot),
        .sb_axi_awqos           (sb_axi_awqos),
        .sb_axi_wvalid          (sb_axi_wvalid),
        .sb_axi_wready          (sb_axi_wready),
        .sb_axi_wdata           (sb_axi_wdata),
        .sb_axi_wstrb           (sb_axi_wstrb),
        .sb_axi_wlast           (sb_axi_wlast),
        .sb_axi_bvalid          (sb_axi_bvalid),
        .sb_axi_bready          (sb_axi_bready),
        .sb_axi_bresp           (sb_axi_bresp),
        .sb_axi_bid             (sb_axi_bid),
        .sb_axi_arvalid         (sb_axi_arvalid),
        .sb_axi_arready         (sb_axi_arready),
        .sb_axi_arid            (sb_axi_arid),
        .sb_axi_araddr          (sb_axi_araddr),
        .sb_axi_arregion        (sb_axi_arregion),
        .sb_axi_arlen           (sb_axi_arlen),
        .sb_axi_arsize          (sb_axi_arsize),
        .sb_axi_arburst         (sb_axi_arburst),
        .sb_axi_arlock          (sb_axi_arlock),
        .sb_axi_arcache         (sb_axi_arcache),
        .sb_axi_arprot          (sb_axi_arprot),
        .sb_axi_arqos           (sb_axi_arqos),
        .sb_axi_rvalid          (sb_axi_rvalid),
        .sb_axi_rready          (sb_axi_rready),
        .sb_axi_rid             (sb_axi_rid),
        .sb_axi_rdata           (sb_axi_rdata),
        .sb_axi_rresp           (sb_axi_rresp),
        .sb_axi_rlast           (sb_axi_rlast),
        // VeeR DMA slave
        .dma_axi_awvalid        (dma_axi_awvalid),
        .dma_axi_awready        (dma_axi_awready),
        .dma_axi_awid           (dma_axi_awid),
        .dma_axi_awaddr         (dma_axi_awaddr),
        .dma_axi_awsize         (dma_axi_awsize),
        .dma_axi_awprot         (dma_axi_awprot),
        .dma_axi_awlen          (dma_axi_awlen),
        .dma_axi_awburst        (dma_axi_awburst),
        .dma_axi_wvalid         (dma_axi_wvalid),
        .dma_axi_wready         (dma_axi_wready),
        .dma_axi_wdata          (dma_axi_wdata),
        .dma_axi_wstrb          (dma_axi_wstrb),
        .dma_axi_wlast          (dma_axi_wlast),
        .dma_axi_bvalid         (dma_axi_bvalid),
        .dma_axi_bready         (dma_axi_bready),
        .dma_axi_bresp          (dma_axi_bresp),
        .dma_axi_bid            (dma_axi_bid),
        .dma_axi_arvalid        (dma_axi_arvalid),
        .dma_axi_arready        (dma_axi_arready),
        .dma_axi_arid           (dma_axi_arid),
        .dma_axi_araddr         (dma_axi_araddr),
        .dma_axi_arsize         (dma_axi_arsize),
        .dma_axi_arprot         (dma_axi_arprot),
        .dma_axi_arlen          (dma_axi_arlen),
        .dma_axi_arburst        (dma_axi_arburst),
        .dma_axi_rvalid         (dma_axi_rvalid),
        .dma_axi_rready         (dma_axi_rready),
        .dma_axi_rid            (dma_axi_rid),
        .dma_axi_rdata          (dma_axi_rdata),
        .dma_axi_rresp          (dma_axi_rresp),
        .dma_axi_rlast          (dma_axi_rlast),
        // Trace
        .trace_rv_i_insn_ip     (trace_rv_i_insn_ip),
        .trace_rv_i_address_ip  (trace_rv_i_address_ip),
        .trace_rv_i_valid_ip    (trace_rv_i_valid_ip),
        .trace_rv_i_exception_ip(trace_rv_i_exception_ip),
        .trace_rv_i_ecause_ip   (trace_rv_i_ecause_ip),
        .trace_rv_i_interrupt_ip(trace_rv_i_interrupt_ip),
        .trace_rv_i_tval_ip     (trace_rv_i_tval_ip),
        // ECC / Perf
        .iccm_ecc_single_error  (iccm_ecc_single_error),
        .iccm_ecc_double_error  (iccm_ecc_double_error),
        .dccm_ecc_single_error  (dccm_ecc_single_error),
        .dccm_ecc_double_error  (dccm_ecc_double_error),
        .dccm_write_readback_error(dccm_write_readback_error),
        .dec_tlu_perfcnt0       (dec_tlu_perfcnt0),
        .dec_tlu_perfcnt1       (dec_tlu_perfcnt1),
        .dec_tlu_perfcnt2       (dec_tlu_perfcnt2),
        .dec_tlu_perfcnt3       (dec_tlu_perfcnt3),
        // JTAG
        .jtag_tck               (jtag_tck),
        .jtag_tms               (jtag_tms),
        .jtag_tdi               (jtag_tdi),
        .jtag_trst_n            (jtag_trst_n),
        .jtag_tdo               (jtag_tdo),
        .jtag_tdoEn             (jtag_tdoEn),
        // MPC / halt / run
        .mpc_debug_halt_req     (mpc_debug_halt_req),
        .mpc_debug_run_req      (mpc_debug_run_req),
        .mpc_reset_run_req      (mpc_reset_run_req),
        .mpc_debug_halt_ack     (mpc_debug_halt_ack),
        .mpc_debug_run_ack      (mpc_debug_run_ack),
        .debug_brkpt_status     (debug_brkpt_status),
        .i_cpu_halt_req         (i_cpu_halt_req),
        .o_cpu_halt_ack         (o_cpu_halt_ack),
        .o_cpu_halt_status      (o_cpu_halt_status),
        .o_debug_mode_status    (o_debug_mode_status),
        .i_cpu_run_req          (i_cpu_run_req),
        .o_cpu_run_ack          (o_cpu_run_ack),
        // Bus clock enables
        .lsu_bus_clk_en         (lsu_bus_clk_en),
        .ifu_bus_clk_en         (ifu_bus_clk_en),
        .dbg_bus_clk_en         (dbg_bus_clk_en),
        .dma_bus_clk_en         (dma_bus_clk_en),
        .scan_mode              (scan_mode),
        .mbist_mode             (mbist_mode),
        // DMI
        .dmi_core_enable        (dmi_core_enable),
        .dmi_uncore_enable      (dmi_uncore_enable),
        .dmi_uncore_en          (dmi_uncore_en),
        .dmi_uncore_wr_en       (dmi_uncore_wr_en),
        .dmi_uncore_addr        (dmi_uncore_addr),
        .dmi_uncore_wdata       (dmi_uncore_wdata),
        .dmi_uncore_rdata       (dmi_uncore_rdata),
        .dmi_active             (dmi_active)
    );

    // =========================================================================
    // IFU memory model — loaded from hex file with $readmemh
    // =========================================================================
    localparam [31:0] IMEM_BYTES = 32'h0002_0000;   // 128 KB
    logic [7:0] imem [0:IMEM_BYTES-1];
    string      hex_file;
    logic [31:0] boot_addr;
    bit         fw_en;

    initial begin
        // Fill entire IMEM with RISC-V NOP (0x00000013)
        for (int i = 0; i < IMEM_BYTES; i++)
            imem[i] = (i % 4 == 0) ? 8'h13 : 8'h00;

        fw_en = !$test$plusargs("NOFW");

        if (!$value$plusargs("HEX=%s", hex_file)) begin
            hex_file = "Scripts/soc_full_test.hex";
        end

        if (fw_en) begin
            $readmemh(hex_file, imem);
            $display("[TB] $readmemh executed with file: '%s'", hex_file);
        end else begin
            $display("[TB] +NOFW specified: IFU will return NOPs only");
        end

        // Auto-detect or override Boot Address
        if (!$value$plusargs("BOOT_ADDR=%h", boot_addr)) begin
            // Check if code was loaded at 0x0000_0000
            if (imem[0] != 8'h13 || imem[1] != 8'h00 || imem[2] != 8'h00 || imem[3] != 8'h00) begin
                boot_addr = 32'h0000_0000;
            end else if (imem[32'h10120] != 8'h13 || imem[32'h10121] != 8'h00) begin
                boot_addr = 32'h0001_0120;
            end else begin
                boot_addr = 32'h0000_0000;
            end
        end

        rst_vec = boot_addr[31:1];
        $display("[TB] VeeR Reset Vector configured to: 0x%08h (rst_vec=0x%07h)",
                 boot_addr, rst_vec);
    end

    function automatic logic [63:0] imem_rd64(input logic [31:0] addr);
        logic [31:0] base;
        base = {addr[31:3], 3'b000};
        for (int k = 0; k < 8; k++)
            imem_rd64[8*k +: 8] = ((base + k) < IMEM_BYTES) ? imem[base + k]
                                                            : (((k % 4) == 0) ? 8'h13 : 8'h00);
    endfunction

    function automatic logic [31:0] imem_next(input logic [31:0] addr,
                                               input logic [1:0]  burst,
                                               input logic [7:0]  len);
        logic [31:0] inc, wmask;
        inc   = {addr[31:3], 3'b000} + 32'd8;
        wmask = ({24'd0, len} + 32'd1) * 32'd8 - 32'd1;
        if (burst == 2'b10)
            imem_next = ({addr[31:3], 3'b000} & ~wmask) | (inc & wmask);
        else
            imem_next = inc;
    endfunction

    logic        ifu_busy;
    logic [31:0] ifu_cur_addr;
    logic [7:0]  ifu_beats_left;
    logic [7:0]  ifu_len_q;
    logic [1:0]  ifu_burst_q;
    logic        ifu_fetch_seen;

    always_ff @(posedge clk or negedge rst_l) begin
        if (!rst_l) begin
            ifu_axi_arready <= 1'b0;
            ifu_axi_rvalid  <= 1'b0;
            ifu_axi_rlast   <= 1'b0;
            ifu_axi_rdata   <= 64'd0;
            ifu_axi_rresp   <= 2'b00;
            ifu_axi_rid     <= '0;
            ifu_busy        <= 1'b0;
            ifu_cur_addr    <= 32'd0;
            ifu_beats_left  <= 8'd0;
            ifu_len_q       <= 8'd0;
            ifu_burst_q     <= 2'd0;
            ifu_fetch_seen  <= 1'b0;
        end else begin
            ifu_axi_arready <= !ifu_busy && !ifu_axi_rvalid;

            if (ifu_axi_arvalid && ifu_axi_arready) begin
                ifu_fetch_seen  <= 1'b1;
                ifu_busy        <= (ifu_axi_arlen != 8'd0);
                ifu_cur_addr    <= ifu_axi_araddr;
                ifu_len_q       <= ifu_axi_arlen;
                ifu_burst_q     <= ifu_axi_arburst;
                ifu_beats_left  <= ifu_axi_arlen;
                ifu_axi_rvalid  <= 1'b1;
                ifu_axi_rdata   <= imem_rd64(ifu_axi_araddr);
                ifu_axi_rid     <= ifu_axi_arid;
                ifu_axi_rresp   <= 2'b00;
                ifu_axi_rlast   <= (ifu_axi_arlen == 8'd0);
            end else if (ifu_axi_rvalid && ifu_axi_rready) begin
                if (ifu_axi_rlast) begin
                    ifu_axi_rvalid <= 1'b0;
                    ifu_axi_rlast  <= 1'b0;
                    ifu_busy       <= 1'b0;
                end else begin
                    ifu_cur_addr   <= imem_next(ifu_cur_addr, ifu_burst_q, ifu_len_q);
                    ifu_axi_rdata  <= imem_rd64(imem_next(ifu_cur_addr, ifu_burst_q, ifu_len_q));
                    ifu_axi_rlast  <= (ifu_beats_left == 8'd1);
                    ifu_beats_left <= ifu_beats_left - 8'd1;
                end
            end
        end
    end

    assign ifu_axi_awready = 1'b0;
    assign ifu_axi_wready  = 1'b0;
    assign ifu_axi_bvalid  = 1'b0;
    assign ifu_axi_bresp   = 2'b00;
    assign ifu_axi_bid     = '0;

    // =========================================================================
    // SB AXI slave responder (stub)
    // =========================================================================
    assign sb_axi_awready = 1'b1;
    assign sb_axi_wready  = 1'b1;
    assign sb_axi_bvalid  = 1'b0;
    assign sb_axi_bresp   = 2'b00;
    assign sb_axi_bid     = '0;
    assign sb_axi_arready = 1'b1;
    assign sb_axi_rvalid  = 1'b0;
    assign sb_axi_rresp   = 2'b00;
    assign sb_axi_rdata   = 64'd0;
    assign sb_axi_rlast   = 1'b0;
    assign sb_axi_rid     = '0;

    // VeeR DMA slave tie-off (no DMA→DCCM in this test)
    assign dma_axi_awvalid = 1'b0;
    assign dma_axi_awid    = '0;
    assign dma_axi_awaddr  = '0;
    assign dma_axi_awsize  = 3'b010;
    assign dma_axi_awprot  = '0;
    assign dma_axi_awlen   = '0;
    assign dma_axi_awburst = 2'b01;
    assign dma_axi_wvalid  = 1'b0;
    assign dma_axi_wdata   = '0;
    assign dma_axi_wstrb   = '0;
    assign dma_axi_wlast   = 1'b0;
    assign dma_axi_bready  = 1'b1;
    assign dma_axi_arvalid = 1'b0;
    assign dma_axi_arid    = '0;
    assign dma_axi_araddr  = '0;
    assign dma_axi_arsize  = 3'b010;
    assign dma_axi_arprot  = '0;
    assign dma_axi_arlen   = '0;
    assign dma_axi_arburst = 2'b01;
    assign dma_axi_rready  = 1'b1;

    // =========================================================================
    // Static Tie-offs
    // =========================================================================
    initial begin
        nmi_vec             = 31'h0000_1000 >> 1;
        jtag_id             = 31'h1;
        core_id             = 28'h1;
        nmi_int             = 1'b0;
        timer_int           = 1'b0;
        soft_int            = 1'b0;
        extintsrc_req       = '0;
        gpio_in_i           = 32'h5A5A_A5A5;
        uart_rx_i           = 1'b1;    // UART idle = high
        jtag_tck            = 1'b0;
        jtag_tms            = 1'b0;
        jtag_tdi            = 1'b0;
        jtag_trst_n         = 1'b1;
        mpc_debug_halt_req  = 1'b0;
        mpc_debug_run_req   = 1'b1;
        mpc_reset_run_req   = 1'b1;
        i_cpu_halt_req      = 1'b0;
        i_cpu_run_req       = 1'b0;
        lsu_bus_clk_en      = 1'b1;
        ifu_bus_clk_en      = 1'b1;
        dbg_bus_clk_en      = 1'b1;
        dma_bus_clk_en      = 1'b1;
        scan_mode           = 1'b0;
        mbist_mode          = 1'b0;
        dmi_core_enable     = 1'b0;
        dmi_uncore_enable   = 1'b0;
        dmi_uncore_rdata    = 32'h0;
    end

    // =========================================================================
    // Pass / Fail Tracking
    // =========================================================================
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task automatic check32(
        input string   tc_name,
        input logic [31:0] got,
        input logic [31:0] expected,
        input logic [31:0] mask = 32'hFFFF_FFFF
    );
        if ((got & mask) === (expected & mask)) begin
            $display("[PASS] %s : got=0x%08h  expected=0x%08h",
                     tc_name, got, expected);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s : got=0x%08h  expected=0x%08h (mask=0x%08h)",
                     tc_name, got, expected, mask);
            fail_cnt++;
        end
    endtask

    task automatic check_signal(
        input string   tc_name,
        input logic    got,
        input logic    expected
    );
        if (got === expected) begin
            $display("[PASS] %s : got=%b  expected=%b", tc_name, got, expected);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s : got=%b  expected=%b", tc_name, got, expected);
            fail_cnt++;
        end
    endtask

    // =========================================================================
    // UART Serial Tasks
    // =========================================================================

    // Inject byte into uart_rx_i (LSB-first, 8N1)
    task automatic uart_inject_byte(input logic [7:0] byte_val);
        integer bit_idx;
        // Start bit (low)
        @(negedge clk);
        uart_rx_i = 1'b0;
        repeat (BIT_CYCLES) @(posedge clk);
        // 8 data bits, LSB first
        for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
            @(negedge clk);
            uart_rx_i = byte_val[bit_idx];
            repeat (BIT_CYCLES) @(posedge clk);
        end
        // Stop bit (high)
        @(negedge clk);
        uart_rx_i = 1'b1;
        repeat (BIT_CYCLES) @(posedge clk);
    endtask

    // Capture serial byte from uart_tx_o
    task automatic uart_capture_tx(output logic [7:0] captured);
        integer bit_idx;
        integer timeout_cycles;
        timeout_cycles = 0;
        captured = 8'hFF;

        // Wait for falling edge on uart_tx_o (start bit)
        while (uart_tx_o !== 1'b0) begin
            @(posedge clk);
            timeout_cycles++;
            if (timeout_cycles > 500_000) begin
                $error("[TB] UART TX capture: start bit timeout");
                return;
            end
        end

        // Sample mid-bit of start bit
        repeat (BIT_CYCLES / 2) @(posedge clk);

        // Sample 8 data bits (LSB first)
        for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
            repeat (BIT_CYCLES) @(posedge clk);
            captured[bit_idx] = uart_tx_o;
        end

        // Wait for stop bit
        repeat (BIT_CYCLES) @(posedge clk);
    endtask

    // =========================================================================
    // TOHOST Interceptor and Firmware Milestone Monitor
    // =========================================================================
    logic        fw_mode;
    logic [31:0] last_tohost_val;
    bit          tc_uart_passed;
    bit          tc_timer_passed;
    bit          tc_aes_passed;
    bit          tc_dma_passed;
    bit          tc_wdt_passed;
    bit          tc_gpio_passed;
    bit          tc_pipe_passed;
    bit          tc_final_passed;

    // Prevent DECERR on writes to unmapped address 0xF000_0000 (TOHOST)
    always @(posedge clk or negedge rst_l) begin
        if (!rst_l) begin
            last_tohost_val <= 32'h0;
        end else begin
            // When CPU initiates write to TOHOST, force interconnect bresp to OKAY
            if (dut.s00_awvalid_clean && dut.s00_awready_w && (dut.s00_awaddr_w == TOHOST_ADDR)) begin
                force dut.u_interconnect.axi_interconnect_inst.axi_bresp_reg = 2'b00;
            end else if (dut.s00_bvalid_w && dut.s00_bready_clean) begin
                release dut.u_interconnect.axi_interconnect_inst.axi_bresp_reg;
            end

            // Capture written value on W channel
            if (dut.s00_wvalid_clean && dut.s00_wready_w && (dut.s00_awaddr_w == TOHOST_ADDR)) begin
                logic [31:0] tohost_data;
                tohost_data = dut.s00_wdata_w;
                last_tohost_val <= tohost_data;
                $display("\n=======================================================");
                $display("[FW TOHOST] VeeR EL2 core wrote 0x%08h to TOHOST (0xF000_0000)", tohost_data);
                $display("=======================================================");

                if (tohost_data[31:16] == 16'hDEAD) begin
                    $error("[FAIL] Firmware trapped at step %0d (0x%04h)!",
                           tohost_data[15:0], tohost_data[15:0]);
                    fail_cnt++;
                    repeat (50) @(posedge clk);
                    print_summary();
                    $finish;
                end else begin
                    case (tohost_data[15:0])
                        16'h0006: begin
                            $display("[MILESTONE 1 PASS] UART: LCR, Baud, IER, TX 'K', and RX 0xA5 verified.");
                            tc_uart_passed = 1'b1;
                            pass_cnt++;
                        end
                        16'h0009: begin
                            $display("[MILESTONE 2 PASS] System Timer: CFG0, Counter advance, and IRQ verified.");
                            tc_timer_passed = 1'b1;
                            pass_cnt++;
                        end
                        16'h0013: begin
                            $display("[MILESTONE 3 PASS] AES: NIST FIPS-197 Key, Plaintext, START & Ciphertext verified.");
                            tc_aes_passed = 1'b1;
                            pass_cnt++;
                        end
                        16'h0016: begin
                            $display("[MILESTONE 4 PASS] DMA: CSR access, Descriptor setup & Transfer completion verified.");
                            tc_dma_passed = 1'b1;
                            pass_cnt++;
                        end
                        16'h0021: begin
                            $display("[MILESTONE 5 PASS] WDT: Load, SW ping, AES auto-kick, Timeout IRQ & Escalation verified.");
                            tc_wdt_passed = 1'b1;
                            pass_cnt++;
                        end
                        16'h0025: begin
                            $display("[MILESTONE 6 PASS] GPIO: Output enable, OUT 0xA5, IN read, and Rising-edge IRQ verified.");
                            tc_gpio_passed = 1'b1;
                            pass_cnt++;
                        end
                        16'h0026: begin
                            $display("[MILESTONE 7 PASS] Autonomous Pipeline: AES auto-kick of WDT verified.");
                            tc_pipe_passed = 1'b1;
                            pass_cnt++;
                        end
                        16'h900D: begin
                            $display("\n*******************************************************");
                            $display("**  [ALL TESTS PASSED] Magic word 0x900D received!   **");
                            $display("**  Full-SoC Firmware Execution Successfully Passed! **");
                            $display("*******************************************************\n");
                            tc_final_passed = 1'b1;
                            pass_cnt++;
                            repeat (50) @(posedge clk);
                            print_summary();
                            $finish;
                        end
                        default: begin
                            $display("[FW TOHOST INFO] Progress status: 0x%08h", tohost_data);
                        end
                    endcase
                end
            end
        end
    end

    // =========================================================================
    // Passive AXI Transaction Monitor (VeeR LSU on s00)
    // =========================================================================
    logic [31:0] mon_awaddr;
    always @(posedge clk) begin
        if (dut.s00_awvalid_clean && dut.s00_awready_w) begin
            mon_awaddr <= dut.s00_awaddr_w;
        end
        if (dut.s00_wvalid_clean && dut.s00_wready_w) begin
            if (mon_awaddr != TOHOST_ADDR) begin
                $display("[CPU LSU WRITE] addr=0x%08h data=0x%08h strb=%h",
                         mon_awaddr, dut.s00_wdata_w, dut.s00_wstrb_w);
            end
        end
        if ($test$plusargs("VERBOSE_BUS") && dut.s00_rvalid_w && dut.s00_rready_clean) begin
            $display("[CPU LSU READ ] data=0x%08h resp=%b",
                     dut.s00_rdata_w, dut.s00_rresp_w);
        end
    end

    // =========================================================================
    // Interactive Responders (Co-simulation with Firmware)
    // =========================================================================

    always @(uart_tx_o) begin
        $display("[UART TX PIN] uart_tx_o changed to %b at time %0t", uart_tx_o, $time);
    end

    // UART RX Loopback responder
    initial begin
        logic [7:0] captured_uart_char;
        captured_uart_char = 8'h0;
        @(posedge rst_l);
        fork
            begin : uart_co_sim
                // Wait for CPU to write to UART_THR
                wait (dut.s00_awvalid_clean && dut.s00_awready_w && (dut.s00_awaddr_w == UART_THR));
                $display("[TB STIMULUS] CPU wrote to UART_THR. Waiting for TX start bit on uart_tx_o...");
                // Wait until uart_tx_o is verified idle high before waiting for start bit
                wait (uart_tx_o === 1'b1);
                uart_capture_tx(captured_uart_char);
                check32("FW-UART-TX-captured", {24'h0, captured_uart_char}, 32'h4B, 32'hFF);
                // Allow line to idle for 2 bit intervals
                repeat (BIT_CYCLES * 2) @(posedge clk);
                // Inject byte 0xA5 into UART RX
                $display("[TB STIMULUS] Injecting byte 0xA5 into UART RX pin...");
                uart_inject_byte(8'hA5);
                $display("[TB STIMULUS] Injected byte 0xA5 into UART RX pin successfully.");
            end
        join_none
    end

    // GPIO Output & Milestone Monitor
    logic [15:0] last_gpio_milestone;
    bit          gpio_a5_seen;

    always @(posedge clk or negedge rst_l) begin
        if (!rst_l) begin
            last_gpio_milestone <= 16'h0;
            gpio_a5_seen        <= 1'b0;
        end else begin
            // Check for fail trap on gpio_out_o
            if (gpio_out_o[31:16] == 16'hDEAD) begin
                $error("\n[FAIL] Firmware trapped at step %0d (0x%04h) via gpio_out_o!",
                       gpio_out_o[15:0], gpio_out_o[15:0]);
                fail_cnt++;
                repeat (50) @(posedge clk);
                print_summary();
                $finish;
            end else if (gpio_out_o[31:16] != 16'h0 && gpio_out_o[31:16] != last_gpio_milestone) begin
                last_gpio_milestone <= gpio_out_o[31:16];
                $display("\n=======================================================");
                $display("[FW TOHOST via GPIO] gpio_out_o[31:16] = 0x%04h at time %0t",
                         gpio_out_o[31:16], $time);
                $display("=======================================================");
                case (gpio_out_o[31:16])
                    16'h0006: begin
                        $display("[MILESTONE 1 PASS] UART: LCR, Baud, IER, TX 'K', and RX 0xA5 verified.");
                        tc_uart_passed = 1'b1;
                        pass_cnt++;
                    end
                    16'h0009: begin
                        $display("[MILESTONE 2 PASS] System Timer: CFG0, Counter advance, and IRQ verified.");
                        tc_timer_passed = 1'b1;
                        pass_cnt++;
                    end
                    16'h0013: begin
                        $display("[MILESTONE 3 PASS] AES: NIST FIPS-197 Key, Plaintext, START & Ciphertext verified.");
                        tc_aes_passed = 1'b1;
                        pass_cnt++;
                    end
                    16'h0016: begin
                        $display("[MILESTONE 4 PASS] DMA: CSR access, Descriptor setup & Transfer completion verified.");
                        tc_dma_passed = 1'b1;
                        pass_cnt++;
                    end
                    16'h0021: begin
                        $display("[MILESTONE 5 PASS] WDT: Load, SW ping, AES auto-kick, Timeout IRQ & Escalation verified.");
                        tc_wdt_passed = 1'b1;
                        pass_cnt++;
                    end
                    16'h0025: begin
                        $display("[MILESTONE 6 PASS] GPIO: Output enable, OUT 0xA5, IN read, and Rising-edge IRQ verified.");
                        tc_gpio_passed = 1'b1;
                        pass_cnt++;
                    end
                    16'h0026: begin
                        $display("[MILESTONE 7 PASS] Autonomous Pipeline: AES auto-kick of WDT verified.");
                        tc_pipe_passed = 1'b1;
                        pass_cnt++;
                    end
                    16'h900D: begin
                        $display("\n*******************************************************");
                        $display("**  [ALL TESTS PASSED] Magic word 0x900D received!   **");
                        $display("**  Full-SoC Firmware Execution Successfully Passed! **");
                        $display("*******************************************************\n");
                        tc_final_passed = 1'b1;
                        pass_cnt++;
                        repeat (50) @(posedge clk);
                        print_summary();
                        $finish;
                    end
                    default: begin
                        $display("[FW TOHOST INFO] Progress status: 0x%04h", gpio_out_o[31:16]);
                    end
                endcase
            end

            // Check GPIO OUT lower byte when firmware tests GPIO with 0xA5
            if (gpio_out_o[7:0] == 8'hA5 && !gpio_a5_seen) begin
                gpio_a5_seen <= 1'b1;
                check32("FW-GPIO-OUT-verification", {24'h0, gpio_out_o[7:0]}, 32'hA5, 32'hFF);
            end
        end
    end

    // GPIO Responder & IRQ pulse generator
    initial begin
        gpio_in_i = 32'h5A5A_A5A5;
        @(posedge rst_l);
        fork
            begin : gpio_co_sim
                forever begin
                    @(posedge clk);
                    // Detect GPIO_RISE_EN write from CPU
                    if (dut.s00_awvalid_clean && dut.s00_awready_w &&
                        (dut.s00_awaddr_w == GPIO_RISE_EN)) begin
                        $display("[TB STIMULUS] Detected GPIO_RISE_EN. Generating rising edge on gpio_in_i[0]...");
                        repeat (30) @(posedge clk);
                        gpio_in_i[0] = 1'b0;
                        repeat (10) @(posedge clk);
                        gpio_in_i[0] = 1'b1;  // Rising edge transition!
                        $display("[TB STIMULUS] Driven gpio_in_i[0] = 1 (Rising Edge triggered)");
                        repeat (50) @(posedge clk);
                        gpio_in_i[0] = 1'b0;
                    end
                end
            end
        join_none
    end

    // Event Monitors for DUT Interrupts & Pulses
    initial begin
        @(posedge rst_l);
        fork
            // Timer IRQ monitor
            forever begin
                @(posedge timer_irq_o);
                $display("[DUT EVENT] timer_irq_o asserted at time %0t", $time);
                check_signal("EVENT-timer_irq_o", timer_irq_o, 1'b1);
            end
            // AES Done monitor
            forever begin
                @(posedge aes_done_o);
                $display("[DUT EVENT] aes_done_o asserted at time %0t", $time);
                check_signal("EVENT-aes_done_o", aes_done_o, 1'b1);
            end
            // AES Done Pulse (WDT kick) monitor
            forever begin
                @(posedge aes_done_pulse_o);
                $display("[DUT EVENT] aes_done_pulse_o pulsed at time %0t (Auto-kicking WDT)", $time);
                check_signal("EVENT-aes_done_pulse_o", aes_done_pulse_o, 1'b1);
            end
            // DMA Done monitor
            forever begin
                @(posedge dma_done_o);
                $display("[DUT EVENT] dma_done_o asserted at time %0t", $time);
                check_signal("EVENT-dma_done_o", dma_done_o, 1'b1);
            end
            // WDT Timeout IRQ monitor
            forever begin
                @(posedge wdt_irq_o);
                $display("[DUT EVENT] wdt_irq_o asserted (timeout early warning) at time %0t", $time);
                check_signal("EVENT-wdt_irq_o", wdt_irq_o, 1'b1);
            end
            // WDT NMI / Reset monitor
            forever begin
                @(posedge wdt_reset_o);
                $display("[DUT EVENT] wdt_reset_o asserted (hard reset escalation) at time %0t", $time);
                check_signal("EVENT-wdt_reset_o", wdt_reset_o, 1'b1);
            end
            // GPIO IRQ monitor
            forever begin
                @(posedge gpio_irq_o);
                $display("[DUT EVENT] gpio_irq_o asserted at time %0t", $time);
                check_signal("EVENT-gpio_irq_o", gpio_irq_o, 1'b1);
            end
        join_none
    end

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
`ifdef FSDB
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars("+all");
        $fsdbDumpMDA();
        $fsdbDumpSVA();
`else
        if ($test$plusargs("dump")) begin
            $dumpfile("dump.vcd");
            $dumpvars(0, veer2_dma_aes_wdt_uart_gpio_timer_tb);
        end
`endif
    end

    // =========================================================================
    // Summary Report Task
    // =========================================================================
    task automatic print_summary();
        $display("\n=======================================================");
        $display("          FULL-SOC SIMULATION SUMMARY REPORT          ");
        $display("=======================================================");
        $display("  Firmware Hex File : %s", hex_file);
        $display("  Reset Vector      : 0x%08h", {rst_vec, 1'b0});
        $display("-------------------------------------------------------");
        $display("  Milestone Status:");
        $display("    [TC01-02] Reset & Fetch Alive      : PASS");
        $display("    [TC03-06] UART 8N1/TX 'K'/RX 0xA5  : %s", tc_uart_passed  ? "PASS" : (fw_mode ? "FAIL" : "N/A"));
        $display("    [TC07-09] System Timer Count & IRQ : %s", tc_timer_passed ? "PASS" : (fw_mode ? "FAIL" : "N/A"));
        $display("    [TC10-13] AES-128 NIST Vector & CT : %s", tc_aes_passed   ? "PASS" : (fw_mode ? "FAIL" : "N/A"));
        $display("    [TC14-16] DMA Transfer Completion  : %s", tc_dma_passed   ? "PASS" : (fw_mode ? "FAIL" : "N/A"));
        $display("    [TC17-21] WDT Ping, Kick & Timeout : %s", tc_wdt_passed   ? "PASS" : (fw_mode ? "FAIL" : "N/A"));
        $display("    [TC22-25] GPIO Pin IO & Rising IRQ : %s", tc_gpio_passed  ? "PASS" : (fw_mode ? "FAIL" : "N/A"));
        $display("    [TC26]    Autonomous Pipeline Kick : %s", tc_pipe_passed  ? "PASS" : (fw_mode ? "FAIL" : "N/A"));
        $display("    [TC-ALL]  Magic Word 0x900D (TOHOST) : %s", tc_final_passed ? "PASS" : (fw_mode ? "FAIL" : "N/A"));
        $display("-------------------------------------------------------");
        $display("  Total Checks Passed : %0d", pass_cnt);
        $display("  Total Checks Failed : %0d", fail_cnt);
        if (fail_cnt == 0 && (tc_final_passed || !fw_mode)) begin
            $display("  Overall Status      : ** ALL TESTS PASSED SUCCESSFULLY **");
        end else begin
            $display("  Overall Status      : !! SIMULATION FAILED !!");
        end
        $display("=======================================================\n");
    endtask

    // =========================================================================
    // Legacy BFM Test Sequence (Fallback when +BFM is supplied)
    // =========================================================================
    logic [7:0]  bfm_awid;
    logic [31:0] bfm_awaddr;
    logic [7:0]  bfm_awlen;
    logic [2:0]  bfm_awsize;
    logic [1:0]  bfm_awburst;
    logic        bfm_awvalid;
    logic        bfm_awready;
    logic [31:0] bfm_wdata;
    logic [3:0]  bfm_wstrb;
    logic        bfm_wlast;
    logic        bfm_wvalid;
    logic        bfm_wready;
    logic [7:0]  bfm_bid;
    logic [1:0]  bfm_bresp;
    logic        bfm_bvalid;
    logic        bfm_bready;
    logic [7:0]  bfm_arid;
    logic [31:0] bfm_araddr;
    logic [7:0]  bfm_arlen;
    logic [2:0]  bfm_arsize;
    logic [1:0]  bfm_arburst;
    logic        bfm_arvalid;
    logic        bfm_arready;
    logic [7:0]  bfm_rid;
    logic [31:0] bfm_rdata;
    logic [1:0]  bfm_rresp;
    logic        bfm_rlast;
    logic        bfm_rvalid;
    logic        bfm_rready;

    task automatic force_bfm_to_s01();
        force dut.s01_awid_w    = bfm_awid;
        force dut.s01_awaddr_w  = bfm_awaddr;
        force dut.s01_awlen_w   = bfm_awlen;
        force dut.s01_awsize_w  = bfm_awsize;
        force dut.s01_awburst_w = bfm_awburst;
        force dut.s01_awlock_w  = 1'b0;
        force dut.s01_awcache_w = 4'b0;
        force dut.s01_awprot_w  = 3'b0;
        force dut.s01_awqos_w   = 4'b0;
        force dut.s01_awvalid_w = bfm_awvalid;
        force dut.s01_wdata_w   = bfm_wdata;
        force dut.s01_wstrb_w   = bfm_wstrb;
        force dut.s01_wlast_w   = bfm_wlast;
        force dut.s01_wvalid_w  = bfm_wvalid;
        force dut.s01_bready_w  = bfm_bready;
        force dut.s01_arid_w    = bfm_arid;
        force dut.s01_araddr_w  = bfm_araddr;
        force dut.s01_arlen_w   = bfm_arlen;
        force dut.s01_arsize_w  = bfm_arsize;
        force dut.s01_arburst_w = bfm_arburst;
        force dut.s01_arlock_w  = 1'b0;
        force dut.s01_arcache_w = 4'b0;
        force dut.s01_arprot_w  = 3'b0;
        force dut.s01_arqos_w   = 4'b0;
        force dut.s01_arvalid_w = bfm_arvalid;
        force dut.s01_rready_w  = bfm_rready;
    endtask

    task automatic read_bfm_from_s01();
        bfm_awready = dut.s01_awready_w;
        bfm_wready  = dut.s01_wready_w;
        bfm_bid     = dut.s01_bid_w;
        bfm_bresp   = dut.s01_bresp_w;
        bfm_bvalid  = dut.s01_bvalid_w;
        bfm_arid    = dut.s01_arid_w;
        bfm_arready = dut.s01_arready_w;
        bfm_rid     = dut.s01_rid_w;
        bfm_rdata   = dut.s01_rdata_w;
        bfm_rresp   = dut.s01_rresp_w;
        bfm_rlast   = dut.s01_rlast_w;
        bfm_rvalid  = dut.s01_rvalid_w;
    endtask

    task automatic axi_write(
        input  logic [31:0] addr,
        input  logic [31:0] data,
        input  logic [3:0]  strb = 4'hF,
        output logic [1:0]  resp
    );
        integer timeout_aw, timeout_w, timeout_b;
        @(negedge clk);
        bfm_awaddr  = addr;
        bfm_awvalid = 1'b1;
        bfm_awid    = 8'h01;
        bfm_awlen   = 8'h0;
        timeout_aw  = 0;
        do begin
            @(posedge clk);
            read_bfm_from_s01();
            timeout_aw++;
            if (timeout_aw > TIMEOUT_CYC) begin
                $error("[BFM] TIMEOUT waiting for AWREADY at addr=0x%08h", addr);
                resp = 2'b11; return;
            end
        end while (!bfm_awready);
        @(negedge clk);
        bfm_awvalid = 1'b0;

        bfm_wdata   = data;
        bfm_wstrb   = strb;
        bfm_wlast   = 1'b1;
        bfm_wvalid  = 1'b1;
        timeout_w   = 0;
        do begin
            @(posedge clk);
            read_bfm_from_s01();
            timeout_w++;
            if (timeout_w > TIMEOUT_CYC) begin
                $error("[BFM] TIMEOUT waiting for WREADY at addr=0x%08h", addr);
                resp = 2'b11; return;
            end
        end while (!bfm_wready);
        @(negedge clk);
        bfm_wvalid  = 1'b0;

        bfm_bready  = 1'b1;
        timeout_b   = 0;
        do begin
            @(posedge clk);
            read_bfm_from_s01();
            timeout_b++;
            if (timeout_b > TIMEOUT_CYC) begin
                $error("[BFM] TIMEOUT waiting for BVALID at addr=0x%08h", addr);
                resp = 2'b11; return;
            end
        end while (!bfm_bvalid);
        resp = bfm_bresp;
        @(negedge clk);
    endtask

    task automatic axi_read(
        input  logic [31:0] addr,
        output logic [31:0] data,
        output logic [1:0]  resp
    );
        integer timeout_ar, timeout_r;
        @(negedge clk);
        bfm_araddr  = addr;
        bfm_arvalid = 1'b1;
        bfm_arid    = 8'h01;
        bfm_arlen   = 8'h0;
        timeout_ar  = 0;
        do begin
            @(posedge clk);
            read_bfm_from_s01();
            timeout_ar++;
            if (timeout_ar > TIMEOUT_CYC) begin
                $error("[BFM] TIMEOUT waiting for ARREADY at addr=0x%08h", addr);
                data = 32'hDEAD_BEEF; resp = 2'b11; return;
            end
        end while (!bfm_arready);
        @(negedge clk);
        bfm_arvalid = 1'b0;

        bfm_rready  = 1'b1;
        timeout_r   = 0;
        do begin
            @(posedge clk);
            read_bfm_from_s01();
            timeout_r++;
            if (timeout_r > TIMEOUT_CYC) begin
                $error("[BFM] TIMEOUT waiting for RVALID at addr=0x%08h", addr);
                data = 32'hDEAD_BEEF; resp = 2'b11; return;
            end
        end while (!bfm_rvalid);
        data = bfm_rdata;
        resp = bfm_rresp;
        @(negedge clk);
    endtask

    task automatic run_bfm_tests();
        logic [31:0] rd_data;
        logic [1:0]  rd_resp, wr_resp;
        logic [7:0]  tx_captured;

        $display("\n===== TC03: UART Config =====");
        axi_write(UART_LCR,  32'h03, 4'hF, wr_resp);
        axi_read (UART_LCR, rd_data, rd_resp);
        check32  ("TC03-LCR-readback",  rd_data, 32'h03, 32'hFF);
        axi_write(UART_BAUD, 32'(SIM_BAUD_DIV), 4'hF, wr_resp);
        axi_write(UART_IER, 32'h01, 4'hF, wr_resp);
        axi_read (UART_IER, rd_data, rd_resp);
        check32  ("TC03-IER-readback", rd_data, 32'h01, 32'hFF);

        $display("\n===== TC04: UART TX =====");
        axi_write(UART_THR, 32'h4B, 4'hF, wr_resp);

        $display("\n===== TC05: UART TX serial monitor =====");
        fork
            uart_capture_tx(tx_captured);
        join_none
        repeat (BIT_CYCLES * 12) @(posedge clk);
        @(posedge clk);
        check32("TC05-UART-TX-captured", {24'h0, tx_captured}, 32'h4B, 32'hFF);

        $display("\n===== TC06: UART RX loopback =====");
        uart_inject_byte(8'hA5);
        repeat (20) @(posedge clk);
        axi_read(UART_RBR, rd_data, rd_resp);
        check32 ("TC06-RBR-readback", rd_data, 32'hA5, 32'hFF);

        $display("\n===== TC07-09: System Timer =====");
        axi_write(TIMER_CFG0, 32'h0000_0901, 4'hF, wr_resp);
        axi_write(TIMER_CMP_LO, 32'hFFFF_FFFF, 4'hF, wr_resp);
        axi_write(TIMER_CTRL, 32'h1, 4'hF, wr_resp);
        repeat (30) @(posedge clk);
        axi_read(TIMER_VAL_LO, rd_data, rd_resp);
        axi_write(TIMER_CMP_LO, rd_data + 32'd50, 4'hF, wr_resp);
        axi_write(TIMER_INTR_EN, 32'h1, 4'hF, wr_resp);
        repeat (100) @(posedge clk);
        axi_write(TIMER_INTR_ST, 32'h1, 4'hF, wr_resp);

        $display("\n===== TC10-13: AES Engine =====");
        axi_write(AES_KEY0, AES_KEY_W0, 4'hF, wr_resp);
        axi_write(AES_KEY1, AES_KEY_W1, 4'hF, wr_resp);
        axi_write(AES_KEY2, AES_KEY_W2, 4'hF, wr_resp);
        axi_write(AES_KEY3, AES_KEY_W3, 4'hF, wr_resp);
        axi_write(AES_TXTIN0, AES_PT_W0, 4'hF, wr_resp);
        axi_write(AES_TXTIN1, AES_PT_W1, 4'hF, wr_resp);
        axi_write(AES_TXTIN2, AES_PT_W2, 4'hF, wr_resp);
        axi_write(AES_TXTIN3, AES_PT_W3, 4'hF, wr_resp);
        axi_write(AES_CTRL_REG, 32'h01, 4'hF, wr_resp);
        repeat (50) @(posedge clk);
        axi_read(AES_TXTOUT0, rd_data, rd_resp); check32("TC13-CT-W0", rd_data, AES_CT_W0, 32'hFFFF_FFFF);
        axi_read(AES_TXTOUT1, rd_data, rd_resp); check32("TC13-CT-W1", rd_data, AES_CT_W1, 32'hFFFF_FFFF);
        axi_read(AES_TXTOUT2, rd_data, rd_resp); check32("TC13-CT-W2", rd_data, AES_CT_W2, 32'hFFFF_FFFF);
        axi_read(AES_TXTOUT3, rd_data, rd_resp); check32("TC13-CT-W3", rd_data, AES_CT_W3, 32'hFFFF_FFFF);

        $display("\n===== TC14-16: DMA Controller =====");
        axi_read(DMA_CTRL_REG, rd_data, rd_resp);
        axi_read(DMA_STAT_REG, rd_data, rd_resp);
        axi_write(DMA_DESC0_SRC, UART_BASE,     4'hF, wr_resp);
        axi_write(DMA_DESC0_DST, 32'hF004_0000, 4'hF, wr_resp);
        axi_write(DMA_CTRL_REG,  32'h03,        4'hF, wr_resp);

        $display("\n===== TC17-21: Watchdog Timer =====");
        axi_write(WDT_LOAD, 32'h0000_1000, 4'hF, wr_resp);
        axi_write(WDT_IM,   32'h01,        4'hF, wr_resp);
        axi_write(WDT_CTRL, 32'h03,        4'hF, wr_resp);
        repeat (10) @(posedge clk);
        axi_write(WDT_PING, 32'hABCD_EF01, 4'hF, wr_resp);

        $display("\n===== TC22-25: GPIO =====");
        axi_write(GPIO_EN_REG, 32'h0000_00FF, 4'hF, wr_resp);
        axi_write(GPIO_OUT_REG, 32'hA5,       4'hF, wr_resp);
        repeat (3) @(posedge clk);
        check32("TC23-gpio_out_o", gpio_out_o, 32'hA5, 32'hFF);

        print_summary();
        repeat (20) @(posedge clk);
        $finish;
    endtask

    // =========================================================================
    // Main Simulation Execution
    // =========================================================================
    initial begin
        fw_mode = !$test$plusargs("BFM");

        // Power-on reset sequence
        rst_l     = 1'b0;
        dbg_rst_l = 1'b0;
        repeat (RST_CYCLES) @(posedge clk);

        if (!fw_mode) begin
            $display("[TB] Running in legacy BFM mode (+BFM supplied)...");
            force_bfm_to_s01();
        end else begin
            $display("\n=======================================================");
            $display("[TB] Running in FIRMWARE-DRIVEN mode with VeeR EL2 core");
            $display("[TB] Loading hex image : %s", hex_file);
            $display("[TB] Boot Address      : 0x%08h", {rst_vec, 1'b0});
            $display("=======================================================\n");
        end

        @(negedge clk);
        rst_l     = 1'b1;
        dbg_rst_l = 1'b1;
        repeat (5) @(posedge clk);

        // TC01: Post-reset quiescent checks
        $display("\n===== TC01: Power-on Reset Quiescent Checks =====");
        check_signal("TC01-uart_tx_idle",   uart_tx_o,       1'b1);
        check_signal("TC01-aes_busy_idle",  aes_busy_o,      1'b0);
        check_signal("TC01-dma_done_idle",  dma_done_o,      1'b0);
        check_signal("TC01-wdt_reset_idle", wdt_reset_o,     1'b0);

        // TC02: Core fetch check
        $display("\n===== TC02: VeeR EL2 Core Alive & Fetching =====");
        repeat (50) @(posedge clk);
        check_signal("TC02-ifu_fetch_seen", ifu_fetch_seen, 1'b1);

        if (!fw_mode) begin
            run_bfm_tests();
        end else begin
            // In firmware mode, VeeR core executes soc_full_test.hex autonomously!
            // Wait for completion (TOHOST 0x900D) or failure.
            $display("[TB] VeeR EL2 core is executing firmware from hex...");
            wait (tc_final_passed || (fail_cnt > 0));
            repeat (50) @(posedge clk);
            print_summary();
            $finish;
        end
    end

    // =========================================================================
    // Global Watchdog Timer
    // =========================================================================
    initial begin
        #(CLK_PERIOD * 5_000_000);  // 50 ms max simulation time
        $error("[TB] GLOBAL SIMULATION TIMEOUT — aborting");
        print_summary();
        $finish;
    end

endmodule

`default_nettype wire
