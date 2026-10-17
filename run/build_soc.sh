#!/usr/bin/env bash
# =============================================================================
# build_soc.sh — Build + simulate veer2_dma_aes_wdt_uart_gpio_timer
#
# Uses: run/runf.f
# DUT : veer2_dma_aes_wdt_uart_gpio_timer
# TB  : veer2_dma_aes_wdt_uart_gpio_timer_tb
#
# Usage (from the run/ directory):
#   chmod +x build_soc.sh
#   ./build_soc.sh               # compile + BFM directed tests (default)
#   ./build_soc.sh bfm           # same as above (explicit)
#   ./build_soc.sh fw            # compile + firmware C test (+FWONLY +HEX=...)
#   ./build_soc.sh compile_only  # compile only, no simulation
#   ./build_soc.sh sim_only      # re-simulate existing binary (BFM mode)
#   ./build_soc.sh sim_fw        # re-simulate existing binary (firmware mode)
#   ./build_soc.sh verdi         # compile + BFM sim + open Verdi
#   ./build_soc.sh verdi_fw      # compile + firmware sim + open Verdi
#   ./build_soc.sh clean         # remove build artifacts
#
# Firmware hex:
#   The testbench loads soc_full_test.hex from the path passed via +HEX=.
#   This script always passes the absolute path to Scripts/soc_full_test.hex.
#   A symlink run/soc_full_test.hex is also created for fallback.
#
# Prerequisites:
#   • Synopsys VCS on PATH (source setup before running)
#   • soc_full_test.hex already built in Scripts/ (see Scripts/Makefile)
# =============================================================================

set -euo pipefail

# ---- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(dirname "${SCRIPT_DIR}")"
RUN_DIR="${SCRIPT_DIR}"

FILELIST="${RUN_DIR}/runf.f"
SIMV_NAME="simv_soc"
SIMV_BIN="${RUN_DIR}/${SIMV_NAME}"
COMPILE_LOG="${RUN_DIR}/compile_soc.log"
SIM_LOG_BFM="${RUN_DIR}/sim_soc_bfm.log"
SIM_LOG_FW="${RUN_DIR}/sim_soc_fw.log"

# Firmware hex — built by Scripts/Makefile; also copied to run/ for fallback
HEX_SRC="${PROJ_ROOT}/Scripts/soc_full_test.hex"
HEX_LINK="${RUN_DIR}/soc_full_test.hex"

# ---- Helpers -----------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { err "$*"; exit 1; }

# ---- Sanity checks -----------------------------------------------------------
check_vcs() {
    command -v vcs >/dev/null 2>&1 || die "vcs not found on PATH. Source your VCS setup script first."
}

# Create symlink so TB can find hex via relative path fallback
ensure_hex_link() {
    if [[ -f "${HEX_SRC}" ]]; then
        ln -sf "${HEX_SRC}" "${HEX_LINK}"
        info "Hex symlink: ${HEX_LINK} -> ${HEX_SRC}"
    else
        warn "Hex not found at ${HEX_SRC} — firmware mode will fail."
        warn "Build firmware first: cd Scripts && make"
    fi
}

# ---- Clean -------------------------------------------------------------------
do_clean() {
    info "Removing build artifacts..."
    cd "${RUN_DIR}"
    rm -rf "${SIMV_BIN}" "${SIMV_NAME}.daidir" csrc \
           compile_soc.log sim_soc_bfm.log sim_soc_fw.log \
           dump.vcd dump.fsdb ucli.key novas_dump.log
    info "Clean complete."
}

# ---- Compile -----------------------------------------------------------------
do_compile() {
    check_vcs
    [[ -f "${FILELIST}" ]] || die "Filelist not found: ${FILELIST}"
    ensure_hex_link

    info "Compiling..."
    info "  Filelist : ${FILELIST}"
    info "  Binary   : ${SIMV_BIN}"
    info "  Log      : ${COMPILE_LOG}"

    cd "${RUN_DIR}"
    rm -rf "${SIMV_BIN}" "${SIMV_NAME}.daidir" csrc

    if vcs -full64 -sverilog \
           -debug_access+all -kdb \
           -timescale=1ns/1ps \
           -l "${COMPILE_LOG}" \
           -f "${FILELIST}" \
           -o "${SIMV_NAME}"; then
        info "Compile SUCCEEDED → ${SIMV_BIN}"
    else
        err "Compile FAILED. See: ${COMPILE_LOG}"
        echo "--- Last 40 lines of compile log ---"
        tail -40 "${COMPILE_LOG}" 2>/dev/null || true
        exit 1
    fi
}

