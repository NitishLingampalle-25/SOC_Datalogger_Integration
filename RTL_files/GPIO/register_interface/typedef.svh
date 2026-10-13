// =============================================================================
// register_interface/typedef.svh
// Minimal stub — provides only the macros used by gpio.sv and gpio_reg_top.sv
// in this project.  Full pulp-platform register_interface not required.
//
// Macro: REG_BUS_TYPEDEF_ALL(name, addr_t, data_t, strb_t)
//   Defines:  <name>_req_t  — request struct  { addr, write, wdata, wstrb, valid }
//             <name>_rsp_t  — response struct { rdata, error, ready }
// =============================================================================

`ifndef REGISTER_INTERFACE_TYPEDEF_SVH_
`define REGISTER_INTERFACE_TYPEDEF_SVH_

`define REG_BUS_TYPEDEF_REQ(req_name, addr_t, data_t, strb_t) \
  typedef struct packed { \
    addr_t  addr;  \
    logic   write; \
    data_t  wdata; \
    strb_t  wstrb; \
    logic   valid; \
  } req_name;

`define REG_BUS_TYPEDEF_RSP(rsp_name, data_t) \
  typedef struct packed { \
    data_t  rdata; \
    logic   error; \
    logic   ready; \
  } rsp_name;

// REG_BUS_TYPEDEF_ALL defines both req and rsp types with names:
//   <name>_req_t  and  <name>_rsp_t
`define REG_BUS_TYPEDEF_ALL(name, addr_t, data_t, strb_t) \
  `REG_BUS_TYPEDEF_REQ(name``_req_t, addr_t, data_t, strb_t) \
  `REG_BUS_TYPEDEF_RSP(name``_rsp_t, data_t)

`endif // REGISTER_INTERFACE_TYPEDEF_SVH_
