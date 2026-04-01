#!/usr/bin/env python3
from __future__ import annotations

import argparse
import dataclasses
import pathlib
import re
import sys
from typing import Iterable


REGISTER_MAP = {f"R{i}": i for i in range(16)}

SINGLE_REG_REG = {
    "ADD": 0x00,
    "SUB": 0x01,
    "AND": 0x02,
    "CMP": 0x03,
    "XOR": 0x04,
    "TEST": 0x05,
    "OR": 0x06,
    "MVRR": 0x07,
    "ADC": 0x0C,
    "SBB": 0x0D,
}

SINGLE_REG = {
    "DEC": 0x08,
    "INC": 0x09,
    "SHL": 0x0A,
    "SHR": 0x0B,
}

SINGLE_BRANCH = {
    "JR": 0x40,
    "JRC": 0x44,
    "JRNC": 0x45,
    "JRZ": 0x46,
    "JRNZ": 0x47,
    "JRS": 0x41,
    "JRNS": 0x43,
}

NO_OPERAND = {
    "CLC": 0x7800,
    "STC": 0x7A00,
}

DOUBLE_WORD = {
    "JMPA": 0x8000,
    "MVRD": 0x8100,
}

TWO_CYCLE_SINGLE_WORD = {
    "LDRR": 0x8200,
    "STRR": 0x8300,
}


@dataclasses.dataclass
class SourceLine:
    lineno: int
    text: str
    labels: list[str]
    mnemonic: str | None
    operands: list[str]
    address: int = 0
    words: list[int] = dataclasses.field(default_factory=list)


def strip_comment(line: str) -> str:
    return line.split(";", 1)[0].strip()


def parse_lines(text: str) -> list[SourceLine]:
    parsed: list[SourceLine] = []
    for lineno, raw in enumerate(text.splitlines(), start=1):
        body = strip_comment(raw)
        if not body:
            continue

        labels: list[str] = []
        while ":" in body:
            head, tail = body.split(":", 1)
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*|[0-9]+", head.strip()):
                break
            labels.append(head.strip())
            body = tail.strip()
            if not body:
                break

        mnemonic = None
        operands: list[str] = []
        if body:
            parts = body.split(None, 1)
            mnemonic = parts[0].upper()
            if len(parts) > 1:
                operands = [item.strip() for item in parts[1].split(",") if item.strip()]

        parsed.append(SourceLine(lineno=lineno, text=raw.rstrip(), labels=labels, mnemonic=mnemonic, operands=operands))
    return parsed


def instruction_size(mnemonic: str | None) -> int:
    if mnemonic is None:
        return 0
    if (
        mnemonic in SINGLE_REG_REG
        or mnemonic in SINGLE_REG
        or mnemonic in SINGLE_BRANCH
        or mnemonic in NO_OPERAND
        or mnemonic in TWO_CYCLE_SINGLE_WORD
    ):
        return 1
    if mnemonic in DOUBLE_WORD:
        return 2
    raise ValueError(f"Unsupported mnemonic {mnemonic}")


def parse_number(token: str) -> int:
    token = token.strip()
    if token.upper() in REGISTER_MAP:
        raise ValueError(f"Expected immediate, got register {token}")
    return int(token, 0)


def parse_register(token: str) -> int:
    key = token.strip().upper()
    if key not in REGISTER_MAP:
        raise ValueError(f"Unknown register {token}")
    return REGISTER_MAP[key]


def build_label_table(lines: Iterable[SourceLine]) -> dict[str, list[int]]:
    table: dict[str, list[int]] = {}
    for line in lines:
        for label in line.labels:
            table.setdefault(label, []).append(line.address)
    return table


def resolve_target(token: str, current_addr: int, label_table: dict[str, list[int]]) -> int:
    number_pattern = r"[+-]?(?:0[xX][0-9a-fA-F]+|\d+)"
    if re.fullmatch(number_pattern, token.strip()):
        return parse_number(token)

    match = re.fullmatch(r"([0-9]+)([FBfb])", token.strip())
    if match:
        label_name, direction = match.groups()
        candidates = label_table.get(label_name, [])
        if direction.upper() == "F":
            for addr in candidates:
                if addr > current_addr:
                    return addr
        else:
            for addr in reversed(candidates):
                if addr <= current_addr:
                    return addr
        raise ValueError(f"Cannot resolve local label {token} at address 0x{current_addr:04X}")

    if token in label_table:
        return label_table[token][0]

    return parse_number(token)


