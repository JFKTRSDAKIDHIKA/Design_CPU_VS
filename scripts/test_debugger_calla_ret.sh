#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEX_FILE="${ROOT_DIR}/reports/hex/calla_ret.hex"
LAYOUT_FILE="${ROOT_DIR}/reports/layouts/calla_ret.txt"
DEBUG_LOG="${ROOT_DIR}/logs/debugger_calla_ret.log"

mkdir -p "${ROOT_DIR}/reports/hex" "${ROOT_DIR}/reports/layouts" "${ROOT_DIR}/logs"

python3 "${ROOT_DIR}/model/assembler.py" \
    "${ROOT_DIR}/sw/tests/direct/calla_ret.asm" \
    --hex-out "${HEX_FILE}" \
    --layout-out "${LAYOUT_FILE}"

make -C "${ROOT_DIR}" debug-build >/dev/null

(
cd "${ROOT_DIR}"
cat <<'EOF_CMDS' | "${ROOT_DIR}/build/vcs_debug/simv" -no_save >"${DEBUG_LOG}" 2>&1
load reports/hex/calla_ret.hex
si
si
si
si
si
info reg
si 3
info reg
si 2
info reg
quit
EOF_CMDS
)

grep -F "[si] stop=step complete pc=0x0002" "${DEBUG_LOG}" >/dev/null
grep -F "[si] stop=step complete pc=0x0004" "${DEBUG_LOG}" >/dev/null
grep -F "[si] stop=step complete pc=0x0006" "${DEBUG_LOG}" >/dev/null
grep -F "[si] stop=step complete pc=0x0008" "${DEBUG_LOG}" >/dev/null
grep -F "[si] stop=step complete pc=0x000d" "${DEBUG_LOG}" >/dev/null
grep -E "R15 = 0x000a" "${DEBUG_LOG}" >/dev/null
grep -F "[si] stop=step complete pc=0x000a" "${DEBUG_LOG}" >/dev/null
grep -F "[si] stop=step complete pc=0x000c" "${DEBUG_LOG}" >/dev/null
grep -E "R 4 = 0x000a|R4 = 0x000a" "${DEBUG_LOG}" >/dev/null
grep -E "R 0 = 0x0004|R0 = 0x0004" "${DEBUG_LOG}" >/dev/null

echo "debugger-calla-ret|PASS|${DEBUG_LOG}"
