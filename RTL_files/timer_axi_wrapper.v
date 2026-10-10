// =============================================================================
// Module  : timer_axi_wrapper
// File    : RTL_files/timer_axi_wrapper.v
//
// Purpose : Self-contained AXI4 slave wrapper for the RISC-V System Timer.
//           Implements all 10 rv_timer registers inline and instantiates only
//           timer_core.sv (zero external IP dependencies).
//           Compatible with the SoC AXI4 interconnect m01 port @ 0x4000_1000.
//
// Register Map (offsets from base, matching rv_timer_reg_pkg.sv):
//   0x000 : CTRL           – bit[0] = timer enable
//   0x100 : INTR_ENABLE0   – bit[0] = interrupt enable
//   0x104 : INTR_STATE0    – bit[0] = interrupt pending (W1C)
//   0x108 : INTR_TEST0     – bit[0] = force interrupt (write-only)
//   0x10C : CFG0           – [19:8]=prescaler [7:0]=step
//   0x110 : TIMER_V_LOWER0 – mtime[31:0]  (RW, hw-updated each tick)
//   0x114 : TIMER_V_UPPER0 – mtime[63:32] (RW, hw-updated each tick)
//   0x118 : COMPARE_LOWER0 – mtimecmp[31:0]
//   0x11C : COMPARE_UPPER0 – mtimecmp[63:32]
// =============================================================================

