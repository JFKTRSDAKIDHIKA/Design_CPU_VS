#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/vcs_basic"
LOG_DIR="${ROOT_DIR}/logs"
SIM_DIR="${ROOT_DIR}/sim"

MEM_FILE="${1:-${ROOT_DIR}/sw/mult8.hex}"
STEP_MODE="${STEP_MODE:-${2:-cycle}}"
STEPS="${STEPS:-${3:-1}}"
MEM_START="${MEM_START:-${4:-0000}}"
MEM_WORDS="${MEM_WORDS:-${5:-16}}"
SIM_LOG="${LOG_DIR}/basic_rtl_run.log"
VPD_FILE="${SIM_DIR}/basic_cpu_tb.vpd"

mkdir -p "${LOG_DIR}" "${SIM_DIR}"

if [[ ! -x "${BUILD_DIR}/simv" ]]; then
    "${ROOT_DIR}/scripts/compile_basic_vcs.sh"
fi

echo "[run_basic_vcs] running mem=${MEM_FILE} step_mode=${STEP_MODE} steps=${STEPS}"
(
    cd "${ROOT_DIR}"
    "${BUILD_DIR}/simv" \
        -no_save \
        +mem="${MEM_FILE}" \
        +step_mode="${STEP_MODE}" \
        +steps="${STEPS}" \
        +mem_start="${MEM_START}" \
        +mem_words="${MEM_WORDS}" \
        +vpd="${VPD_FILE}" \
        -l "${SIM_LOG}"
)

echo "[run_basic_vcs] simulation finished"
echo "[run_basic_vcs] log: ${SIM_LOG}"
