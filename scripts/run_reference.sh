#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${ROOT_DIR}/logs"

MEM_FILE="${1:-${ROOT_DIR}/sw/mult8.hex}"
REF_TRACE="${2:-${LOG_DIR}/ref_trace.txt}"
REF_SUMMARY="${3:-${LOG_DIR}/ref_summary.txt}"
REF_EVENTS="${4:-}"
REF_MAX_STEPS="${REF_MAX_STEPS:-2048}"
REF_HALT_REPEAT_THRESHOLD="${REF_HALT_REPEAT_THRESHOLD:-3}"

mkdir -p "${LOG_DIR}"

cmd=(
    python3 "${ROOT_DIR}/model/reference_model.py"
    --hex "${MEM_FILE}"
    --trace-out "${REF_TRACE}"
    --summary-out "${REF_SUMMARY}"
    --max-steps "${REF_MAX_STEPS}"
    --halt-repeat-threshold "${REF_HALT_REPEAT_THRESHOLD}"
)

if [[ -n "${REF_EVENTS}" ]]; then
    cmd+=(--events-out "${REF_EVENTS}")
fi

"${cmd[@]}"
