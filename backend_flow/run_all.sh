#!/usr/bin/env bash
set -euo pipefail

FLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${FLOW_DIR}/logs"

mkdir -p "${LOG_DIR}/dc" "${LOG_DIR}/icc2" "${LOG_DIR}/pt"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

fail() {
  printf '[%s] ERROR: %s\n' "$(timestamp)" "$*" >&2
  exit 1
}

run_stage() {
  local stage_name="$1"
  local tool_bin="$2"
  local script_name="$3"
  local log_file="$4"

  command -v "${tool_bin}" >/dev/null 2>&1 || fail "未找到 ${tool_bin}，请先加载 Synopsys 工具环境。"
  log "开始执行 ${stage_name}，日志: ${log_file}"
  if ! "${tool_bin}" -f "${FLOW_DIR}/${script_name}" | tee "${log_file}"; then
    fail "${stage_name} 执行失败，请检查 ${log_file}"
  fi
  log "${stage_name} 执行完成"
}

log "初始化输出目录"

run_stage "Design Compiler 综合" "dc_shell" "synth_dc.tcl" "${LOG_DIR}/dc/run_all_dc.log"
run_stage "IC Compiler II 布局布线" "icc2_shell" "pnr_icc2.tcl" "${LOG_DIR}/icc2/run_all_icc2.log"
run_stage "PrimeTime 时序签核" "pt_shell" "signoff_pt.tcl" "${LOG_DIR}/pt/run_all_pt.log"

log "RTL-to-GDSII 流程全部完成"