`timescale 1ns/1ps

module timer_axi_wrapper #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = DATA_WIDTH / 8
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // AXI4 Slave Interface
    input  wire [ID_WIDTH-1:0]      s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]               s_axi_awlen,
    input  wire [2:0]               s_axi_awsize,
    input  wire [1:0]               s_axi_awburst,
    input  wire                     s_axi_awlock,
    input  wire [3:0]               s_axi_awcache,
    input  wire [2:0]               s_axi_awprot,
    input  wire [3:0]               s_axi_awqos,
    input  wire [3:0]               s_axi_awregion,
    input  wire                     s_axi_awvalid,
    output wire                     s_axi_awready,

    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]    s_axi_wstrb,
    input  wire                     s_axi_wlast,
    input  wire                     s_axi_wvalid,
    output wire                     s_axi_wready,

    output wire [ID_WIDTH-1:0]      s_axi_bid,
    output wire [1:0]               s_axi_bresp,
    output wire                     s_axi_bvalid,
    input  wire                     s_axi_bready,

    input  wire [ID_WIDTH-1:0]      s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [7:0]               s_axi_arlen,
    input  wire [2:0]               s_axi_arsize,
    input  wire [1:0]               s_axi_arburst,
    input  wire                     s_axi_arlock,
    input  wire [3:0]               s_axi_arcache,
    input  wire [2:0]               s_axi_arprot,
    input  wire [3:0]               s_axi_arqos,
    input  wire [3:0]               s_axi_arregion,
    input  wire                     s_axi_arvalid,
    output wire                     s_axi_arready,

    output wire [ID_WIDTH-1:0]      s_axi_rid,
    output wire [DATA_WIDTH-1:0]    s_axi_rdata,
    output wire [1:0]               s_axi_rresp,
    output wire                     s_axi_rlast,
    output wire                     s_axi_rvalid,
    input  wire                     s_axi_rready,

    // Timer interrupt output
    output wire                     timer_irq_o
);

    // =========================================================================
    // Registers
    // =========================================================================
    reg         ctrl_en;          // 0x000 bit0
    reg         intr_enable;      // 0x100 bit0
    reg         intr_state;       // 0x104 bit0  (W1C)
    reg [11:0]  prescaler;        // 0x10C [19:8]
    reg [7:0]   step;             // 0x10C [7:0]
    reg [31:0]  timer_lo;         // 0x110 mtime lower (sw-writable, hw-updated)
    reg [31:0]  timer_hi;         // 0x114 mtime upper
    reg [31:0]  cmp_lo;           // 0x118
    reg [31:0]  cmp_hi;           // 0x11C

    // =========================================================================
    // timer_core connections
    // =========================================================================
    wire        tick;
    wire [63:0] mtime_d;
    wire [63:0] mtime   = {timer_hi, timer_lo};
    wire [63:0] mtimecmp[1];
    wire [0:0]  intr_raw;
    reg         cmp_update_r;

    assign mtimecmp[0] = {cmp_hi, cmp_lo};

    // Update mtime from timer_core each tick
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_lo    <= 32'b0;
            timer_hi    <= 32'b0;
        end else if (tick) begin
            timer_lo    <= mtime_d[31:0];
            timer_hi    <= mtime_d[63:32];
        end
    end

    // Interrupt state: set by timer_core, cleared W1C; also cleared on cmp update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            intr_state <= 1'b0;
        else begin
            if (cmp_update_r)
                intr_state <= 1'b0;
            else if (intr_raw[0] & intr_enable)
                intr_state <= 1'b1;
        end
    end

    assign timer_irq_o = intr_state;

    timer_core #(.N(1)) u_timer_core (
        .clk_i     (clk),
        .rst_ni    (rst_n),
        .active    (ctrl_en),
        .prescaler (prescaler),
        .step      (step),
        .tick      (tick),
        .mtime_d   (mtime_d),
        .mtime     (mtime),
        .mtimecmp  (mtimecmp),
        .intr      (intr_raw)
    );

    // =========================================================================
    // AXI4 Write FSM
    // =========================================================================
    localparam WR_IDLE = 2'd0, WR_DATA = 2'd1, WR_RESP = 2'd2;

    reg [1:0]          wr_state;
    reg [ID_WIDTH-1:0] wr_id_r;
    reg [8:0]          wr_addr_r;   // 9-bit (BlockAw)
    reg [31:0]         wr_data_r;
    reg [3:0]          wr_strb_r;
    reg                wr_do_r;

    assign s_axi_awready = (wr_state == WR_IDLE);
    assign s_axi_wready  = (wr_state == WR_DATA) | (wr_state == WR_IDLE & s_axi_awvalid);
    assign s_axi_bid     = wr_id_r;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bvalid  = (wr_state == WR_RESP);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state  <= WR_IDLE; wr_id_r <= {ID_WIDTH{1'b0}};
            wr_addr_r <= 9'b0;   wr_data_r <= 32'b0;
            wr_strb_r <= 4'b0;   wr_do_r   <= 1'b0;
            cmp_update_r <= 1'b0;
        end else begin
            wr_do_r      <= 1'b0;
            cmp_update_r <= 1'b0;
            case (wr_state)
                WR_IDLE: begin
                    if (s_axi_awvalid & s_axi_wvalid) begin
                        wr_id_r   <= s_axi_awid;
                        wr_addr_r <= s_axi_awaddr[8:0];
                        wr_data_r <= s_axi_wdata;
                        wr_strb_r <= s_axi_wstrb;
                        wr_do_r   <= 1'b1;
                        wr_state  <= WR_RESP;
                    end else if (s_axi_awvalid) begin
                        wr_id_r   <= s_axi_awid;
                        wr_addr_r <= s_axi_awaddr[8:0];
                        wr_state  <= WR_DATA;
                    end
                end
                WR_DATA: if (s_axi_wvalid) begin
                    wr_data_r <= s_axi_wdata;
                    wr_strb_r <= s_axi_wstrb;
                    wr_do_r   <= 1'b1;
                    wr_state  <= WR_RESP;
                end
                WR_RESP: if (s_axi_bready) wr_state <= WR_IDLE;
                default: wr_state <= WR_IDLE;
            endcase

            if (wr_do_r) begin
                case (wr_addr_r)
                    9'h000: ctrl_en      <= wr_data_r[0];
                    9'h100: intr_enable  <= wr_data_r[0];
                    9'h104: intr_state   <= intr_state & ~wr_data_r[0]; // W1C
                    9'h108: ; // INTR_TEST write-only: pulse (not latched in this impl)
                    9'h10C: begin
                        prescaler <= wr_data_r[19:8];
                        step      <= wr_data_r[7:0];
                    end
                    9'h110: timer_lo     <= wr_data_r;
                    9'h114: timer_hi     <= wr_data_r;
                    9'h118: begin cmp_lo <= wr_data_r; cmp_update_r <= 1'b1; end
                    9'h11C: begin cmp_hi <= wr_data_r; cmp_update_r <= 1'b1; end
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // AXI4 Read FSM
    // =========================================================================
    localparam RD_IDLE = 1'b0, RD_DATA = 1'b1;

    reg                  rd_state;
    reg [ID_WIDTH-1:0]   rd_id_r;
    reg [DATA_WIDTH-1:0] rd_data_r;

    assign s_axi_arready = (rd_state == RD_IDLE);
    assign s_axi_rid     = rd_id_r;
    assign s_axi_rdata   = rd_data_r;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rlast   = 1'b1;
    assign s_axi_rvalid  = (rd_state == RD_DATA);

    reg [31:0] rd_mux;
    always @(*) begin
        case (s_axi_araddr[8:0])
            9'h000: rd_mux = {31'b0, ctrl_en};
            9'h100: rd_mux = {31'b0, intr_enable};
            9'h104: rd_mux = {31'b0, intr_state};
            9'h108: rd_mux = 32'b0;
            9'h10C: rd_mux = {12'b0, prescaler, step};
            9'h110: rd_mux = timer_lo;
            9'h114: rd_mux = timer_hi;
            9'h118: rd_mux = cmp_lo;
            9'h11C: rd_mux = cmp_hi;
            default: rd_mux = 32'hDEAD_BEEF;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state <= RD_IDLE; rd_id_r <= {ID_WIDTH{1'b0}}; rd_data_r <= 32'b0;
        end else begin
            case (rd_state)
                RD_IDLE: if (s_axi_arvalid) begin
                    rd_id_r   <= s_axi_arid;
                    rd_data_r <= rd_mux;
                    rd_state  <= RD_DATA;
                end
                RD_DATA: if (s_axi_rready) rd_state <= RD_IDLE;
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // Default register values on reset
    initial begin
        ctrl_en    = 1'b0;
        intr_enable = 1'b0;
        intr_state  = 1'b0;
        prescaler   = 12'd0;
        step        = 8'd1;
        timer_lo    = 32'b0;
        timer_hi    = 32'b0;
        cmp_lo      = 32'hFFFF_FFFF;
        cmp_hi      = 32'hFFFF_FFFF;
    end

endmodule
