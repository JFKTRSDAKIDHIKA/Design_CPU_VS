#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import pathlib
from dataclasses import dataclass


def sign16(value: int) -> int:
    return value - 0x10000 if value & 0x8000 else value


def sign8(value: int) -> int:
    return value - 0x100 if value & 0x80 else value


@dataclass
class Flags:
    c: int = 0
    z: int = 0
    v: int = 0
    s: int = 0

    def as_dict(self) -> dict[str, int]:
        return {"c": self.c, "z": self.z, "v": self.v, "s": self.s}


OPCODE_NAMES = {
    0x00: "ADD",
    0x01: "SUB",
    0x02: "AND",
    0x03: "CMP",
    0x04: "XOR",
    0x05: "TEST",
    0x06: "OR",
    0x07: "MVRR",
    0x08: "DEC",
    0x09: "INC",
    0x0A: "SHL",
    0x0B: "SHR",
    0x0C: "ADC",
    0x0D: "SBB",
    0x40: "JR",
    0x41: "JRS",
    0x43: "JRNS",
    0x44: "JRC",
    0x45: "JRNC",
    0x46: "JRZ",
    0x47: "JRNZ",
    0x78: "CLC",
    0x7A: "STC",
    0x80: "JMPA",
    0x81: "MVRD",
    0x82: "LDRR",
    0x83: "STRR",
}


