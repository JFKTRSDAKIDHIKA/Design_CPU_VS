#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/vcs_basic"
LOG_DIR="${ROOT_DIR}/logs"
FILELIST="${BUILD_DIR}/vcs_basic_files.f"
COMPILE_LOG="${LOG_DIR}/compile_basic_vcs.log"

mkdir -p "${BUILD_DIR}" "${LOG_DIR}" "${ROOT_DIR}/sim"

cp "${ROOT_DIR}/vsrc/files.f" "${FILELIST}"
cat >> "${FILELIST}" <<'EOF'
tb/memory_model.sv
tb/basic_cpu_tb.sv
EOF

echo "[compile_basic_vcs] compiling basic debug TB with filelist ${FILELIST}"
(
    cd "${ROOT_DIR}"
    vcs -full64 -sverilog -timescale=1ns/1ps -debug_access+all \
        +incdir+${ROOT_DIR} \
        -o "${BUILD_DIR}/simv" \
        -top basic_cpu_tb \
        -l "${COMPILE_LOG}" \
        -f "${FILELIST}"
)

echo "[compile_basic_vcs] build complete: ${BUILD_DIR}/simv"
