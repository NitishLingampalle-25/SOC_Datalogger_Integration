#!/usr/bin/env bash
# =============================================================================
# build_full_soc.sh
# Build + simulate: veer2_dma_aes_wdt_uart_gpio_timer_tb
#
# Usage (from the run/ directory):
#   chmod +x build_full_soc.sh
#   ./build_full_soc.sh               # compile + simulate
#   ./build_full_soc.sh verdi         # compile + simulate + open Verdi
#   ./build_full_soc.sh compile_only  # compile only, no simulation
#   ./build_full_soc.sh sim_only      # re-simulate existing binary
#   ./build_full_soc.sh firmware      # compile C firmware (soc_full_test.c)
#   ./build_full_soc.sh clean         # remove build artifacts
#
# Prerequisites:
#   • Synopsys VCS installed and on PATH
#   • riscv64-unknown-elf-gcc toolchain (for 'firmware' target only)
#   • Cores-VeeR-EL2 snapshot generated at the path in run_full_soc.f
# =============================================================================

set -euo pipefail

# ---- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(dirname "${SCRIPT_DIR}")"
RUN_DIR="${SCRIPT_DIR}"

FILELIST="${RUN_DIR}/run_full_soc.f"
SIMV_NAME="simv_full_soc"
SIMV_BIN="${RUN_DIR}/${SIMV_NAME}"
COMPILE_LOG="${RUN_DIR}/compile_full_soc.log"
SIM_LOG="${RUN_DIR}/sim_full_soc.log"

SNAPSHOT_DIR="/home/student/034_Honours/Cores-VeeR-EL2/snapshots/default"
# NOTE: The VeeR EL2 core lives outside SOC_Datalogger_project at the path above.
#       This matches all other filelists in this project (runf.f, run_soc_top.f).
#       If you relocate the core, update this variable and run_full_soc.f together.

# Firmware paths
FW_DIR="${PROJ_ROOT}/hex_files"
FW_SRC="${FW_DIR}/soc_full_test.c"
CRT0="${FW_DIR}/crt0.S"
FW_ELF="${FW_DIR}/soc_full_test.elf"
FW_HEX="${FW_DIR}/soc_full_test.hex"
FW_DIS="${FW_DIR}/soc_full_test.dis"
LINK_LD="${SNAPSHOT_DIR}/link.ld"

CROSS="riscv64-unknown-elf"
CC="${CROSS}-gcc"
OBJCOPY="${CROSS}-objcopy"
OBJDUMP="${CROSS}-objdump"

# ---- Helpers -----------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { err "$*"; exit 1; }

# ---- Sanity checks -----------------------------------------------------------
check_vcs() {
    command -v vcs >/dev/null 2>&1 || die "vcs not found on PATH. Source your VCS setup script first."
}

check_filelist() {
    [[ -f "${FILELIST}" ]] || die "Filelist not found: ${FILELIST}"
}

# ---- Clean -------------------------------------------------------------------
do_clean() {
    info "Removing build artifacts..."
    cd "${RUN_DIR}"
    rm -rf "${SIMV_BIN}" "${SIMV_NAME}.daidir" csrc \
           compile_full_soc.log sim_full_soc.log \
           full_soc_tb.vcd full_soc_tb.fsdb \
           ucli.key novas_dump.log
    info "Clean complete."
}

# ---- Firmware ----------------------------------------------------------------
do_firmware() {
    info "Compiling C firmware: ${FW_SRC}"
    command -v "${CC}" >/dev/null 2>&1 || die "${CC} not found. Install the RISC-V toolchain."
    [[ -f "${LINK_LD}" ]] || die "Link script not found: ${LINK_LD}. Run 'make snapshot' in Cores-VeeR-EL2 first."
    [[ -f "${FW_SRC}" ]] || die "Firmware source not found: ${FW_SRC}"

    ${CC} \
        -march=rv32imc_zicsr -mabi=ilp32 \
        -O1 -g \
        -static -nostdlib -nostartfiles \
        -Wall -Wextra \
        -ffreestanding \
        -fno-common \
        -fomit-frame-pointer \
        -T "${LINK_LD}" \
        "${FW_SRC}" "${CRT0}" \
        -o "${FW_ELF}"

    ${OBJCOPY} -O ihex    "${FW_ELF}" "${FW_HEX}"
    ${OBJCOPY} -O verilog "${FW_ELF}" "${FW_DIR}/soc_full_test.vmem"
    ${OBJDUMP} -d -S -M no-aliases "${FW_ELF}" > "${FW_DIS}"

    info "Firmware built:"
    info "  ELF  : ${FW_ELF}"
    info "  HEX  : ${FW_HEX}"
    info "  DIS  : ${FW_DIS}"
}