class CpuModel:
    def __init__(self, memory: list[int]) -> None:
        self.mem = [0] * 0x10000
        for idx, word in enumerate(memory):
            self.mem[idx] = word & 0xFFFF
        self.regs = [0] * 16
        self.pc = 0
        self.flags = Flags()
        self.trace: list[str] = []
        self.events: list[dict[str, object]] = []
        self.steps = 0

    def _update_logic_flags(self, value: int, carry: int = 0) -> None:
        self.flags.c = carry
        self.flags.z = 1 if value == 0 else 0
        self.flags.v = 0
        self.flags.s = 1 if value & 0x8000 else 0

    def _update_add_flags(self, a: int, b: int, result: int, carry_out: int) -> None:
        self.flags.c = carry_out
        self.flags.z = 1 if result == 0 else 0
        self.flags.v = 1 if ((a ^ result) & (b ^ result) & 0x8000) != 0 else 0
        self.flags.s = 1 if result & 0x8000 else 0

    def _update_sub_flags(self, operand_a: int, operand_b: int, result: int, carry_out: int) -> None:
        self.flags.c = carry_out
        self.flags.z = 1 if result == 0 else 0
        self.flags.v = 1 if ((operand_a ^ operand_b) & (result ^ operand_b) & 0x8000) != 0 else 0
        self.flags.s = 1 if result & 0x8000 else 0

    def _trace(self, pc_after: int, instr_addr: int, instr: int) -> None:
        regs = " ".join(f"R{i}={self.regs[i]:04x}" for i in range(16))
        flags = f"C={self.flags.c} Z={self.flags.z} V={self.flags.v} S={self.flags.s}"
        self.trace.append(
            f"TRACE step={self.steps:03d} addr={instr_addr:04x} pc={pc_after:04x} ir={instr:04x} {regs} {flags}"
        )

    def _emit_event(
        self,
        *,
        instr_addr: int,
        instr: int,
        pc_before: int,
        pc_after: int,
        flags_before: Flags,
        mem_kind: str | None = None,
        mem_addr: int | None = None,
        mem_data: int | None = None,
        extra_word: int | None = None,
    ) -> None:
        opcode = (instr >> 8) & 0xFF
        dr = (instr >> 4) & 0xF
        sr = instr & 0xF
        event = {
            "step": self.steps,
            "instr_addr": instr_addr,
            "pc_before": pc_before,
            "pc_after": pc_after,
            "ir": instr,
            "opcode": opcode,
            "opcode_name": OPCODE_NAMES.get(opcode, f"OP_{opcode:02X}"),
            "instruction_class": self._instruction_class(opcode),
            "dr": dr,
            "sr": sr,
            "flags_before": flags_before.as_dict(),
            "flags_after": self.flags.as_dict(),
            "branch_taken": pc_after != ((instr_addr + (2 if opcode in {0x80, 0x81} else 1)) & 0xFFFF)
            if opcode in {0x41, 0x43, 0x44, 0x45, 0x46, 0x47}
            else opcode in {0x40, 0x80},
            "branch_target": pc_after if opcode in {0x40, 0x41, 0x43, 0x44, 0x45, 0x46, 0x47, 0x80} else None,
            "offset": sign8(instr & 0xFF) if opcode in {0x40, 0x41, 0x43, 0x44, 0x45, 0x46, 0x47} else None,
            "immediate": extra_word if opcode in {0x80, 0x81} else None,
            "mem_kind": mem_kind,
            "mem_addr": mem_addr,
            "mem_data": mem_data,
            "extra_word": extra_word,
        }
        self.events.append(event)

    @staticmethod
    def _instruction_class(opcode: int) -> str:
        if opcode in {0x00, 0x01, 0x0C, 0x0D, 0x08, 0x09}:
            return "arithmetic"
        if opcode in {0x02, 0x03, 0x04, 0x05, 0x06}:
            return "logic"
        if opcode in {0x07, 0x81}:
            return "move"
        if opcode in {0x0A, 0x0B}:
            return "shift"
        if opcode in {0x40, 0x41, 0x43, 0x44, 0x45, 0x46, 0x47, 0x80}:
            return "control"
        if opcode in {0x78, 0x7A}:
            return "flag_control"
        if opcode in {0x82, 0x83}:
            return "memory"
        return "other"

    def run(self, max_steps: int, halt_repeat_threshold: int) -> None:
        self_loop_retire_count = 0
        while self.steps < max_steps:
            instr_addr = self.pc
            pc_before = self.pc
            instr = self.mem[self.pc]
            self.pc = (self.pc + 1) & 0xFFFF
            opcode = (instr >> 8) & 0xFF
            dr = (instr >> 4) & 0xF
            sr = instr & 0xF
            flags_before = Flags(self.flags.c, self.flags.z, self.flags.v, self.flags.s)
            mem_kind = None
            mem_addr = None
            mem_data = None
            extra_word = None

            if opcode == 0x81:
                imm = self.mem[self.pc]
                extra_word = imm
                self.pc = (self.pc + 1) & 0xFFFF
                self.regs[dr] = imm
            elif opcode == 0x80:
                extra_word = self.mem[self.pc]
                self.pc = extra_word
            elif opcode == 0x82:
                mem_addr = self.regs[sr] & 0xFFFF
                mem_kind = "READ"
                mem_data = self.mem[mem_addr]
                self.regs[dr] = mem_data
            elif opcode == 0x83:
                mem_addr = self.regs[dr] & 0xFFFF
                mem_kind = "WRITE"
                mem_data = self.regs[sr] & 0xFFFF
                self.mem[mem_addr] = mem_data
            elif opcode == 0x02:
                result = self.regs[dr] & self.regs[sr]
                self.regs[dr] = result & 0xFFFF
                self._update_logic_flags(result & 0xFFFF)
            elif opcode == 0x06:
                result = self.regs[dr] | self.regs[sr]
                self.regs[dr] = result & 0xFFFF
                self._update_logic_flags(result & 0xFFFF)
            elif opcode == 0x04:
                result = self.regs[dr] ^ self.regs[sr]
                self.regs[dr] = result & 0xFFFF
                self._update_logic_flags(result & 0xFFFF)
            elif opcode == 0x07:
                self.regs[dr] = self.regs[sr] & 0xFFFF
            elif opcode == 0x05:
                result = self.regs[dr] & self.regs[sr]
                self._update_logic_flags(result & 0xFFFF)
            elif opcode == 0x00:
                a = self.regs[sr]
                b = self.regs[dr]
                full = b + a
                result = full & 0xFFFF
                self.regs[dr] = result
                self._update_add_flags(a, b, result, 1 if full > 0xFFFF else 0)
            elif opcode == 0x0C:
                a = self.regs[sr]
                b = self.regs[dr]
                full = b + a + self.flags.c
                result = full & 0xFFFF
                self.regs[dr] = result
                self._update_add_flags(a, b, result, 1 if full > 0xFFFF else 0)
            elif opcode == 0x01:
                a = self.regs[sr]
                b = self.regs[dr]
                full = (b - a) & 0x1FFFF
                result = full & 0xFFFF
                self.regs[dr] = result
                self._update_sub_flags(a, b, result, (full >> 16) & 0x1)
            elif opcode == 0x03:
                a = self.regs[sr]
                b = self.regs[dr]
                full = (b - a) & 0x1FFFF
                result = full & 0xFFFF
                self._update_sub_flags(a, b, result, (full >> 16) & 0x1)
            elif opcode == 0x0D:
                a = self.regs[sr]
                b = self.regs[dr]
                full = (b - a - self.flags.c) & 0x1FFFF
                result = full & 0xFFFF
                self.regs[dr] = result
                self._update_sub_flags(a, b, result, (full >> 16) & 0x1)
            elif opcode == 0x0A:
                b = self.regs[dr]
                result = ((b << 1) & 0xFFFF)
                self.regs[dr] = result
                self.flags.c = 1 if (b & 0x8000) else 0
                self.flags.z = 1 if result == 0 else 0
                self.flags.v = 0
                self.flags.s = 1 if result & 0x8000 else 0
            elif opcode == 0x0B:
                b = self.regs[dr]
                result = (b >> 1) & 0xFFFF
                self.regs[dr] = result
                self.flags.c = b & 0x1
                self.flags.z = 1 if result == 0 else 0
                self.flags.v = 0
                self.flags.s = 1 if result & 0x8000 else 0
            elif opcode == 0x08:
                b = self.regs[dr]
                full = (b - 1) & 0x1FFFF
                result = full & 0xFFFF
                self.regs[dr] = result
                self._update_sub_flags(1, b, result, (full >> 16) & 0x1)
            elif opcode == 0x09:
                b = self.regs[dr]
                full = b + 1
                result = full & 0xFFFF
                self.regs[dr] = result
                self._update_add_flags(0, b, result, 1 if full > 0xFFFF else 0)
            elif opcode == 0x78:
                self.flags.c = 0
            elif opcode == 0x7A:
                self.flags.c = 1
            elif opcode in {0x40, 0x41, 0x43, 0x44, 0x45, 0x46, 0x47}:
                offset = sign8(instr & 0x00FF)
                take = {
                    0x40: True,
                    0x41: self.flags.s == 1,
                    0x43: self.flags.s == 0,
                    0x44: self.flags.c == 1,
                    0x45: self.flags.c == 0,
                    0x46: self.flags.z == 1,
                    0x47: self.flags.z == 0,
                }[opcode]
                if take:
                    self.pc = (self.pc + offset) & 0xFFFF
            else:
                raise RuntimeError(f"Unsupported opcode 0x{opcode:02X} at PC 0x{instr_addr:04X}")

            self._trace(self.pc, instr_addr, instr)
            self._emit_event(
                instr_addr=instr_addr,
                instr=instr,
                pc_before=pc_before,
                pc_after=self.pc,
                flags_before=flags_before,
                mem_kind=mem_kind,
                mem_addr=mem_addr,
                mem_data=mem_data,
                extra_word=extra_word,
            )
            self.steps += 1

            if instr == 0x40FF:
                self_loop_retire_count += 1
            else:
                self_loop_retire_count = 0

            if self_loop_retire_count >= halt_repeat_threshold:
                return

        raise RuntimeError(f"Exceeded max steps {max_steps}")


