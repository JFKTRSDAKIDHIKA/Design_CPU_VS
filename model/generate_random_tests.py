#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import pathlib
import random
from dataclasses import dataclass


ARITH_OPS = ["ADD", "SUB", "AND", "XOR", "OR", "ADC", "SBB", "CMP", "TEST", "MVRR"]
UNARY_OPS = ["DEC", "INC", "SHL", "SHR"]
BRANCH_OPS = ["JRZ", "JRNZ", "JRC", "JRNC", "JRS", "JRNS"]
ALL_OPCODE_CLASSES = ("arith", "unary", "mem", "flag_branch")
REGISTER_POOL = [f"R{i}" for i in range(10)]


@dataclass
class GeneratorConfig:
    body_ops: int
    branch_density: float
    load_store_density: float
    loop_probability: float
    max_loop_depth: int
    program_prefix: str
    opcode_weights: dict[str, int]
    register_weights: dict[str, int]
    targeted_bins: set[str]


def parse_weight_map(raw: str | None) -> dict[str, int]:
    if not raw:
        return {}
    weights: dict[str, int] = {}
    for chunk in raw.split(","):
        name, value = chunk.split("=", 1)
        weights[name.strip().upper()] = max(1, int(value))
    return weights


def weighted_choice(rng: random.Random, values: list[str], weights: dict[str, int]) -> str:
    scored = [max(1, weights.get(value.upper(), 1)) for value in values]
    return rng.choices(values, weights=scored, k=1)[0]


def choose_reg(rng: random.Random, register_weights: dict[str, int]) -> str:
    return weighted_choice(rng, REGISTER_POOL, register_weights)


def load_targeted_bins(path: pathlib.Path | None) -> set[str]:
    if path is None or not path.exists():
        return set()
    payload = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(payload, dict) and "uncovered_bins" in payload:
        entries = payload["uncovered_bins"]
    else:
        entries = payload
    bins = {
        entry["name"] if isinstance(entry, dict) else str(entry)
        for entry in entries
    }
    return bins


def emit_targeted_setup(lines: list[str], targeted_bins: set[str]) -> None:
    if not targeted_bins:
        return
    if any(name in targeted_bins for name in {"mvrd_imm_zero", "test_zero", "cmp_zero"}):
        lines.append("MVRD R0,0x0000")
    if any(name in targeted_bins for name in {"mvrd_imm_high", "add_overflow", "shl_sets_carry"}):
        lines.append("MVRD R9,0x8001")
    if any(name.startswith("mem_addr_high") or name.startswith("mem_") for name in targeted_bins):
        lines.append("MVRD R13,0xFF10")


def emit_flag_branch_block(rng: random.Random, idx: int, lines: list[str], config: GeneratorConfig) -> None:
    dst = choose_reg(rng, config.register_weights)
    src = choose_reg(rng, config.register_weights)
    if dst == src:
        src = REGISTER_POOL[(REGISTER_POOL.index(src) + 1) % len(REGISTER_POOL)]

    if "jrz_taken" in config.targeted_bins:
        lines.append(f"CMP {dst},{dst}")
        lines.append(f"JRZ SKIP_{idx}")
    elif "jrnz_taken" in config.targeted_bins:
        lines.append(f"CMP {dst},{src}")
        lines.append(f"JRNZ SKIP_{idx}")
    elif "jrc_taken" in config.targeted_bins or "jrnc_not_taken" in config.targeted_bins:
        lines.append("STC")
        lines.append(f"JRC SKIP_{idx}")
    elif "jrnc_taken" in config.targeted_bins or "jrc_not_taken" in config.targeted_bins:
        lines.append("CLC")
        lines.append(f"JRNC SKIP_{idx}")
    elif "jrs_taken" in config.targeted_bins:
        lines.append("MVRD R0,0x0000")
        lines.append("MVRD R1,0x0001")
        lines.append("SUB R0,R1")
        lines.append(f"JRS SKIP_{idx}")
    elif "jrns_taken" in config.targeted_bins:
        lines.append("MVRD R0,0x0001")
        lines.append("MVRD R1,0x0001")
        lines.append("CMP R0,R1")
        lines.append(f"JRNS SKIP_{idx}")
    else:
        lines.append(f"CMP {dst},{src}")
        lines.append(f"{weighted_choice(rng, BRANCH_OPS, config.opcode_weights)} SKIP_{idx}")

    lines.append("CLC" if rng.choice([True, False]) else "STC")
    lines.append(f"SKIP_{idx}:")


