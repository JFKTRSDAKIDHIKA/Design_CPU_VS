#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/vcs"
LOG_DIR="${ROOT_DIR}/logs"
FILELIST="${BUILD_DIR}/vcs_files.f"
COMPILE_LOG="${LOG_DIR}/compile_vcs.log"
ENABLE_CODE_COVERAGE="${ENABLE_CODE_COVERAGE:-0}"
CM_METRICS="${CM_METRICS:-line+cond+fsm+tgl+branch}"

mkdir -p "${BUILD_DIR}" "${LOG_DIR}" "${ROOT_DIR}/sim"

cp "${ROOT_DIR}/vsrc/files.f" "${FILELIST}"
cat >> "${FILELIST}" <<'EOF'
uvm_tb/interfaces/cpu_core_if.sv
uvm_tb/pkg/cpu_uvm_pkg.sv
uvm_tb/top/cpu_uvm_top.sv
EOF

echo "[compile_vcs] compiling with filelist ${FILELIST}"
cm_args=()
if [[ "${ENABLE_CODE_COVERAGE}" == "1" ]]; then
    cm_args=(-cm "${CM_METRICS}" -cm_dir "${BUILD_DIR}/compile.vdb")
fi
(
    cd "${ROOT_DIR}"
    vcs -full64 -sverilog -timescale=1ns/1ps -debug_access+all -ntb_opts uvm-1.2 \
        +incdir+${ROOT_DIR} \
        -o "${BUILD_DIR}/simv" \
        -top cpu_uvm_top \
        -l "${COMPILE_LOG}" \
        "${cm_args[@]}" \
        -f "${FILELIST}"
)

echo "[compile_vcs] build complete: ${BUILD_DIR}/simv"
