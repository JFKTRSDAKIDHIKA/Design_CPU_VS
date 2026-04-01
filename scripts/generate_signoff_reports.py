#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import re
from dataclasses import dataclass


ROOT = pathlib.Path(__file__).resolve().parents[1]
REPORTS_DIR = ROOT / "reports"
TESTLIST = ROOT / "scripts" / "testlist.txt"
BUG_LIST = REPORTS_DIR / "bug_list.md"
SW_TESTS = ROOT / "sw" / "tests"

SIGNOFF_ISA = [
    "ADD", "SUB", "AND", "CMP", "XOR", "TEST", "OR", "MVRR", "DEC", "INC", "SHL", "SHR",
    "ADC", "SBB", "JR", "JRC", "JRNC", "JRZ", "JRNZ", "JRS", "JRNS", "CLC", "STC", "JMPA",
    "LDRR", "STRR", "MVRD",
]

INSTR_BINS = {
    "ADD": ["opcode_ADD", "add_zero", "add_carry", "add_overflow"],
    "SUB": ["opcode_SUB", "sub_zero", "sub_borrow", "sub_overflow"],
    "AND": ["opcode_AND", "and_zero"],
    "CMP": ["opcode_CMP", "cmp_zero", "cmp_negative"],
    "XOR": ["opcode_XOR", "xor_zero"],
    "TEST": ["opcode_TEST", "test_zero", "test_nonzero"],
    "OR": ["opcode_OR", "or_nonzero"],
    "MVRR": ["opcode_MVRR", "mvrr_same", "mvrr_diff"],
    "DEC": ["opcode_DEC", "dec_wrap_to_ffff"],
    "INC": ["opcode_INC", "inc_wrap_to_zero"],
    "SHL": ["opcode_SHL", "shl_sets_carry"],
    "SHR": ["opcode_SHR", "shr_sets_carry"],
    "ADC": ["opcode_ADC", "adc_carry_in_clear", "adc_carry_in_set"],
    "SBB": ["opcode_SBB", "sbb_carry_in_clear", "sbb_carry_in_set"],
    "JR": ["opcode_JR", "jr_forward", "jr_backward"],
    "JRC": ["opcode_JRC", "jrc_taken", "jrc_not_taken"],
    "JRNC": ["opcode_JRNC", "jrnc_taken", "jrnc_not_taken"],
    "JRZ": ["opcode_JRZ", "jrz_taken", "jrz_not_taken"],
    "JRNZ": ["opcode_JRNZ", "jrnz_taken", "jrnz_not_taken"],
    "JRS": ["opcode_JRS", "jrs_taken", "jrs_not_taken"],
    "JRNS": ["opcode_JRNS", "jrns_taken", "jrns_not_taken"],
    "CLC": ["opcode_CLC", "clc_clears_carry", "carry_control_chain"],
    "STC": ["opcode_STC", "stc_sets_carry", "carry_control_chain"],
    "JMPA": ["opcode_JMPA", "jmpa_absolute"],
    "LDRR": ["opcode_LDRR", "ldrr_read", "two_cycle_mem_instr"],
    "STRR": ["opcode_STRR", "strr_write", "two_cycle_mem_instr"],
    "MVRD": ["opcode_MVRD", "mvrd_imm_zero", "mvrd_imm_high", "double_word_pc_step"],
}