def emit_random_program(seed: int, config: GeneratorConfig) -> str:
    rng = random.Random(seed)
    lines: list[str] = [
        f"; {config.program_prefix} random test seed={seed}",
        "MVRD R10,0x0100",
        "MVRD R11,0x0101",
        f"MVRD R12,{rng.randint(2, max(2, config.max_loop_depth + 2))}",
    ]
    emit_targeted_setup(lines, config.targeted_bins)

    for idx, reg in enumerate(REGISTER_POOL):
        weight_bias = rng.randint(0, 0xFFFF)
        if "mvrd_imm_zero" in config.targeted_bins and idx == 0:
            imm = 0x0000
        elif "mvrd_imm_high" in config.targeted_bins and idx == len(REGISTER_POOL) - 1:
            imm = 0xF123
        else:
            imm = weight_bias
        lines.append(f"MVRD {reg},0x{imm:04X}")
        if idx == 1:
            lines.append("STRR R10,R1")
        if idx == 2:
            lines.append("STRR R11,R2")

    if "mem_addr_high" in config.targeted_bins:
        lines.extend(["MVRD R13,0xFF10", "STRR R13,R3", "LDRR R4,R13"])

    lines.append("LOOP:")
    for idx in range(config.body_ops):
        random_gate = rng.random()
        if random_gate < config.load_store_density:
            choice = "mem"
        elif random_gate < config.load_store_density + config.branch_density:
            choice = "flag_branch"
        else:
            choice = weighted_choice(rng, ["arith", "unary"], config.opcode_weights)

        dst = choose_reg(rng, config.register_weights)
        src = choose_reg(rng, config.register_weights)

        if choice == "arith":
            op = weighted_choice(rng, ARITH_OPS, config.opcode_weights)
            if op in {"CMP", "TEST"} and dst == src:
                src = REGISTER_POOL[(REGISTER_POOL.index(src) + 1) % len(REGISTER_POOL)]
            if "add_overflow" in config.targeted_bins and idx == 0:
                lines.extend(["MVRD R0,0x7FFF", "MVRD R1,0x0001", "ADD R0,R1"])
            elif "adc_carry_in_set" in config.targeted_bins and idx == 1:
                lines.extend(["STC", f"ADC {dst},{src}"])
            elif "sbb_carry_in_set" in config.targeted_bins and idx == 2:
                lines.extend(["STC", f"SBB {dst},{src}"])
            else:
                lines.append(f"{op} {dst},{src}")
        elif choice == "unary":
            op = weighted_choice(rng, UNARY_OPS, config.opcode_weights)
            if "shl_sets_carry" in config.targeted_bins and idx == 0:
                lines.extend(["MVRD R9,0x8001", "SHL R9"])
            elif "shr_sets_carry" in config.targeted_bins and idx == 1:
                lines.extend(["MVRD R8,0x0001", "SHR R8"])
            else:
                lines.append(f"{op} {dst}")
        elif choice == "mem":
            addr_reg = "R10" if rng.random() < 0.5 else "R11"
            data_reg = choose_reg(rng, config.register_weights)
            if "mem_addr_high" in config.targeted_bins and rng.random() < 0.3:
                addr_reg = "R13"
            if rng.choice([True, False]):
                lines.append(f"STRR {addr_reg},{data_reg}")
            else:
                lines.append(f"LDRR {dst},{addr_reg}")
        else:
            emit_flag_branch_block(rng, idx, lines, config)

    lines.extend(
        [
            "DEC R12",
            "JRNZ LOOP",
            f"MVRD R13,0x{rng.randint(0, 0xFFFF):04X}",
            "JMPA EXIT",
            "MVRD R13,0xDEAD",
            "EXIT:",
            "HALT: JR HALT",
        ]
    )
    return "\n".join(lines) + "\n"


def build_config(args: argparse.Namespace) -> GeneratorConfig:
    opcode_weights = parse_weight_map(args.opcode_weights)
    register_weights = parse_weight_map(args.register_weights)
    targeted_bins = load_targeted_bins(args.coverage_targets)

    if targeted_bins:
        opcode_weights.setdefault("ARITH", 3)
        opcode_weights.setdefault("UNARY", 2)
        if any(name.startswith("mem_") for name in targeted_bins):
            args.load_store_density = max(args.load_store_density, 0.35)
        if any(name in targeted_bins for name in {"jrc_taken", "jrnc_taken", "jrz_taken", "jrnz_taken", "jrs_taken", "jrns_taken"}):
            args.branch_density = max(args.branch_density, 0.35)

    return GeneratorConfig(
        body_ops=args.body_ops,
        branch_density=args.branch_density,
        load_store_density=args.load_store_density,
        loop_probability=args.loop_probability,
        max_loop_depth=args.max_loop_depth,
        program_prefix="coverage-driven" if targeted_bins else "baseline",
        opcode_weights=opcode_weights,
        register_weights=register_weights,
        targeted_bins=targeted_bins,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate bounded random assembly tests")
    parser.add_argument("--out-dir", type=pathlib.Path, required=True)
    parser.add_argument("--count", type=int, default=4)
    parser.add_argument("--seed-base", type=int, default=100)
    parser.add_argument("--body-ops", type=int, default=8)
    parser.add_argument("--opcode-weights")
    parser.add_argument("--register-weights")
    parser.add_argument("--branch-density", type=float, default=0.25)
    parser.add_argument("--load-store-density", type=float, default=0.25)
    parser.add_argument("--loop-probability", type=float, default=0.10)
    parser.add_argument("--max-loop-depth", type=int, default=4)
    parser.add_argument("--coverage-targets", type=pathlib.Path)
    args = parser.parse_args()

    config = build_config(args)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    for idx in range(args.count):
        seed = args.seed_base + idx
        name = f"rand_{seed}"
        if config.targeted_bins:
            name = f"rand_cov_{seed}"
        asm_path = args.out_dir / f"{name}.asm"
        asm_path.write_text(emit_random_program(seed, config), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