# ---- Parse + print results ---------------------------------------------------
print_results() {
    local log="$1"
    local pass_count fail_count
    pass_count=$(grep -c '^\[PASS\]' "${log}" 2>/dev/null || true)
    fail_count=$(grep -c '^\[FAIL\]' "${log}" 2>/dev/null || true)
    echo ""
    echo "======================================================="
    echo "  Simulation complete"
    printf "  PASS  : %s\n" "${pass_count:-0}"
    printf "  FAIL  : %s\n" "${fail_count:-0}"
    if [[ "${fail_count:-0}" -eq 0 ]]; then
        echo -e "  STATUS: ${GREEN}** ALL TESTS PASSED **${NC}"
    else
        echo -e "  STATUS: ${RED}!! ${fail_count} TEST(S) FAILED !!${NC}"
    fi
    echo "======================================================="
    [[ "${fail_count:-0}" -eq 0 ]]
}

# ---- BFM Simulation ----------------------------------------------------------
do_sim_bfm() {
    [[ -x "${SIMV_BIN}" ]] || die "Binary not found: ${SIMV_BIN}. Run compile first."
    info "Running BFM directed tests..."
    info "  Log : ${SIM_LOG_BFM}"
    cd "${RUN_DIR}"
    set +e
    "${SIMV_BIN}" -l "${SIM_LOG_BFM}" 2>&1 | tee "${SIM_LOG_BFM}"
    set -e
    print_results "${SIM_LOG_BFM}"
}

# ---- Firmware Simulation -----------------------------------------------------
do_sim_fw() {
    [[ -x "${SIMV_BIN}" ]] || die "Binary not found: ${SIMV_BIN}. Run compile first."
    [[ -f "${HEX_SRC}" ]] || die "Hex not found: ${HEX_SRC}. Build firmware first: cd Scripts && make"
    info "Running firmware (C test) simulation..."
    info "  Hex : ${HEX_SRC}"
    info "  Log : ${SIM_LOG_FW}"
    cd "${RUN_DIR}"
    set +e
    "${SIMV_BIN}" +FWONLY "+HEX=${HEX_SRC}" -l "${SIM_LOG_FW}" 2>&1 | tee "${SIM_LOG_FW}"
    set -e
    # Check for firmware pass/fail codes in the log
    if grep -q '\[TB-FW\].*ALL FIRMWARE CHECKS PASSED' "${SIM_LOG_FW}" 2>/dev/null; then
        echo ""
        echo "======================================================="
        echo -e "  STATUS: ${GREEN}** FIRMWARE ALL PASSED (0x900D) **${NC}"
        echo "======================================================="
    elif grep -q 'FIRMWARE FAILED' "${SIM_LOG_FW}" 2>/dev/null; then
        echo ""
        echo "======================================================="
        echo -e "  STATUS: ${RED}!! FIRMWARE FAILED !!${NC}"
        echo "======================================================="
        exit 1
    else
        print_results "${SIM_LOG_FW}"
    fi
}

# ---- Verdi helpers -----------------------------------------------------------
do_sim_bfm_verdi() {
    [[ -x "${SIMV_BIN}" ]] || die "Binary not found: ${SIMV_BIN}. Run compile first."
    info "Running BFM sim with Verdi..."
    cd "${RUN_DIR}"
    "${SIMV_BIN}" -verdi -l "${SIM_LOG_BFM}"
}

do_sim_fw_verdi() {
    [[ -x "${SIMV_BIN}" ]] || die "Binary not found: ${SIMV_BIN}. Run compile first."
    [[ -f "${HEX_SRC}" ]] || die "Hex not found: ${HEX_SRC}. Build firmware first."
    info "Running firmware sim with Verdi..."
    cd "${RUN_DIR}"
    "${SIMV_BIN}" +FWONLY "+HEX=${HEX_SRC}" -verdi -l "${SIM_LOG_FW}"
}

# ---- Main dispatch -----------------------------------------------------------
MODE="${1:-bfm}"

case "${MODE}" in
    all|bfm)
        do_compile
        do_sim_bfm
        ;;
    fw|firmware)
        do_compile
        do_sim_fw
        ;;
    compile_only|compile)
        do_compile
        ;;
    sim_only|sim|sim_bfm)
        do_sim_bfm
        ;;
    sim_fw)
        do_sim_fw
        ;;
    verdi)
        do_compile
        do_sim_bfm_verdi
        ;;
    verdi_fw)
        do_compile
        do_sim_fw_verdi
        ;;
    clean)
        do_clean
        ;;
    *)
        cat <<EOF
Usage: $0 [MODE]

Modes:
  bfm          — compile + run BFM directed tests TC01–TC28 (default)
  fw           — compile + run firmware C test (soc_full_test.hex)
  compile_only — VCS compile only (no simulation)
  sim_only     — re-simulate with BFM tests (no recompile)
  sim_fw       — re-simulate with firmware (no recompile)
  verdi        — compile + BFM sim + open Verdi waveform viewer
  verdi_fw     — compile + firmware sim + open Verdi waveform viewer
  clean        — remove all build artifacts

Firmware hex path: ${HEX_SRC}
Build firmware:    cd \$(dirname \$0)/../Scripts && make
EOF
        exit 1
        ;;
esac