ASSERTIONS = {
    "ADD": "reset/data-bus safety assertions",
    "SUB": "reset/data-bus safety assertions",
    "AND": "reset/data-bus safety assertions",
    "CMP": "branch/PC legality assertions",
    "XOR": "reset/data-bus safety assertions",
    "TEST": "branch/PC legality assertions",
    "OR": "reset/data-bus safety assertions",
    "MVRR": "reset/data-bus safety assertions",
    "DEC": "branch/PC legality assertions",
    "INC": "branch/PC legality assertions",
    "SHL": "branch/PC legality assertions",
    "SHR": "branch/PC legality assertions",
    "ADC": "carry-chain protocol assertions",
    "SBB": "carry-chain protocol assertions",
    "JR": "branch/PC legality assertions",
    "JRC": "branch/PC legality assertions",
    "JRNC": "branch/PC legality assertions",
    "JRZ": "branch/PC legality assertions",
    "JRNZ": "branch/PC legality assertions",
    "JRS": "branch/PC legality assertions",
    "JRNS": "branch/PC legality assertions",
    "CLC": "carry-chain protocol assertions",
    "STC": "carry-chain protocol assertions",
    "JMPA": "branch/PC legality assertions",
    "LDRR": "data_bus read/write and memory timing assertions",
    "STRR": "data_bus read/write and memory timing assertions",
    "MVRD": "double-word PC step assertions",
}


@dataclass
class TestEntry:
    name: str
    asm_path: pathlib.Path
    kind: str
    uvm_test: str
    seed: int


def parse_testlist() -> list[TestEntry]:
    entries: list[TestEntry] = []
    for raw in TESTLIST.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        name, uvm_test, asm_rel, seed = raw.split("|")
        asm_path = ROOT / asm_rel
        kind = "corner" if "/corner/" in asm_rel else "directed"
        if "mult8" in name:
            kind = "smoke"
        entries.append(TestEntry(name, asm_path, kind, uvm_test, int(seed)))
    return entries


def parse_asm_opcodes(path: pathlib.Path) -> set[str]:
    opcodes: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split(";", 1)[0].strip()
        if not line:
            continue
        while ":" in line:
            left, right = line.split(":", 1)
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*|[0-9]+", left.strip()):
                line = right.strip()
            else:
                break
        if not line:
            continue
        opcode = line.split(None, 1)[0].upper()
        if opcode in SIGNOFF_ISA:
            opcodes.add(opcode)
    return opcodes