# ---- Compile -----------------------------------------------------------------
do_compile() {
    check_vcs
    check_filelist
    info "Compiling design + testbench..."
    info "  Filelist : ${FILELIST}"
    info "  Binary   : ${SIMV_BIN}"
    info "  Log      : ${COMPILE_LOG}"

    cd "${RUN_DIR}"

    # Remove stale binary to avoid false-negative sim from cached build
    rm -rf "${SIMV_BIN}" "${SIMV_NAME}.daidir" csrc

    local vcs_flags=(
        -full64
        -sverilog
        -debug_access+all
        -kdb
        -timescale=1ns/1ps
        -l "${COMPILE_LOG}"
        -f "${FILELIST}"
        -o "${SIMV_NAME}"
    )

    if vcs "${vcs_flags[@]}"; then
        info "Compile SUCCEEDED  → ${SIMV_BIN}"
    else
        err "Compile FAILED.  See: ${COMPILE_LOG}"
        echo ""
        echo "--- Last 30 lines of compile log ---"
        tail -30 "${COMPILE_LOG}" 2>/dev/null || true
        exit 1
    fi
}

# ---- Simulate ----------------------------------------------------------------
do_sim() {
    [[ -x "${SIMV_BIN}" ]] || die "Simulation binary not found: ${SIMV_BIN}. Run compile first."
    info "Running simulation..."
    info "  Binary : ${SIMV_BIN}"
    info "  Log    : ${SIM_LOG}"

    cd "${RUN_DIR}"

    if "${SIMV_BIN}" -l "${SIM_LOG}" 2>&1 | tee "${SIM_LOG}"; then
        :
    fi

    # Parse pass/fail from stdout
    local pass_count fail_count
    pass_count=$(grep -c '^\[PASS\]' "${SIM_LOG}" 2>/dev/null || echo 0)
    fail_count=$(grep -c '^\[FAIL\]' "${SIM_LOG}" 2>/dev/null || echo 0)

    echo ""
    echo "======================================================="
    echo "  Simulation complete"
    printf "  PASS  : %s\n" "${pass_count}"
    printf "  FAIL  : %s\n" "${fail_count}"
    if [[ "${fail_count}" -eq 0 ]]; then
        echo -e "  STATUS: ${GREEN}** ALL TESTS PASSED **${NC}"
    else
        echo -e "  STATUS: ${RED}!! ${fail_count} TEST(S) FAILED !!${NC}"
    fi
    echo "======================================================="
    echo ""

    [[ "${fail_count}" -eq 0 ]] || exit 1
}

# ---- Simulate with Verdi -----------------------------------------------------
do_sim_verdi() {
    [[ -x "${SIMV_BIN}" ]] || die "Simulation binary not found: ${SIMV_BIN}. Run compile first."
    info "Running simulation with Verdi..."
    cd "${RUN_DIR}"
    "${SIMV_BIN}" -verdi -l "${SIM_LOG}"
}

# ---- Main dispatch -----------------------------------------------------------
MODE="${1:-all}"

case "${MODE}" in
    all)
        do_compile
        do_sim
        ;;
    compile_only|compile)
        do_compile
        ;;
    sim_only|sim)
        do_sim
        ;;
    verdi)
        do_compile
        do_sim_verdi
        ;;
    firmware|fw)
        do_firmware
        ;;
    clean)
        do_clean
        ;;
    *)
        echo "Usage: $0 [all|compile_only|sim_only|verdi|firmware|clean]"
        echo ""
        echo "  all          — compile + simulate (default)"
        echo "  compile_only — VCS compile only"
        echo "  sim_only     — simulate existing binary (no recompile)"
        echo "  verdi        — compile + simulate + open Verdi waveform viewer"
        echo "  firmware     — compile soc_full_test.c → ELF/HEX with riscv64-unknown-elf-gcc"
        echo "  clean        — remove all build artifacts"
        exit 1
        ;;
esac
