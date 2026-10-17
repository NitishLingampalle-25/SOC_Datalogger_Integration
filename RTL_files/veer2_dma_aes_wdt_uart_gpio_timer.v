// =============================================================================
// Module  : veer2_dma_aes_wdt_uart_gpio_timer
// File    : RTL_files/veer2_dma_aes_wdt_uart_gpio_timer.v
//
// Purpose : Top-level SoC integration of:
//             1. el2_veer_wrapper           – VeeR EL2 RISC-V core (AXI4, Master 1)
//             2. axi_dwidth_converter_64to32 – VeeR LSU 64-to-32 bit adapter
//             3. axi_interconnect_wrap_2x6  – AXI4 2x6 crossbar interconnect
//             4. UART Subsystem             – axi4_to_axilite_bridge + axi_uart_top  (0x4000_0000)
//             5. System Timer               – timer_axi_wrapper → timer_core          (0x4000_1000)
//             6. AES Subsystem              – aes_veer_adapter                       (0x4000_2000)
//             7. DMA Controller Subsystem   – dma_axi_wrapper                        (0x4000_3000)
//             8. Watchdog Timer Subsystem   – ef_wdt32_axi_wrapper + EF_WDT32        (0x4000_4000)
//             9. GPIO Subsystem             – gpio_axi_wrapper → gpio_reg_top + gpio (0x4000_5000)
//
// Address Map:
//   0x4000_0000 – 0x4000_0FFF : UART          (4 KB)
//   0x4000_1000 – 0x4000_1FFF : System Timer  (4 KB)
//   0x4000_2000 – 0x4000_2FFF : AES           (4 KB)
//   0x4000_3000 – 0x4000_3FFF : DMA CSRs      (4 KB)
//   0x4000_4000 – 0x4000_4FFF : Watchdog      (4 KB)
//   0x4000_5000 – 0x4000_5FFF : GPIO          (4 KB)
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

import amba_axi_pkg::*;
import dma_utils_pkg::*;

