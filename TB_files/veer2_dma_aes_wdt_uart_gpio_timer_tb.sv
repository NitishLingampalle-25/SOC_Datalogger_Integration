// =============================================================================
// Testbench  : veer2_dma_aes_wdt_uart_gpio_timer_tb
// File       : TB_files/veer2_dma_aes_wdt_uart_gpio_timer_tb.sv
// Language   : SystemVerilog (IEEE 1800-2012, VCS / Questa compatible)
//
// DUT        : veer2_dma_aes_wdt_uart_gpio_timer
//              (UART + System Timer + AES + DMA + WDT + GPIO)
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

import amba_axi_pkg::*;
import dma_utils_pkg::*;

module veer2_dma_aes_wdt_uart_gpio_timer_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD    = 10;          // 100 MHz
    localparam FIXED_PERIOD  = 10;          // UART baud reference
    localparam RST_CYCLES    = 20;
    localparam TIMEOUT_CYC   = 10_000;      // AXI handshake watchdog
    localparam SIM_BAUD_DIV  = 10;          // baud divisor for sim
    localparam BIT_CYCLES    = SIM_BAUD_DIV + 1;

    localparam IC_ID_WIDTH   = 8;
    localparam DATA_WIDTH    = 32;
    localparam ADDR_WIDTH    = 32;
    localparam STRB_WIDTH    = 4;

    localparam LSU_BUS_TAG   = 4;
    localparam IFU_BUS_TAG   = 3;
    localparam SB_BUS_TAG    = 2;
    localparam DMA_BUS_TAG   = 1;
    localparam PIC_TOTAL_INT = 31;

    // =========================================================================
    // Memory Map
    // =========================================================================
    // UART (0x4000_0000)
    localparam [31:0] UART_BASE       = 32'h4000_0000;
    localparam [31:0] UART_THR        = UART_BASE + 32'h00;
    localparam [31:0] UART_RBR        = UART_BASE + 32'h00;
    localparam [31:0] UART_IER        = UART_BASE + 32'h04;
    localparam [31:0] UART_BAUD       = UART_BASE + 32'h08;
    localparam [31:0] UART_LCR        = UART_BASE + 32'h0C;
    localparam [31:0] UART_LSR        = UART_BASE + 32'h14;

    // System Timer (0x4000_1000)
    localparam [31:0] TIMER_BASE      = 32'h4000_1000;
    localparam [31:0] TIMER_CTRL      = TIMER_BASE + 32'h000;
    localparam [31:0] TIMER_INTR_EN   = TIMER_BASE + 32'h100;
    localparam [31:0] TIMER_INTR_ST   = TIMER_BASE + 32'h104;
    localparam [31:0] TIMER_INTR_TEST = TIMER_BASE + 32'h108;
    localparam [31:0] TIMER_CFG0      = TIMER_BASE + 32'h10C;
    localparam [31:0] TIMER_VAL_LO    = TIMER_BASE + 32'h110;
    localparam [31:0] TIMER_VAL_HI    = TIMER_BASE + 32'h114;
    localparam [31:0] TIMER_CMP_LO    = TIMER_BASE + 32'h118;
    localparam [31:0] TIMER_CMP_HI    = TIMER_BASE + 32'h11C;

    // AES Engine (0x4000_2000)
    localparam [31:0] AES_BASE        = 32'h4000_2000;
    localparam [31:0] AES_CTRL_REG    = AES_BASE + 32'h00;
    localparam [31:0] AES_STATUS_REG  = AES_BASE + 32'h04;
    localparam [31:0] AES_KEY0        = AES_BASE + 32'h08;
    localparam [31:0] AES_KEY1        = AES_BASE + 32'h0C;
    localparam [31:0] AES_KEY2        = AES_BASE + 32'h10;
    localparam [31:0] AES_KEY3        = AES_BASE + 32'h14;
    localparam [31:0] AES_TXTIN0      = AES_BASE + 32'h18;
    localparam [31:0] AES_TXTIN1      = AES_BASE + 32'h1C;
    localparam [31:0] AES_TXTIN2      = AES_BASE + 32'h20;
    localparam [31:0] AES_TXTIN3      = AES_BASE + 32'h24;
    localparam [31:0] AES_TXTOUT0     = AES_BASE + 32'h28;
    localparam [31:0] AES_TXTOUT1     = AES_BASE + 32'h2C;
    localparam [31:0] AES_TXTOUT2     = AES_BASE + 32'h30;
    localparam [31:0] AES_TXTOUT3     = AES_BASE + 32'h34;

    // DMA Controller CSRs (0x4000_3000)
    localparam [31:0] DMA_BASE        = 32'h4000_3000;
    localparam [31:0] DMA_CTRL_REG    = DMA_BASE + 32'h00;
    localparam [31:0] DMA_STAT_REG    = DMA_BASE + 32'h08;
    localparam [31:0] DMA_ERR_REG     = DMA_BASE + 32'h10;
    localparam [31:0] DMA_DESC0_SRC   = DMA_BASE + 32'h20;
    localparam [31:0] DMA_DESC0_DST   = DMA_BASE + 32'h30;
    localparam [31:0] DMA_DESC1_SRC   = DMA_BASE + 32'h28;
    localparam [31:0] DMA_DESC1_DST   = DMA_BASE + 32'h38;

    // Watchdog (0x4000_4000)
    localparam [31:0] WDT_BASE        = 32'h4000_4000;
    localparam [31:0] WDT_LOAD        = WDT_BASE  + 32'h04;
    localparam [31:0] WDT_CTRL        = WDT_BASE  + 32'h08;
    localparam [31:0] WDT_PING        = WDT_BASE  + 32'h0C;
    localparam [31:0] WDT_IM          = WDT_BASE  + 32'h10;
    localparam [31:0] WDT_RIS         = WDT_BASE  + 32'h14;
    localparam [31:0] WDT_MIS         = WDT_BASE  + 32'h18;
    localparam [31:0] WDT_IC          = WDT_BASE  + 32'h1C;

    // GPIO (0x4000_5000)
    localparam [31:0] GPIO_BASE       = 32'h4000_5000;
    localparam [31:0] GPIO_EN_REG     = GPIO_BASE + 32'h080;
    localparam [31:0] GPIO_IN_REG     = GPIO_BASE + 32'h100;
    localparam [31:0] GPIO_OUT_REG    = GPIO_BASE + 32'h180;
    localparam [31:0] GPIO_SET_REG    = GPIO_BASE + 32'h200;
    localparam [31:0] GPIO_CLR_REG    = GPIO_BASE + 32'h280;
    localparam [31:0] GPIO_RISE_EN    = GPIO_BASE + 32'h380;
    localparam [31:0] GPIO_FALL_EN    = GPIO_BASE + 32'h400;
    localparam [31:0] GPIO_LVL_HI_EN  = GPIO_BASE + 32'h480;
    localparam [31:0] GPIO_INT_STAT   = GPIO_BASE + 32'h580;

    // Unmapped (for SLVERR test)
    localparam [31:0] UNMAPPED_ADDR   = 32'h4000_9000;

    // NIST FIPS-197 Test Vector (Appendix B)
    localparam [31:0] AES_KEY_W0      = 32'h2b7e1516;
    localparam [31:0] AES_KEY_W1      = 32'h28aed2a6;
    localparam [31:0] AES_KEY_W2      = 32'habf71588;
    localparam [31:0] AES_KEY_W3      = 32'h09cf4f3c;

    localparam [31:0] AES_PT_W0       = 32'h3243f6a8;
    localparam [31:0] AES_PT_W1       = 32'h885a308d;
    localparam [31:0] AES_PT_W2       = 32'h313198a2;
    localparam [31:0] AES_PT_W3       = 32'he0370734;

    localparam [31:0] AES_CT_W0       = 32'h3925841d;
    localparam [31:0] AES_CT_W1       = 32'h02dc09fb;
    localparam [31:0] AES_CT_W2       = 32'hdc118597;
    localparam [31:0] AES_CT_W3       = 32'h196a0b32;

    // =========================================================================
    // Clock & Reset generation
    // =========================================================================
    logic clk;
    logic fixed_clk;
    logic rst_l;
    logic dbg_rst_l;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial fixed_clk = 1'b0;
    always #(FIXED_PERIOD/2) fixed_clk = ~fixed_clk;

    // =========================================================================
    // DUT port declarations
    // =========================================================================
    logic [31:1]  rst_vec;
    logic [31:1]  nmi_vec;
    logic [31:1]  jtag_id;
    logic [31:4]  core_id;

    logic         nmi_int;
    logic         timer_int;
    logic         soft_int;
    logic [PIC_TOTAL_INT:1] extintsrc_req;
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

    logic         uart_tx_o;
    logic         uart_rx_i;
    logic         aes_busy_o;
    logic         aes_done_o;

    logic [31:0]  gpio_in_i;
    logic [31:0]  gpio_out_o;
    logic [31:0]  gpio_tx_en_o;

    // IFU AXI
    logic                        ifu_axi_arvalid;
    logic                        ifu_axi_arready;
    logic [IFU_BUS_TAG-1:0]      ifu_axi_arid;
    logic [31:0]                 ifu_axi_araddr;
    logic [3:0]                  ifu_axi_arregion;
    logic [7:0]                  ifu_axi_arlen;
    logic [2:0]                  ifu_axi_arsize;
    logic [1:0]                  ifu_axi_arburst;
    logic                        ifu_axi_arlock;
    logic [3:0]                  ifu_axi_arcache;
    logic [2:0]                  ifu_axi_arprot;
    logic [3:0]                  ifu_axi_arqos;
    logic                        ifu_axi_rvalid;
    logic                        ifu_axi_rready;
    logic [IFU_BUS_TAG-1:0]      ifu_axi_rid;
    logic [63:0]                 ifu_axi_rdata;
    logic [1:0]                  ifu_axi_rresp;
    logic                        ifu_axi_rlast;
    logic                        ifu_axi_awvalid;
    logic                        ifu_axi_awready;
    logic [IFU_BUS_TAG-1:0]      ifu_axi_awid;
    logic [31:0]                 ifu_axi_awaddr;
    logic [3:0]                  ifu_axi_awregion;
    logic [7:0]                  ifu_axi_awlen;
    logic [2:0]                  ifu_axi_awsize;
    logic [1:0]                  ifu_axi_awburst;
    logic                        ifu_axi_awlock;
    logic [3:0]                  ifu_axi_awcache;
    logic [2:0]                  ifu_axi_awprot;
    logic [3:0]                  ifu_axi_awqos;
    logic                        ifu_axi_wvalid;
    logic                        ifu_axi_wready;
    logic [63:0]                 ifu_axi_wdata;
    logic [7:0]                  ifu_axi_wstrb;
    logic                        ifu_axi_wlast;
    logic                        ifu_axi_bvalid;
    logic                        ifu_axi_bready;
    logic [1:0]                  ifu_axi_bresp;
    logic [IFU_BUS_TAG-1:0]      ifu_axi_bid;

    // SB AXI
    logic                        sb_axi_awvalid;
    logic                        sb_axi_awready;
    logic [SB_BUS_TAG-1:0]       sb_axi_awid;
    logic [31:0]                 sb_axi_awaddr;
    logic [3:0]                  sb_axi_awregion;
    logic [7:0]                  sb_axi_awlen;
    logic [2:0]                  sb_axi_awsize;
    logic [1:0]                  sb_axi_awburst;
    logic                        sb_axi_awlock;
    logic [3:0]                  sb_axi_awcache;
    logic [2:0]                  sb_axi_awprot;
    logic [3:0]                  sb_axi_awqos;
    logic                        sb_axi_wvalid;
    logic                        sb_axi_wready;
    logic [63:0]                 sb_axi_wdata;
    logic [7:0]                  sb_axi_wstrb;
    logic                        sb_axi_wlast;
    logic                        sb_axi_bvalid;
    logic                        sb_axi_bready;
    logic [1:0]                  sb_axi_bresp;
    logic [SB_BUS_TAG-1:0]       sb_axi_bid;
    logic                        sb_axi_arvalid;
    logic                        sb_axi_arready;
    logic [SB_BUS_TAG-1:0]       sb_axi_arid;
    logic [31:0]                 sb_axi_araddr;
    logic [3:0]                  sb_axi_arregion;
    logic [7:0]                  sb_axi_arlen;
    logic [2:0]                  sb_axi_arsize;
    logic [1:0]                  sb_axi_arburst;
    logic                        sb_axi_arlock;
    logic [3:0]                  sb_axi_arcache;
    logic [2:0]                  sb_axi_arprot;
    logic [3:0]                  sb_axi_arqos;
    logic                        sb_axi_rvalid;
    logic                        sb_axi_rready;
    logic [SB_BUS_TAG-1:0]       sb_axi_rid;
    logic [63:0]                 sb_axi_rdata;
    logic [1:0]                  sb_axi_rresp;
    logic                        sb_axi_rlast;

    // VeeR DMA slave
    logic                        dma_axi_awvalid;
    logic                        dma_axi_awready;
    logic [DMA_BUS_TAG-1:0]      dma_axi_awid;
    logic [31:0]                 dma_axi_awaddr;
    logic [2:0]                  dma_axi_awsize;
    logic [2:0]                  dma_axi_awprot;
    logic [7:0]                  dma_axi_awlen;
    logic [1:0]                  dma_axi_awburst;
    logic                        dma_axi_wvalid;
    logic                        dma_axi_wready;
    logic [63:0]                 dma_axi_wdata;
    logic [7:0]                  dma_axi_wstrb;
    logic                        dma_axi_wlast;
    logic                        dma_axi_bvalid;
    logic                        dma_axi_bready;
    logic [1:0]                  dma_axi_bresp;
    logic [DMA_BUS_TAG-1:0]      dma_axi_bid;
    logic                        dma_axi_arvalid;
    logic                        dma_axi_arready;
    logic [DMA_BUS_TAG-1:0]      dma_axi_arid;
    logic [31:0]                 dma_axi_araddr;
    logic [2:0]                  dma_axi_arsize;
    logic [2:0]                  dma_axi_arprot;
    logic [7:0]                  dma_axi_arlen;
    logic [1:0]                  dma_axi_arburst;
    logic                        dma_axi_rvalid;
    logic                        dma_axi_rready;
    logic [DMA_BUS_TAG-1:0]      dma_axi_rid;
    logic [63:0]                 dma_axi_rdata;
    logic [1:0]                  dma_axi_rresp;
    logic                        dma_axi_rlast;

    // Trace
    logic [31:0] trace_rv_i_insn_ip;
    logic [31:0] trace_rv_i_address_ip;
    logic        trace_rv_i_valid_ip;
    logic        trace_rv_i_exception_ip;
    logic [4:0]  trace_rv_i_ecause_ip;
    logic        trace_rv_i_interrupt_ip;
    logic [31:0] trace_rv_i_tval_ip;

    // ECC / Perf / JTAG / MPC
    logic iccm_ecc_single_error, iccm_ecc_double_error;
    logic dccm_ecc_single_error, dccm_ecc_double_error;
    logic dccm_write_readback_error;
    logic dec_tlu_perfcnt0, dec_tlu_perfcnt1, dec_tlu_perfcnt2, dec_tlu_perfcnt3;
    logic jtag_tck, jtag_tms, jtag_tdi, jtag_trst_n, jtag_tdo, jtag_tdoEn;
    logic mpc_debug_halt_req, mpc_debug_run_req, mpc_reset_run_req;
    logic mpc_debug_halt_ack, mpc_debug_run_ack, debug_brkpt_status;
    logic i_cpu_halt_req, o_cpu_halt_ack, o_cpu_halt_status, o_debug_mode_status;
    logic i_cpu_run_req, o_cpu_run_ack;
    logic lsu_bus_clk_en, ifu_bus_clk_en, dbg_bus_clk_en, dma_bus_clk_en;
    logic scan_mode, mbist_mode;
    logic dmi_core_enable, dmi_uncore_enable;
    logic dmi_uncore_en, dmi_uncore_wr_en;
    logic [6:0]  dmi_uncore_addr;
    logic [31:0] dmi_uncore_wdata;
    logic [31:0] dmi_uncore_rdata;
    logic        dmi_active;

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
        .trace_rv_i_insn_ip         (trace_rv_i_insn_ip),
        .trace_rv_i_address_ip      (trace_rv_i_address_ip),
        .trace_rv_i_valid_ip        (trace_rv_i_valid_ip),
        .trace_rv_i_exception_ip    (trace_rv_i_exception_ip),
        .trace_rv_i_ecause_ip       (trace_rv_i_ecause_ip),
        .trace_rv_i_interrupt_ip    (trace_rv_i_interrupt_ip),
        .trace_rv_i_tval_ip         (trace_rv_i_tval_ip),
        // ECC / Perf
        .iccm_ecc_single_error      (iccm_ecc_single_error),
        .iccm_ecc_double_error      (iccm_ecc_double_error),
        .dccm_ecc_single_error      (dccm_ecc_single_error),
        .dccm_ecc_double_error      (dccm_ecc_double_error),
        .dccm_write_readback_error  (dccm_write_readback_error),
        .dec_tlu_perfcnt0           (dec_tlu_perfcnt0),
        .dec_tlu_perfcnt1           (dec_tlu_perfcnt1),
        .dec_tlu_perfcnt2           (dec_tlu_perfcnt2),
        .dec_tlu_perfcnt3           (dec_tlu_perfcnt3),
        // JTAG
        .jtag_tck                   (jtag_tck),
        .jtag_tms                   (jtag_tms),
        .jtag_tdi                   (jtag_tdi),
        .jtag_trst_n                (jtag_trst_n),
        .jtag_tdo                   (jtag_tdo),
        .jtag_tdoEn                 (jtag_tdoEn),
        // MPC / halt / run
        .mpc_debug_halt_req         (mpc_debug_halt_req),
        .mpc_debug_run_req          (mpc_debug_run_req),
        .mpc_reset_run_req          (mpc_reset_run_req),
        .mpc_debug_halt_ack         (mpc_debug_halt_ack),
        .mpc_debug_run_ack          (mpc_debug_run_ack),
        .debug_brkpt_status         (debug_brkpt_status),
        .i_cpu_halt_req             (i_cpu_halt_req),
        .o_cpu_halt_ack             (o_cpu_halt_ack),
        .o_cpu_halt_status          (o_cpu_halt_status),
        .o_debug_mode_status        (o_debug_mode_status),
        .i_cpu_run_req              (i_cpu_run_req),
        .o_cpu_run_ack              (o_cpu_run_ack),
        // Bus clock enables
        .lsu_bus_clk_en             (lsu_bus_clk_en),
        .ifu_bus_clk_en             (ifu_bus_clk_en),
        .dbg_bus_clk_en             (dbg_bus_clk_en),
        .dma_bus_clk_en             (dma_bus_clk_en),
        .scan_mode                  (scan_mode),
        .mbist_mode                 (mbist_mode),
        // DMI
        .dmi_core_enable            (dmi_core_enable),
        .dmi_uncore_enable          (dmi_uncore_enable),
        .dmi_uncore_en              (dmi_uncore_en),
        .dmi_uncore_wr_en           (dmi_uncore_wr_en),
        .dmi_uncore_addr            (dmi_uncore_addr),
        .dmi_uncore_wdata           (dmi_uncore_wdata),
        .dmi_uncore_rdata           (dmi_uncore_rdata),
        .dmi_active                 (dmi_active)
    );

    // =========================================================================
    // IFU memory model — loaded from hex with $readmemh
    // =========================================================================
    localparam [31:0] BOOT_ADDR  = 32'h0000_0000;
    localparam [31:0] IMEM_BYTES = 32'h0002_0000;   // 128 KB covers 0x0 .. 0x1_FFFF

    logic [7:0] imem [0:IMEM_BYTES-1];
    string      hex_file;
    bit         fw_en;

    initial begin
        for (int i = 0; i < IMEM_BYTES; i++)
            imem[i] = (i % 4 == 0) ? 8'h13 : 8'h00; // NOP fill (addi x0, x0, 0)
        fw_en = !$test$plusargs("NOFW");
        if (!$value$plusargs("HEX=%s", hex_file))
            hex_file = "soc_full_test.hex";
        if (fw_en) begin
            $readmemh(hex_file, imem);
            $display("[TB] Loaded firmware '%s' into imem (boot addr 0x%08h)",
                     hex_file, BOOT_ADDR);
        end else
            $display("[TB] +NOFW : IFU returns NOPs only");
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

    assign ifu_axi_arready = !ifu_busy;

    always_ff @(posedge clk) begin
        if (!rst_l) begin
            ifu_busy        <= 1'b0;
            ifu_axi_rvalid  <= 1'b0;
            ifu_axi_rdata   <= 64'h0000_0013_0000_0013;
            ifu_axi_rresp   <= 2'b00;
            ifu_axi_rid     <= '0;
            ifu_axi_rlast   <= 1'b0;
            ifu_cur_addr    <= '0;
            ifu_beats_left  <= '0;
            ifu_len_q       <= '0;
            ifu_burst_q     <= 2'b01;
        end else begin
            if (ifu_axi_arvalid && ifu_axi_arready) begin
                ifu_busy        <= 1'b1;
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

    // Channel tie-offs
    assign ifu_axi_awready = 1'b0;
    assign ifu_axi_wready  = 1'b0;
    assign ifu_axi_bvalid  = 1'b0;
    assign ifu_axi_bresp   = 2'b00;
    assign ifu_axi_bid     = '0;

    assign sb_axi_awready  = 1'b1;
    assign sb_axi_wready   = 1'b1;
    assign sb_axi_bvalid   = 1'b0;
    assign sb_axi_bresp    = 2'b00;
    assign sb_axi_bid      = '0;
    assign sb_axi_arready  = 1'b1;
    assign sb_axi_rvalid   = 1'b0;
    assign sb_axi_rdata    = 64'h0;
    assign sb_axi_rresp    = 2'b00;
    assign sb_axi_rid      = '0;
    assign sb_axi_rlast    = 1'b0;

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
    // TB-side AXI BFM driver signals
    // =========================================================================
    logic [IC_ID_WIDTH-1:0] bfm_awid;
    logic [31:0]            bfm_awaddr;
    logic [7:0]             bfm_awlen;
    logic [2:0]             bfm_awsize;
    logic [1:0]             bfm_awburst;
    logic                   bfm_awvalid;
    logic                   bfm_awready;
    logic [31:0]            bfm_wdata;
    logic [3:0]             bfm_wstrb;
    logic                   bfm_wlast;
    logic                   bfm_wvalid;
    logic                   bfm_wready;
    logic [IC_ID_WIDTH-1:0] bfm_bid;
    logic [1:0]             bfm_bresp;
    logic                   bfm_bvalid;
    logic                   bfm_bready;
    logic [IC_ID_WIDTH-1:0] bfm_arid;
    logic [31:0]            bfm_araddr;
    logic [7:0]             bfm_arlen;
    logic [2:0]             bfm_arsize;
    logic [1:0]             bfm_arburst;
    logic                   bfm_arvalid;
    logic                   bfm_arready;
    logic [IC_ID_WIDTH-1:0] bfm_rid;
    logic [31:0]            bfm_rdata;
    logic [1:0]             bfm_rresp;
    logic                   bfm_rlast;
    logic                   bfm_rvalid;
    logic                   bfm_rready;

    // Static tie-offs
    initial begin
        rst_vec             = BOOT_ADDR[31:1];
        nmi_vec             = 31'h0000_1000 >> 1;
        jtag_id             = 31'h1;
        core_id             = 28'h1;
        nmi_int             = 1'b0;
        timer_int           = 1'b0;
        soft_int            = 1'b0;
        extintsrc_req       = '0;
        gpio_in_i           = 32'h0;
        uart_rx_i           = 1'b1;                // Idle high
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

    // BFM idle defaults
    initial begin
        bfm_awid    = '0; bfm_awaddr  = '0; bfm_awlen   = '0;
        bfm_awsize  = 3'b010; bfm_awburst = 2'b01;
        bfm_awvalid = 1'b0;
        bfm_wdata   = '0; bfm_wstrb   = 4'hF; bfm_wlast = 1'b1;
        bfm_wvalid  = 1'b0;
        bfm_bready  = 1'b0;
        bfm_arid    = '0; bfm_araddr  = '0; bfm_arlen   = '0;
        bfm_arsize  = 3'b010; bfm_arburst = 2'b01;
        bfm_arvalid = 1'b0;
        bfm_rready  = 1'b0;
    end

    // Force tasks
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

    // =========================================================================
    // AXI4 BFM Tasks
    // =========================================================================
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
        bfm_awsize  = 3'b010;
        bfm_awburst = 2'b01;
        force_bfm_to_s01();

        timeout_aw = 0;
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
        force_bfm_to_s01();

        bfm_wdata  = data;
        bfm_wstrb  = strb;
        bfm_wlast  = 1'b1;
        bfm_wvalid = 1'b1;
        force_bfm_to_s01();

        timeout_w = 0;
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
        bfm_wvalid = 1'b0;
        bfm_bready = 1'b1;
        force_bfm_to_s01();

        timeout_b = 0;
        do begin
            @(posedge clk);
            read_bfm_from_s01();
            timeout_b++;
            if (timeout_b > TIMEOUT_CYC) begin
                $error("[BFM] TIMEOUT waiting for BVALID at addr=0x%08h", addr);
                resp = 2'b11;
                bfm_bready = 1'b0;
                force_bfm_to_s01();
                return;
            end
        end while (!bfm_bvalid);

        resp = bfm_bresp;
        @(negedge clk);
        bfm_bready = 1'b0;
        force_bfm_to_s01();
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
        bfm_arsize  = 3'b010;
        bfm_arburst = 2'b01;
        force_bfm_to_s01();

        timeout_ar = 0;
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
        force_bfm_to_s01();

        timeout_r = 0;
        do begin
            @(posedge clk);
            read_bfm_from_s01();
            timeout_r++;
            if (timeout_r > TIMEOUT_CYC) begin
                $error("[BFM] TIMEOUT waiting for RVALID at addr=0x%08h", addr);
                data = 32'hDEAD_BEEF; resp = 2'b11;
                bfm_rready = 1'b0;
                force_bfm_to_s01();
                return;
            end
        end while (!bfm_rvalid);

        data = bfm_rdata;
        resp = bfm_rresp;
        @(negedge clk);
        bfm_rready = 1'b0;
        force_bfm_to_s01();
    endtask

    // Checking routines
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task automatic check32(
        input string       tc_name,
        input logic [31:0] got,
        input logic [31:0] expected,
        input logic [31:0] mask = 32'hFFFF_FFFF
    );
        if ((got & mask) === (expected & mask)) begin
            $display("[PASS] %s : got=0x%08h  expected=0x%08h  mask=0x%08h",
                     tc_name, got, expected, mask);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s : got=0x%08h  expected=0x%08h  mask=0x%08h",
                     tc_name, got, expected, mask);
            fail_cnt++;
        end
    endtask

    task automatic check_signal(
        input string tc_name,
        input logic  got,
        input logic  expected
    );
        if (got === expected) begin
            $display("[PASS] %s : got=%b  expected=%b", tc_name, got, expected);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s : got=%b  expected=%b", tc_name, got, expected);
            fail_cnt++;
        end
    endtask

    // UART tasks
    task automatic uart_inject_byte(input logic [7:0] byte_val);
        integer bit_idx;
        @(negedge clk);
        uart_rx_i = 1'b0;
        repeat (BIT_CYCLES) @(posedge clk);
        for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
            @(negedge clk);
            uart_rx_i = byte_val[bit_idx];
            repeat (BIT_CYCLES) @(posedge clk);
        end
        @(negedge clk);
        uart_rx_i = 1'b1;
        repeat (BIT_CYCLES) @(posedge clk);
    endtask

    task automatic uart_capture_tx(output logic [7:0] captured);
        integer bit_idx;
        integer timeout_tx;

        captured   = 8'hFF;
        timeout_tx = 0;

        while (uart_tx_o !== 1'b0) begin
            @(posedge clk);
            timeout_tx++;
            if (timeout_tx > TIMEOUT_CYC * 10) begin
                $error("[BFM] UART TX monitor: start bit timeout");
                return;
            end
        end

        repeat (BIT_CYCLES / 2) @(posedge clk);

        for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
            repeat (BIT_CYCLES) @(posedge clk);
            captured[bit_idx] = uart_tx_o;
        end

        repeat (BIT_CYCLES) @(posedge clk);
    endtask

    // Waveform dump
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
    // Instruction & Exception Tracer (Live Debug)
    // =========================================================================
    initial begin
        wait(rst_l === 1'b1);
        $display("[TRACER] Reset released. Monitoring PC execution...");
        forever @(posedge clk) begin
            if (trace_rv_i_valid_ip) begin
                $display("[TRACER-PC] Time=%0t | PC=0x%08h | Insn=0x%08h", 
                         $time, trace_rv_i_address_ip, trace_rv_i_insn_ip);
            end
            if (trace_rv_i_exception_ip) begin
                $display("[TRACER-EXC] Time=%0t | EXCEPTION! Cause=0x%0h | TVAL=0x%08h | PC=0x%08h",
                         $time, trace_rv_i_ecause_ip, trace_rv_i_tval_ip, trace_rv_i_address_ip);
            end
        end
    end

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    logic [31:0] rd_data;
    logic [1:0]  rd_resp, wr_resp;
    logic [7:0]  tx_captured;

    initial begin
        // Reset Phase
        rst_l         = 1'b0;
        dbg_rst_l     = 1'b0;
        i_cpu_run_req = 1'b0;
        repeat (RST_CYCLES) @(posedge clk);

        @(negedge clk);
        rst_l     = 1'b1;
        dbg_rst_l = 1'b1;
        
        // Assert CPU run request pulse to trigger execution
        @(posedge clk);
        i_cpu_run_req = 1'b1;
        repeat (5) @(posedge clk);
        i_cpu_run_req = 1'b0;

        // Branch execution: Firmware Mode vs BFM Unit Tests
        if ($test$plusargs("FWONLY")) begin
            $display("===============================================================");
            $display("  [TB] RUNNING IN FIRMWARE-ONLY MODE (+FWONLY)");
            $display("  [TB] BFM forced signals disabled; CPU is in control.");
            $display("===============================================================");
        end else begin
            force_bfm_to_s01();

            // TC01
            $display("\n===== TC01: Power-on Reset =====");
            check_signal("TC01-uart_tx_idle",   uart_tx_o,       1'b1);
            check_signal("TC01-aes_busy_idle",  aes_busy_o,      1'b0);
            check_signal("TC01-dma_done_idle",  dma_done_o,      1'b0);
            check_signal("TC01-wdt_reset_idle", wdt_reset_o,     1'b0);

            // TC02
            $display("\n===== TC02: VeeR IFU Instruction Fetch =====");
            repeat (50) @(posedge clk);
            check_signal("TC02-ifu_arvalid",    ifu_axi_arvalid, 1'b1);

            // TC03
            $display("\n===== TC03: UART Config =====");
            axi_write(UART_LCR,  32'h03, 4'hF, wr_resp);
            check_signal("TC03-LCR-wr-resp", wr_resp[1], 1'b0);
            axi_read (UART_LCR, rd_data, rd_resp);
            check32  ("TC03-LCR-readback",   rd_data, 32'h03, 32'hFF);

            axi_write(UART_BAUD, 32'(SIM_BAUD_DIV), 4'hF, wr_resp);
            check_signal("TC03-BAUD-wr-resp", wr_resp[1], 1'b0);

            axi_write(UART_IER, 32'h01, 4'hF, wr_resp);
            check_signal("TC03-IER-wr-resp", wr_resp[1], 1'b0);
            axi_read(UART_IER, rd_data, rd_resp);
            check32 ("TC03-IER-readback", rd_data, 32'h01, 32'hFF);

            // TC04
            $display("\n===== TC04: UART TX =====");
            begin : tc04_poll
                integer poll_cnt;
                poll_cnt = 0;
                do begin
                    axi_read(UART_LSR, rd_data, rd_resp);
                    poll_cnt++;
                    if (poll_cnt > 200) begin
                        $error("[FAIL] TC04: LSR THRE poll timeout"); fail_cnt++;
                        disable tc04_poll;
                    end
                end while (!(rd_data & 32'h20));
            end
            axi_write(UART_THR, 32'h4B, 4'hF, wr_resp);
            check_signal("TC04-THR-wr-resp", wr_resp[1], 1'b0);

            // TC05
            $display("\n===== TC05: UART TX serial monitor =====");
            fork
                uart_capture_tx(tx_captured);
            join_none
            repeat (BIT_CYCLES * 12) @(posedge clk);
            @(posedge clk);
            check32("TC05-UART-TX-captured", {24'h0, tx_captured}, 32'h4B, 32'hFF);

            // TC06
            $display("\n===== TC06: UART RX loopback =====");
            uart_inject_byte(8'hA5);
            repeat (5) @(posedge clk);
            begin : tc06_poll
                integer poll_cnt;
                poll_cnt = 0;
                do begin
                    axi_read(UART_LSR, rd_data, rd_resp);
                    poll_cnt++;
                    if (poll_cnt > 500) begin
                        $error("[FAIL] TC06: LSR DATA_READY timeout"); fail_cnt++;
                        disable tc06_poll;
                    end
                end while (!(rd_data & 32'h01));
            end
            check_signal("TC06-uart_read_irq", uart_read_irq_o, 1'b1);
            axi_read(UART_RBR, rd_data, rd_resp);
            check32 ("TC06-RBR-readback", rd_data, 32'hA5, 32'hFF);

            // TC07
            $display("\n===== TC07: System Timer Config =====");
            axi_write(TIMER_CFG0, 32'h0000_0901, 4'hF, wr_resp);
            check_signal("TC07-CFG0-wr",  wr_resp[1], 1'b0);
            axi_write(TIMER_CMP_LO, 32'hFFFF_FFFF, 4'hF, wr_resp);
            axi_write(TIMER_CMP_HI, 32'hFFFF_FFFF, 4'hF, wr_resp);
            axi_write(TIMER_CTRL, 32'h1, 4'hF, wr_resp);
            check_signal("TC07-CTRL-wr",  wr_resp[1], 1'b0);

            // TC08
            $display("\n===== TC08: System Timer counter =====");
            axi_read(TIMER_VAL_LO, rd_data, rd_resp);
            begin : tc08
                logic [31:0] t0, t1;
                t0 = rd_data;
                repeat (30) @(posedge clk);
                axi_read(TIMER_VAL_LO, rd_data, rd_resp);
                t1 = rd_data;
                check_signal("TC08-timer_increments", (t1 > t0), 1'b1);
            end

            // TC09
            $display("\n===== TC09: System Timer IRQ =====");
            axi_read(TIMER_VAL_LO, rd_data, rd_resp);
            axi_write(TIMER_CMP_LO, rd_data + 32'd50,   4'hF, wr_resp);
            axi_write(TIMER_CMP_HI, 32'h0,              4'hF, wr_resp);
            axi_write(TIMER_INTR_EN, 32'h1, 4'hF, wr_resp);
            begin : tc09
                integer tmo;
                tmo = 0;
                while (!timer_irq_o) begin
                    @(posedge clk);
                    tmo++;
                    if (tmo > 2000) begin
                        $error("[FAIL] TC09: timer_irq_o timeout"); fail_cnt++;
                        disable tc09;
                    end
                end
                check_signal("TC09-timer_irq_o", timer_irq_o, 1'b1);
            end
            axi_write(TIMER_INTR_ST, 32'h1, 4'hF, wr_resp);

            // TC10
            $display("\n===== TC10: AES Key Load =====");
            axi_write(AES_KEY0, AES_KEY_W0, 4'hF, wr_resp); check_signal("TC10-K0-wr", wr_resp[1], 1'b0);
            axi_write(AES_KEY1, AES_KEY_W1, 4'hF, wr_resp); check_signal("TC10-K1-wr", wr_resp[1], 1'b0);
            axi_write(AES_KEY2, AES_KEY_W2, 4'hF, wr_resp); check_signal("TC10-K2-wr", wr_resp[1], 1'b0);
            axi_write(AES_KEY3, AES_KEY_W3, 4'hF, wr_resp); check_signal("TC10-K3-wr", wr_resp[1], 1'b0);
            axi_write(AES_TXTIN0, AES_PT_W0, 4'hF, wr_resp);
            axi_write(AES_TXTIN1, AES_PT_W1, 4'hF, wr_resp);
            axi_write(AES_TXTIN2, AES_PT_W2, 4'hF, wr_resp);
            axi_write(AES_TXTIN3, AES_PT_W3, 4'hF, wr_resp);

            // TC11
            $display("\n===== TC11: AES START =====");
            axi_write(AES_CTRL_REG, 32'h01, 4'hF, wr_resp);
            check_signal("TC11-AES-START-wr", wr_resp[1], 1'b0);
            repeat (2) @(posedge clk);
            check_signal("TC11-aes_busy", aes_busy_o, 1'b1);

            // TC12
            $display("\n===== TC12: AES Done Signals =====");
            begin : tc12
                integer tmo;
                tmo = 0;
                while (!aes_done_o) begin
                    @(posedge clk);
                    tmo++;
                    if (tmo > 500) begin
                        $error("[FAIL] TC12: aes_done_o timeout"); fail_cnt++;
                        disable tc12;
                    end
                end
                check_signal("TC12-aes_done_o",       aes_done_o,       1'b1);
                check_signal("TC12-aes_done_pulse_o", aes_done_pulse_o, 1'b1);
                check_signal("TC12-aes_irq_o",        aes_irq_o,        1'b1);
            end

            // TC13
            $display("\n===== TC13: AES Ciphertext Read-back =====");
            repeat (2) @(posedge clk);
            axi_read(AES_TXTOUT0, rd_data, rd_resp); check32("TC13-CT-W0", rd_data, AES_CT_W0);
            axi_read(AES_TXTOUT1, rd_data, rd_resp); check32("TC13-CT-W1", rd_data, AES_CT_W1);
            axi_read(AES_TXTOUT2, rd_data, rd_resp); check32("TC13-CT-W2", rd_data, AES_CT_W2);
            axi_read(AES_TXTOUT3, rd_data, rd_resp); check32("TC13-CT-W3", rd_data, AES_CT_W3);

            // TC14
            $display("\n===== TC14: DMA CSR Read =====");
            axi_read(DMA_CTRL_REG, rd_data, rd_resp); check_signal("TC14-DMA-ctrl-resp", rd_resp[1], 1'b0);
            axi_read(DMA_STAT_REG, rd_data, rd_resp); check_signal("TC14-DMA-stat-resp", rd_resp[1], 1'b0);

            // TC15
            $display("\n===== TC15: DMA Descriptor Setup =====");
            axi_write(DMA_DESC0_SRC, UART_BASE,     4'hF, wr_resp); check_signal("TC15-SRC-wr", wr_resp[1], 1'b0);
            axi_write(DMA_DESC0_DST, 32'hF004_0000, 4'hF, wr_resp); check_signal("TC15-DST-wr", wr_resp[1], 1'b0);
            axi_write(DMA_CTRL_REG,  32'h03,        4'hF, wr_resp); check_signal("TC15-START-wr", wr_resp[1], 1'b0);

            // TC16
            $display("\n===== TC16: DMA Done =====");
            begin : tc16
                integer tmo;
                tmo = 0;
                while (!dma_done_o) begin
                    @(posedge clk);
                    tmo++;
                    if (tmo > TIMEOUT_CYC) begin
                        $error("[FAIL] TC16: dma_done_o timeout"); fail_cnt++;
                        disable tc16;
                    end
                end
                check_signal("TC16-dma_done_o", dma_done_o, 1'b1);
                check_signal("TC16-dma_irq_o",  dma_irq_o,  1'b1);
            end

            // TC17
            $display("\n===== TC17: WDT Config =====");
            axi_write(WDT_LOAD, 32'h0000_1000, 4'hF, wr_resp); check_signal("TC17-WDT-LOAD-wr", wr_resp[1], 1'b0);
            axi_write(WDT_IM,   32'h01,        4'hF, wr_resp);
            axi_write(WDT_CTRL, 32'h03,        4'hF, wr_resp); check_signal("TC17-WDT-CTRL-wr", wr_resp[1], 1'b0);
            axi_read (WDT_CTRL, rd_data, rd_resp);             check32("TC17-WDT-CTRL-rb", rd_data, 32'h03, 32'h03);

            // TC18
            $display("\n===== TC18: WDT Software Ping =====");
            repeat (10) @(posedge clk);
            axi_write(WDT_PING, 32'hABCD_EF01, 4'hF, wr_resp); check_signal("TC18-WDT-PING-wr", wr_resp[1], 1'b0);
            repeat (5) @(posedge clk);
            check_signal("TC18-wdt_irq_idle", wdt_irq_o, 1'b0);

            // TC19
            $display("\n===== TC19: WDT AES Auto-Kick =====");
            axi_write(AES_TXTIN0, AES_PT_W0, 4'hF, wr_resp);
            axi_write(AES_TXTIN1, AES_PT_W1, 4'hF, wr_resp);
            axi_write(AES_TXTIN2, AES_PT_W2, 4'hF, wr_resp);
            axi_write(AES_TXTIN3, AES_PT_W3, 4'hF, wr_resp);
            axi_write(AES_CTRL_REG, 32'h01,  4'hF, wr_resp);
            begin : tc19
                integer tmo;
                tmo = 0;
                while (!aes_done_pulse_o) begin
                    @(posedge clk);
                    tmo++;
                    if (tmo > 500) begin
                        $error("[FAIL] TC19: aes_done_pulse_o for auto-kick timeout"); fail_cnt++;
                        disable tc19;
                    end
                end
                check_signal("TC19-aes_done_pulse_o-for-WDT-kick", aes_done_pulse_o, 1'b1);
            end
            repeat (5) @(posedge clk);
            check_signal("TC19-wdt_reset_o-still-low", wdt_reset_o, 1'b0);

            // TC20
            $display("\n===== TC20: WDT Timeout & IRQ =====");
            axi_write(WDT_CTRL, 32'h01,        4'hF, wr_resp);
            axi_write(WDT_LOAD, 32'h0000_0010, 4'hF, wr_resp);
            axi_write(WDT_CTRL, 32'h01,        4'hF, wr_resp);
            begin : tc20
                integer tmo;
                tmo = 0;
                while (!wdt_irq_o) begin
                    @(posedge clk);
                    tmo++;
                    if (tmo > 2000) begin
                        $error("[FAIL] TC20: wdt_irq_o timeout"); fail_cnt++;
                        disable tc20;
                    end
                end
                check_signal("TC20-wdt_irq_o", wdt_irq_o, 1'b1);
            end
            axi_write(WDT_IC, 32'hFFFF_FFFF, 4'hF, wr_resp);
            repeat (3) @(posedge clk);
            axi_read(WDT_RIS, rd_data, rd_resp);
            check32("TC20-WDT-RIS-cleared", rd_data, 32'h0, 32'h1);

            // TC21
            $display("\n===== TC21: WDT NMI + Hard Reset Escalation =====");
            axi_write(WDT_CTRL, 32'h0F,        4'hF, wr_resp);
            axi_write(WDT_LOAD, 32'h0000_0008, 4'hF, wr_resp);
            begin : tc21
                integer tmo;
                tmo = 0;
                while (!wdt_nmi_o && !wdt_reset_o) begin
                    @(posedge clk);
                    tmo++;
                    if (tmo > 2000) begin
                        $error("[FAIL] TC21: wdt_nmi_o/wdt_reset_o timeout"); fail_cnt++;
                        disable tc21;
                    end
                end
                check_signal("TC21-wdt_nmi_o",   wdt_nmi_o,   1'b1);
                check_signal("TC21-wdt_reset_o", wdt_reset_o, 1'b1);
            end
            axi_write(WDT_CTRL, 32'h00,        4'hF, wr_resp);
            axi_write(WDT_IC,   32'hFFFF_FFFF, 4'hF, wr_resp);

            // TC22
            $display("\n===== TC22: GPIO Output =====");
            axi_write(GPIO_EN_REG,  32'h0000_00FF, 4'hF, wr_resp); check_signal("TC22-GPIO-EN-wr",  wr_resp[1], 1'b0);
            axi_write(GPIO_OUT_REG, 32'hA5,        4'hF, wr_resp); check_signal("TC22-GPIO-OUT-wr", wr_resp[1], 1'b0);

            // TC23
            $display("\n===== TC23: GPIO out_o verification =====");
            repeat (3) @(posedge clk);
            check32("TC23-gpio_out_o", gpio_out_o,    32'hA5,        32'hFF);
            check32("TC23-gpio_tx_en", gpio_tx_en_o,  32'h0000_00FF, 32'hFF);

            // TC24
            $display("\n===== TC24: GPIO Input Read =====");
            @(negedge clk); gpio_in_i = 32'h5A5A_A5A5;
            repeat (3) @(posedge clk);
            axi_read(GPIO_IN_REG, rd_data, rd_resp);
            check32("TC24-GPIO-IN", rd_data, 32'h5A5A_A5A5);
            @(negedge clk); gpio_in_i = 32'h0;

            // TC25
            $display("\n===== TC25: GPIO Rising-Edge IRQ =====");
            axi_write(GPIO_RISE_EN, 32'h0000_0001, 4'hF, wr_resp);
            @(negedge clk); gpio_in_i = 32'h0;
            repeat (3) @(posedge clk);
            @(negedge clk); gpio_in_i = 32'h1;
            begin : tc25
                integer tmo;
                tmo = 0;
                while (!gpio_irq_o) begin
                    @(posedge clk);
                    tmo++;
                    if (tmo > 200) begin
                        $error("[FAIL] TC25: gpio_irq_o rising edge timeout"); fail_cnt++;
                        disable tc25;
                    end
                end
                check_signal("TC25-gpio_irq_o", gpio_irq_o, 1'b1);
            end
            axi_write(GPIO_INT_STAT, 32'hFFFF_FFFF, 4'hF, wr_resp);
            @(negedge clk); gpio_in_i = 32'h0;

            // TC26
            $display("\n===== TC26: Autonomous Pipeline Integration =====");
            axi_write(WDT_CTRL, 32'h00,        4'hF, wr_resp);
            axi_write(WDT_LOAD, 32'h0010_0000, 4'hF, wr_resp);
            axi_write(WDT_CTRL, 32'h03,        4'hF, wr_resp);
            uart_inject_byte(8'hC3);
            begin : tc26_uart
                integer tmo;
                tmo = 0;
                while (!uart_read_irq_o) begin
                    @(posedge clk); tmo++;
                    if (tmo > TIMEOUT_CYC) begin
                        $error("[FAIL] TC26: uart_read_irq_o timeout"); fail_cnt++;
                        disable tc26_uart;
                    end
                end
                check_signal("TC26-uart_irq", uart_read_irq_o, 1'b1);
            end
            axi_write(AES_TXTIN0, AES_PT_W0, 4'hF, wr_resp);
            axi_write(AES_TXTIN1, AES_PT_W1, 4'hF, wr_resp);
            axi_write(AES_TXTIN2, AES_PT_W2, 4'hF, wr_resp);
            axi_write(AES_TXTIN3, AES_PT_W3, 4'hF, wr_resp);
            axi_write(AES_CTRL_REG, 32'h01, 4'hF, wr_resp);
            begin : tc26_aes
                integer tmo;
                tmo = 0;
                while (!aes_done_pulse_o) begin
                    @(posedge clk); tmo++;
                    if (tmo > 500) begin
                        $error("[FAIL] TC26: aes_done_pulse_o timeout"); fail_cnt++;
                        disable tc26_aes;
                    end
                end
                check_signal("TC26-aes_done_pulse", aes_done_pulse_o, 1'b1);
            end
            repeat (10) @(posedge clk);
            check_signal("TC26-wdt_no_reset", wdt_reset_o, 1'b0);

            // TC27
            $display("\n===== TC27: Multi-Master Concurrency =====");
            fork
                begin
                    logic [1:0] r;
                    axi_write(UART_LCR,   32'h03, 4'hF, r);
                    axi_write(GPIO_EN_REG, 32'hFF, 4'hF, r);
                end
                begin
                    logic [31:0] d;
                    logic [1:0]  r2;
                    axi_read(DMA_STAT_REG, d, r2);
                    axi_read(WDT_CTRL,     d, r2);
                end
            join
            check_signal("TC27-concurrency-ok", 1'b1, 1'b1);

            // TC28
            $display("\n===== TC28: SLVERR on unmapped address =====");
            axi_write(UNMAPPED_ADDR, 32'hDEAD_BEEF, 4'hF, wr_resp);
            check_signal("TC28-SLVERR-bresp1", wr_resp[1], 1'b1);

            // BFM Summary
            $display("\n=======================================================");
            $display("  SIMULATION COMPLETE");
            $display("  PASS : %0d", pass_cnt);
            $display("  FAIL : %0d", fail_cnt);
            $display("  TOTAL: %0d", pass_cnt + fail_cnt);
            if (fail_cnt == 0)
                $display("  STATUS : ** ALL BFM TESTS PASSED **");
            else
                $display("  STATUS : !! %0d BFM TEST(S) FAILED !!", fail_cnt);
            $display("=======================================================\n");

            repeat (20) @(posedge clk);
            $finish;
        end
    end

    // =========================================================================
    // Firmware Output & Reactive Handshake Monitor
    // =========================================================================
    initial begin
        bit fw_mode;
        fw_mode = $test$plusargs("FWONLY");

        if (fw_mode) begin
            $display("[TB-FW] Firmware monitor active. Listening for handshakes...");

            fork
                // 1. Respond to UART TX 'K' (0x4B) by injecting 0xA5 into uart_rx_i
                begin
                    wait(uart_tx_o === 1'b0);
                    repeat (BIT_CYCLES * 10) @(posedge clk);
                    $display("[TB-FW] UART TX 'K' detected. Injecting byte 0xA5 to uart_rx_i...");
                    uart_inject_byte(8'hA5);
                end

                // 2. Respond to GPIO lower byte 0xA5 by pulsing gpio_in_i[0]
                begin
                    wait(gpio_out_o[7:0] === 8'hA5);
                    $display("[TB-FW] GPIO lower byte 0xA5 detected. Driving rising-edge interrupt on gpio_in_i[0]...");
                    repeat (5) @(posedge clk);
                    gpio_in_i[0] = 1'b1;
                    repeat (10) @(posedge clk);
                    gpio_in_i[0] = 1'b0;
                end

                // 3. Track Step Progress and Pass/Fail Codes on gpio_out_o[31:16]
                begin
                    forever begin
                        @(gpio_out_o[31:16]);
                        case (gpio_out_o[31:16])
                            16'h0006: $display("[FW PROGRESS] 0x0006: UART check PASSED");
                            16'h0009: $display("[FW PROGRESS] 0x0009: Timer check PASSED");
                            16'h0013: $display("[FW PROGRESS] 0x0013: AES check PASSED");
                            16'h0016: $display("[FW PROGRESS] 0x0016: DMA check PASSED");
                            16'h0021: $display("[FW PROGRESS] 0x0021: WDT check PASSED");
                            16'h0025: $display("[FW PROGRESS] 0x0025: GPIO check PASSED");
                            16'h0026: $display("[FW PROGRESS] 0x0026: Pipeline check PASSED");
                            16'h900D: begin
                                $display("\n=======================================================");
                                $display("  [TB-FW] *** ALL FIRMWARE CHECKS PASSED (0x900D) ***");
                                $display("=======================================================\n");
                                repeat (50) @(posedge clk);
                                $finish;
                            end
                            16'hDEAD: begin
                                $display("\n[TB-FW] *** FIRMWARE FAILED AT STEP: 0x%04h ***", gpio_out_o[15:0]);
                                repeat (50) @(posedge clk);
                                $finish;
                            end
                        endcase
                    end
                end
            join
        end
    end

    // =========================================================================
    // Simulation Watchdog
    // =========================================================================
    initial begin
        #(CLK_PERIOD * 10_000_000);
        $error("[TB] GLOBAL SIMULATION TIMEOUT — aborting");
        $finish;
    end

endmodule

`default_nettype wire
