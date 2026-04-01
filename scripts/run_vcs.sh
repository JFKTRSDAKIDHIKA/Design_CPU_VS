#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/vcs"
LOG_DIR="${ROOT_DIR}/logs"
SIM_DIR="${ROOT_DIR}/sim"

MEM_FILE="${1:-${ROOT_DIR}/sw/mult8.hex}"
REF_TRACE="${2:-${LOG_DIR}/ref_trace.txt}"
REF_SUMMARY="${3:-${LOG_DIR}/ref_summary.txt}"
COVERAGE_REPORT="${4:-${ROOT_DIR}/reports/coverage/default.txt}"
UVM_TESTNAME="${5:-cpu_smoke_test}"
SIM_LOG="${LOG_DIR}/rtl_run.log"
VPD_FILE="${SIM_DIR}/cpu_uvm_top.vpd"

mkdir -p "${LOG_DIR}" "${SIM_DIR}"

if [[ ! -x "${BUILD_DIR}/simv" ]]; then
    "${ROOT_DIR}/scripts/compile_vcs.sh"
fi

mkdir -p "$(dirname "${COVERAGE_REPORT}")"

echo "[run_vcs] running with memory image ${MEM_FILE}"
(
    cd "${ROOT_DIR}"
    "${BUILD_DIR}/simv" \
        +UVM_TESTNAME="${UVM_TESTNAME}" \
        +program_hex="${MEM_FILE}" \
        +ref_trace="${REF_TRACE}" \
        +ref_summary="${REF_SUMMARY}" \
        +coverage_report="${COVERAGE_REPORT}" \
        -l "${SIM_LOG}"
)

echo "[run_vcs] simulation finished"
echo "[run_vcs] log: ${SIM_LOG}"