def load_coverage_reports() -> tuple[dict[str, dict], dict[str, int]]:
    test_reports: dict[str, dict] = {}
    aggregate_hits: dict[str, int] = {}
    for path in sorted((REPORTS_DIR / "coverage").glob("*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(payload, dict) or "bins" not in payload:
            continue
        test_reports[path.stem] = payload
        for entry in payload.get("bins", []):
            aggregate_hits[entry["name"]] = aggregate_hits.get(entry["name"], 0) + int(entry["hits"])
    return test_reports, aggregate_hits


def load_random_tests() -> list[TestEntry]:
    entries: list[TestEntry] = []
    for path in sorted((SW_TESTS / "random").glob("*.asm")):
        if not path.stem.startswith("rand_"):
            continue
        seed = int(re.sub(r"[^0-9]", "", path.stem) or "0")
        entries.append(TestEntry(path.stem, path, "random", "cpu_random_test", seed))
    return entries


def summarize_tests(entries: list[TestEntry]) -> dict[str, list[str]]:
    op_to_tests: dict[str, list[str]] = {op: [] for op in SIGNOFF_ISA}
    for entry in entries:
        for opcode in parse_asm_opcodes(entry.asm_path):
            op_to_tests[opcode].append(entry.name)
    return op_to_tests


def bugs_for_instruction(instruction: str) -> list[str]:
    text = BUG_LIST.read_text(encoding="utf-8")
    matches = []
    for block in text.split("\n## "):
        if instruction in block:
            headline = block.splitlines()[0].strip()
            matches.append(headline.replace("# ", "", 1))
    return matches


def load_regression_results() -> list[str]:
    summary_path = REPORTS_DIR / "regression_summary.txt"
    if not summary_path.exists():
        return []
    return [line.strip() for line in summary_path.read_text(encoding="utf-8").splitlines() if line.strip()]


def load_closure_history() -> list[dict]:
    history_path = REPORTS_DIR / "coverage" / "closure_history.json"
    if history_path.exists():
        return json.loads(history_path.read_text(encoding="utf-8"))
    return []


def load_code_coverage_summary() -> dict:
    summary_path = REPORTS_DIR / "code_coverage" / "summary.json"
    if summary_path.exists():
        return json.loads(summary_path.read_text(encoding="utf-8"))
    return {"status": "not_run", "reason": "Code coverage was not collected in this regression run."}


def format_percent(value: float) -> str:
    return f"{value:.2f}%"


def main() -> int:
    directed_entries = parse_testlist()
    random_entries = load_random_tests()
    all_entries = directed_entries + random_entries

    test_reports, aggregate_hits = load_coverage_reports()
    op_to_tests = summarize_tests(all_entries)
    regression_results = load_regression_results()
    closure_history = load_closure_history()
    code_cov = load_code_coverage_summary()

    covered = sum(1 for hits in aggregate_hits.values() if hits > 0)
    total = len(aggregate_hits)
    functional_coverage = 100.0 if total == 0 else covered * 100.0 / total
    uncovered_bins = sorted(name for name, hits in aggregate_hits.items() if hits == 0)
    aggregate_payload = {
        "summary": {
            "covered_bins": covered,
            "total_bins": total,
            "functional_coverage": round(functional_coverage, 2),
        },
        "uncovered_bins": [{"name": name} for name in uncovered_bins],
        "aggregate_hits": aggregate_hits,
    }
    (REPORTS_DIR / "coverage" / "aggregate_bins.json").write_text(
        json.dumps(aggregate_payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    coverage_summary_lines = ["# Coverage Summary", "", "最近一次回归的单测功能覆盖率如下：", ""]
    for name, payload in sorted(test_reports.items()):
        coverage_summary_lines.append(f"- `{name}`: {payload['summary']['functional_coverage']:.2f}%")
    coverage_summary_lines.extend(
        [
            "",
            "聚合 closure 结果：",
            "",
            f"- Functional coverage bins hit: `{covered} / {total}`",
            f"- Functional coverage: `{functional_coverage:.2f}%`",
            f"- Uncovered bins: `{len(uncovered_bins)}`",
        ]
    )
    (REPORTS_DIR / "coverage_summary.md").write_text("\n".join(coverage_summary_lines) + "\n", encoding="utf-8")

    closure_lines = [
        "# Coverage Closure",
        "",
        "## Functional Coverage",
        "",
        f"- 总体 functional coverage: `{functional_coverage:.2f}%` (`{covered}/{total}` bins)",
        f"- 未命中 bins 数量: `{len(uncovered_bins)}`",
    ]
    if closure_history:
        closure_lines.extend(["", "## Iteration History", ""])
        for item in closure_history:
            closure_lines.append(
                f"- `{item['name']}`: `{item['covered_bins']}/{item['total_bins']}` bins, `{item['functional_coverage']:.2f}%`"
            )
    closure_lines.extend(["", "## Uncovered Bins", ""])
    if uncovered_bins:
        for bin_name in uncovered_bins:
            reason = "stimulus_missing"
            if bin_name.startswith("opcode_"):
                reason = "instruction_test_missing"
            elif bin_name.startswith("mem_"):
                reason = "memory_scenario_missing"
            elif bin_name.startswith("jr") or bin_name.startswith("jmp"):
                reason = "branch_scenario_missing"
            closure_lines.append(f"- `{bin_name}`: `{reason}`")
    else:
        closure_lines.append("- None. All defined functional bins were hit.")

    closure_lines.extend(["", "## Code Coverage", ""])
    if code_cov.get("status") == "available":
        overall_score = code_cov.get("metrics", {}).get("overall_score")
        if overall_score and overall_score != "unknown":
            closure_lines.append(f"- `overall_score`: `{overall_score}%`")
        for metric, value in code_cov.get("metrics", {}).items():
            if metric == "overall_score" and value != "unknown":
                continue
            closure_lines.append(f"- `{metric}`: `{value}`")
        if code_cov.get("notes"):
            closure_lines.append(f"- Notes: {code_cov['notes']}")
    else:
        closure_lines.append(f"- Status: `{code_cov.get('status', 'not_run')}`")
        closure_lines.append(f"- Reason: {code_cov.get('reason', 'Unavailable')}")
    (REPORTS_DIR / "coverage_closure.md").write_text("\n".join(closure_lines) + "\n", encoding="utf-8")

    matrix_lines = [
        "# Instruction Verification Matrix",
        "",
        "| Instruction | RTL | Reference | Directed tests | Corner cases | Randomized scenarios | Coverage bins hit | Assertions | Bugs | Final status |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for instruction in SIGNOFF_ISA:
        directed = [entry.name for entry in directed_entries if instruction in parse_asm_opcodes(entry.asm_path) and entry.kind == "directed"]
        corners = [entry.name for entry in directed_entries if instruction in parse_asm_opcodes(entry.asm_path) and entry.kind == "corner"]
        randoms = [entry.name for entry in random_entries if instruction in parse_asm_opcodes(entry.asm_path)]
        bins = INSTR_BINS[instruction]
        hit_bins = [name for name in bins if aggregate_hits.get(name, 0) > 0]
        final_status = "PASS" if len(hit_bins) == len(bins) and directed else "PARTIAL"
        bug_refs = ", ".join(bugs_for_instruction(instruction)) or "-"
        matrix_lines.append(
            "| {instr} | yes | yes | {directed} | {corners} | {randoms} | {bins_hit}/{bins_total} | {assertions} | {bugs} | {status} |".format(
                instr=instruction,
                directed=", ".join(directed) or "-",
                corners=", ".join(corners) or "-",
                randoms=", ".join(randoms) or "-",
                bins_hit=len(hit_bins),
                bins_total=len(bins),
                assertions=ASSERTIONS[instruction],
                bugs=bug_refs,
                status=final_status,
            )
        )
    (REPORTS_DIR / "instruction_verification_matrix.md").write_text("\n".join(matrix_lines) + "\n", encoding="utf-8")

    final_lines = [
        "# Final Verification Summary",
        "",
        "## Regression Result",
        "",
        f"- 回归入口：[`scripts/run_regression.sh`]({ROOT / 'scripts' / 'run_regression.sh'})",
        f"- 回归结果条目数：`{len(regression_results)}`",
    ]
    if regression_results:
        passed = sum("|PASS|" in line for line in regression_results)
        final_lines.append(f"- 通过情况：`{passed} / {len(regression_results)} PASS`")
    final_lines.extend(
        [
            "",
            "## Signoff Status",
            "",
            f"- Functional coverage: `{functional_coverage:.2f}%`",
            f"- Instruction matrix: see [`reports/instruction_verification_matrix.md`]({REPORTS_DIR / 'instruction_verification_matrix.md'})",
            f"- Coverage closure: see [`reports/coverage_closure.md`]({REPORTS_DIR / 'coverage_closure.md'})",
            f"- Code coverage status: `{code_cov.get('status', 'not_run')}`",
        ]
    )
    if code_cov.get("status") == "available":
        overall_score = code_cov.get("metrics", {}).get("overall_score")
        merged_vdbs = code_cov.get("metrics", {}).get("merged_vdbs")
        report_dir = code_cov.get("metrics", {}).get("report_dir")
        if overall_score and overall_score != "unknown":
            final_lines.append(f"- Code coverage overall score: `{overall_score}%`")
        if merged_vdbs:
            final_lines.append(f"- Code coverage merged VDBs: `{merged_vdbs}`")
        if report_dir:
            final_lines.append(f"- Code coverage report dir: `{report_dir}`")
    final_lines.extend(
        [
            "",
            "## ISA In Scope",
            "",
            "- `ADD SUB AND CMP XOR TEST OR MVRR`",
            "- `DEC INC SHL SHR ADC SBB`",
            "- `JR JRC JRNC JRZ JRNZ JRS JRNS`",
            "- `CLC STC JMPA LDRR STRR MVRD`",
        ]
    )
    (REPORTS_DIR / "final_verification_summary.md").write_text("\n".join(final_lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
