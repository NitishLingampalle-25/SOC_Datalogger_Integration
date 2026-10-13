// =============================================================================
// final_run.f
// =============================================================================
// VCS filelist — 100% self-contained within SOC_Datalogger_project.
// No external paths.  Snapshot was generated with:
//   cd RTL_files/Cores-VeeR-EL2
//   BUILD_PATH=snapshots/default ./configs/veer.config -target=default -set build_axi4
//
// Top module  : veer2_dma_aes_wdt_uart_gpio_timer
// Testbench   : veer2_dma_aes_wdt_uart_gpio_timer_tb
//
// Compile (from the run/ directory):
//   vcs -full64 -sverilog -l compile_final.log -f final_run.f -o simv_final
//
// Simulate:
//   ./simv_final -l sim_final.log
//
// With Verdi:
//   vcs -full64 -sverilog -debug_access+all -kdb \
//       -l compile_final.log -f final_run.f -o simv_final
//   ./simv_final -verdi
// =============================================================================

-sverilog
-timescale=1ns/1ps
+define+RV_BUILD_AXI4
+define+RV_PHYSICAL

// ---- Include Directories (all inside project) ----
+incdir+/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/snapshots/default
+incdir+/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/include
+incdir+/home/student/Documents/SOC_Datalogger_project/axi-lite_uart-ipcore-develop/src/include
+incdir+/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/inc
// GPIO: resolves `include "common_cells/assertions.svh"
+incdir+/home/student/Documents/SOC_Datalogger_project/RTL_files/GPIO
// GPIO: resolves `include "register_interface/typedef.svh" and "register_interface/assign.svh"
+incdir+/home/student/Documents/SOC_Datalogger_project/RTL_files/GPIO/register_interface

// =============================================================================
// VeeR EL2 Core — snapshot defines (common_defines.vh MUST be the very first file)
// =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/snapshots/default/common_defines.vh
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/include/el2_def.sv

// ---- VeeR EL2: lib / packages ----
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lib/el2_assert.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/el2_mubi_pkg.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lib/el2_mem_if.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lib/el2_prim_generic_buf.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lib/el2_prim_buf.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lib/beh_lib.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lib/mem_lib.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lib/el2_lib.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lib/ahb_to_axi4.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lib/axi4_to_ahb.sv

// ---- VeeR EL2: DMI ----
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/dmi/dmi_mux.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/dmi/dmi_wrapper.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/dmi/dmi_jtag_to_core_sync.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/dmi/rvjtag_tap.v

// ---- VeeR EL2: IFU ----
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/ifu/el2_ifu_aln_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/ifu/el2_ifu_compress_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/ifu/el2_ifu_ifc_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/ifu/el2_ifu_bp_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/ifu/el2_ifu_ic_mem.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/ifu/el2_ifu_mem_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/ifu/el2_ifu_iccm_mem.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/ifu/el2_ifu.sv

// ---- VeeR EL2: DEC ----
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/dec/el2_dec_decode_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/dec/el2_dec_gpr_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/dec/el2_dec_ib_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/dec/el2_dec_pmp_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/dec/el2_dec_tlu_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/dec/el2_dec_trigger.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/dec/el2_dec.sv

// ---- VeeR EL2: EXU ----
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/exu/el2_exu_alu_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/exu/el2_exu_mul_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/exu/el2_exu_div_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/exu/el2_exu.sv

// ---- VeeR EL2: LSU ----
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lsu/el2_lsu.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lsu/el2_lsu_clkdomain.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lsu/el2_lsu_addrcheck.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lsu/el2_lsu_lsc_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lsu/el2_lsu_stbuf.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lsu/el2_lsu_bus_buffer.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lsu/el2_lsu_bus_intf.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lsu/el2_lsu_ecc.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lsu/el2_lsu_dccm_mem.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lsu/el2_lsu_dccm_ctl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/lsu/el2_lsu_trigger.sv

// ---- VeeR EL2: DBG ----
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/dbg/el2_dbg.sv

// ---- VeeR EL2: top-level ----
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/el2_lockstep_pkg.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/el2_veer_lockstep.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/el2_mem.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/el2_pic_ctrl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/el2_dma_ctrl.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/el2_pmp.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/el2_veer.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/Cores-VeeR-EL2/design/el2_veer_wrapper.sv

// =============================================================================
// UART IP Core
// =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/uart/rtl/axi_internal_fifo.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/uart/rtl/uart_parity_bit_compute.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/uart/rtl/uart_controller.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/uart/rtl/uart_receiver.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/uart/rtl/uart_transmitter.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/uart/rtl/axi_uart_top.v

// =============================================================================
// AES Engine
// =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/aes/aes_rcon.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/aes/aes_sbox.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/aes/aes_inv_sbox.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/aes/aes_key_expand_128.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/aes/aes_cipher_top.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/aes/aes_inv_cipher_top.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/aes_veer_adapter.v

// =============================================================================
// DMA Controller  (packages first, then CSR shim, then RTL)
// =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/inc/amba_axi_pkg.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/inc/dma_utils_pkg.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen_default_register_shim.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/csr_dma.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/dma_fifo.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/dma_fsm.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/dma_streamer.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/dma_axi_if.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/dma_func_wrapper.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/dma_axi_wrapper.sv

// =============================================================================
// Watchdog Timer
// =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/WDT/EF_WDT32.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/WDT/ef_wdt32_axi_wrapper.v

// =============================================================================
// GPIO (gpio_reg_pkg.sv MUST precede gpio_reg_top.sv and gpio.sv)
// =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/GPIO/gpio_reg_pkg.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/GPIO/gpio_input_stage.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/GPIO/gpio_reg_top.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/GPIO/gpio.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/gpio_axi_wrapper.v

// =============================================================================
// System Timer (timer_core.sv only — rv_timer.sv excluded, needs OpenTitan TLUL)
// =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/System_Timer/timer_core.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/timer_axi_wrapper.v

// =============================================================================
// AXI Interconnect + AXI4 → AXI4-Lite Bridge
// =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/Interconnect/priority_encoder.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/Interconnect/arbiter.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/Interconnect/axi_interconnect.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/Interconnect/axi_interconnect_wrap_2x6.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/axi4_to_axilite_bridge.v

// =============================================================================
// Full SoC Top-Level
// (axi_dwidth_converter_64to32 and ef_wdt32_axi_wrapper are inlined inside this file)
// =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/veer2_dma_aes_wdt_uart_gpio_timer.v

// =============================================================================
// Testbench — MUST be last
// =============================================================================
/home/student/Documents/SOC_Datalogger_project/TB_files/veer2_dma_aes_wdt_uart_gpio_timer_tb.sv
