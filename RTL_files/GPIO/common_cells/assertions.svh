// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`ifndef ASSERTIONS_SVH_
`define ASSERTIONS_SVH_

`ifndef ASSERT
`define ASSERT(__name, __prop) \
  __name: assert property (@(posedge clk_i) disable iff (!rst_ni) (__prop)) \
    else $error("[ASSERT FAILED] %m: %s", `"__prop`");
`endif

`endif // ASSERTIONS_SVH_
