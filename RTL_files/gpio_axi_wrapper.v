// =============================================================================
// Module  : gpio_axi_wrapper
// File    : RTL_files/gpio_axi_wrapper.v
//
// Purpose : AXI4 slave wrapper around the GPIO IP (gpio_reg_top + gpio).
//           Converts the AXI4 bus transactions from the interconnect m05 port
//           to the flat reg_bus protocol expected by gpio_reg_top, avoiding
//           any dependency on pulp-platform macro header files.
//
// Address : 0x4000_5000 (4 KB aperture, GPIO register space is 2 KB / BlockAw=11)
//
// GPIO IP:  gpio_reg_pkg::GPIOCount = 32 pins
// =============================================================================

`timescale 1ns/1ps

module gpio_axi_wrapper #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = DATA_WIDTH / 8
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // AXI4 Slave Interface (from interconnect m05)
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

    // GPIO physical signals
    input  wire [31:0]              gpio_in_i,
    output wire [31:0]              gpio_out_o,
    output wire [31:0]              gpio_tx_en_o,
    output wire                     gpio_irq_o
);

    // =========================================================================
    // Flat reg_bus typedef (mirrors register_interface protocol without macros)
    //   req: valid, write, addr[10:0], wdata[31:0], wstrb[3:0]
    //   rsp: rdata[31:0], error, ready
    // =========================================================================
    typedef struct packed {
        logic              valid;
        logic              write;
        logic [10:0]       addr;
        logic [31:0]       wdata;
        logic [3:0]        wstrb;
    } gpio_reg_req_t;

    typedef struct packed {
        logic [31:0]       rdata;
        logic              error;
        logic              ready;
    } gpio_reg_rsp_t;

    gpio_reg_req_t reg_req;
    gpio_reg_rsp_t reg_rsp;

    // =========================================================================
    // AXI4 Write FSM  (single-beat; GPIO regs are all 32-bit single-beat)
    // =========================================================================
    localparam WR_IDLE = 2'd0, WR_DATA = 2'd1, WR_RESP = 2'd2;

    reg [1:0]          wr_state;
    reg [ID_WIDTH-1:0] wr_id_r;
    reg [10:0]         wr_addr_r;
    reg [31:0]         wr_data_r;
    reg [3:0]          wr_strb_r;
    reg                wr_do_r;     // pulse: drive reg_req for one cycle

    assign s_axi_awready = (wr_state == WR_IDLE);
    assign s_axi_wready  = (wr_state == WR_DATA) | (wr_state == WR_IDLE & s_axi_awvalid);
    assign s_axi_bid     = wr_id_r;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bvalid  = (wr_state == WR_RESP);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state  <= WR_IDLE;
            wr_id_r   <= {ID_WIDTH{1'b0}};
            wr_addr_r <= 11'b0;
            wr_data_r <= 32'b0;
            wr_strb_r <= 4'b0;
            wr_do_r   <= 1'b0;
        end else begin
            wr_do_r <= 1'b0;
            case (wr_state)
                WR_IDLE: begin
                    if (s_axi_awvalid & s_axi_wvalid) begin
                        wr_id_r   <= s_axi_awid;
                        wr_addr_r <= s_axi_awaddr[10:0];
                        wr_data_r <= s_axi_wdata;
                        wr_strb_r <= s_axi_wstrb;
                        wr_do_r   <= 1'b1;
                        wr_state  <= WR_RESP;
                    end else if (s_axi_awvalid) begin
                        wr_id_r   <= s_axi_awid;
                        wr_addr_r <= s_axi_awaddr[10:0];
                        wr_state  <= WR_DATA;
                    end
                end
                WR_DATA: begin
                    if (s_axi_wvalid) begin
                        wr_data_r <= s_axi_wdata;
                        wr_strb_r <= s_axi_wstrb;
                        wr_do_r   <= 1'b1;
                        wr_state  <= WR_RESP;
                    end
                end
                WR_RESP: begin
                    if (s_axi_bready)
                        wr_state <= WR_IDLE;
                end
                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // =========================================================================
    // AXI4 Read FSM
    // =========================================================================
    localparam RD_IDLE = 1'b0, RD_DATA = 1'b1;

    reg                  rd_state;
    reg [ID_WIDTH-1:0]   rd_id_r;
    reg [10:0]           rd_addr_r;
    reg                  rd_do_r;    // pulse: drive reg_req read for one cycle
    reg [31:0]           rd_data_r;
    reg                  rd_data_valid_r;

    assign s_axi_arready = (rd_state == RD_IDLE);
    assign s_axi_rid     = rd_id_r;
    assign s_axi_rdata   = rd_data_r;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rlast   = 1'b1;
    assign s_axi_rvalid  = rd_data_valid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state        <= RD_IDLE;
            rd_id_r         <= {ID_WIDTH{1'b0}};
            rd_addr_r       <= 11'b0;
            rd_do_r         <= 1'b0;
            rd_data_r       <= 32'b0;
            rd_data_valid_r <= 1'b0;
        end else begin
            rd_do_r <= 1'b0;
            case (rd_state)
                RD_IDLE: begin
                    if (s_axi_arvalid) begin
                        rd_id_r   <= s_axi_arid;
                        rd_addr_r <= s_axi_araddr[10:0];
                        rd_do_r   <= 1'b1;
                        rd_state  <= RD_DATA;
                    end
                end
                RD_DATA: begin
                    // Capture reg_rsp.rdata one cycle after rd_do_r
                    if (!rd_data_valid_r) begin
                        rd_data_r       <= reg_rsp.rdata;
                        rd_data_valid_r <= 1'b1;
                    end
                    if (rd_data_valid_r & s_axi_rready) begin
                        rd_data_valid_r <= 1'b0;
                        rd_state        <= RD_IDLE;
                    end
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // =========================================================================
    // reg_bus drive: mux write/read requests; ready is combinatorial from GPIO
    // =========================================================================
    always @(*) begin
        reg_req.valid = 1'b0;
        reg_req.write = 1'b0;
        reg_req.addr  = 11'b0;
        reg_req.wdata = 32'b0;
        reg_req.wstrb = 4'b0;
        if (wr_do_r) begin
            reg_req.valid = 1'b1;
            reg_req.write = 1'b1;
            reg_req.addr  = wr_addr_r;
            reg_req.wdata = wr_data_r;
            reg_req.wstrb = wr_strb_r;
        end else if (rd_do_r) begin
            reg_req.valid = 1'b1;
            reg_req.write = 1'b0;
            reg_req.addr  = rd_addr_r;
            reg_req.wdata = 32'b0;
            reg_req.wstrb = 4'b0;
        end
    end

    // =========================================================================
    // GPIO IP instantiation (gpio_reg_top + gpio via gpio.sv's reg_req_t)
    // The gpio.sv module is parameterized with reg_req_t / reg_rsp_t.
    // We pass our locally-defined structs as the type parameters.
    // =========================================================================
    wire [31:0] gpio_in_sync_unused;
    wire [31:0] pin_level_irqs_unused;

    gpio #(
        .DATA_WIDTH (32),
        .reg_req_t  (gpio_reg_req_t),
        .reg_rsp_t  (gpio_reg_rsp_t)
    ) u_gpio_core (
        .clk_i                 (clk),
        .rst_ni                (rst_n),
        .gpio_in               (gpio_in_i),
        .gpio_out              (gpio_out_o),
        .gpio_tx_en_o          (gpio_tx_en_o),
        .gpio_in_sync_o        (gpio_in_sync_unused),
        .global_interrupt_o    (gpio_irq_o),
        .pin_level_interrupts_o(pin_level_irqs_unused),
        .reg_req_i             (reg_req),
        .reg_rsp_o             (reg_rsp)
    );

endmodule
