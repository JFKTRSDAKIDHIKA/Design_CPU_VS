#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import re
import sys


SUMMARY_RE = re.compile(r"^([A-Za-z0-9_]+)=(.+)$")
TRACE_RE = re.compile(
    r"TRACE step=(?P<step>\d+) addr=(?P<addr>[0-9a-fA-F]+) pc=(?P<pc>[0-9a-fA-F]+) ir=(?P<ir>[0-9a-fA-F]+) "
    r"R0=(?P<r0>[0-9a-fA-F]+) R1=(?P<r1>[0-9a-fA-F]+) R2=(?P<r2>[0-9a-fA-F]+) "
    r"R3=(?P<r3>[0-9a-fA-F]+) R4=(?P<r4>[0-9a-fA-F]+) R5=(?P<r5>[0-9a-fA-F]+) "
    r"R6=(?P<r6>[0-9a-fA-F]+) R7=(?P<r7>[0-9a-fA-F]+) R8=(?P<r8>[0-9a-fA-F]+) "
    r"R9=(?P<r9>[0-9a-fA-F]+) R10=(?P<r10>[0-9a-fA-F]+) R11=(?P<r11>[0-9a-fA-F]+) "
    r"R12=(?P<r12>[0-9a-fA-F]+) R13=(?P<r13>[0-9a-fA-F]+) R14=(?P<r14>[0-9a-fA-F]+) "
    r"R15=(?P<r15>[0-9a-fA-F]+) C=(?P<c>\d) Z=(?P<z>\d) V=(?P<v>\d) S=(?P<s>\d)"
)


def load_summary(path: pathlib.Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = SUMMARY_RE.match(line.strip())
        if match:
            data[match.group(1).lower()] = match.group(2)
    return data


def load_trace(path: pathlib.Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = TRACE_RE.search(line)
        if match:
            rows.append({k: v.lower() for k, v in match.groupdict().items()})
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare RTL and reference model outputs")
    parser.add_argument("--rtl-summary", type=pathlib.Path, required=True)
    parser.add_argument("--ref-summary", type=pathlib.Path, required=True)
    parser.add_argument("--rtl-trace", type=pathlib.Path)
    parser.add_argument("--ref-trace", type=pathlib.Path)
    parser.add_argument("--report-out", type=pathlib.Path, required=True)
    args = parser.parse_args()

    rtl = load_summary(args.rtl_summary)
    ref = load_summary(args.ref_summary)

    def parse_int(value: str | None) -> int | None:
        if value is None:
            return None
        value = value.strip().lower()
        base = 16 if value.startswith("0x") else 10
        return int(value, base)

    keys = [*[f"r{i}" for i in range(16)], "pc", "c", "z", "v", "s"]
    mismatches = [key for key in keys if rtl.get(key) != ref.get(key)]

    trace_status = "not_run"
    trace_detail = ""
    if args.rtl_trace and args.ref_trace and args.rtl_trace.exists() and args.ref_trace.exists():
        rtl_trace = load_trace(args.rtl_trace)
        ref_trace = load_trace(args.ref_trace)
        trace_status = "match"
        if len(rtl_trace) != len(ref_trace):
            trace_status = "mismatch"
            trace_detail = f"trace length mismatch rtl={len(rtl_trace)} ref={len(ref_trace)}"
        else:
            compare_fields = ["addr", "pc", "ir", *[f"r{i}" for i in range(16)], "c", "z", "v", "s"]
            for idx, (rtl_row, ref_row) in enumerate(zip(rtl_trace, ref_trace)):
                bad = [field for field in compare_fields if rtl_row[field] != ref_row[field]]
                if bad:
                    trace_status = "mismatch"
                    trace_detail = f"trace step {idx} mismatch fields={','.join(bad)}"
                    break

    rtl_r2 = parse_int(rtl.get("r2"))
    ref_r2 = parse_int(ref.get("r2"))
    report_lines = [
        "cpu_core verification summary",
        f"test_program=8bit multiply 25 x 6",
        f"program_ran_successfully={'yes' if rtl.get('result') == 'PASS' else 'no'}",
        "expected_result_decimal=150",
        f"rtl_result_decimal={rtl_r2 if rtl_r2 is not None else 'n/a'}",
        f"reference_result_decimal={ref_r2 if ref_r2 is not None else 'n/a'}",
        f"rtl_result_hex={rtl.get('r2', 'n/a')}",
        f"reference_result_hex={ref.get('r2', 'n/a')}",
        f"final_state_match={'yes' if not mismatches else 'no'}",
        f"trace_match={trace_status}",
        f"rtl_cycles={rtl.get('cycles', 'n/a')}",
        f"reference_steps={ref.get('steps', 'n/a')}",
        f"halt_condition=detected repeated retired JR -1 self-loop",
        "rtl_suspicious_points=wr polarity is 1=read 0=write in RTL; controller uses task calls inside always_comb and triggers VCS TBIFASL warnings",
    ]
    if mismatches:
        report_lines.append("mismatch_fields=" + ",".join(mismatches))
    if trace_detail:
        report_lines.append(trace_detail)

    args.report_out.parent.mkdir(parents=True, exist_ok=True)
    args.report_out.write_text("\n".join(report_lines) + "\n", encoding="utf-8")

    if mismatches or trace_status == "mismatch":
        print(args.report_out.read_text(encoding="utf-8"), file=sys.stderr)
        return 1

    print(args.report_out.read_text(encoding="utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
