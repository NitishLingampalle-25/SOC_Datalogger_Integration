# =============================================================================
# Filelist : run_soc_top.f
# Target   : veer2_dma_aes_wdt_uart_gpio_timer (full SoC top)
# Testbench: tb_soc_top
# Tool     : Synopsys VCS
#
# Compile:
#   cd /home/student/Documents/SOC_Datalogger_project/run
#   vcs -full64 -sverilog -l compile_soc_top.log -f run_soc_top.f -o simv_soc_top
#
# Simulate:
#   ./simv_soc_top -l sim_soc_top.log
#
# With Verdi waveforms:
#   vcs -full64 -sverilog -debug_access+all -kdb -f run_soc_top.f -o simv_soc_top
#   ./simv_soc_top -verdi
# =============================================================================

-sverilog
-timescale=1ns/1ps
+define+RV_BUILD_AXI4
# RV_PHYSICAL: prevents VCS elaborating $error() in beh_lib.sv width-check else-branches
+define+RV_PHYSICAL

# =============================================================================
# Include Directories
# =============================================================================
+incdir+/home/student/Documents/SOC_Datalogger_project/axi-lite_uart-ipcore-develop/src/include
+incdir+/home/student/034_Honours/Cores-VeeR-EL2/snapshots/default
+incdir+/home/student/034_Honours/Cores-VeeR-EL2/design/include
+incdir+/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/inc
+incdir+/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl
+incdir+/home/student/Documents/SOC_Datalogger_project/RTL_files/GPIO

# =============================================================================
# VeeR EL2 Core — global defines & packages (common_defines.vh MUST be first)
# =============================================================================
/home/student/034_Honours/Cores-VeeR-EL2/snapshots/default/common_defines.vh
/home/student/034_Honours/Cores-VeeR-EL2/design/include/el2_def.sv

/home/student/034_Honours/Cores-VeeR-EL2/design/lib/el2_assert.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/el2_mubi_pkg.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lib/el2_mem_if.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lib/el2_prim_generic_buf.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lib/el2_prim_buf.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lib/beh_lib.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lib/mem_lib.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lib/el2_lib.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lib/ahb_to_axi4.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lib/axi4_to_ahb.sv

# =============================================================================
# VeeR EL2 Core — DMI
# =============================================================================
/home/student/034_Honours/Cores-VeeR-EL2/design/dmi/dmi_mux.v
/home/student/034_Honours/Cores-VeeR-EL2/design/dmi/dmi_wrapper.v
/home/student/034_Honours/Cores-VeeR-EL2/design/dmi/dmi_jtag_to_core_sync.v
/home/student/034_Honours/Cores-VeeR-EL2/design/dmi/rvjtag_tap.v

# =============================================================================
# VeeR EL2 Core — sub-blocks
# =============================================================================
/home/student/034_Honours/Cores-VeeR-EL2/design/ifu/el2_ifu_aln_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/ifu/el2_ifu_compress_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/ifu/el2_ifu_ifc_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/ifu/el2_ifu_bp_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/ifu/el2_ifu_ic_mem.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/ifu/el2_ifu_mem_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/ifu/el2_ifu_iccm_mem.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/ifu/el2_ifu.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/dec/el2_dec_decode_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/dec/el2_dec_gpr_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/dec/el2_dec_ib_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/dec/el2_dec_pmp_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/dec/el2_dec_tlu_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/dec/el2_dec_trigger.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/dec/el2_dec.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/exu/el2_exu_alu_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/exu/el2_exu_mul_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/exu/el2_exu_div_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/exu/el2_exu.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lsu/el2_lsu.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lsu/el2_lsu_clkdomain.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lsu/el2_lsu_addrcheck.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lsu/el2_lsu_lsc_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lsu/el2_lsu_stbuf.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lsu/el2_lsu_bus_buffer.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lsu/el2_lsu_bus_intf.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lsu/el2_lsu_ecc.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lsu/el2_lsu_dccm_mem.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lsu/el2_lsu_dccm_ctl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/lsu/el2_lsu_trigger.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/dbg/el2_dbg.sv