def encode_line(line: SourceLine, label_table: dict[str, list[int]]) -> list[int]:
    if line.mnemonic is None:
        return []
    mnemonic = line.mnemonic
    ops = line.operands

    if mnemonic in SINGLE_REG_REG:
        if len(ops) != 2:
            raise ValueError(f"{mnemonic} expects 2 operands")
        dr = parse_register(ops[0])
        sr = parse_register(ops[1])
        return [(SINGLE_REG_REG[mnemonic] << 8) | (dr << 4) | sr]

    if mnemonic in SINGLE_REG:
        if len(ops) != 1:
            raise ValueError(f"{mnemonic} expects 1 operand")
        dr = parse_register(ops[0])
        return [(SINGLE_REG[mnemonic] << 8) | (dr << 4)]

    if mnemonic in SINGLE_BRANCH:
        if len(ops) != 1:
            raise ValueError(f"{mnemonic} expects 1 operand")
        target_addr = resolve_target(ops[0], line.address, label_table)
        offset = target_addr - line.address - 1
        if not -128 <= offset <= 127:
            raise ValueError(f"Branch offset out of range for {mnemonic} at 0x{line.address:04X}")
        return [(SINGLE_BRANCH[mnemonic] << 8) | (offset & 0xFF)]

    if mnemonic in NO_OPERAND:
        if ops:
            raise ValueError(f"{mnemonic} expects no operands")
        return [NO_OPERAND[mnemonic]]

    if mnemonic == "MVRD":
        if len(ops) != 2:
            raise ValueError("MVRD expects 2 operands")
        dr = parse_register(ops[0])
        imm = resolve_target(ops[1], line.address, label_table) & 0xFFFF
        return [DOUBLE_WORD[mnemonic] | (dr << 4), imm]

    if mnemonic == "JMPA":
        if len(ops) != 1:
            raise ValueError("JMPA expects 1 operand")
        target = resolve_target(ops[0], line.address, label_table) & 0xFFFF
        return [DOUBLE_WORD[mnemonic], target]

    if mnemonic in {"LDRR", "STRR"}:
        if len(ops) != 2:
            raise ValueError(f"{mnemonic} expects 2 operands")
        dr = parse_register(ops[0])
        sr = parse_register(ops[1])
        return [TWO_CYCLE_SINGLE_WORD[mnemonic] | (dr << 4) | sr]

    raise ValueError(f"Unsupported mnemonic {mnemonic}")


def assemble(asm_path: pathlib.Path) -> tuple[list[SourceLine], list[int]]:
    lines = parse_lines(asm_path.read_text(encoding="utf-8"))
    address = 0
    for line in lines:
        line.address = address
        address += instruction_size(line.mnemonic)
    label_table = build_label_table(lines)
    words: list[int] = []
    for line in lines:
        try:
            line.words = encode_line(line, label_table)
        except Exception as exc:  # noqa: BLE001
            raise ValueError(f"{asm_path}:{line.lineno}: {exc}") from exc
        words.extend(line.words)
    return lines, words


def render_layout(lines: Iterable[SourceLine]) -> str:
    rows = ["Address  Machine  Assembly"]
    for line in lines:
        if not line.words:
            continue
        for idx, word in enumerate(line.words):
            asm = line.text.strip() if idx == 0 else "(extension word)"
            rows.append(f"0x{line.address + idx:04X}  0x{word:04X}  {asm}")
    return "\n".join(rows) + "\n"


def write_hex(path: pathlib.Path, words: Iterable[int]) -> None:
    path.write_text("".join(f"{word:04x}\n" for word in words), encoding="ascii")


def main() -> int:
    parser = argparse.ArgumentParser(description="Assemble the minimal cpu_core ISA program")
    parser.add_argument("asm", type=pathlib.Path)
    parser.add_argument("--hex-out", type=pathlib.Path, required=True)
    parser.add_argument("--layout-out", type=pathlib.Path, required=True)
    args = parser.parse_args()

    try:
        lines, words = assemble(args.asm)
    except Exception as exc:  # noqa: BLE001
        print(f"[assembler] ERROR: {exc}", file=sys.stderr)
        return 1

    args.hex_out.parent.mkdir(parents=True, exist_ok=True)
    args.layout_out.parent.mkdir(parents=True, exist_ok=True)
    write_hex(args.hex_out, words)
    args.layout_out.write_text(render_layout(lines), encoding="utf-8")
    print(f"[assembler] Wrote {len(words)} words to {args.hex_out}")
    print(f"[assembler] Wrote layout to {args.layout_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
