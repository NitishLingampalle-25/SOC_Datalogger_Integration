module axi_dwidth_converter_64to32 #(
    parameter ID_WIDTH_M = 4,
    parameter ID_WIDTH_S = 8,
    parameter ADDR_WIDTH = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // Master side – 64-bit data bus (connects to VeeR EL2 LSU)
    input  wire [ID_WIDTH_M-1:0]    m_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    m_axi_awaddr,
    input  wire [7:0]               m_axi_awlen,
    input  wire [2:0]               m_axi_awsize,
    input  wire [1:0]               m_axi_awburst,
    input  wire                     m_axi_awlock,
    input  wire [3:0]               m_axi_awcache,
    input  wire [2:0]               m_axi_awprot,
    input  wire [3:0]               m_axi_awqos,
    input  wire [3:0]               m_axi_awregion,
    input  wire                     m_axi_awvalid,
    output wire                     m_axi_awready,

    input  wire [63:0]              m_axi_wdata,
    input  wire [7:0]               m_axi_wstrb,
    input  wire                     m_axi_wlast,
    input  wire                     m_axi_wvalid,
    output wire                     m_axi_wready,

    output wire [ID_WIDTH_M-1:0]    m_axi_bid,
    output wire [1:0]               m_axi_bresp,
    output wire                     m_axi_bvalid,
    input  wire                     m_axi_bready,

    input  wire [ID_WIDTH_M-1:0]    m_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    m_axi_araddr,
    input  wire [7:0]               m_axi_arlen,
    input  wire [2:0]               m_axi_arsize,
    input  wire [1:0]               m_axi_arburst,
    input  wire                     m_axi_arlock,
    input  wire [3:0]               m_axi_arcache,
    input  wire [2:0]               m_axi_arprot,
    input  wire [3:0]               m_axi_arqos,
    input  wire [3:0]               m_axi_arregion,
    input  wire                     m_axi_arvalid,
    output wire                     m_axi_arready,

    output wire [ID_WIDTH_M-1:0]    m_axi_rid,
    output wire [63:0]              m_axi_rdata,
    output wire [1:0]               m_axi_rresp,
    output wire                     m_axi_rlast,
    output wire                     m_axi_rvalid,
    input  wire                     m_axi_rready,

    // Slave side – 32-bit data bus (connects to AXI interconnect s00)
    output wire [ID_WIDTH_S-1:0]    s_axi_awid,
    output wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    output wire [7:0]               s_axi_awlen,
    output wire [2:0]               s_axi_awsize,
    output wire [1:0]               s_axi_awburst,
    output wire                     s_axi_awlock,
    output wire [3:0]               s_axi_awcache,
    output wire [2:0]               s_axi_awprot,
    output wire [3:0]               s_axi_awqos,
    output wire                     s_axi_awvalid,
    input  wire                     s_axi_awready,

    output wire [31:0]              s_axi_wdata,
    output wire [3:0]               s_axi_wstrb,
    output wire                     s_axi_wlast,
    output wire                     s_axi_wvalid,
    input  wire                     s_axi_wready,

    input  wire [ID_WIDTH_S-1:0]    s_axi_bid,
    input  wire [1:0]               s_axi_bresp,
    input  wire                     s_axi_bvalid,
    output wire                     s_axi_bready,

    output wire [ID_WIDTH_S-1:0]    s_axi_arid,
    output wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    output wire [7:0]               s_axi_arlen,
    output wire [2:0]               s_axi_arsize,
    output wire [1:0]               s_axi_arburst,
    output wire                     s_axi_arlock,
    output wire [3:0]               s_axi_arcache,
    output wire [2:0]               s_axi_arprot,
    output wire [3:0]               s_axi_arqos,
    output wire                     s_axi_arvalid,
    input  wire                     s_axi_arready,

    input  wire [ID_WIDTH_S-1:0]    s_axi_rid,
    input  wire [31:0]              s_axi_rdata,
    input  wire [1:0]               s_axi_rresp,
    input  wire                     s_axi_rlast,
    input  wire                     s_axi_rvalid,
    output wire                     s_axi_rready
);

    reg         aw_lane_r;
    reg         aw_pending_r;

    wire aw_hs = m_axi_awvalid && s_axi_awready;
    wire w_hs  = m_axi_wvalid && s_axi_wready && m_axi_wlast;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_lane_r    <= 1'b0;
            aw_pending_r <= 1'b0;
        end else begin
            if (aw_hs) begin
                aw_lane_r    <= m_axi_awaddr[2];
                aw_pending_r <= !w_hs;
            end else if (w_hs) begin
                aw_pending_r <= 1'b0;
            end
        end
    end

    wire aw_lane = (|m_axi_wstrb[7:4]) ? 1'b1 :
                   (|m_axi_wstrb[3:0]) ? 1'b0 :
                   (aw_pending_r ? aw_lane_r : m_axi_awaddr[2]);

    reg         ar_lane_r;
    reg         ar_pending_r;

    wire ar_hs = m_axi_arvalid && s_axi_arready;
    wire r_hs  = s_axi_rvalid && m_axi_rready && s_axi_rlast;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_lane_r    <= 1'b0;
            ar_pending_r <= 1'b0;
        end else begin
            if (ar_hs) begin
                ar_lane_r    <= m_axi_araddr[2];
                ar_pending_r <= !r_hs;
            end else if (r_hs) begin
                ar_pending_r <= 1'b0;
            end
        end
    end

    wire ar_lane = ar_pending_r ? ar_lane_r : m_axi_araddr[2];

    wire [2:0] aw_size_clamped = (m_axi_awsize == 3'b011) ? 3'b010 : m_axi_awsize;
    wire [2:0] ar_size_clamped = (m_axi_arsize == 3'b011) ? 3'b010 : m_axi_arsize;

    generate
        if (ID_WIDTH_M >= ID_WIDTH_S) begin : id_trunc
            assign s_axi_awid = m_axi_awid[ID_WIDTH_S-1:0];
            assign s_axi_arid = m_axi_arid[ID_WIDTH_S-1:0];
        end else begin : id_pad
            assign s_axi_awid = {{(ID_WIDTH_S-ID_WIDTH_M){1'b0}}, m_axi_awid};
            assign s_axi_arid = {{(ID_WIDTH_S-ID_WIDTH_M){1'b0}}, m_axi_arid};
        end
    endgenerate

    assign s_axi_awaddr   = {m_axi_awaddr[ADDR_WIDTH-1:3], aw_lane, m_axi_awaddr[1:0]};
    assign s_axi_awlen    = m_axi_awlen;
    assign s_axi_awsize   = aw_size_clamped;
    assign s_axi_awburst  = m_axi_awburst;
    assign s_axi_awlock   = m_axi_awlock;
    assign s_axi_awcache  = m_axi_awcache;
    assign s_axi_awprot   = m_axi_awprot;
    assign s_axi_awqos    = m_axi_awqos;
    assign s_axi_awvalid  = m_axi_awvalid;
    assign m_axi_awready  = s_axi_awready;

    assign s_axi_wdata    = aw_lane ? m_axi_wdata[63:32] : m_axi_wdata[31:0];
    assign s_axi_wstrb    = aw_lane ? m_axi_wstrb[7:4]   : m_axi_wstrb[3:0];
    assign s_axi_wlast    = m_axi_wlast;
    assign s_axi_wvalid   = m_axi_wvalid;
    assign m_axi_wready   = s_axi_wready;

    assign m_axi_bid      = s_axi_bid[ID_WIDTH_M-1:0];
    assign m_axi_bresp    = s_axi_bresp;
    assign m_axi_bvalid   = s_axi_bvalid;
    assign s_axi_bready   = m_axi_bready;

    assign s_axi_araddr   = {m_axi_araddr[ADDR_WIDTH-1:3], ar_lane, m_axi_araddr[1:0]};
    assign s_axi_arlen    = m_axi_arlen;
    assign s_axi_arsize   = ar_size_clamped;
    assign s_axi_arburst  = m_axi_arburst;
    assign s_axi_arlock   = m_axi_arlock;
    assign s_axi_arcache  = m_axi_arcache;
    assign s_axi_arprot   = m_axi_arprot;
    assign s_axi_arqos    = m_axi_arqos;
    assign s_axi_arvalid  = m_axi_arvalid;
    assign m_axi_arready  = s_axi_arready;

    assign m_axi_rid      = s_axi_rid[ID_WIDTH_M-1:0];
    assign m_axi_rdata    = {s_axi_rdata, s_axi_rdata};
    assign m_axi_rresp    = s_axi_rresp;
    assign m_axi_rlast    = s_axi_rlast;
    assign m_axi_rvalid   = s_axi_rvalid;
    assign s_axi_rready   = m_axi_rready;

endmodule