module veer2_dma_aes_wdt_uart_gpio_timer #(
    parameter IC_ID_WIDTH         = 8,
    parameter DATA_WIDTH          = 32,
    parameter ADDR_WIDTH          = 32,
    parameter STRB_WIDTH          = DATA_WIDTH / 8,
    parameter UART_ID_W           = 12,
    parameter [ADDR_WIDTH-1:0] UART_BASE_ADDR  = 32'h4000_0000,
    parameter [ADDR_WIDTH-1:0] TIMER_BASE_ADDR = 32'h4000_1000,
    parameter [ADDR_WIDTH-1:0] AES_BASE_ADDR   = 32'h4000_2000,
    parameter [ADDR_WIDTH-1:0] DMA_BASE_ADDR   = 32'h4000_3000,
    parameter [ADDR_WIDTH-1:0] WDT_BASE_ADDR   = 32'h4000_4000,
    parameter [ADDR_WIDTH-1:0] GPIO_BASE_ADDR  = 32'h4000_5000,
    parameter [ADDR_WIDTH-1:0] M01_BASE        = 32'h4000_1000,

    parameter LSU_BUS_TAG   = 4,
    parameter IFU_BUS_TAG   = 3,
    parameter SB_BUS_TAG    = 2,
    parameter DMA_BUS_TAG   = 1,
    parameter PIC_TOTAL_INT = 31
)(
    // Global
    input  wire                   clk,
    input  wire                   rst_l,
    input  wire                   dbg_rst_l,
    input  wire                   fixed_clk,

    // VeeR boot
    input  wire [31:1]            rst_vec,
    input  wire [31:1]            nmi_vec,
    input  wire [31:1]            jtag_id,
    input  wire [31:4]            core_id,

    // Interrupts / handshaking
    input  wire                         nmi_int,
    input  wire                         timer_int,
    input  wire                         soft_int,
    input  wire [PIC_TOTAL_INT:1]       extintsrc_req,
    output wire                         uart_read_irq_o,
    output wire                         aes_irq_o,
    output wire                         aes_done_pulse_o,
    output wire                         dma_done_o,
    output wire                         dma_error_o,
    output wire                         dma_irq_o,
    output wire                         wdt_irq_o,
    output wire                         wdt_nmi_o,
    output wire                         wdt_reset_o,
    output wire                         wdt_timeout_o,
    output wire                         gpio_irq_o,      // GPIO global interrupt
    output wire                         timer_irq_o,     // System Timer interrupt

    // Peripheral physical signals
    output wire                         uart_tx_o,
    input  wire                         uart_rx_i,
    output wire                         aes_busy_o,
    output wire                         aes_done_o,

    // GPIO physical signals (32-bit)
    input  wire [31:0]                  gpio_in_i,
    output wire [31:0]                  gpio_out_o,
    output wire [31:0]                  gpio_tx_en_o,

    // IFU AXI master
    output wire                         ifu_axi_arvalid,
    input  wire                         ifu_axi_arready,
    output wire [IFU_BUS_TAG-1:0]       ifu_axi_arid,
    output wire [31:0]                  ifu_axi_araddr,
    output wire [3:0]                   ifu_axi_arregion,
    output wire [7:0]                   ifu_axi_arlen,
    output wire [2:0]                   ifu_axi_arsize,
    output wire [1:0]                   ifu_axi_arburst,
    output wire                         ifu_axi_arlock,
    output wire [3:0]                   ifu_axi_arcache,
    output wire [2:0]                   ifu_axi_arprot,
    output wire [3:0]                   ifu_axi_arqos,
    input  wire                         ifu_axi_rvalid,
    output wire                         ifu_axi_rready,
    input  wire [IFU_BUS_TAG-1:0]       ifu_axi_rid,
    input  wire [63:0]                  ifu_axi_rdata,
    input  wire [1:0]                   ifu_axi_rresp,
    input  wire                         ifu_axi_rlast,
    output wire                         ifu_axi_awvalid,
    input  wire                         ifu_axi_awready,
    output wire [IFU_BUS_TAG-1:0]       ifu_axi_awid,
    output wire [31:0]                  ifu_axi_awaddr,
    output wire [3:0]                   ifu_axi_awregion,
    output wire [7:0]                   ifu_axi_awlen,
    output wire [2:0]                   ifu_axi_awsize,
    output wire [1:0]                   ifu_axi_awburst,
    output wire                         ifu_axi_awlock,
    output wire [3:0]                   ifu_axi_awcache,
    output wire [2:0]                   ifu_axi_awprot,
    output wire [3:0]                   ifu_axi_awqos,
    output wire                         ifu_axi_wvalid,
    input  wire                         ifu_axi_wready,
    output wire [63:0]                  ifu_axi_wdata,
    output wire [7:0]                   ifu_axi_wstrb,
    output wire                         ifu_axi_wlast,
    input  wire                         ifu_axi_bvalid,
    output wire                         ifu_axi_bready,
    input  wire [1:0]                   ifu_axi_bresp,
    input  wire [IFU_BUS_TAG-1:0]       ifu_axi_bid,

    // SB AXI master
    output wire                         sb_axi_awvalid,
    input  wire                         sb_axi_awready,
    output wire [SB_BUS_TAG-1:0]        sb_axi_awid,
    output wire [31:0]                  sb_axi_awaddr,
    output wire [3:0]                   sb_axi_awregion,
    output wire [7:0]                   sb_axi_awlen,
    output wire [2:0]                   sb_axi_awsize,
    output wire [1:0]                   sb_axi_awburst,
    output wire                         sb_axi_awlock,
    output wire [3:0]                   sb_axi_awcache,
    output wire [2:0]                   sb_axi_awprot,
    output wire [3:0]                   sb_axi_awqos,
    output wire                         sb_axi_wvalid,
    input  wire                         sb_axi_wready,
    output wire [63:0]                  sb_axi_wdata,
    output wire [7:0]                   sb_axi_wstrb,
    output wire                         sb_axi_wlast,
    input  wire                         sb_axi_bvalid,
    output wire                         sb_axi_bready,
    input  wire [1:0]                   sb_axi_bresp,
    input  wire [SB_BUS_TAG-1:0]        sb_axi_bid,
    output wire                         sb_axi_arvalid,
    input  wire                         sb_axi_arready,
    output wire [SB_BUS_TAG-1:0]        sb_axi_arid,
    output wire [31:0]                  sb_axi_araddr,
    output wire [3:0]                   sb_axi_arregion,
    output wire [7:0]                   sb_axi_arlen,
    output wire [2:0]                   sb_axi_arsize,
    output wire [1:0]                   sb_axi_arburst,
    output wire                         sb_axi_arlock,
    output wire [3:0]                   sb_axi_arcache,
    output wire [2:0]                   sb_axi_arprot,
    output wire [3:0]                   sb_axi_arqos,
    input  wire                         sb_axi_rvalid,
    output wire                         sb_axi_rready,
    input  wire [SB_BUS_TAG-1:0]        sb_axi_rid,
    input  wire [63:0]                  sb_axi_rdata,
    input  wire [1:0]                   sb_axi_rresp,
    input  wire                         sb_axi_rlast,

    // DMA AXI slave
    input  wire                         dma_axi_awvalid,
    output wire                         dma_axi_awready,
    input  wire [DMA_BUS_TAG-1:0]       dma_axi_awid,
    input  wire [31:0]                  dma_axi_awaddr,
    input  wire [2:0]                   dma_axi_awsize,
    input  wire [2:0]                   dma_axi_awprot,
    input  wire [7:0]                   dma_axi_awlen,
    input  wire [1:0]                   dma_axi_awburst,
    input  wire                         dma_axi_wvalid,
    output wire                         dma_axi_wready,
    input  wire [63:0]                  dma_axi_wdata,
    input  wire [7:0]                   dma_axi_wstrb,
    input  wire                         dma_axi_wlast,
    output wire                         dma_axi_bvalid,
    input  wire                         dma_axi_bready,
    output wire [1:0]                   dma_axi_bresp,
    output wire [DMA_BUS_TAG-1:0]       dma_axi_bid,
    input  wire                         dma_axi_arvalid,
    output wire                         dma_axi_arready,
    input  wire [DMA_BUS_TAG-1:0]       dma_axi_arid,
    input  wire [31:0]                  dma_axi_araddr,
    input  wire [2:0]                   dma_axi_arsize,
    input  wire [2:0]                   dma_axi_arprot,
    input  wire [7:0]                   dma_axi_arlen,
    input  wire [1:0]                   dma_axi_arburst,
    output wire                         dma_axi_rvalid,
    input  wire                         dma_axi_rready,
    output wire [DMA_BUS_TAG-1:0]       dma_axi_rid,
    output wire [63:0]                  dma_axi_rdata,
    output wire [1:0]                   dma_axi_rresp,
    output wire                         dma_axi_rlast,

    // VeeR trace
    output wire [31:0]  trace_rv_i_insn_ip,
    output wire [31:0]  trace_rv_i_address_ip,
    output wire         trace_rv_i_valid_ip,
    output wire         trace_rv_i_exception_ip,
    output wire [4:0]   trace_rv_i_ecause_ip,
    output wire         trace_rv_i_interrupt_ip,
    output wire [31:0]  trace_rv_i_tval_ip,

    // ECC
    output wire         iccm_ecc_single_error,
    output wire         iccm_ecc_double_error,
    output wire         dccm_ecc_single_error,
    output wire         dccm_ecc_double_error,
    output wire         dccm_write_readback_error,

    // Perf counters
    output wire         dec_tlu_perfcnt0,
    output wire         dec_tlu_perfcnt1,
    output wire         dec_tlu_perfcnt2,
    output wire         dec_tlu_perfcnt3,

    // JTAG
    input  wire         jtag_tck,
    input  wire         jtag_tms,
    input  wire         jtag_tdi,
    input  wire         jtag_trst_n,
    output wire         jtag_tdo,
    output wire         jtag_tdoEn,

    // MPC / halt / run
    input  wire         mpc_debug_halt_req,
    input  wire         mpc_debug_run_req,
    input  wire         mpc_reset_run_req,
    output wire         mpc_debug_halt_ack,
    output wire         mpc_debug_run_ack,
    output wire         debug_brkpt_status,
    input  wire         i_cpu_halt_req,
    output wire         o_cpu_halt_ack,
    output wire         o_cpu_halt_status,
    output wire         o_debug_mode_status,
    input  wire         i_cpu_run_req,
    output wire         o_cpu_run_ack,

    // Misc VeeR inputs
    input  wire         lsu_bus_clk_en,
    input  wire         ifu_bus_clk_en,
    input  wire         dbg_bus_clk_en,
    input  wire         dma_bus_clk_en,
    input  wire         scan_mode,
    input  wire         mbist_mode,

    // DMI
    input  wire         dmi_core_enable,
    input  wire         dmi_uncore_enable,
    output wire         dmi_uncore_en,
    output wire         dmi_uncore_wr_en,
    output wire [6:0]   dmi_uncore_addr,
    output wire [31:0]  dmi_uncore_wdata,
    input  wire [31:0]  dmi_uncore_rdata,
    output wire         dmi_active
);

    // =========================================================================
    // Internal wires: VeeR LSU AXI (64-bit) ↔ axi_dwidth_converter_64to32
    // =========================================================================
    wire                        lsu_axi_awvalid_w; wire lsu_axi_awready_w;
    wire [LSU_BUS_TAG-1:0]      lsu_axi_awid_w;
    wire [31:0]                 lsu_axi_awaddr_w;  wire [3:0] lsu_axi_awregion_w;
    wire [7:0]                  lsu_axi_awlen_w;   wire [2:0] lsu_axi_awsize_w;
    wire [1:0]                  lsu_axi_awburst_w; wire lsu_axi_awlock_w;
    wire [3:0]                  lsu_axi_awcache_w; wire [2:0] lsu_axi_awprot_w;
    wire [3:0]                  lsu_axi_awqos_w;
    wire                        lsu_axi_wvalid_w;  wire lsu_axi_wready_w;
    wire [63:0]                 lsu_axi_wdata_w;   wire [7:0] lsu_axi_wstrb_w;
    wire                        lsu_axi_wlast_w;
    wire                        lsu_axi_bvalid_w;  wire lsu_axi_bready_w;
    wire [1:0]                  lsu_axi_bresp_w;   wire [LSU_BUS_TAG-1:0] lsu_axi_bid_w;
    wire                        lsu_axi_arvalid_w; wire lsu_axi_arready_w;
    wire [LSU_BUS_TAG-1:0]      lsu_axi_arid_w;
    wire [31:0]                 lsu_axi_araddr_w;  wire [3:0] lsu_axi_arregion_w;
    wire [7:0]                  lsu_axi_arlen_w;   wire [2:0] lsu_axi_arsize_w;
    wire [1:0]                  lsu_axi_arburst_w; wire lsu_axi_arlock_w;
    wire [3:0]                  lsu_axi_arcache_w; wire [2:0] lsu_axi_arprot_w;
    wire [3:0]                  lsu_axi_arqos_w;
    wire                        lsu_axi_rvalid_w;  wire lsu_axi_rready_w;
    wire [LSU_BUS_TAG-1:0]      lsu_axi_rid_w;
    wire [63:0]                 lsu_axi_rdata_w;   wire [1:0] lsu_axi_rresp_w;
    wire                        lsu_axi_rlast_w;

    // =========================================================================
    // Internal wires: interconnect s00 (32-bit, VeeR LSU) and s01 (DMA Master)
    // =========================================================================
    wire [IC_ID_WIDTH-1:0] s00_awid_w;   wire [ADDR_WIDTH-1:0] s00_awaddr_w;
    wire [7:0] s00_awlen_w;  wire [2:0] s00_awsize_w;  wire [1:0] s00_awburst_w;
    wire s00_awlock_w; wire [3:0] s00_awcache_w; wire [2:0] s00_awprot_w;
    wire [3:0] s00_awqos_w;  wire s00_awvalid_w; wire s00_awready_w;
    wire [DATA_WIDTH-1:0] s00_wdata_w; wire [STRB_WIDTH-1:0] s00_wstrb_w;
    wire s00_wlast_w; wire s00_wvalid_w; wire s00_wready_w;
    wire [IC_ID_WIDTH-1:0] s00_bid_w; wire [1:0] s00_bresp_w;
    wire s00_bvalid_w; wire s00_bready_w;
    wire [IC_ID_WIDTH-1:0] s00_arid_w;   wire [ADDR_WIDTH-1:0] s00_araddr_w;
    wire [7:0] s00_arlen_w;  wire [2:0] s00_arsize_w;  wire [1:0] s00_arburst_w;
    wire s00_arlock_w; wire [3:0] s00_arcache_w; wire [2:0] s00_arprot_w;
    wire [3:0] s00_arqos_w;  wire s00_arvalid_w; wire s00_arready_w;
    wire [IC_ID_WIDTH-1:0] s00_rid_w; wire [DATA_WIDTH-1:0] s00_rdata_w;
    wire [1:0] s00_rresp_w; wire s00_rlast_w; wire s00_rvalid_w; wire s00_rready_w;

    wire [IC_ID_WIDTH-1:0] s01_awid_w;   wire [ADDR_WIDTH-1:0] s01_awaddr_w;
    wire [7:0] s01_awlen_w;  wire [2:0] s01_awsize_w;  wire [1:0] s01_awburst_w;
    wire s01_awlock_w; wire [3:0] s01_awcache_w; wire [2:0] s01_awprot_w;
    wire [3:0] s01_awqos_w;  wire s01_awvalid_w; wire s01_awready_w;
    wire [DATA_WIDTH-1:0] s01_wdata_w; wire [STRB_WIDTH-1:0] s01_wstrb_w;
    wire s01_wlast_w; wire s01_wvalid_w; wire s01_wready_w;
    wire [IC_ID_WIDTH-1:0] s01_bid_w; wire [1:0] s01_bresp_w;
    wire s01_bvalid_w; wire s01_bready_w;
    wire [IC_ID_WIDTH-1:0] s01_arid_w;   wire [ADDR_WIDTH-1:0] s01_araddr_w;
    wire [7:0] s01_arlen_w;  wire [2:0] s01_arsize_w;  wire [1:0] s01_arburst_w;
    wire s01_arlock_w; wire [3:0] s01_arcache_w; wire [2:0] s01_arprot_w;
    wire [3:0] s01_arqos_w;  wire s01_arvalid_w; wire s01_arready_w;
    wire [IC_ID_WIDTH-1:0] s01_rid_w; wire [DATA_WIDTH-1:0] s01_rdata_w;
    wire [1:0] s01_rresp_w; wire s01_rlast_w; wire s01_rvalid_w; wire s01_rready_w;

    // =========================================================================
    // Interconnect master-port wires: m00(UART) m02(AES) m03(DMA) m04(WDT) m05(GPIO)
    // =========================================================================
    wire [IC_ID_WIDTH-1:0] m00_awid,m00_bid,m00_arid,m00_rid;
    wire [ADDR_WIDTH-1:0]  m00_awaddr,m00_araddr;
    wire [7:0] m00_awlen,m00_arlen; wire [2:0] m00_awsize,m00_arsize;
    wire [1:0] m00_awburst,m00_arburst; wire m00_awlock,m00_arlock;
    wire [3:0] m00_awcache,m00_arcache,m00_awqos,m00_arqos,m00_awregion,m00_arregion;
    wire [2:0] m00_awprot,m00_arprot;
    wire m00_awvalid,m00_awready,m00_wvalid,m00_wready,m00_bvalid,m00_bready;
    wire m00_arvalid,m00_arready,m00_rvalid,m00_rready,m00_wlast,m00_rlast;
    wire [DATA_WIDTH-1:0] m00_wdata,m00_rdata; wire [STRB_WIDTH-1:0] m00_wstrb;
    wire [1:0] m00_bresp,m00_rresp;

    // m01: System Timer
    wire [IC_ID_WIDTH-1:0] m01_awid,m01_bid,m01_arid,m01_rid;
    wire [ADDR_WIDTH-1:0]  m01_awaddr,m01_araddr;
    wire [7:0] m01_awlen,m01_arlen; wire [2:0] m01_awsize,m01_arsize;
    wire [1:0] m01_awburst,m01_arburst; wire m01_awlock,m01_arlock;
    wire [3:0] m01_awcache,m01_arcache,m01_awqos,m01_arqos,m01_awregion,m01_arregion;
    wire [2:0] m01_awprot,m01_arprot;
    wire m01_awvalid,m01_awready,m01_wvalid,m01_wready,m01_bvalid,m01_bready;
    wire m01_arvalid,m01_arready,m01_rvalid,m01_rready,m01_wlast,m01_rlast;
    wire [DATA_WIDTH-1:0] m01_wdata,m01_rdata; wire [STRB_WIDTH-1:0] m01_wstrb;
    wire [1:0] m01_bresp,m01_rresp;

    wire [IC_ID_WIDTH-1:0] m02_awid,m02_bid,m02_arid,m02_rid;
    wire [ADDR_WIDTH-1:0]  m02_awaddr,m02_araddr;
    wire [7:0] m02_awlen,m02_arlen; wire [2:0] m02_awsize,m02_arsize;
    wire [1:0] m02_awburst,m02_arburst; wire m02_awlock,m02_arlock;
    wire [3:0] m02_awcache,m02_arcache,m02_awqos,m02_arqos,m02_awregion,m02_arregion;
    wire [2:0] m02_awprot,m02_arprot;
    wire m02_awvalid,m02_awready,m02_wvalid,m02_wready,m02_bvalid,m02_bready;
    wire m02_arvalid,m02_arready,m02_rvalid,m02_rready,m02_wlast,m02_rlast;
    wire [DATA_WIDTH-1:0] m02_wdata,m02_rdata; wire [STRB_WIDTH-1:0] m02_wstrb;
    wire [1:0] m02_bresp,m02_rresp;

    wire [IC_ID_WIDTH-1:0] m03_awid,m03_bid,m03_arid,m03_rid;
    wire [ADDR_WIDTH-1:0]  m03_awaddr,m03_araddr;
    wire [7:0] m03_awlen,m03_arlen; wire [2:0] m03_awsize,m03_arsize;
    wire [1:0] m03_awburst,m03_arburst; wire m03_awlock,m03_arlock;
    wire [3:0] m03_awcache,m03_arcache,m03_awqos,m03_arqos,m03_awregion,m03_arregion;
    wire [2:0] m03_awprot,m03_arprot;
    wire m03_awvalid,m03_awready,m03_wvalid,m03_wready,m03_bvalid,m03_bready;
    wire m03_arvalid,m03_arready,m03_rvalid,m03_rready,m03_wlast,m03_rlast;
    wire [DATA_WIDTH-1:0] m03_wdata,m03_rdata; wire [STRB_WIDTH-1:0] m03_wstrb;
    wire [1:0] m03_bresp,m03_rresp;

    wire [IC_ID_WIDTH-1:0] m04_awid,m04_bid,m04_arid,m04_rid;
    wire [ADDR_WIDTH-1:0]  m04_awaddr,m04_araddr;
    wire [7:0] m04_awlen,m04_arlen; wire [2:0] m04_awsize,m04_arsize;
    wire [1:0] m04_awburst,m04_arburst; wire m04_awlock,m04_arlock;
    wire [3:0] m04_awcache,m04_arcache,m04_awqos,m04_arqos,m04_awregion,m04_arregion;
    wire [2:0] m04_awprot,m04_arprot;
    wire m04_awvalid,m04_awready,m04_wvalid,m04_wready,m04_bvalid,m04_bready;
    wire m04_arvalid,m04_arready,m04_rvalid,m04_rready,m04_wlast,m04_rlast;
    wire [DATA_WIDTH-1:0] m04_wdata,m04_rdata; wire [STRB_WIDTH-1:0] m04_wstrb;
    wire [1:0] m04_bresp,m04_rresp;

    // m05: GPIO
    wire [IC_ID_WIDTH-1:0] m05_awid,m05_bid,m05_arid,m05_rid;
    wire [ADDR_WIDTH-1:0]  m05_awaddr,m05_araddr;
    wire [7:0] m05_awlen,m05_arlen; wire [2:0] m05_awsize,m05_arsize;
    wire [1:0] m05_awburst,m05_arburst; wire m05_awlock,m05_arlock;
    wire [3:0] m05_awcache,m05_arcache,m05_awqos,m05_arqos,m05_awregion,m05_arregion;
    wire [2:0] m05_awprot,m05_arprot;
    wire m05_awvalid,m05_awready,m05_wvalid,m05_wready,m05_bvalid,m05_bready;
    wire m05_arvalid,m05_arready,m05_rvalid,m05_rready,m05_wlast,m05_rlast;
    wire [DATA_WIDTH-1:0] m05_wdata,m05_rdata; wire [STRB_WIDTH-1:0] m05_wstrb;
    wire [1:0] m05_bresp,m05_rresp;

    // UART bridge AXI-Lite wires
    wire [UART_ID_W-1:0] uart_awid,uart_bid,uart_arid,uart_rid;
    wire [4:0]  uart_awaddr,uart_araddr;
    wire        uart_awvalid,uart_awready,uart_wvalid,uart_wready;
    wire        uart_bvalid,uart_bready,uart_arvalid,uart_arready;
    wire        uart_rvalid,uart_rready;
    wire [DATA_WIDTH-1:0] uart_wdata,uart_rdata; wire [STRB_WIDTH-1:0] uart_wstrb;
    wire [1:0] uart_bresp,uart_rresp;

    wire rst_ic = ~rst_l;

    // X-propagation guards
    // s00 _clean guards: simple wire pass-through (no === so X doesn't gate the bus)
    wire s00_awvalid_clean = s00_awvalid_w;
    wire s00_wvalid_clean  = s00_wvalid_w;
    wire s00_bready_clean  = s00_bready_w;
    wire s00_arvalid_clean = s00_arvalid_w;
    wire s00_rready_clean  = s00_rready_w;
    // s01 _clean guards: use reg + always so TB `force` on the _w nets propagates
    reg  s01_awvalid_clean;
    reg  s01_wvalid_clean;
    reg  s01_bready_clean;
    reg  s01_arvalid_clean;
    reg  s01_rready_clean;
    always @(*) begin
        s01_awvalid_clean = (s01_awvalid_w === 1'b1);
        s01_wvalid_clean  = (s01_wvalid_w  === 1'b1);
        s01_bready_clean  = (s01_bready_w  === 1'b1);
        s01_arvalid_clean = (s01_arvalid_w === 1'b1);
        s01_rready_clean  = (s01_rready_w  === 1'b1);
    end

    // WDT NMI escalation
    wire core_nmi_int = nmi_int | wdt_nmi_o;

    // =========================================================================
    // el2_mem_if tie-offs
    // =========================================================================
    el2_mem_if el2_mem_export_if ();
    assign el2_mem_export_if.iccm_bank_dout            = '0;
    assign el2_mem_export_if.iccm_bank_ecc             = '0;
    assign el2_mem_export_if.dccm_bank_dout            = '0;
    assign el2_mem_export_if.dccm_bank_ecc             = '0;
    assign el2_mem_export_if.wb_packeddout_pre          = '0;
    assign el2_mem_export_if.wb_dout_pre_up             = '0;
    assign el2_mem_export_if.ic_tag_data_raw_packed_pre = '0;
    assign el2_mem_export_if.ic_tag_data_raw_pre        = '0;

    // =========================================================================
    // Data-width adapter: VeeR LSU 64-bit → Interconnect s00 32-bit
    // =========================================================================
    axi_dwidth_converter_64to32 #(
        .ID_WIDTH_M (LSU_BUS_TAG),
        .ID_WIDTH_S (IC_ID_WIDTH),
        .ADDR_WIDTH (32)
    ) u_dwidth_conv (
        .clk             (clk),          .rst_n           (rst_l),
        .m_axi_awid      (lsu_axi_awid_w),   .m_axi_awaddr    (lsu_axi_awaddr_w),
        .m_axi_awlen     (lsu_axi_awlen_w),   .m_axi_awsize    (lsu_axi_awsize_w),
        .m_axi_awburst   (lsu_axi_awburst_w), .m_axi_awlock    (lsu_axi_awlock_w),
        .m_axi_awcache   (lsu_axi_awcache_w), .m_axi_awprot    (lsu_axi_awprot_w),
        .m_axi_awqos     (lsu_axi_awqos_w),   .m_axi_awregion  (lsu_axi_awregion_w),
        .m_axi_awvalid   (lsu_axi_awvalid_w), .m_axi_awready   (lsu_axi_awready_w),
        .m_axi_wdata     (lsu_axi_wdata_w),   .m_axi_wstrb     (lsu_axi_wstrb_w),
        .m_axi_wlast     (lsu_axi_wlast_w),   .m_axi_wvalid    (lsu_axi_wvalid_w),
        .m_axi_wready    (lsu_axi_wready_w),
        .m_axi_bid       (lsu_axi_bid_w),     .m_axi_bresp     (lsu_axi_bresp_w),
        .m_axi_bvalid    (lsu_axi_bvalid_w),  .m_axi_bready    (lsu_axi_bready_w),
        .m_axi_arid      (lsu_axi_arid_w),    .m_axi_araddr    (lsu_axi_araddr_w),
        .m_axi_arlen     (lsu_axi_arlen_w),   .m_axi_arsize    (lsu_axi_arsize_w),
        .m_axi_arburst   (lsu_axi_arburst_w), .m_axi_arlock    (lsu_axi_arlock_w),
        .m_axi_arcache   (lsu_axi_arcache_w), .m_axi_arprot    (lsu_axi_arprot_w),
        .m_axi_arqos     (lsu_axi_arqos_w),   .m_axi_arregion  (lsu_axi_arregion_w),
        .m_axi_arvalid   (lsu_axi_arvalid_w), .m_axi_arready   (lsu_axi_arready_w),
        .m_axi_rid       (lsu_axi_rid_w),     .m_axi_rdata     (lsu_axi_rdata_w),
        .m_axi_rresp     (lsu_axi_rresp_w),   .m_axi_rlast     (lsu_axi_rlast_w),
        .m_axi_rvalid    (lsu_axi_rvalid_w),  .m_axi_rready    (lsu_axi_rready_w),
        .s_axi_awid      (s00_awid_w),    .s_axi_awaddr    (s00_awaddr_w),
        .s_axi_awlen     (s00_awlen_w),   .s_axi_awsize    (s00_awsize_w),
        .s_axi_awburst   (s00_awburst_w), .s_axi_awlock    (s00_awlock_w),
        .s_axi_awcache   (s00_awcache_w), .s_axi_awprot    (s00_awprot_w),
        .s_axi_awqos     (s00_awqos_w),   .s_axi_awvalid   (s00_awvalid_w),
        .s_axi_awready   (s00_awready_w),
        .s_axi_wdata     (s00_wdata_w),   .s_axi_wstrb     (s00_wstrb_w),
        .s_axi_wlast     (s00_wlast_w),   .s_axi_wvalid    (s00_wvalid_w),
        .s_axi_wready    (s00_wready_w),
        .s_axi_bid       (s00_bid_w),     .s_axi_bresp     (s00_bresp_w),
        .s_axi_bvalid    (s00_bvalid_w),  .s_axi_bready    (s00_bready_w),
        .s_axi_arid      (s00_arid_w),    .s_axi_araddr    (s00_araddr_w),
        .s_axi_arlen     (s00_arlen_w),   .s_axi_arsize    (s00_arsize_w),
        .s_axi_arburst   (s00_arburst_w), .s_axi_arlock    (s00_arlock_w),
        .s_axi_arcache   (s00_arcache_w), .s_axi_arprot    (s00_arprot_w),
        .s_axi_arqos     (s00_arqos_w),   .s_axi_arvalid   (s00_arvalid_w),
        .s_axi_arready   (s00_arready_w),
        .s_axi_rid       (s00_rid_w),     .s_axi_rdata     (s00_rdata_w),
        .s_axi_rresp     (s00_rresp_w),   .s_axi_rlast     (s00_rlast_w),
        .s_axi_rvalid    (s00_rvalid_w),  .s_axi_rready    (s00_rready_w)
    );

    // =========================================================================
    // Inst 1: VeeR EL2 Core (Master 1)
    // =========================================================================
    el2_veer_wrapper veer_inst (
        .clk(clk), .rst_l(rst_l), .dbg_rst_l(dbg_rst_l),
        .rst_vec(rst_vec), .nmi_int(core_nmi_int), .nmi_vec(nmi_vec),
        .jtag_id(jtag_id),
        .trace_rv_i_insn_ip(trace_rv_i_insn_ip),
        .trace_rv_i_address_ip(trace_rv_i_address_ip),
        .trace_rv_i_valid_ip(trace_rv_i_valid_ip),
        .trace_rv_i_exception_ip(trace_rv_i_exception_ip),
        .trace_rv_i_ecause_ip(trace_rv_i_ecause_ip),
        .trace_rv_i_interrupt_ip(trace_rv_i_interrupt_ip),
        .trace_rv_i_tval_ip(trace_rv_i_tval_ip),
        // LSU
        .lsu_axi_awvalid(lsu_axi_awvalid_w), .lsu_axi_awready(lsu_axi_awready_w),
        .lsu_axi_awid(lsu_axi_awid_w),       .lsu_axi_awaddr(lsu_axi_awaddr_w),
        .lsu_axi_awregion(lsu_axi_awregion_w),.lsu_axi_awlen(lsu_axi_awlen_w),
        .lsu_axi_awsize(lsu_axi_awsize_w),   .lsu_axi_awburst(lsu_axi_awburst_w),
        .lsu_axi_awlock(lsu_axi_awlock_w),   .lsu_axi_awcache(lsu_axi_awcache_w),
        .lsu_axi_awprot(lsu_axi_awprot_w),   .lsu_axi_awqos(lsu_axi_awqos_w),
        .lsu_axi_wvalid(lsu_axi_wvalid_w),   .lsu_axi_wready(lsu_axi_wready_w),
        .lsu_axi_wdata(lsu_axi_wdata_w),     .lsu_axi_wstrb(lsu_axi_wstrb_w),
        .lsu_axi_wlast(lsu_axi_wlast_w),
        .lsu_axi_bvalid(lsu_axi_bvalid_w),   .lsu_axi_bready(lsu_axi_bready_w),
        .lsu_axi_bresp(lsu_axi_bresp_w),     .lsu_axi_bid(lsu_axi_bid_w),
        .lsu_axi_arvalid(lsu_axi_arvalid_w), .lsu_axi_arready(lsu_axi_arready_w),
        .lsu_axi_arid(lsu_axi_arid_w),       .lsu_axi_araddr(lsu_axi_araddr_w),
        .lsu_axi_arregion(lsu_axi_arregion_w),.lsu_axi_arlen(lsu_axi_arlen_w),
        .lsu_axi_arsize(lsu_axi_arsize_w),   .lsu_axi_arburst(lsu_axi_arburst_w),
        .lsu_axi_arlock(lsu_axi_arlock_w),   .lsu_axi_arcache(lsu_axi_arcache_w),
        .lsu_axi_arprot(lsu_axi_arprot_w),   .lsu_axi_arqos(lsu_axi_arqos_w),
        .lsu_axi_rvalid(lsu_axi_rvalid_w),   .lsu_axi_rready(lsu_axi_rready_w),
        .lsu_axi_rid(lsu_axi_rid_w),         .lsu_axi_rdata(lsu_axi_rdata_w),
        .lsu_axi_rresp(lsu_axi_rresp_w),     .lsu_axi_rlast(lsu_axi_rlast_w),
        // IFU
        .ifu_axi_awvalid(ifu_axi_awvalid), .ifu_axi_awready(ifu_axi_awready),
        .ifu_axi_awid(ifu_axi_awid),       .ifu_axi_awaddr(ifu_axi_awaddr),
        .ifu_axi_awregion(ifu_axi_awregion),.ifu_axi_awlen(ifu_axi_awlen),
        .ifu_axi_awsize(ifu_axi_awsize),   .ifu_axi_awburst(ifu_axi_awburst),
        .ifu_axi_awlock(ifu_axi_awlock),   .ifu_axi_awcache(ifu_axi_awcache),
        .ifu_axi_awprot(ifu_axi_awprot),   .ifu_axi_awqos(ifu_axi_awqos),
        .ifu_axi_wvalid(ifu_axi_wvalid),   .ifu_axi_wready(ifu_axi_wready),
        .ifu_axi_wdata(ifu_axi_wdata),     .ifu_axi_wstrb(ifu_axi_wstrb),
        .ifu_axi_wlast(ifu_axi_wlast),
        .ifu_axi_bvalid(ifu_axi_bvalid),   .ifu_axi_bready(ifu_axi_bready),
        .ifu_axi_bresp(ifu_axi_bresp),     .ifu_axi_bid(ifu_axi_bid),
        .ifu_axi_arvalid(ifu_axi_arvalid), .ifu_axi_arready(ifu_axi_arready),
        .ifu_axi_arid(ifu_axi_arid),       .ifu_axi_araddr(ifu_axi_araddr),
        .ifu_axi_arregion(ifu_axi_arregion),.ifu_axi_arlen(ifu_axi_arlen),
        .ifu_axi_arsize(ifu_axi_arsize),   .ifu_axi_arburst(ifu_axi_arburst),
        .ifu_axi_arlock(ifu_axi_arlock),   .ifu_axi_arcache(ifu_axi_arcache),
        .ifu_axi_arprot(ifu_axi_arprot),   .ifu_axi_arqos(ifu_axi_arqos),
        .ifu_axi_rvalid(ifu_axi_rvalid),   .ifu_axi_rready(ifu_axi_rready),
        .ifu_axi_rid(ifu_axi_rid),         .ifu_axi_rdata(ifu_axi_rdata),
        .ifu_axi_rresp(ifu_axi_rresp),     .ifu_axi_rlast(ifu_axi_rlast),
        // SB
        .sb_axi_awvalid(sb_axi_awvalid), .sb_axi_awready(sb_axi_awready),
        .sb_axi_awid(sb_axi_awid),       .sb_axi_awaddr(sb_axi_awaddr),
        .sb_axi_awregion(sb_axi_awregion),.sb_axi_awlen(sb_axi_awlen),
        .sb_axi_awsize(sb_axi_awsize),   .sb_axi_awburst(sb_axi_awburst),
        .sb_axi_awlock(sb_axi_awlock),   .sb_axi_awcache(sb_axi_awcache),
        .sb_axi_awprot(sb_axi_awprot),   .sb_axi_awqos(sb_axi_awqos),
        .sb_axi_wvalid(sb_axi_wvalid),   .sb_axi_wready(sb_axi_wready),
        .sb_axi_wdata(sb_axi_wdata),     .sb_axi_wstrb(sb_axi_wstrb),
        .sb_axi_wlast(sb_axi_wlast),
        .sb_axi_bvalid(sb_axi_bvalid),   .sb_axi_bready(sb_axi_bready),
        .sb_axi_bresp(sb_axi_bresp),     .sb_axi_bid(sb_axi_bid),
        .sb_axi_arvalid(sb_axi_arvalid), .sb_axi_arready(sb_axi_arready),
        .sb_axi_arid(sb_axi_arid),       .sb_axi_araddr(sb_axi_araddr),
        .sb_axi_arregion(sb_axi_arregion),.sb_axi_arlen(sb_axi_arlen),
        .sb_axi_arsize(sb_axi_arsize),   .sb_axi_arburst(sb_axi_arburst),
        .sb_axi_arlock(sb_axi_arlock),   .sb_axi_arcache(sb_axi_arcache),
        .sb_axi_arprot(sb_axi_arprot),   .sb_axi_arqos(sb_axi_arqos),
        .sb_axi_rvalid(sb_axi_rvalid),   .sb_axi_rready(sb_axi_rready),
        .sb_axi_rid(sb_axi_rid),         .sb_axi_rdata(sb_axi_rdata),
        .sb_axi_rresp(sb_axi_rresp),     .sb_axi_rlast(sb_axi_rlast),
        // DMA slave
        .dma_axi_awvalid(dma_axi_awvalid), .dma_axi_awready(dma_axi_awready),
        .dma_axi_awid(dma_axi_awid),       .dma_axi_awaddr(dma_axi_awaddr),
        .dma_axi_awsize(dma_axi_awsize),   .dma_axi_awprot(dma_axi_awprot),
        .dma_axi_awlen(dma_axi_awlen),     .dma_axi_awburst(dma_axi_awburst),
        .dma_axi_wvalid(dma_axi_wvalid),   .dma_axi_wready(dma_axi_wready),
        .dma_axi_wdata(dma_axi_wdata),     .dma_axi_wstrb(dma_axi_wstrb),
        .dma_axi_wlast(dma_axi_wlast),
        .dma_axi_bvalid(dma_axi_bvalid),   .dma_axi_bready(dma_axi_bready),
        .dma_axi_bresp(dma_axi_bresp),     .dma_axi_bid(dma_axi_bid),
        .dma_axi_arvalid(dma_axi_arvalid), .dma_axi_arready(dma_axi_arready),
        .dma_axi_arid(dma_axi_arid),       .dma_axi_araddr(dma_axi_araddr),
        .dma_axi_arsize(dma_axi_arsize),   .dma_axi_arprot(dma_axi_arprot),
        .dma_axi_arlen(dma_axi_arlen),     .dma_axi_arburst(dma_axi_arburst),
        .dma_axi_rvalid(dma_axi_rvalid),   .dma_axi_rready(dma_axi_rready),
        .dma_axi_rid(dma_axi_rid),         .dma_axi_rdata(dma_axi_rdata),
        .dma_axi_rresp(dma_axi_rresp),     .dma_axi_rlast(dma_axi_rlast),
        // Misc
        .core_id(core_id), .timer_int(timer_int), .soft_int(soft_int),
        .extintsrc_req(extintsrc_req),
        .iccm_ecc_single_error(iccm_ecc_single_error),
        .iccm_ecc_double_error(iccm_ecc_double_error),
        .dccm_ecc_single_error(dccm_ecc_single_error),
        .dccm_ecc_double_error(dccm_ecc_double_error),
        .dccm_write_readback_error(dccm_write_readback_error),
        .dec_tlu_perfcnt0(dec_tlu_perfcnt0), .dec_tlu_perfcnt1(dec_tlu_perfcnt1),
        .dec_tlu_perfcnt2(dec_tlu_perfcnt2), .dec_tlu_perfcnt3(dec_tlu_perfcnt3),
        .jtag_tck(jtag_tck), .jtag_tms(jtag_tms), .jtag_tdi(jtag_tdi),
        .jtag_trst_n(jtag_trst_n), .jtag_tdo(jtag_tdo), .jtag_tdoEn(jtag_tdoEn),
        .mpc_debug_halt_req(mpc_debug_halt_req), .mpc_debug_run_req(mpc_debug_run_req),
        .mpc_reset_run_req(mpc_reset_run_req),   .mpc_debug_halt_ack(mpc_debug_halt_ack),
        .mpc_debug_run_ack(mpc_debug_run_ack),   .debug_brkpt_status(debug_brkpt_status),
        .i_cpu_halt_req(i_cpu_halt_req), .o_cpu_halt_ack(o_cpu_halt_ack),
        .o_cpu_halt_status(o_cpu_halt_status), .o_debug_mode_status(o_debug_mode_status),
        .i_cpu_run_req(i_cpu_run_req),   .o_cpu_run_ack(o_cpu_run_ack),
        .lsu_bus_clk_en(lsu_bus_clk_en), .ifu_bus_clk_en(ifu_bus_clk_en),
        .dbg_bus_clk_en(dbg_bus_clk_en), .dma_bus_clk_en(dma_bus_clk_en),
        .scan_mode(scan_mode), .mbist_mode(mbist_mode),
        .dmi_core_enable(dmi_core_enable), .dmi_uncore_enable(dmi_uncore_enable),
        .dmi_uncore_en(dmi_uncore_en),     .dmi_uncore_wr_en(dmi_uncore_wr_en),
        .dmi_uncore_addr(dmi_uncore_addr), .dmi_uncore_wdata(dmi_uncore_wdata),
        .el2_icache_export(el2_mem_export_if.veer_icache_src),
        .el2_mem_export(el2_mem_export_if.veer_sram_src)
    );

    // =========================================================================
    // Inst 2: AXI4 2x6 Crossbar Interconnect
    // =========================================================================
    axi_interconnect_wrap_2x6 #(
        .DATA_WIDTH        (DATA_WIDTH),
        .ADDR_WIDTH        (ADDR_WIDTH),
        .ID_WIDTH          (IC_ID_WIDTH),
        .M00_BASE_ADDR     (UART_BASE_ADDR),  .M00_ADDR_WIDTH (32'd12),
        .M00_CONNECT_READ  (2'b11),           .M00_CONNECT_WRITE(2'b11),
        .M01_BASE_ADDR     (TIMER_BASE_ADDR), .M01_ADDR_WIDTH (32'd12),
        .M01_CONNECT_READ  (2'b11),           .M01_CONNECT_WRITE(2'b11),
        .M02_BASE_ADDR     (AES_BASE_ADDR),  .M02_ADDR_WIDTH (32'd12),
        .M02_CONNECT_READ  (2'b11),          .M02_CONNECT_WRITE(2'b11),
        .M03_BASE_ADDR     (DMA_BASE_ADDR),  .M03_ADDR_WIDTH (32'd12),
        .M03_CONNECT_READ  (2'b11),          .M03_CONNECT_WRITE(2'b11),
        .M04_BASE_ADDR     (WDT_BASE_ADDR),  .M04_ADDR_WIDTH (32'd12),
        .M04_CONNECT_READ  (2'b11),          .M04_CONNECT_WRITE(2'b11),
        .M05_BASE_ADDR     (GPIO_BASE_ADDR), .M05_ADDR_WIDTH (32'd12),
        .M05_CONNECT_READ  (2'b11),          .M05_CONNECT_WRITE(2'b11)
    ) u_interconnect (
        .clk(clk), .rst(rst_ic),
        // s00
        .s00_axi_awid(s00_awid_w),       .s00_axi_awaddr(s00_awaddr_w),
        .s00_axi_awlen(s00_awlen_w),      .s00_axi_awsize(s00_awsize_w),
        .s00_axi_awburst(s00_awburst_w),  .s00_axi_awlock(s00_awlock_w),
        .s00_axi_awcache(s00_awcache_w),  .s00_axi_awprot(s00_awprot_w),
        .s00_axi_awqos(s00_awqos_w),      .s00_axi_awuser(1'b0),
        .s00_axi_awvalid(s00_awvalid_clean),.s00_axi_awready(s00_awready_w),
        .s00_axi_wdata(s00_wdata_w),      .s00_axi_wstrb(s00_wstrb_w),
        .s00_axi_wlast(s00_wlast_w),      .s00_axi_wuser(1'b0),
        .s00_axi_wvalid(s00_wvalid_clean),.s00_axi_wready(s00_wready_w),
        .s00_axi_bid(s00_bid_w),          .s00_axi_bresp(s00_bresp_w),
        .s00_axi_buser(),                 .s00_axi_bvalid(s00_bvalid_w),
        .s00_axi_bready(s00_bready_clean),
        .s00_axi_arid(s00_arid_w),        .s00_axi_araddr(s00_araddr_w),
        .s00_axi_arlen(s00_arlen_w),      .s00_axi_arsize(s00_arsize_w),
        .s00_axi_arburst(s00_arburst_w),  .s00_axi_arlock(s00_arlock_w),
        .s00_axi_arcache(s00_arcache_w),  .s00_axi_arprot(s00_arprot_w),
        .s00_axi_arqos(s00_arqos_w),      .s00_axi_aruser(1'b0),
        .s00_axi_arvalid(s00_arvalid_clean),.s00_axi_arready(s00_arready_w),
        .s00_axi_rid(s00_rid_w),          .s00_axi_rdata(s00_rdata_w),
        .s00_axi_rresp(s00_rresp_w),      .s00_axi_rlast(s00_rlast_w),
        .s00_axi_ruser(),                 .s00_axi_rvalid(s00_rvalid_w),
        .s00_axi_rready(s00_rready_clean),
        // s01
        .s01_axi_awid(s01_awid_w),        .s01_axi_awaddr(s01_awaddr_w),
        .s01_axi_awlen(s01_awlen_w),       .s01_axi_awsize(s01_awsize_w),
        .s01_axi_awburst(s01_awburst_w),   .s01_axi_awlock(s01_awlock_w),
        .s01_axi_awcache(s01_awcache_w),   .s01_axi_awprot(s01_awprot_w),
        .s01_axi_awqos(s01_awqos_w),       .s01_axi_awuser(1'b0),
        .s01_axi_awvalid(s01_awvalid_clean),.s01_axi_awready(s01_awready_w),
        .s01_axi_wdata(s01_wdata_w),       .s01_axi_wstrb(s01_wstrb_w),
        .s01_axi_wlast(s01_wlast_w),       .s01_axi_wuser(1'b0),
        .s01_axi_wvalid(s01_wvalid_clean), .s01_axi_wready(s01_wready_w),
        .s01_axi_bid(s01_bid_w),           .s01_axi_bresp(s01_bresp_w),
        .s01_axi_buser(),                  .s01_axi_bvalid(s01_bvalid_w),
        .s01_axi_bready(s01_bready_clean),
        .s01_axi_arid(s01_arid_w),         .s01_axi_araddr(s01_araddr_w),
        .s01_axi_arlen(s01_arlen_w),       .s01_axi_arsize(s01_arsize_w),
        .s01_axi_arburst(s01_arburst_w),   .s01_axi_arlock(s01_arlock_w),
        .s01_axi_arcache(s01_arcache_w),   .s01_axi_arprot(s01_arprot_w),
        .s01_axi_arqos(s01_arqos_w),       .s01_axi_aruser(1'b0),
        .s01_axi_arvalid(s01_arvalid_clean),.s01_axi_arready(s01_arready_w),
        .s01_axi_rid(s01_rid_w),           .s01_axi_rdata(s01_rdata_w),
        .s01_axi_rresp(s01_rresp_w),       .s01_axi_rlast(s01_rlast_w),
        .s01_axi_ruser(),                  .s01_axi_rvalid(s01_rvalid_w),
        .s01_axi_rready(s01_rready_clean),
        // m00 UART
        .m00_axi_awid(m00_awid),    .m00_axi_awaddr(m00_awaddr),
        .m00_axi_awlen(m00_awlen),  .m00_axi_awsize(m00_awsize),
        .m00_axi_awburst(m00_awburst),.m00_axi_awlock(m00_awlock),
        .m00_axi_awcache(m00_awcache),.m00_axi_awprot(m00_awprot),
        .m00_axi_awqos(m00_awqos),  .m00_axi_awregion(m00_awregion),
        .m00_axi_awuser(),          .m00_axi_awvalid(m00_awvalid),
        .m00_axi_awready(m00_awready),
        .m00_axi_wdata(m00_wdata),  .m00_axi_wstrb(m00_wstrb),
        .m00_axi_wlast(m00_wlast),  .m00_axi_wuser(), .m00_axi_wvalid(m00_wvalid),
        .m00_axi_wready(m00_wready),
        .m00_axi_bid(m00_bid),      .m00_axi_bresp(m00_bresp),
        .m00_axi_buser(1'b0),       .m00_axi_bvalid(m00_bvalid),
        .m00_axi_bready(m00_bready),
        .m00_axi_arid(m00_arid),    .m00_axi_araddr(m00_araddr),
        .m00_axi_arlen(m00_arlen),  .m00_axi_arsize(m00_arsize),
        .m00_axi_arburst(m00_arburst),.m00_axi_arlock(m00_arlock),
        .m00_axi_arcache(m00_arcache),.m00_axi_arprot(m00_arprot),
        .m00_axi_arqos(m00_arqos),  .m00_axi_arregion(m00_arregion),
        .m00_axi_aruser(),          .m00_axi_arvalid(m00_arvalid),
        .m00_axi_arready(m00_arready),
        .m00_axi_rid(m00_rid),      .m00_axi_rdata(m00_rdata),
        .m00_axi_rresp(m00_rresp),  .m00_axi_rlast(m00_rlast),
        .m00_axi_ruser(1'b0),       .m00_axi_rvalid(m00_rvalid),
        .m00_axi_rready(m00_rready),
        // m01 System Timer
        .m01_axi_awid(m01_awid),    .m01_axi_awaddr(m01_awaddr),
        .m01_axi_awlen(m01_awlen),  .m01_axi_awsize(m01_awsize),
        .m01_axi_awburst(m01_awburst),.m01_axi_awlock(m01_awlock),
        .m01_axi_awcache(m01_awcache),.m01_axi_awprot(m01_awprot),
        .m01_axi_awqos(m01_awqos),  .m01_axi_awregion(m01_awregion),
        .m01_axi_awuser(),          .m01_axi_awvalid(m01_awvalid),
        .m01_axi_awready(m01_awready),
        .m01_axi_wdata(m01_wdata),  .m01_axi_wstrb(m01_wstrb),
        .m01_axi_wlast(m01_wlast),  .m01_axi_wuser(), .m01_axi_wvalid(m01_wvalid),
        .m01_axi_wready(m01_wready),
        .m01_axi_bid(m01_bid),      .m01_axi_bresp(m01_bresp),
        .m01_axi_buser(1'b0),       .m01_axi_bvalid(m01_bvalid),
        .m01_axi_bready(m01_bready),
        .m01_axi_arid(m01_arid),    .m01_axi_araddr(m01_araddr),
        .m01_axi_arlen(m01_arlen),  .m01_axi_arsize(m01_arsize),
        .m01_axi_arburst(m01_arburst),.m01_axi_arlock(m01_arlock),
        .m01_axi_arcache(m01_arcache),.m01_axi_arprot(m01_arprot),
        .m01_axi_arqos(m01_arqos),  .m01_axi_arregion(m01_arregion),
        .m01_axi_aruser(),          .m01_axi_arvalid(m01_arvalid),
        .m01_axi_arready(m01_arready),
        .m01_axi_rid(m01_rid),      .m01_axi_rdata(m01_rdata),
        .m01_axi_rresp(m01_rresp),  .m01_axi_rlast(m01_rlast),
        .m01_axi_ruser(1'b0),       .m01_axi_rvalid(m01_rvalid),
        .m01_axi_rready(m01_rready),
        // m02 AES
        .m02_axi_awid(m02_awid),    .m02_axi_awaddr(m02_awaddr),
        .m02_axi_awlen(m02_awlen),  .m02_axi_awsize(m02_awsize),
        .m02_axi_awburst(m02_awburst),.m02_axi_awlock(m02_awlock),
        .m02_axi_awcache(m02_awcache),.m02_axi_awprot(m02_awprot),
        .m02_axi_awqos(m02_awqos),  .m02_axi_awregion(m02_awregion),
        .m02_axi_awuser(),          .m02_axi_awvalid(m02_awvalid),
        .m02_axi_awready(m02_awready),
        .m02_axi_wdata(m02_wdata),  .m02_axi_wstrb(m02_wstrb),
        .m02_axi_wlast(m02_wlast),  .m02_axi_wuser(), .m02_axi_wvalid(m02_wvalid),
        .m02_axi_wready(m02_wready),
        .m02_axi_bid(m02_bid),      .m02_axi_bresp(m02_bresp),
        .m02_axi_buser(1'b0),       .m02_axi_bvalid(m02_bvalid),
        .m02_axi_bready(m02_bready),
        .m02_axi_arid(m02_arid),    .m02_axi_araddr(m02_araddr),
        .m02_axi_arlen(m02_arlen),  .m02_axi_arsize(m02_arsize),
        .m02_axi_arburst(m02_arburst),.m02_axi_arlock(m02_arlock),
        .m02_axi_arcache(m02_arcache),.m02_axi_arprot(m02_arprot),
        .m02_axi_arqos(m02_arqos),  .m02_axi_arregion(m02_arregion),
        .m02_axi_aruser(),          .m02_axi_arvalid(m02_arvalid),
        .m02_axi_arready(m02_arready),
        .m02_axi_rid(m02_rid),      .m02_axi_rdata(m02_rdata),
        .m02_axi_rresp(m02_rresp),  .m02_axi_rlast(m02_rlast),
        .m02_axi_ruser(1'b0),       .m02_axi_rvalid(m02_rvalid),
        .m02_axi_rready(m02_rready),
        // m03 DMA CSR
        .m03_axi_awid(m03_awid),    .m03_axi_awaddr(m03_awaddr),
        .m03_axi_awlen(m03_awlen),  .m03_axi_awsize(m03_awsize),
        .m03_axi_awburst(m03_awburst),.m03_axi_awlock(m03_awlock),
        .m03_axi_awcache(m03_awcache),.m03_axi_awprot(m03_awprot),
        .m03_axi_awqos(m03_awqos),  .m03_axi_awregion(m03_awregion),
        .m03_axi_awuser(),          .m03_axi_awvalid(m03_awvalid),
        .m03_axi_awready(m03_awready),
        .m03_axi_wdata(m03_wdata),  .m03_axi_wstrb(m03_wstrb),
        .m03_axi_wlast(m03_wlast),  .m03_axi_wuser(), .m03_axi_wvalid(m03_wvalid),
        .m03_axi_wready(m03_wready),
        .m03_axi_bid(m03_bid),      .m03_axi_bresp(m03_bresp),
        .m03_axi_buser(1'b0),       .m03_axi_bvalid(m03_bvalid),
        .m03_axi_bready(m03_bready),
        .m03_axi_arid(m03_arid),    .m03_axi_araddr(m03_araddr),
        .m03_axi_arlen(m03_arlen),  .m03_axi_arsize(m03_arsize),
        .m03_axi_arburst(m03_arburst),.m03_axi_arlock(m03_arlock),
        .m03_axi_arcache(m03_arcache),.m03_axi_arprot(m03_arprot),
        .m03_axi_arqos(m03_arqos),  .m03_axi_arregion(m03_arregion),
        .m03_axi_aruser(),          .m03_axi_arvalid(m03_arvalid),
        .m03_axi_arready(m03_arready),
        .m03_axi_rid(m03_rid),      .m03_axi_rdata(m03_rdata),
        .m03_axi_rresp(m03_rresp),  .m03_axi_rlast(m03_rlast),
        .m03_axi_ruser(1'b0),       .m03_axi_rvalid(m03_rvalid),
        .m03_axi_rready(m03_rready),
        // m04 WDT
        .m04_axi_awid(m04_awid),    .m04_axi_awaddr(m04_awaddr),
        .m04_axi_awlen(m04_awlen),  .m04_axi_awsize(m04_awsize),
        .m04_axi_awburst(m04_awburst),.m04_axi_awlock(m04_awlock),
        .m04_axi_awcache(m04_awcache),.m04_axi_awprot(m04_awprot),
        .m04_axi_awqos(m04_awqos),  .m04_axi_awregion(m04_awregion),
        .m04_axi_awuser(),          .m04_axi_awvalid(m04_awvalid),
        .m04_axi_awready(m04_awready),
        .m04_axi_wdata(m04_wdata),  .m04_axi_wstrb(m04_wstrb),
        .m04_axi_wlast(m04_wlast),  .m04_axi_wuser(), .m04_axi_wvalid(m04_wvalid),
        .m04_axi_wready(m04_wready),
        .m04_axi_bid(m04_bid),      .m04_axi_bresp(m04_bresp),
        .m04_axi_buser(1'b0),       .m04_axi_bvalid(m04_bvalid),
        .m04_axi_bready(m04_bready),
        .m04_axi_arid(m04_arid),    .m04_axi_araddr(m04_araddr),
        .m04_axi_arlen(m04_arlen),  .m04_axi_arsize(m04_arsize),
        .m04_axi_arburst(m04_arburst),.m04_axi_arlock(m04_arlock),
        .m04_axi_arcache(m04_arcache),.m04_axi_arprot(m04_arprot),
        .m04_axi_arqos(m04_arqos),  .m04_axi_arregion(m04_arregion),
        .m04_axi_aruser(),          .m04_axi_arvalid(m04_arvalid),
        .m04_axi_arready(m04_arready),
        .m04_axi_rid(m04_rid),      .m04_axi_rdata(m04_rdata),
        .m04_axi_rresp(m04_rresp),  .m04_axi_rlast(m04_rlast),
        .m04_axi_ruser(1'b0),       .m04_axi_rvalid(m04_rvalid),
        .m04_axi_rready(m04_rready),
        // m05 GPIO
        .m05_axi_awid(m05_awid),    .m05_axi_awaddr(m05_awaddr),
        .m05_axi_awlen(m05_awlen),  .m05_axi_awsize(m05_awsize),
        .m05_axi_awburst(m05_awburst),.m05_axi_awlock(m05_awlock),
        .m05_axi_awcache(m05_awcache),.m05_axi_awprot(m05_awprot),
        .m05_axi_awqos(m05_awqos),  .m05_axi_awregion(m05_awregion),
        .m05_axi_awuser(),          .m05_axi_awvalid(m05_awvalid),
        .m05_axi_awready(m05_awready),
        .m05_axi_wdata(m05_wdata),  .m05_axi_wstrb(m05_wstrb),
        .m05_axi_wlast(m05_wlast),  .m05_axi_wuser(), .m05_axi_wvalid(m05_wvalid),
        .m05_axi_wready(m05_wready),
        .m05_axi_bid(m05_bid),      .m05_axi_bresp(m05_bresp),
        .m05_axi_buser(1'b0),       .m05_axi_bvalid(m05_bvalid),
        .m05_axi_bready(m05_bready),
        .m05_axi_arid(m05_arid),    .m05_axi_araddr(m05_araddr),
        .m05_axi_arlen(m05_arlen),  .m05_axi_arsize(m05_arsize),
        .m05_axi_arburst(m05_arburst),.m05_axi_arlock(m05_arlock),
        .m05_axi_arcache(m05_arcache),.m05_axi_arprot(m05_arprot),
        .m05_axi_arqos(m05_arqos),  .m05_axi_arregion(m05_arregion),
        .m05_axi_aruser(),          .m05_axi_arvalid(m05_arvalid),
        .m05_axi_arready(m05_arready),
        .m05_axi_rid(m05_rid),      .m05_axi_rdata(m05_rdata),
        .m05_axi_rresp(m05_rresp),  .m05_axi_rlast(m05_rlast),
        .m05_axi_ruser(1'b0),       .m05_axi_rvalid(m05_rvalid),
        .m05_axi_rready(m05_rready)
    );

    // =========================================================================
    // Inst 3: AXI4 → AXI4-Lite Bridge for UART
    // =========================================================================
    axi4_to_axilite_bridge #(
        .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(IC_ID_WIDTH),  .STRB_WIDTH(STRB_WIDTH)
    ) u_uart_bridge (
        .clk(clk), .rst_n(rst_l),
        .s_axi_awid(m00_awid),    .s_axi_awaddr(m00_awaddr),
        .s_axi_awlen(m00_awlen),  .s_axi_awsize(m00_awsize),
        .s_axi_awburst(m00_awburst),.s_axi_awlock(m00_awlock),
        .s_axi_awcache(m00_awcache),.s_axi_awprot(m00_awprot),
        .s_axi_awqos(m00_awqos),  .s_axi_awregion(m00_awregion),
        .s_axi_awvalid(m00_awvalid),.s_axi_awready(m00_awready),
        .s_axi_wdata(m00_wdata),  .s_axi_wstrb(m00_wstrb),
        .s_axi_wlast(m00_wlast),  .s_axi_wvalid(m00_wvalid),
        .s_axi_wready(m00_wready),
        .s_axi_bid(m00_bid),      .s_axi_bresp(m00_bresp),
        .s_axi_bvalid(m00_bvalid),.s_axi_bready(m00_bready),
        .s_axi_arid(m00_arid),    .s_axi_araddr(m00_araddr),
        .s_axi_arlen(m00_arlen),  .s_axi_arsize(m00_arsize),
        .s_axi_arburst(m00_arburst),.s_axi_arlock(m00_arlock),
        .s_axi_arcache(m00_arcache),.s_axi_arprot(m00_arprot),
        .s_axi_arqos(m00_arqos),  .s_axi_arregion(m00_arregion),
        .s_axi_arvalid(m00_arvalid),.s_axi_arready(m00_arready),
        .s_axi_rid(m00_rid),      .s_axi_rdata(m00_rdata),
        .s_axi_rresp(m00_rresp),  .s_axi_rlast(m00_rlast),
        .s_axi_rvalid(m00_rvalid),.s_axi_rready(m00_rready),
        .m_axi_awid(uart_awid),   .m_axi_awaddr(uart_awaddr),
        .m_axi_awvalid(uart_awvalid),.m_axi_awready(uart_awready),
        .m_axi_wdata(uart_wdata), .m_axi_wstrb(uart_wstrb),
        .m_axi_wvalid(uart_wvalid),.m_axi_wready(uart_wready),
        .m_axi_bid(uart_bid),     .m_axi_bresp(uart_bresp),
        .m_axi_bvalid(uart_bvalid),.m_axi_bready(uart_bready),
        .m_axi_arid(uart_arid),   .m_axi_araddr(uart_araddr),
        .m_axi_arvalid(uart_arvalid),.m_axi_arready(uart_arready),
        .m_axi_rid(uart_rid),     .m_axi_rdata(uart_rdata),
        .m_axi_rresp(uart_rresp), .m_axi_rvalid(uart_rvalid),
        .m_axi_rready(uart_rready)
    );

    // =========================================================================
    // Inst 4: UART IP
    // =========================================================================
    axi_uart_top u_uart (
        .fixed_clk_i(fixed_clk), .axi_aclk_i(clk), .axi_aresetn_i(rst_l),
        .axi_awid_i(uart_awid),   .axi_awaddr_i(uart_awaddr),
        .axi_awvalid_i(uart_awvalid),.axi_awready_o(uart_awready),
        .axi_wdata_i(uart_wdata), .axi_wstrb_i(uart_wstrb),
        .axi_wvalid_i(uart_wvalid),.axi_wready_o(uart_wready),
        .axi_bid_o(uart_bid),     .axi_bresp_o(uart_bresp),
        .axi_bvalid_o(uart_bvalid),.axi_bready_i(uart_bready),
        .axi_arid_i(uart_arid),   .axi_araddr_i(uart_araddr),
        .axi_arvalid_i(uart_arvalid),.axi_arready_o(uart_arready),
        .axi_rid_o(uart_rid),     .axi_rdata_o(uart_rdata),
        .axi_rresp_o(uart_rresp), .axi_rvalid_o(uart_rvalid),
        .axi_rready_i(uart_rready),
        .uart_tx_o(uart_tx_o),    .uart_rx_i(uart_rx_i),
        .read_interrupt_o(uart_read_irq_o)
    );

    // =========================================================================
    // Inst 5: AES Adapter (m02 @ 0x4000_2000)
    // =========================================================================
    aes_veer_adapter #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(IC_ID_WIDTH)
    ) u_aes_adapter (
        .clk(clk), .rst_n(rst_l),
        .s_axi_awid(m02_awid),    .s_axi_awaddr(m02_awaddr),
        .s_axi_awlen(m02_awlen),  .s_axi_awsize(m02_awsize),
        .s_axi_awburst(m02_awburst),.s_axi_awlock(m02_awlock),
        .s_axi_awcache(m02_awcache),.s_axi_awprot(m02_awprot),
        .s_axi_awqos(m02_awqos),  .s_axi_awregion(m02_awregion),
        .s_axi_awvalid(m02_awvalid),.s_axi_awready(m02_awready),
        .s_axi_wdata(m02_wdata),  .s_axi_wstrb(m02_wstrb),
        .s_axi_wlast(m02_wlast),  .s_axi_wvalid(m02_wvalid),
        .s_axi_wready(m02_wready),
        .s_axi_bid(m02_bid),      .s_axi_bresp(m02_bresp),
        .s_axi_bvalid(m02_bvalid),.s_axi_bready(m02_bready),
        .s_axi_arid(m02_arid),    .s_axi_araddr(m02_araddr),
        .s_axi_arlen(m02_arlen),  .s_axi_arsize(m02_arsize),
        .s_axi_arburst(m02_arburst),.s_axi_arlock(m02_arlock),
        .s_axi_arcache(m02_arcache),.s_axi_arprot(m02_arprot),
        .s_axi_arqos(m02_arqos),  .s_axi_arregion(m02_arregion),
        .s_axi_arvalid(m02_arvalid),.s_axi_arready(m02_arready),
        .s_axi_rid(m02_rid),      .s_axi_rdata(m02_rdata),
        .s_axi_rresp(m02_rresp),  .s_axi_rlast(m02_rlast),
        .s_axi_rvalid(m02_rvalid),.s_axi_rready(m02_rready),
        .aes_key_128_o(),         .aes_text_in_128_o(),
        .aes_text_out_128_o(),    .aes_core_start_o(),
        .aes_core_mode_o(),       .aes_core_done_o(aes_done_o),
        .aes_core_busy_o(aes_busy_o),
        .aes_done_pulse_o(aes_done_pulse_o), .irq_aes_done_o(aes_irq_o)
    );

    // =========================================================================
    // Inst 6: DMA Controller (Master 2 on s01, CSR slave on m03)
    // =========================================================================
    s_axil_mosi_t dma_csr_mosi;
    s_axil_miso_t dma_csr_miso;
    s_axi_mosi_t  dma_m_mosi;
    s_axi_miso_t  dma_m_miso;

    assign dma_csr_mosi.awid    = m03_awid;
    assign dma_csr_mosi.awaddr  = m03_awaddr;
    assign dma_csr_mosi.awprot  = axi_prot_t'(m03_awprot);
    assign dma_csr_mosi.awvalid = m03_awvalid;
    assign m03_awready          = dma_csr_miso.awready;
    assign dma_csr_mosi.wdata   = m03_wdata;
    assign dma_csr_mosi.wstrb   = m03_wstrb;
    assign dma_csr_mosi.wvalid  = m03_wvalid;
    assign m03_wready           = dma_csr_miso.wready;
    assign m03_bid              = dma_csr_miso.bid;
    assign m03_bresp            = dma_csr_miso.bresp;
    assign m03_bvalid           = dma_csr_miso.bvalid;
    assign dma_csr_mosi.bready  = m03_bready;
    assign dma_csr_mosi.arid    = m03_arid;
    assign dma_csr_mosi.araddr  = m03_araddr;
    assign dma_csr_mosi.arprot  = axi_prot_t'(m03_arprot);
    assign dma_csr_mosi.arvalid = m03_arvalid;
    assign m03_arready          = dma_csr_miso.arready;
    assign m03_rid              = dma_csr_miso.rid;
    assign m03_rdata            = dma_csr_miso.rdata;
    assign m03_rresp            = dma_csr_miso.rresp;
    assign m03_rlast            = 1'b1;
    assign m03_rvalid           = dma_csr_miso.rvalid;
    assign dma_csr_mosi.rready  = m03_rready;

    assign s01_awid_w      = dma_m_mosi.awid;   assign s01_awaddr_w    = dma_m_mosi.awaddr;
    assign s01_awlen_w     = dma_m_mosi.awlen;  assign s01_awsize_w    = dma_m_mosi.awsize;
    assign s01_awburst_w   = dma_m_mosi.awburst;assign s01_awlock_w    = dma_m_mosi.awlock;
    assign s01_awcache_w   = dma_m_mosi.awcache;assign s01_awprot_w    = dma_m_mosi.awprot;
    assign s01_awqos_w     = dma_m_mosi.awqos;  assign s01_awvalid_w   = dma_m_mosi.awvalid;
    assign dma_m_miso.awready = s01_awready_w;
    assign s01_wdata_w     = dma_m_mosi.wdata;  assign s01_wstrb_w     = dma_m_mosi.wstrb;
    assign s01_wlast_w     = dma_m_mosi.wlast;  assign s01_wvalid_w    = dma_m_mosi.wvalid;
    assign dma_m_miso.wready  = s01_wready_w;
    assign dma_m_miso.bid     = s01_bid_w;
    assign dma_m_miso.bresp   = axi_resp_t'(s01_bresp_w);
    assign dma_m_miso.buser   = '0;
    assign dma_m_miso.bvalid  = s01_bvalid_w;   assign s01_bready_w    = dma_m_mosi.bready;
    assign s01_arid_w      = dma_m_mosi.arid;   assign s01_araddr_w    = dma_m_mosi.araddr;
    assign s01_arlen_w     = dma_m_mosi.arlen;  assign s01_arsize_w    = dma_m_mosi.arsize;
    assign s01_arburst_w   = dma_m_mosi.arburst;assign s01_arlock_w    = dma_m_mosi.arlock;
    assign s01_arcache_w   = dma_m_mosi.arcache;assign s01_arprot_w    = dma_m_mosi.arprot;
    assign s01_arqos_w     = dma_m_mosi.arqos;  assign s01_arvalid_w   = dma_m_mosi.arvalid;
    assign dma_m_miso.arready = s01_arready_w;
    assign dma_m_miso.rid     = s01_rid_w;      assign dma_m_miso.rdata  = s01_rdata_w;
    assign dma_m_miso.rresp   = axi_resp_t'(s01_rresp_w);
    assign dma_m_miso.rlast   = s01_rlast_w;    assign dma_m_miso.ruser  = '0;
    assign dma_m_miso.rvalid  = s01_rvalid_w;   assign s01_rready_w      = dma_m_mosi.rready;

    dma_axi_wrapper #(.DMA_ID_VAL(0)) u_dma_top (
        .clk(clk), .rst(rst_ic),
        .dma_csr_mosi_i(dma_csr_mosi), .dma_csr_miso_o(dma_csr_miso),
        .dma_m_mosi_o(dma_m_mosi),     .dma_m_miso_i(dma_m_miso),
        .dma_done_o(dma_done_o),        .dma_error_o(dma_error_o)
    );
    assign dma_irq_o = dma_done_o;

    // =========================================================================
    // Inst 7: Watchdog Timer (m04 @ 0x4000_4000)
    // =========================================================================
    ef_wdt32_axi_wrapper #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(IC_ID_WIDTH)
    ) u_wdt (
        .clk(clk), .rst_n(rst_l),
        .s_axi_awid(m04_awid),    .s_axi_awaddr(m04_awaddr),
        .s_axi_awlen(m04_awlen),  .s_axi_awsize(m04_awsize),
        .s_axi_awburst(m04_awburst),.s_axi_awlock(m04_awlock),
        .s_axi_awcache(m04_awcache),.s_axi_awprot(m04_awprot),
        .s_axi_awqos(m04_awqos),  .s_axi_awregion(m04_awregion),
        .s_axi_awvalid(m04_awvalid),.s_axi_awready(m04_awready),
        .s_axi_wdata(m04_wdata),  .s_axi_wstrb(m04_wstrb),
        .s_axi_wlast(m04_wlast),  .s_axi_wvalid(m04_wvalid),
        .s_axi_wready(m04_wready),
        .s_axi_bid(m04_bid),      .s_axi_bresp(m04_bresp),
        .s_axi_bvalid(m04_bvalid),.s_axi_bready(m04_bready),
        .s_axi_arid(m04_arid),    .s_axi_araddr(m04_araddr),
        .s_axi_arlen(m04_arlen),  .s_axi_arsize(m04_arsize),
        .s_axi_arburst(m04_arburst),.s_axi_arlock(m04_arlock),
        .s_axi_arcache(m04_arcache),.s_axi_arprot(m04_arprot),
        .s_axi_arqos(m04_arqos),  .s_axi_arregion(m04_arregion),
        .s_axi_arvalid(m04_arvalid),.s_axi_arready(m04_arready),
        .s_axi_rid(m04_rid),      .s_axi_rdata(m04_rdata),
        .s_axi_rresp(m04_rresp),  .s_axi_rlast(m04_rlast),
        .s_axi_rvalid(m04_rvalid),.s_axi_rready(m04_rready),
        .aes_done_pulse_i(aes_done_pulse_o),
        .wdt_irq_o(wdt_irq_o),    .wdt_nmi_o(wdt_nmi_o),
        .wdt_reset_o(wdt_reset_o),.wdt_timeout_o(wdt_timeout_o)
    );

    // =========================================================================
    // Inst 8: GPIO Subsystem (m05 @ 0x4000_5000)
    // =========================================================================
    gpio_axi_wrapper #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(IC_ID_WIDTH)
    ) u_gpio (
        .clk(clk), .rst_n(rst_l),
        .s_axi_awid(m05_awid),    .s_axi_awaddr(m05_awaddr),
        .s_axi_awlen(m05_awlen),  .s_axi_awsize(m05_awsize),
        .s_axi_awburst(m05_awburst),.s_axi_awlock(m05_awlock),
        .s_axi_awcache(m05_awcache),.s_axi_awprot(m05_awprot),
        .s_axi_awqos(m05_awqos),  .s_axi_awregion(m05_awregion),
        .s_axi_awvalid(m05_awvalid),.s_axi_awready(m05_awready),
        .s_axi_wdata(m05_wdata),  .s_axi_wstrb(m05_wstrb),
        .s_axi_wlast(m05_wlast),  .s_axi_wvalid(m05_wvalid),
        .s_axi_wready(m05_wready),
        .s_axi_bid(m05_bid),      .s_axi_bresp(m05_bresp),
        .s_axi_bvalid(m05_bvalid),.s_axi_bready(m05_bready),
        .s_axi_arid(m05_arid),    .s_axi_araddr(m05_araddr),
        .s_axi_arlen(m05_arlen),  .s_axi_arsize(m05_arsize),
        .s_axi_arburst(m05_arburst),.s_axi_arlock(m05_arlock),
        .s_axi_arcache(m05_arcache),.s_axi_arprot(m05_arprot),
        .s_axi_arqos(m05_arqos),  .s_axi_arregion(m05_arregion),
        .s_axi_arvalid(m05_arvalid),.s_axi_arready(m05_arready),
        .s_axi_rid(m05_rid),      .s_axi_rdata(m05_rdata),
        .s_axi_rresp(m05_rresp),  .s_axi_rlast(m05_rlast),
        .s_axi_rvalid(m05_rvalid),.s_axi_rready(m05_rready),
        .gpio_in_i(gpio_in_i),    .gpio_out_o(gpio_out_o),
        .gpio_tx_en_o(gpio_tx_en_o),
        .gpio_irq_o(gpio_irq_o)
    );

    // =========================================================================
    // Inst 5 (renamed): System Timer (m01 @ 0x4000_1000)
    // =========================================================================
    timer_axi_wrapper #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(IC_ID_WIDTH)
    ) u_timer (
        .clk(clk), .rst_n(rst_l),
        .s_axi_awid(m01_awid),    .s_axi_awaddr(m01_awaddr),
        .s_axi_awlen(m01_awlen),  .s_axi_awsize(m01_awsize),
        .s_axi_awburst(m01_awburst),.s_axi_awlock(m01_awlock),
        .s_axi_awcache(m01_awcache),.s_axi_awprot(m01_awprot),
        .s_axi_awqos(m01_awqos),  .s_axi_awregion(m01_awregion),
        .s_axi_awvalid(m01_awvalid),.s_axi_awready(m01_awready),
        .s_axi_wdata(m01_wdata),  .s_axi_wstrb(m01_wstrb),
        .s_axi_wlast(m01_wlast),  .s_axi_wvalid(m01_wvalid),
        .s_axi_wready(m01_wready),
        .s_axi_bid(m01_bid),      .s_axi_bresp(m01_bresp),
        .s_axi_bvalid(m01_bvalid),.s_axi_bready(m01_bready),
        .s_axi_arid(m01_arid),    .s_axi_araddr(m01_araddr),
        .s_axi_arlen(m01_arlen),  .s_axi_arsize(m01_arsize),
        .s_axi_arburst(m01_arburst),.s_axi_arlock(m01_arlock),
        .s_axi_arcache(m01_arcache),.s_axi_arprot(m01_arprot),
        .s_axi_arqos(m01_arqos),  .s_axi_arregion(m01_arregion),
        .s_axi_arvalid(m01_arvalid),.s_axi_arready(m01_arready),
        .s_axi_rid(m01_rid),      .s_axi_rdata(m01_rdata),
        .s_axi_rresp(m01_rresp),  .s_axi_rlast(m01_rlast),
        .s_axi_rvalid(m01_rvalid),.s_axi_rready(m01_rready),
        .timer_irq_o(timer_irq_o)
    );

endmodule

`default_nettype wire
