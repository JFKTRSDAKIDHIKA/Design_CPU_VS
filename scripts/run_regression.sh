#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTLIST="${ROOT_DIR}/scripts/testlist.txt"
REPORT_DIR="${ROOT_DIR}/reports"
RESULTS_FILE="${REPORT_DIR}/regression_summary.txt"
COVERAGE_DIR="${REPORT_DIR}/coverage"
RANDOM_DIR="${ROOT_DIR}/sw/tests/random"
AGGREGATE_BINS="${COVERAGE_DIR}/aggregate_bins.json"
CLOSURE_HISTORY="${COVERAGE_DIR}/closure_history.json"
RANDOM_COUNT="${RANDOM_COUNT:-4}"
RANDOM_SEED_BASE="${RANDOM_SEED_BASE:-100}"
RANDOM_BODY_OPS="${RANDOM_BODY_OPS:-8}"
TARGETED_RANDOM_COUNT="${TARGETED_RANDOM_COUNT:-4}"
TARGETED_RANDOM_SEED_BASE="${TARGETED_RANDOM_SEED_BASE:-500}"

mkdir -p "${REPORT_DIR}" "${COVERAGE_DIR}" "${RANDOM_DIR}"
rm -f "${COVERAGE_DIR}"/*.json
rm -f "${RESULTS_FILE}"
rm -rf "${REPORT_DIR}/code_coverage"
printf '[]\n' > "${CLOSURE_HISTORY}"

run_one_test() {
    local test_name="$1"
    local uvm_test="$2"
    local asm_path="$3"
    local seed="$4"
    local result

    result="$("${ROOT_DIR}/scripts/run_single_test.sh" "${test_name}" "${uvm_test}" "${asm_path}" "${seed}" | tail -n 1)"
    echo "${result}" | tee -a "${RESULTS_FILE}"
}

record_history() {
    local phase_name="$1"
    python3 - "${AGGREGATE_BINS}" "${CLOSURE_HISTORY}" "${phase_name}" <<'PY'
import json
import pathlib
import sys

aggregate = pathlib.Path(sys.argv[1])
history = pathlib.Path(sys.argv[2])
phase_name = sys.argv[3]
payload = json.loads(aggregate.read_text(encoding="utf-8"))
history_payload = json.loads(history.read_text(encoding="utf-8"))
history_payload.append(
    {
        "name": phase_name,
        "covered_bins": payload["summary"]["covered_bins"],
        "total_bins": payload["summary"]["total_bins"],
        "functional_coverage": payload["summary"]["functional_coverage"],
    }
)
history.write_text(json.dumps(history_payload, indent=2) + "\n", encoding="utf-8")
PY
}

python3 "${ROOT_DIR}/model/generate_random_tests.py" \
    --out-dir "${RANDOM_DIR}" \
    --count "${RANDOM_COUNT}" \
    --seed-base "${RANDOM_SEED_BASE}" \
    --body-ops "${RANDOM_BODY_OPS}"

"${ROOT_DIR}/scripts/compile_vcs.sh"

while IFS='|' read -r test_name uvm_test asm_path seed; do
    [[ -z "${test_name}" ]] && continue
    run_one_test "${test_name}" "${uvm_test}" "${asm_path}" "${seed}"
done < "${TESTLIST}"

for ((idx = 0; idx < RANDOM_COUNT; idx++)); do
    seed=$((RANDOM_SEED_BASE + idx))
    run_one_test "rand_${seed}" "cpu_random_test" "sw/tests/random/rand_${seed}.asm" "${seed}"
done

python3 "${ROOT_DIR}/scripts/generate_signoff_reports.py"
record_history "baseline"

uncovered_bins="$(python3 - "${AGGREGATE_BINS}" <<'PY'
import json
import pathlib
import sys
payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(len(payload.get("uncovered_bins", [])))
PY
)"

if [[ "${uncovered_bins}" != "0" && "${TARGETED_RANDOM_COUNT}" != "0" ]]; then
    python3 "${ROOT_DIR}/model/generate_random_tests.py" \
        --out-dir "${RANDOM_DIR}" \
        --count "${TARGETED_RANDOM_COUNT}" \
        --seed-base "${TARGETED_RANDOM_SEED_BASE}" \
        --body-ops "$((RANDOM_BODY_OPS + 2))" \
        --coverage-targets "${AGGREGATE_BINS}"

    for ((idx = 0; idx < TARGETED_RANDOM_COUNT; idx++)); do
        seed=$((TARGETED_RANDOM_SEED_BASE + idx))
        run_one_test "rand_cov_${seed}" "cpu_random_test" "sw/tests/random/rand_cov_${seed}.asm" "${seed}"
    done

    python3 "${ROOT_DIR}/scripts/generate_signoff_reports.py"
    record_history "targeted_random"
fi

"${ROOT_DIR}/scripts/merge_code_coverage.sh"
python3 "${ROOT_DIR}/scripts/generate_signoff_reports.py"

echo "[run_regression] completed"
cat "${RESULTS_FILE}"
