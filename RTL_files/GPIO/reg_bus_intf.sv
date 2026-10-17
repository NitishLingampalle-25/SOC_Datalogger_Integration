// =============================================================================
// reg_bus_intf.sv
// Minimal REG_BUS interface definition — matches the struct fields defined in
// register_interface/typedef.svh and the assign macros in assign.svh.
//
// Used by gpio.sv (gpio_intf wrapper module).
// =============================================================================

`timescale 1ns/1ps

interface REG_BUS #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32
) ();
    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

    logic [ADDR_WIDTH-1:0]  addr;
    logic                   write;
    logic [DATA_WIDTH-1:0]  wdata;
    logic [STRB_WIDTH-1:0]  wstrb;
    logic                   valid;
    logic [DATA_WIDTH-1:0]  rdata;
    logic                   error;
    logic                   ready;

    modport in (
        input  addr, write, wdata, wstrb, valid,
        output rdata, error, ready
    );

    modport out (
        output addr, write, wdata, wstrb, valid,
        input  rdata, error, ready
    );

endinterface
