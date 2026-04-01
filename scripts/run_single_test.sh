#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${ROOT_DIR}/reports"
LOG_DIR="${ROOT_DIR}/logs"
ENABLE_CODE_COVERAGE="${ENABLE_CODE_COVERAGE:-0}"
CM_METRICS="${CM_METRICS:-line+cond+fsm+tgl+branch}"

TEST_NAME="${1:?test name required}"
UVM_TESTNAME="${2:?uvm test required}"
ASM_FILE="${3:?asm file required}"
SEED="${4:-1}"

HEX_FILE="${REPORT_DIR}/hex/${TEST_NAME}.hex"
LAYOUT_FILE="${REPORT_DIR}/layouts/${TEST_NAME}.txt"
REF_TRACE="${REPORT_DIR}/reference/${TEST_NAME}_trace.txt"
REF_SUMMARY="${REPORT_DIR}/reference/${TEST_NAME}_summary.txt"
REF_EVENTS="${REPORT_DIR}/reference/${TEST_NAME}_events.jsonl"
COVERAGE_REPORT="${REPORT_DIR}/coverage/${TEST_NAME}.json"
SIM_LOG="${LOG_DIR}/uvm/${TEST_NAME}.log"
CODE_COV_DIR="${REPORT_DIR}/code_coverage/${TEST_NAME}.vdb"

mkdir -p "${REPORT_DIR}/hex" "${REPORT_DIR}/layouts" "${REPORT_DIR}/reference" "${REPORT_DIR}/coverage" "${REPORT_DIR}/code_coverage" "${LOG_DIR}/uvm"

python3 "${ROOT_DIR}/model/assembler.py" \
    "${ROOT_DIR}/${ASM_FILE}" \
    --hex-out "${HEX_FILE}" \
    --layout-out "${LAYOUT_FILE}"

"${ROOT_DIR}/scripts/run_reference.sh" "${HEX_FILE}" "${REF_TRACE}" "${REF_SUMMARY}" "${REF_EVENTS}"

(
    cd "${ROOT_DIR}"
    simv_args=(
        "${ROOT_DIR}/build/vcs/simv"
        +ntb_random_seed="${SEED}"
        +UVM_TESTNAME="${UVM_TESTNAME}"
        +program_hex="${HEX_FILE}"
        +ref_trace="${REF_TRACE}"
        +ref_summary="${REF_SUMMARY}"
        +ref_events="${REF_EVENTS}"
        +coverage_report="${COVERAGE_REPORT}"
        -l "${SIM_LOG}"
    )
    if [[ "${ENABLE_CODE_COVERAGE}" == "1" ]]; then
        simv_args+=(-cm "${CM_METRICS}" -cm_name "${TEST_NAME}" -cm_dir "${CODE_COV_DIR}")
    fi
    "${simv_args[@]}"
)

if rg -q "^(UVM_ERROR|UVM_FATAL) [^:]|^Error-" "${SIM_LOG}"; then
    echo "${TEST_NAME}|FAIL|${SIM_LOG}|${COVERAGE_REPORT}"
    exit 1
fi

echo "${TEST_NAME}|PASS|${SIM_LOG}|${COVERAGE_REPORT}"