# =============================================================================
# VeeR EL2 Core — top-level
# =============================================================================
/home/student/034_Honours/Cores-VeeR-EL2/design/el2_lockstep_pkg.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/el2_veer_lockstep.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/el2_mem.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/el2_pic_ctrl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/el2_dma_ctrl.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/el2_pmp.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/el2_veer.sv
/home/student/034_Honours/Cores-VeeR-EL2/design/el2_veer_wrapper.sv

# =============================================================================
# UART IP Core
# =============================================================================
/home/student/Documents/SOC_Datalogger_project/axi-lite_uart-ipcore-develop/src/rtl/axi_internal_fifo.v
/home/student/Documents/SOC_Datalogger_project/axi-lite_uart-ipcore-develop/src/rtl/uart_parity_bit_compute.v
/home/student/Documents/SOC_Datalogger_project/axi-lite_uart-ipcore-develop/src/rtl/uart_controller.v
/home/student/Documents/SOC_Datalogger_project/axi-lite_uart-ipcore-develop/src/rtl/uart_receiver.v
/home/student/Documents/SOC_Datalogger_project/axi-lite_uart-ipcore-develop/src/rtl/uart_transmitter.v
/home/student/Documents/SOC_Datalogger_project/axi-lite_uart-ipcore-develop/src/rtl/axi_uart_top.v

# =============================================================================
# AES IP Core
# =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/aes/aes_rcon.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/aes/aes_sbox.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/aes/aes_inv_sbox.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/aes/aes_key_expand_128.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/aes/aes_cipher_top.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/aes/aes_inv_cipher_top.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/aes_veer_adapter.v

# =============================================================================
# DMA Controller — packages first, then rggen primitives, then RTL
# =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/inc/amba_axi_pkg.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/inc/dma_utils_pkg.sv

/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_mux.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_or_reducer.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_address_decoder.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_adapter_common.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_axi4lite_skid_buffer.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_axi4lite_bridge.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_axi4lite_adapter.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_bit_field.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_bit_field_w01trg.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_bit_field_counter.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_register_common.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_default_register.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_external_register.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_indirect_register.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/rggen-verilog-rtl/rggen_maskable_register.v

/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/csr_dma.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/dma_fifo.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/dma_fsm.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/dma_streamer.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/dma_axi_if.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/dma_func_wrapper.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/DMA/dma_axi_wrapper.sv

# =============================================================================
# Watchdog Timer (EF_WDT32)
# ef_wdt32_axi_wrapper.v is embedded inside the top module — not compiled separately
# Only the bare core is needed if used standalone; the wrapper is inlined in the top.
# =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/WDT/EF_WDT32.v

# =============================================================================
# GPIO IP Core
# gpio_reg_pkg.sv defines package gpio_reg_pkg (GPIOCount=32) — must be first
# =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/GPIO/gpio_reg_pkg.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/GPIO/gpio_input_stage.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/GPIO/gpio_reg_top.sv
/home/student/Documents/SOC_Datalogger_project/RTL_files/GPIO/gpio.sv

# =============================================================================
# System Timer
# rv_timer.sv requires OpenTitan TLUL stack — NOT included.
# Only timer_core.sv (zero dependencies) is compiled; the AXI wrapper is used.
# =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/System_Timer/timer_core.sv

# =============================================================================
# AXI Interconnect & AXI4→AXI4-Lite Bridge
# =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/Interconnect/priority_encoder.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/Interconnect/arbiter.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/Interconnect/axi_interconnect.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/Interconnect/axi_interconnect_wrap_2x6.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/axi4_to_axilite_bridge.v

# =============================================================================
# SoC Wrapper Modules (GPIO and Timer AXI wrappers)
# These are self-contained wrappers written for this project.
# =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/gpio_axi_wrapper.v
/home/student/Documents/SOC_Datalogger_project/RTL_files/timer_axi_wrapper.v

# =============================================================================
# SoC Top-Level: complete integrated module (all 9 IPs)
# Note: ef_wdt32_axi_wrapper and axi_dwidth_converter_64to32 are defined
#       as inline modules at the bottom of this file (guard-protected).
# =============================================================================
/home/student/Documents/SOC_Datalogger_project/RTL_files/veer2_dma_aes_wdt_uart_gpio_timer.v

# =============================================================================
# Testbench
# =============================================================================
/home/student/Documents/SOC_Datalogger_project/TB_files/tb_soc_top.sv