def load_hex(path: pathlib.Path) -> list[int]:
    words: list[int] = []
    for line in path.read_text(encoding="ascii").splitlines():
        line = line.strip()
        if line:
            words.append(int(line, 16))
    return words


def main() -> int:
    parser = argparse.ArgumentParser(description="Reference model for cpu_core validation")
    parser.add_argument("--hex", dest="hex_path", type=pathlib.Path, required=True)
    parser.add_argument("--trace-out", type=pathlib.Path, required=True)
    parser.add_argument("--summary-out", type=pathlib.Path, required=True)
    parser.add_argument("--events-out", type=pathlib.Path)
    parser.add_argument("--max-steps", type=int, default=256)
    parser.add_argument("--halt-repeat-threshold", type=int, default=3)
    args = parser.parse_args()

    memory = load_hex(args.hex_path)
    model = CpuModel(memory)
    model.run(args.max_steps, args.halt_repeat_threshold)

    args.trace_out.parent.mkdir(parents=True, exist_ok=True)
    args.summary_out.parent.mkdir(parents=True, exist_ok=True)
    args.trace_out.write_text("\n".join(model.trace) + "\n", encoding="utf-8")
    if args.events_out is not None:
        args.events_out.parent.mkdir(parents=True, exist_ok=True)
        args.events_out.write_text(
            "".join(json.dumps(event, sort_keys=True) + "\n" for event in model.events),
            encoding="utf-8",
        )

    summary = [
        f"steps={model.steps}",
        f"pc=0x{model.pc:04X}",
        *[f"r{i}=0x{model.regs[i]:04X}" for i in range(16)],
        f"c={model.flags.c}",
        f"z={model.flags.z}",
        f"v={model.flags.v}",
        f"s={model.flags.s}",
    ]
    args.summary_out.write_text("\n".join(summary) + "\n", encoding="utf-8")
    print(f"[reference] Completed in {model.steps} steps, R2={model.regs[2]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
