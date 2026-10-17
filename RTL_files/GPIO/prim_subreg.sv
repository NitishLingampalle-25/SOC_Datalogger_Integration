// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module prim_subreg #(
  parameter int unsigned   DW       = 32,
  parameter                SWACCESS = "RW",
  parameter logic [DW-1:0] RESVAL   = '0
) (
  input  logic          clk_i,
  input  logic          rst_ni,

  input  logic          we,
  input  logic [DW-1:0] wd,

  input  logic          de,
  input  logic [DW-1:0] d,

  output logic          qe,
  output logic [DW-1:0] q,
  output logic [DW-1:0] qs
);

  logic [DW-1:0] reg_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      reg_q <= RESVAL;
    end else if (de) begin
      reg_q <= d;
    end else if (we) begin
      if (SWACCESS == "W1C") begin
        reg_q <= reg_q & ~wd;
      end else if (SWACCESS == "W1S") begin
        reg_q <= reg_q | wd;
      end else if (SWACCESS == "RO") begin
        reg_q <= reg_q;
      end else begin // "RW"
        reg_q <= wd;
      end
    end
  end

  assign q  = reg_q;
  assign qs = reg_q;
  assign qe = we | de;

endmodule

module prim_subreg_ext #(
  parameter int unsigned DW = 32
) (
  input  logic          re,
  input  logic          we,
  input  logic [DW-1:0] wd,
  input  logic [DW-1:0] d,

  output logic          qre,
  output logic          qe,
  output logic [DW-1:0] q,
  output logic [DW-1:0] qs
);

  assign qs  = d;
  assign q   = wd;
  assign qe  = we;
  assign qre = re;

endmodule

module sync #(
  parameter int unsigned STAGES = 2
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic serial_i,
  output logic serial_o
);
  logic [STAGES-1:0] sync_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sync_q <= '0;
    end else begin
      sync_q <= {sync_q[STAGES-2:0], serial_i};
    end
  end
  assign serial_o = sync_q[STAGES-1];
endmodule

module tc_clk_gating #(
  parameter int unsigned IS_FUNCTIONAL = 0
) (
  input  logic clk_i,
  input  logic en_i,
  input  logic test_en_i,
  output logic clk_o
);
  logic clk_en;
  always_latch begin
    if (!clk_i)
      clk_en <= en_i | test_en_i;
  end
  assign clk_o = clk_i & clk_en;
endmodule
