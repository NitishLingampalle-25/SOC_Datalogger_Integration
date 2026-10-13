// =============================================================================
// register_interface/assign.svh
// Minimal stub — provides only the macros used by gpio.sv and gpio_reg_top.sv
// in this project.  Full pulp-platform register_interface not required.
//
// Macro: REG_BUS_ASSIGN_TO_REQ(req_struct, bus_if)
//   Copies fields from a REG_BUS interface instance into a req struct.
//
// Macro: REG_BUS_ASSIGN_FROM_RSP(bus_if, rsp_struct)
//   Copies fields from a rsp struct back into a REG_BUS interface instance.
// =============================================================================

`ifndef REGISTER_INTERFACE_ASSIGN_SVH_
`define REGISTER_INTERFACE_ASSIGN_SVH_

`define REG_BUS_ASSIGN_TO_REQ(req, bus) \
  assign req.addr  = bus.addr;  \
  assign req.write = bus.write; \
  assign req.wdata = bus.wdata; \
  assign req.wstrb = bus.wstrb; \
  assign req.valid = bus.valid;

`define REG_BUS_ASSIGN_FROM_RSP(bus, rsp) \
  assign bus.rdata = rsp.rdata; \
  assign bus.error = rsp.error; \
  assign bus.ready = rsp.ready;

`endif // REGISTER_INTERFACE_ASSIGN_SVH_
