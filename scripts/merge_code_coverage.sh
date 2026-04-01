#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODE_COV_DIR="${ROOT_DIR}/reports/code_coverage"
SUMMARY_JSON="${CODE_COV_DIR}/summary.json"
REPORT_DIR="${CODE_COV_DIR}/urgReport"

mkdir -p "${CODE_COV_DIR}"

if [[ "${ENABLE_CODE_COVERAGE:-0}" != "1" ]]; then
    cat > "${SUMMARY_JSON}" <<'EOF'
{"status":"not_run","reason":"ENABLE_CODE_COVERAGE was not set for this regression run."}
EOF
    exit 0
fi

if ! command -v urg >/dev/null 2>&1; then
    cat > "${SUMMARY_JSON}" <<'EOF'
{"status":"environment_limited","reason":"Synopsys urg is not available in PATH, so code coverage could not be merged."}
EOF
    exit 0
fi

mapfile -t vdbs < <(find "${CODE_COV_DIR}" -maxdepth 1 -type d -name '*.vdb' | sort)
if [[ "${#vdbs[@]}" -eq 0 ]]; then
    cat > "${SUMMARY_JSON}" <<'EOF'
{"status":"not_run","reason":"No per-test VDB directories were produced."}
EOF
    exit 0
fi

urg -full64 -dir "${vdbs[@]}" -report "${REPORT_DIR}" >/dev/null 2>&1 || {
    cat > "${SUMMARY_JSON}" <<'EOF'
{"status":"environment_limited","reason":"urg failed to merge the generated VDBs in this environment."}
EOF
    exit 0
}

dashboard="${REPORT_DIR}/dashboard.html"
overall_score=""
if [[ -f "${dashboard}" ]]; then
    overall_score="$(
        python3 - "${dashboard}" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
match = re.search(
    r"Total Coverage Summary.*?<td class=\"s\d+ cl rt\">\s*([0-9.]+)\s*</td>",
    text,
    re.S,
)
print(match.group(1) if match else "")
PY
    )"
fi

cat > "${SUMMARY_JSON}" <<EOF
{"status":"available","metrics":{"merged_vdbs":"${#vdbs[@]}","report_dir":"${REPORT_DIR}","overall_score":"${overall_score:-unknown}","metrics_enabled":"${CM_METRICS:-line+cond+fsm+tgl+branch}"},"notes":"Merged code coverage report was generated successfully."}
EOF
