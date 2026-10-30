// =============================================================================
// Testbench : tb_soc_top  (firmware-driven)
// DUT       : veer2_dma_aes_wdt_uart_gpio_timer
//
// Purpose   : Run soc_full_test firmware on the VeeR EL2 core. A TB-owned
//             memory ($readmemh) is served on the IFU AXI port. The TB does
//             not drive any peripheral bus; it only observes DUT outputs
//             (UART TX, IRQ/NMI/reset lines, GPIO) and logs them.
//
// Hex file  : default "soc_full_test.hex", override with +HEX=<file>
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

import amba_axi_pkg::*;
import dma_utils_pkg::*;

module tb_soc_top;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD    = 10;          // 100 MHz
    localparam FIXED_PERIOD  = 10;
    localparam RST_CYCLES    = 20;
    localparam SIM_RUN_CYC   = 2_000_000;   // total run length (clk cycles)

    // UART TX decode: bit period in fixed_clk cycles. MUST match the baud
    // divisor the firmware programs (original TB used divisor 10 -> 11 cycles).
    localparam SIM_BAUD_DIV  = 10;
    localparam BIT_CYCLES    = SIM_BAUD_DIV + 1;

    localparam IC_ID_WIDTH   = 8;
    localparam DATA_WIDTH    = 32;
    localparam ADDR_WIDTH    = 32;

    localparam LSU_BUS_TAG   = 4;
    localparam IFU_BUS_TAG   = 3;
    localparam SB_BUS_TAG    = 2;
    localparam DMA_BUS_TAG   = 1;
    localparam PIC_TOTAL_INT = 31;

    // Instruction memory (TB-owned, served on IFU AXI)
    localparam [31:0] IMEM_BASE  = 32'h0000_0000;   // firmware is linked at 0 (hex starts @00000000)
    localparam        IMEM_BYTES = 64 * 1024;

    // Core vectors (byte addresses; rst_vec/nmi_vec ports are addr[31:1])
    localparam [31:0] RST_VEC_ADDR = 32'h0000_0000;
    localparam [31:0] NMI_VEC_ADDR = 32'h0000_0020;  // placeholder: set to your NMI handler

    // RISC-V NOP (addi x0,x0,0)
    localparam [63:0] NOP64 = 64'h0000_0013_0000_0013;

    // =========================================================================
    // Signals
    // =========================================================================
    reg  clk, fixed_clk, rst_l, dbg_rst_l;

    reg  [31:1]  rst_vec, nmi_vec, jtag_id;
    reg  [31:4]  core_id;

    reg  nmi_int, timer_int, soft_int;
    reg  [PIC_TOTAL_INT:1] extintsrc_req;

    wire uart_read_irq_o, aes_irq_o, aes_done_pulse_o;
    wire dma_done_o, dma_error_o, dma_irq_o;
    wire wdt_irq_o, wdt_nmi_o, wdt_reset_o, wdt_timeout_o;
    wire gpio_irq_o, timer_irq_o;
    wire uart_tx_o, aes_busy_o, aes_done_o;

    reg  [31:0] gpio_in_i;
    wire [31:0] gpio_out_o, gpio_tx_en_o;

    reg  uart_rx_i;

    // IFU AXI
    wire        ifu_axi_arvalid, ifu_axi_rready;
    reg         ifu_axi_arready, ifu_axi_rvalid, ifu_axi_rlast;
    wire [IFU_BUS_TAG-1:0] ifu_axi_arid;
    wire [31:0]  ifu_axi_araddr;
    wire [3:0]   ifu_axi_arregion; wire [7:0] ifu_axi_arlen;
    wire [2:0]   ifu_axi_arsize;   wire [1:0] ifu_axi_arburst;
    wire         ifu_axi_arlock;   wire [3:0] ifu_axi_arcache;
    wire [2:0]   ifu_axi_arprot;   wire [3:0] ifu_axi_arqos;
    reg  [IFU_BUS_TAG-1:0] ifu_axi_rid;
    reg  [63:0]  ifu_axi_rdata;    reg [1:0] ifu_axi_rresp;
    wire         ifu_axi_awvalid;  reg  ifu_axi_awready;
    wire [IFU_BUS_TAG-1:0] ifu_axi_awid;
    wire [31:0]  ifu_axi_awaddr;   wire [3:0]  ifu_axi_awregion;
    wire [7:0]   ifu_axi_awlen;    wire [2:0]  ifu_axi_awsize;
    wire [1:0]   ifu_axi_awburst;  wire ifu_axi_awlock;
    wire [3:0]   ifu_axi_awcache;  wire [2:0]  ifu_axi_awprot;
    wire [3:0]   ifu_axi_awqos;    wire ifu_axi_wvalid;
    reg          ifu_axi_wready;   wire [63:0] ifu_axi_wdata;
    wire [7:0]   ifu_axi_wstrb;    wire ifu_axi_wlast;
    wire         ifu_axi_bvalid;   reg  ifu_axi_bready;
    wire [1:0]   ifu_axi_bresp;    wire [IFU_BUS_TAG-1:0] ifu_axi_bid;

    // SB AXI (tie off)
    wire        sb_axi_awvalid, sb_axi_wvalid, sb_axi_bready;
    wire        sb_axi_arvalid, sb_axi_rready;
    reg         sb_axi_awready, sb_axi_wready, sb_axi_bvalid;
    reg         sb_axi_arready, sb_axi_rvalid, sb_axi_rlast;
    wire [SB_BUS_TAG-1:0] sb_axi_awid, sb_axi_arid;
    wire [31:0]  sb_axi_awaddr, sb_axi_araddr;
    wire [3:0]   sb_axi_awregion, sb_axi_arregion;
    wire [7:0]   sb_axi_awlen, sb_axi_arlen;
    wire [2:0]   sb_axi_awsize, sb_axi_arsize;
    wire [1:0]   sb_axi_awburst, sb_axi_arburst;
    wire         sb_axi_awlock, sb_axi_arlock;
    wire [3:0]   sb_axi_awcache, sb_axi_arcache;
    wire [2:0]   sb_axi_awprot, sb_axi_arprot;
    wire [3:0]   sb_axi_awqos, sb_axi_arqos;
    wire [63:0]  sb_axi_wdata;      wire [7:0]  sb_axi_wstrb;
    wire         sb_axi_wlast;
    reg  [1:0]   sb_axi_bresp;      reg  [SB_BUS_TAG-1:0] sb_axi_bid;
    reg  [SB_BUS_TAG-1:0] sb_axi_rid;
    reg  [63:0]  sb_axi_rdata;      reg  [1:0]  sb_axi_rresp;

    // VeeR DMA slave port (tie off)
    reg         dma_axi_awvalid, dma_axi_wvalid, dma_axi_bready;
    reg         dma_axi_arvalid, dma_axi_rready;
    wire        dma_axi_awready, dma_axi_wready, dma_axi_bvalid;
    wire        dma_axi_arready, dma_axi_rvalid, dma_axi_rlast;
    reg  [DMA_BUS_TAG-1:0] dma_axi_awid, dma_axi_arid;
    reg  [31:0]  dma_axi_awaddr, dma_axi_araddr;
    reg  [2:0]   dma_axi_awsize, dma_axi_awprot;
    reg  [7:0]   dma_axi_awlen;     reg [1:0] dma_axi_awburst;
    reg  [63:0]  dma_axi_wdata;     reg [7:0] dma_axi_wstrb;
    reg          dma_axi_wlast;
    reg  [2:0]   dma_axi_arsize, dma_axi_arprot;
    reg  [7:0]   dma_axi_arlen;     reg [1:0] dma_axi_arburst;
    wire [1:0]   dma_axi_bresp;     wire [DMA_BUS_TAG-1:0] dma_axi_bid;
    wire [DMA_BUS_TAG-1:0] dma_axi_rid;
    wire [63:0]  dma_axi_rdata;     wire [1:0] dma_axi_rresp;

    // Misc VeeR signals
    reg         lsu_bus_clk_en, ifu_bus_clk_en, dbg_bus_clk_en, dma_bus_clk_en;
    reg         scan_mode, mbist_mode;
    reg         mpc_debug_halt_req, mpc_debug_run_req, mpc_reset_run_req;
    reg         i_cpu_halt_req, i_cpu_run_req;
    reg         dmi_core_enable, dmi_uncore_enable;
    reg  [31:0] dmi_uncore_rdata;
    wire        mpc_debug_halt_ack, mpc_debug_run_ack, debug_brkpt_status;
    wire        o_cpu_halt_ack, o_cpu_halt_status, o_debug_mode_status, o_cpu_run_ack;
    wire        dmi_uncore_en, dmi_uncore_wr_en, dmi_active;
    wire [6:0]  dmi_uncore_addr;    wire [31:0] dmi_uncore_wdata;
    wire [31:0] trace_rv_i_insn_ip, trace_rv_i_address_ip, trace_rv_i_tval_ip;
    wire        trace_rv_i_valid_ip, trace_rv_i_exception_ip;
    wire        trace_rv_i_interrupt_ip;
    wire [4:0]  trace_rv_i_ecause_ip;
    wire        iccm_ecc_single_error, iccm_ecc_double_error;
    wire        dccm_ecc_single_error, dccm_ecc_double_error;
    wire        dccm_write_readback_error;
    wire        dec_tlu_perfcnt0, dec_tlu_perfcnt1;
    wire        dec_tlu_perfcnt2, dec_tlu_perfcnt3;
    wire        jtag_tdo, jtag_tdoEn;
    reg         jtag_tck, jtag_tms, jtag_tdi, jtag_trst_n;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    veer2_dma_aes_wdt_uart_gpio_timer #(
        .IC_ID_WIDTH  (IC_ID_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .LSU_BUS_TAG  (LSU_BUS_TAG),
        .IFU_BUS_TAG  (IFU_BUS_TAG),
        .SB_BUS_TAG   (SB_BUS_TAG),
        .DMA_BUS_TAG  (DMA_BUS_TAG),
        .PIC_TOTAL_INT(PIC_TOTAL_INT)
    ) dut (
        .clk              (clk),           .rst_l         (rst_l),
        .dbg_rst_l        (dbg_rst_l),     .fixed_clk     (fixed_clk),
        .rst_vec          (rst_vec),        .nmi_vec       (nmi_vec),
        .jtag_id          (jtag_id),        .core_id       (core_id),
        .nmi_int          (nmi_int),        .timer_int     (timer_int),
        .soft_int         (soft_int),       .extintsrc_req (extintsrc_req),
        .uart_read_irq_o  (uart_read_irq_o),
        .aes_irq_o        (aes_irq_o),
        .aes_done_pulse_o (aes_done_pulse_o),
        .dma_done_o       (dma_done_o),     .dma_error_o   (dma_error_o),
        .dma_irq_o        (dma_irq_o),
        .wdt_irq_o        (wdt_irq_o),      .wdt_nmi_o     (wdt_nmi_o),
        .wdt_reset_o      (wdt_reset_o),    .wdt_timeout_o (wdt_timeout_o),
        .gpio_irq_o       (gpio_irq_o),     .timer_irq_o   (timer_irq_o),
        .uart_tx_o        (uart_tx_o),      .uart_rx_i     (uart_rx_i),
        .aes_busy_o       (aes_busy_o),     .aes_done_o    (aes_done_o),
        .gpio_in_i        (gpio_in_i),      .gpio_out_o    (gpio_out_o),
        .gpio_tx_en_o     (gpio_tx_en_o),
        // IFU
        .ifu_axi_arvalid  (ifu_axi_arvalid),.ifu_axi_arready(ifu_axi_arready),
        .ifu_axi_arid     (ifu_axi_arid),   .ifu_axi_araddr (ifu_axi_araddr),
        .ifu_axi_arregion (ifu_axi_arregion),.ifu_axi_arlen (ifu_axi_arlen),
        .ifu_axi_arsize   (ifu_axi_arsize), .ifu_axi_arburst(ifu_axi_arburst),
        .ifu_axi_arlock   (ifu_axi_arlock), .ifu_axi_arcache(ifu_axi_arcache),
        .ifu_axi_arprot   (ifu_axi_arprot), .ifu_axi_arqos  (ifu_axi_arqos),
        .ifu_axi_rvalid   (ifu_axi_rvalid), .ifu_axi_rready (ifu_axi_rready),
        .ifu_axi_rid      (ifu_axi_rid),    .ifu_axi_rdata  (ifu_axi_rdata),
        .ifu_axi_rresp    (ifu_axi_rresp),  .ifu_axi_rlast  (ifu_axi_rlast),
        .ifu_axi_awvalid  (ifu_axi_awvalid),.ifu_axi_awready(ifu_axi_awready),
        .ifu_axi_awid     (ifu_axi_awid),   .ifu_axi_awaddr (ifu_axi_awaddr),
        .ifu_axi_awregion (ifu_axi_awregion),.ifu_axi_awlen (ifu_axi_awlen),
        .ifu_axi_awsize   (ifu_axi_awsize), .ifu_axi_awburst(ifu_axi_awburst),
        .ifu_axi_awlock   (ifu_axi_awlock), .ifu_axi_awcache(ifu_axi_awcache),
        .ifu_axi_awprot   (ifu_axi_awprot), .ifu_axi_awqos  (ifu_axi_awqos),
        .ifu_axi_wvalid   (ifu_axi_wvalid), .ifu_axi_wready (ifu_axi_wready),
        .ifu_axi_wdata    (ifu_axi_wdata),  .ifu_axi_wstrb  (ifu_axi_wstrb),
        .ifu_axi_wlast    (ifu_axi_wlast),
        .ifu_axi_bvalid   (ifu_axi_bvalid), .ifu_axi_bready (ifu_axi_bready),
        .ifu_axi_bresp    (ifu_axi_bresp),  .ifu_axi_bid    (ifu_axi_bid),
        // SB
        .sb_axi_awvalid   (sb_axi_awvalid), .sb_axi_awready (sb_axi_awready),
        .sb_axi_awid      (sb_axi_awid),    .sb_axi_awaddr  (sb_axi_awaddr),
        .sb_axi_awregion  (sb_axi_awregion),.sb_axi_awlen   (sb_axi_awlen),
        .sb_axi_awsize    (sb_axi_awsize),  .sb_axi_awburst (sb_axi_awburst),
        .sb_axi_awlock    (sb_axi_awlock),  .sb_axi_awcache (sb_axi_awcache),
        .sb_axi_awprot    (sb_axi_awprot),  .sb_axi_awqos   (sb_axi_awqos),
        .sb_axi_wvalid    (sb_axi_wvalid),  .sb_axi_wready  (sb_axi_wready),
        .sb_axi_wdata     (sb_axi_wdata),   .sb_axi_wstrb   (sb_axi_wstrb),
        .sb_axi_wlast     (sb_axi_wlast),
        .sb_axi_bvalid    (sb_axi_bvalid),  .sb_axi_bready  (sb_axi_bready),
        .sb_axi_bresp     (sb_axi_bresp),   .sb_axi_bid     (sb_axi_bid),
        .sb_axi_arvalid   (sb_axi_arvalid), .sb_axi_arready (sb_axi_arready),
        .sb_axi_arid      (sb_axi_arid),    .sb_axi_araddr  (sb_axi_araddr),
        .sb_axi_arregion  (sb_axi_arregion),.sb_axi_arlen   (sb_axi_arlen),
        .sb_axi_arsize    (sb_axi_arsize),  .sb_axi_arburst (sb_axi_arburst),
        .sb_axi_arlock    (sb_axi_arlock),  .sb_axi_arcache (sb_axi_arcache),
        .sb_axi_arprot    (sb_axi_arprot),  .sb_axi_arqos   (sb_axi_arqos),
        .sb_axi_rvalid    (sb_axi_rvalid),  .sb_axi_rready  (sb_axi_rready),
        .sb_axi_rid       (sb_axi_rid),     .sb_axi_rdata   (sb_axi_rdata),
        .sb_axi_rresp     (sb_axi_rresp),   .sb_axi_rlast   (sb_axi_rlast),
        // VeeR DMA slave
        .dma_axi_awvalid  (dma_axi_awvalid),.dma_axi_awready(dma_axi_awready),
        .dma_axi_awid     (dma_axi_awid),   .dma_axi_awaddr (dma_axi_awaddr),
        .dma_axi_awsize   (dma_axi_awsize), .dma_axi_awprot (dma_axi_awprot),
        .dma_axi_awlen    (dma_axi_awlen),  .dma_axi_awburst(dma_axi_awburst),
        .dma_axi_wvalid   (dma_axi_wvalid), .dma_axi_wready (dma_axi_wready),
        .dma_axi_wdata    (dma_axi_wdata),  .dma_axi_wstrb  (dma_axi_wstrb),
        .dma_axi_wlast    (dma_axi_wlast),
        .dma_axi_bvalid   (dma_axi_bvalid), .dma_axi_bready (dma_axi_bready),
        .dma_axi_bresp    (dma_axi_bresp),  .dma_axi_bid    (dma_axi_bid),
        .dma_axi_arvalid  (dma_axi_arvalid),.dma_axi_arready(dma_axi_arready),
        .dma_axi_arid     (dma_axi_arid),   .dma_axi_araddr (dma_axi_araddr),
        .dma_axi_arsize   (dma_axi_arsize), .dma_axi_arprot (dma_axi_arprot),
        .dma_axi_arlen    (dma_axi_arlen),  .dma_axi_arburst(dma_axi_arburst),
        .dma_axi_rvalid   (dma_axi_rvalid), .dma_axi_rready (dma_axi_rready),
        .dma_axi_rid      (dma_axi_rid),    .dma_axi_rdata  (dma_axi_rdata),
        .dma_axi_rresp    (dma_axi_rresp),  .dma_axi_rlast  (dma_axi_rlast),
        // Trace / ECC / perf
        .trace_rv_i_insn_ip        (trace_rv_i_insn_ip),
        .trace_rv_i_address_ip     (trace_rv_i_address_ip),
        .trace_rv_i_valid_ip       (trace_rv_i_valid_ip),
        .trace_rv_i_exception_ip   (trace_rv_i_exception_ip),
        .trace_rv_i_ecause_ip      (trace_rv_i_ecause_ip),
        .trace_rv_i_interrupt_ip   (trace_rv_i_interrupt_ip),
        .trace_rv_i_tval_ip        (trace_rv_i_tval_ip),
        .iccm_ecc_single_error     (iccm_ecc_single_error),
        .iccm_ecc_double_error     (iccm_ecc_double_error),
        .dccm_ecc_single_error     (dccm_ecc_single_error),
        .dccm_ecc_double_error     (dccm_ecc_double_error),
        .dccm_write_readback_error (dccm_write_readback_error),
        .dec_tlu_perfcnt0          (dec_tlu_perfcnt0),
        .dec_tlu_perfcnt1          (dec_tlu_perfcnt1),
        .dec_tlu_perfcnt2          (dec_tlu_perfcnt2),
        .dec_tlu_perfcnt3          (dec_tlu_perfcnt3),
        // JTAG
        .jtag_tck    (jtag_tck),  .jtag_tms  (jtag_tms),
        .jtag_tdi    (jtag_tdi),  .jtag_trst_n(jtag_trst_n),
        .jtag_tdo    (jtag_tdo),  .jtag_tdoEn (jtag_tdoEn),
        // MPC
        .mpc_debug_halt_req (mpc_debug_halt_req),
        .mpc_debug_run_req  (mpc_debug_run_req),
        .mpc_reset_run_req  (mpc_reset_run_req),
        .mpc_debug_halt_ack (mpc_debug_halt_ack),
        .mpc_debug_run_ack  (mpc_debug_run_ack),
        .debug_brkpt_status (debug_brkpt_status),
        .i_cpu_halt_req  (i_cpu_halt_req),  .o_cpu_halt_ack    (o_cpu_halt_ack),
        .o_cpu_halt_status(o_cpu_halt_status),.o_debug_mode_status(o_debug_mode_status),
        .i_cpu_run_req   (i_cpu_run_req),   .o_cpu_run_ack     (o_cpu_run_ack),
        // Clock enables / DFT
        .lsu_bus_clk_en (lsu_bus_clk_en), .ifu_bus_clk_en (ifu_bus_clk_en),
        .dbg_bus_clk_en (dbg_bus_clk_en), .dma_bus_clk_en (dma_bus_clk_en),
        .scan_mode      (scan_mode),       .mbist_mode     (mbist_mode),
        // DMI
        .dmi_core_enable   (dmi_core_enable),
        .dmi_uncore_enable (dmi_uncore_enable),
        .dmi_uncore_en     (dmi_uncore_en),
        .dmi_uncore_wr_en  (dmi_uncore_wr_en),
        .dmi_uncore_addr   (dmi_uncore_addr),
        .dmi_uncore_wdata  (dmi_uncore_wdata),
        .dmi_uncore_rdata  (dmi_uncore_rdata),
        .dmi_active        (dmi_active)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial clk       = 1'b0;
    initial fixed_clk = 1'b0;
    always #(CLK_PERIOD/2)   clk       = ~clk;
    always #(FIXED_PERIOD/2) fixed_clk = ~fixed_clk;

    // =========================================================================
    // Instruction memory: byte array addressed by absolute address.
    // soc_full_test.hex is byte-wise with a single "@00000000" marker, so it
    // loads at IMEM_BASE = 0. Reset vector below must also be 0.
    // =========================================================================
    reg [7:0] imem [IMEM_BASE : IMEM_BASE + IMEM_BYTES - 1];

    string hex_file;
    reg [31:0] k;

    initial begin
        // Pre-fill with NOPs so fetches past the loaded image are benign
        for (k = IMEM_BASE; k < IMEM_BASE + IMEM_BYTES; k = k + 1)
            imem[k] = (k[1:0] == 2'b00) ? 8'h13 : 8'h00;

        hex_file = "soc_full_test.hex";
        void'($value$plusargs("HEX=%s", hex_file));
        $display("[TB] Loading firmware: %s", hex_file);
        $readmemh(soc_full_test.hex, imem);
        $display("[TB] imem[0..7] = %02X %02X %02X %02X %02X %02X %02X %02X (expect 17 01 05 F0 13 01 01 00)",
                 imem[0], imem[1], imem[2], imem[3], imem[4], imem[5], imem[6], imem[7]);
    end

    // 64-bit aligned fetch from imem (little-endian)
    function automatic [63:0] fetch64(input [31:0] a);
        reg [31:0] b;
        integer i;
        begin
            b = {a[31:3], 3'b000};
            if (b >= IMEM_BASE && (b + 7) < (IMEM_BASE + IMEM_BYTES)) begin
                for (i = 0; i < 8; i = i + 1)
                    fetch64[8*i +: 8] = imem[b + i];
            end else begin
                fetch64 = NOP64;
            end
        end
    endfunction

    // IFU AXI slave model
    initial begin
        ifu_axi_arready = 1'b0; ifu_axi_awready = 1'b0; ifu_axi_wready = 1'b0;
        ifu_axi_bready  = 1'b0; ifu_axi_rvalid  = 1'b0; ifu_axi_rlast  = 1'b0;
        ifu_axi_rid     = '0;   ifu_axi_rdata   = '0;   ifu_axi_rresp  = 2'b00;
    end

    always @(posedge clk) begin
        ifu_axi_arready <= 1'b1;
        ifu_axi_awready <= 1'b1;
        ifu_axi_wready  <= 1'b1;
        ifu_axi_bready  <= 1'b0;
        if (ifu_axi_arvalid && ifu_axi_arready) begin
            ifu_axi_rvalid <= 1'b1;
            ifu_axi_rid    <= ifu_axi_arid;
            ifu_axi_rdata  <= fetch64(ifu_axi_araddr);
            ifu_axi_rresp  <= 2'b00;
            ifu_axi_rlast  <= 1'b1;
        end else begin
            ifu_axi_rvalid <= 1'b0;
            ifu_axi_rlast  <= 1'b0;
        end
    end

    // SB: always ready / never valid
    initial begin
        sb_axi_awready = 1'b1; sb_axi_wready  = 1'b1;
        sb_axi_bvalid  = 1'b0; sb_axi_bresp   = 2'b00; sb_axi_bid = '0;
        sb_axi_arready = 1'b1; sb_axi_rvalid  = 1'b0;
        sb_axi_rdata   = '0;   sb_axi_rresp   = 2'b00;
        sb_axi_rid     = '0;   sb_axi_rlast   = 1'b0;
    end

    // VeeR DMA slave: tie off
    initial begin
        dma_axi_awvalid = 1'b0; dma_axi_wvalid  = 1'b0;
        dma_axi_bready  = 1'b0; dma_axi_arvalid = 1'b0;
        dma_axi_rready  = 1'b0; dma_axi_awid    = '0;
        dma_axi_awaddr  = '0;   dma_axi_awsize  = 3'b010;
        dma_axi_awprot  = 3'b0; dma_axi_awlen   = 8'b0;
        dma_axi_awburst = 2'b01;dma_axi_wdata   = '0;
        dma_axi_wstrb   = '0;   dma_axi_wlast   = 1'b0;
        dma_axi_arid    = '0;   dma_axi_araddr  = '0;
        dma_axi_arsize  = 3'b010;dma_axi_arprot = 3'b0;
        dma_axi_arlen   = 8'b0; dma_axi_arburst = 2'b01;
    end

    // =========================================================================
    // Passive monitors
    // =========================================================================
    // UART TX decoder (8N1, LSB first). Prints each received character.
    reg [7:0] tx_byte;
    integer   tx_i;
    always @(negedge uart_tx_o) begin
        if (rst_l === 1'b1) begin
            #(FIXED_PERIOD * BIT_CYCLES / 2);           // middle of start bit
            if (uart_tx_o === 1'b0) begin
                for (tx_i = 0; tx_i < 8; tx_i = tx_i + 1) begin
                    #(FIXED_PERIOD * BIT_CYCLES);
                    tx_byte[tx_i] = uart_tx_o;
                end
                #(FIXED_PERIOD * BIT_CYCLES);           // stop bit
                $display("[UART TX @%0t] 0x%02X '%c'", $time, tx_byte,
                         (tx_byte >= 8'h20 && tx_byte < 8'h7F) ? tx_byte : 8'h2E);
            end
        end
    end

    // Event logging on rising edges
    always @(posedge uart_read_irq_o) $display("[MON @%0t] uart_read_irq_o", $time);
    always @(posedge timer_irq_o)     $display("[MON @%0t] timer_irq_o",     $time);
    always @(posedge aes_done_o)      $display("[MON @%0t] aes_done_o",      $time);
    always @(posedge aes_irq_o)       $display("[MON @%0t] aes_irq_o",       $time);
    always @(posedge dma_done_o)      $display("[MON @%0t] dma_done_o",      $time);
    always @(posedge dma_irq_o)       $display("[MON @%0t] dma_irq_o",       $time);
    always @(posedge dma_error_o)     $error  ("[MON @%0t] dma_error_o",     $time);
    always @(posedge wdt_irq_o)       $display("[MON @%0t] wdt_irq_o",       $time);
    always @(posedge wdt_timeout_o)   $display("[MON @%0t] wdt_timeout_o",   $time);
    always @(posedge wdt_nmi_o)       $display("[MON @%0t] wdt_nmi_o",       $time);
    always @(posedge wdt_reset_o)     $display("[MON @%0t] wdt_reset_o",     $time);
    always @(posedge gpio_irq_o)      $display("[MON @%0t] gpio_irq_o",      $time);
    always @(gpio_out_o)              $display("[MON @%0t] gpio_out_o=0x%08X en=0x%08X",
                                               $time, gpio_out_o, gpio_tx_en_o);

    // Core-side error flags
    always @(posedge clk) begin
        if (iccm_ecc_double_error || dccm_ecc_double_error || dccm_write_readback_error)
            $error("[MON @%0t] core ECC/readback error flag asserted", $time);
        if (trace_rv_i_valid_ip && trace_rv_i_exception_ip)
            $display("[MON @%0t] exception: pc=0x%08X cause=%0d tval=0x%08X",
                     $time, trace_rv_i_address_ip, trace_rv_i_ecause_ip, trace_rv_i_tval_ip);
    end

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("tb_soc_top.vcd");
        $dumpvars(0, tb_soc_top);
    end

    // =========================================================================
    // Reset + run control (single driver of rst_l / dbg_rst_l)
    // =========================================================================
    initial begin
        rst_l          = 1'b0;  dbg_rst_l       = 1'b0;
        rst_vec        = RST_VEC_ADDR[31:1];   // reset PC = 0x0000_0000
        nmi_vec        = NMI_VEC_ADDR[31:1];
        jtag_id        = 31'h0;  core_id        = 28'h0;
        nmi_int        = 1'b0;   timer_int       = 1'b0;
        soft_int       = 1'b0;   extintsrc_req   = '0;
        uart_rx_i      = 1'b1;   gpio_in_i       = 32'hABCD_1234;
        lsu_bus_clk_en = 1'b1;   ifu_bus_clk_en  = 1'b1;
        dbg_bus_clk_en = 1'b1;   dma_bus_clk_en  = 1'b1;
        scan_mode      = 1'b0;   mbist_mode       = 1'b0;
        mpc_debug_halt_req = 1'b0; mpc_debug_run_req = 1'b0;
        mpc_reset_run_req  = 1'b1;
        i_cpu_halt_req = 1'b0;   i_cpu_run_req   = 1'b0;
        dmi_core_enable    = 1'b1;  dmi_uncore_enable = 1'b0;
        dmi_uncore_rdata   = 32'h0;
        jtag_tck = 1'b0; jtag_tms = 1'b1; jtag_tdi = 1'b0; jtag_trst_n = 1'b0;

        repeat (RST_CYCLES) @(posedge clk);
        rst_l       = 1'b1;
        dbg_rst_l   = 1'b1;
        jtag_trst_n = 1'b1;
        $display("[TB @%0t] Reset released, firmware executing", $time);

        repeat (SIM_RUN_CYC) @(posedge clk);

        $display("[TB @%0t] Run length reached (%0d cycles). Finishing.", $time, SIM_RUN_CYC);
        $finish;
    end

endmodule

`default_nettype wire