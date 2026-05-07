// Pure C++ ISA-level golden model for the cpu_core, including the
// A/B/C extensions defined in `Isa扩展设计说明 A B C指令方案.pdf`.
//
// Contract: one call to step() advances the model by exactly one
// instruction (single-word, double-word, or CALLA). It exposes the
// architectural state visible at instruction retirement boundaries:
// regs[16], pc, flags, mem[64K]. This is what the differential
// testbench compares against the RTL after each retire event.

#pragma once

#include <array>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

struct GoldenFlags {
    uint8_t c = 0;
    uint8_t z = 0;
    uint8_t v = 0;
    uint8_t s = 0;
};

class GoldenIsa {
public:
    GoldenIsa() {
        mem_.fill(0);
        for (auto& r : regs_) r = 0;
    }

    void load_words(const std::vector<uint16_t>& image) {
        size_t n = std::min(image.size(), mem_.size());
        for (size_t i = 0; i < n; i++) mem_[i] = image[i];
    }

    void poke(uint16_t addr, uint16_t val) { mem_[addr] = val; }
    uint16_t peek(uint16_t addr) const { return mem_[addr]; }

    uint16_t reg(int i) const { return regs_[i & 0xF]; }
    uint16_t pc()  const { return pc_; }
    const GoldenFlags& flags() const { return flags_; }
    uint16_t last_ir() const { return last_ir_; }
    uint16_t last_pc() const { return last_pc_; }
    uint64_t steps() const { return steps_; }

    // Execute one instruction. Returns the IR word that was retired.
    uint16_t step() {
        last_pc_   = pc_;
        uint16_t ir = mem_[pc_];
        last_ir_   = ir;
        pc_        = (pc_ + 1) & 0xFFFF;
        uint8_t op = (ir >> 8) & 0xFF;
        uint8_t dr = (ir >> 4) & 0xF;
        uint8_t sr =  ir       & 0xF;

        switch (op) {
        // -------- existing single-word reg/reg ALU --------
        case 0x00: { // ADD
            uint16_t a = regs_[sr], b = regs_[dr];
            uint32_t full = uint32_t(b) + uint32_t(a);
            uint16_t r = uint16_t(full);
            regs_[dr] = r;
            update_add_flags(a, b, r, (full >> 16) & 1);
            break;
        }
        case 0x01: { // SUB
            uint16_t a = regs_[sr], b = regs_[dr];
            uint32_t full = (uint32_t(b) - uint32_t(a)) & 0x1FFFF;
            uint16_t r = uint16_t(full);
            regs_[dr] = r;
            update_sub_flags(a, b, r, (full >> 16) & 1);
            break;
        }
        case 0x02: { // AND
            uint16_t r = regs_[dr] & regs_[sr];
            regs_[dr] = r;
            update_logic_flags(r);
            break;
        }
        case 0x03: { // CMP (no writeback)
            uint16_t a = regs_[sr], b = regs_[dr];
            uint32_t full = (uint32_t(b) - uint32_t(a)) & 0x1FFFF;
            uint16_t r = uint16_t(full);
            update_sub_flags(a, b, r, (full >> 16) & 1);
            break;
        }
        case 0x04: { // XOR
            uint16_t r = regs_[dr] ^ regs_[sr];
            regs_[dr] = r;
            update_logic_flags(r);
            break;
        }
        case 0x05: { // TEST (no writeback)
            uint16_t r = regs_[dr] & regs_[sr];
            update_logic_flags(r);
            break;
        }
        case 0x06: { // OR
            uint16_t r = regs_[dr] | regs_[sr];
            regs_[dr] = r;
            update_logic_flags(r);
            break;
        }
        case 0x07: { // MVRR (no flag update)
            regs_[dr] = regs_[sr];
            break;
        }
        case 0x08: { // DEC
            uint16_t b = regs_[dr];
            uint32_t full = (uint32_t(b) - 1) & 0x1FFFF;
            uint16_t r = uint16_t(full);
            regs_[dr] = r;
            update_sub_flags(1, b, r, (full >> 16) & 1);
            break;
        }
        case 0x09: { // INC
            uint16_t b = regs_[dr];
            uint32_t full = uint32_t(b) + 1;
            uint16_t r = uint16_t(full);
            regs_[dr] = r;
            update_add_flags(0, b, r, (full >> 16) & 1);
            break;
        }
        case 0x0A: { // SHL
            uint16_t b = regs_[dr];
            uint16_t r = uint16_t(b << 1);
            regs_[dr] = r;
            flags_.c = (b & 0x8000) ? 1 : 0;
            flags_.z = (r == 0);
            flags_.v = 0;
            flags_.s = (r & 0x8000) ? 1 : 0;
            break;
        }
        case 0x0B: { // SHR
            uint16_t b = regs_[dr];
            uint16_t r = b >> 1;
            regs_[dr] = r;
            flags_.c = b & 1;
            flags_.z = (r == 0);
            flags_.v = 0;
            flags_.s = (r & 0x8000) ? 1 : 0;
            break;
        }
        case 0x0C: { // ADC
            uint16_t a = regs_[sr], b = regs_[dr];
            uint32_t full = uint32_t(b) + uint32_t(a) + flags_.c;
            uint16_t r = uint16_t(full);
            regs_[dr] = r;
            update_add_flags(a, b, r, (full >> 16) & 1);
            break;
        }
        case 0x0D: { // SBB
            uint16_t a = regs_[sr], b = regs_[dr];
            uint32_t full = (uint32_t(b) - uint32_t(a) - flags_.c) & 0x1FFFF;
            uint16_t r = uint16_t(full);
            regs_[dr] = r;
            update_sub_flags(a, b, r, (full >> 16) & 1);
            break;
        }
        // -------- A-class additions (NOT, ASR) --------
        case 0x0E: { // NOT
            uint16_t b = regs_[dr];
            uint16_t r = uint16_t(~b);
            regs_[dr] = r;
            // Per spec: C cleared, V cleared, Z by result, S by bit15.
            flags_.c = 0;
            flags_.v = 0;
            flags_.z = (r == 0);
            flags_.s = (r & 0x8000) ? 1 : 0;
            break;
        }
        case 0x0F: { // ASR
            uint16_t b = regs_[dr];
            uint16_t r = uint16_t((b & 0x8000) | (b >> 1));
            regs_[dr] = r;
            // Per spec: C = old bit0, V cleared, Z by result, S by bit15.
            flags_.c = b & 1;
            flags_.v = 0;
            flags_.z = (r == 0);
            flags_.s = (r & 0x8000) ? 1 : 0;
            break;
        }
        // -------- branches --------
        case 0x40: case 0x41: case 0x43:
        case 0x44: case 0x45: case 0x46: case 0x47: {
            int8_t off = int8_t(ir & 0xFF);
            bool take = false;
            switch (op) {
            case 0x40: take = true;            break;
            case 0x41: take = (flags_.s == 1); break;
            case 0x43: take = (flags_.s == 0); break;
            case 0x44: take = (flags_.c == 1); break;
            case 0x45: take = (flags_.c == 0); break;
            case 0x46: take = (flags_.z == 1); break;
            case 0x47: take = (flags_.z == 0); break;
            }
            if (take) pc_ = uint16_t(pc_ + off);
            break;
        }
        // -------- flag set/clear --------
        case 0x78: flags_.c = 0; break;
        case 0x7A: flags_.c = 1; break;
        // -------- existing double-word --------
        case 0x80: { // JMPA addr16
            uint16_t target = mem_[pc_];
            pc_ = target;
            break;
        }
        case 0x81: { // MVRD dr, imm16
            uint16_t imm = mem_[pc_];
            pc_ = (pc_ + 1) & 0xFFFF;
            regs_[dr] = imm;
            break;
        }
        case 0x82: { // LDRR dr <- mem[sr]
            uint16_t addr = regs_[sr];
            regs_[dr] = mem_[addr];
            break;
        }
        case 0x83: { // STRR mem[dr] <- sr
            uint16_t addr = regs_[dr];
            mem_[addr] = regs_[sr];
            break;
        }
        // -------- B-class additions (ADDI, ANDI) --------
        case 0x84: { // ADDI dr, imm16   (dr <- dr + imm16, full add flags)
            uint16_t imm = mem_[pc_];
            pc_ = (pc_ + 1) & 0xFFFF;
            uint16_t a = imm, b = regs_[dr];
            uint32_t full = uint32_t(b) + uint32_t(a);
            uint16_t r = uint16_t(full);
            regs_[dr] = r;
            update_add_flags(a, b, r, (full >> 16) & 1);
            break;
        }
        case 0x85: { // ANDI dr, imm16   (dr <- dr & imm16, AND flags)
            uint16_t imm = mem_[pc_];
            pc_ = (pc_ + 1) & 0xFFFF;
            uint16_t r = regs_[dr] & imm;
            regs_[dr] = r;
            update_logic_flags(r);
            break;
        }
        // -------- C-class addition (CALLA) --------
        case 0xF0: { // CALLA rel8: R15 <- pc_after_calla, PC <- pc_after_calla + rel8
            (void)mem_[pc_];                    // reserved second word, fetched but ignored
            uint16_t ret = (pc_ + 1) & 0xFFFF;  // address right after the reserved word
            regs_[15] = ret;
            pc_       = uint16_t(ret + int8_t(ir & 0xFF));
            // FLAGS unchanged (SST_HOLD)
            break;
        }
        default:
            throw std::runtime_error("GoldenIsa: unsupported opcode 0x" +
                                     to_hex2(op) + " at PC 0x" + to_hex4(last_pc_));
        }

        steps_++;
        return ir;
    }

    static std::string to_hex2(uint8_t v) {
        const char* hex = "0123456789ABCDEF";
        std::string s; s.push_back(hex[(v >> 4) & 0xF]); s.push_back(hex[v & 0xF]);
        return s;
    }
    static std::string to_hex4(uint16_t v) {
        const char* hex = "0123456789ABCDEF";
        std::string s;
        s.push_back(hex[(v >> 12) & 0xF]);
        s.push_back(hex[(v >>  8) & 0xF]);
        s.push_back(hex[(v >>  4) & 0xF]);
        s.push_back(hex[ v        & 0xF]);
        return s;
    }

private:
    void update_logic_flags(uint16_t r) {
        flags_.c = 0;
        flags_.v = 0;
        flags_.z = (r == 0);
        flags_.s = (r & 0x8000) ? 1 : 0;
    }
    void update_add_flags(uint16_t a, uint16_t b, uint16_t r, uint8_t cout) {
        flags_.c = cout;
        flags_.z = (r == 0);
        flags_.v = (((a ^ r) & (b ^ r) & 0x8000) != 0);
        flags_.s = (r & 0x8000) ? 1 : 0;
    }
    void update_sub_flags(uint16_t a, uint16_t b, uint16_t r, uint8_t cout) {
        // Mirrors reference_model.py _update_sub_flags.
        flags_.c = cout;
        flags_.z = (r == 0);
        flags_.v = (((a ^ b) & (r ^ b) & 0x8000) != 0);
        flags_.s = (r & 0x8000) ? 1 : 0;
    }

    std::array<uint16_t, 16>    regs_{};
    std::array<uint16_t, 65536> mem_{};
    uint16_t                    pc_       = 0;
    GoldenFlags                 flags_{};
    uint16_t                    last_ir_  = 0;
    uint16_t                    last_pc_  = 0;
    uint64_t                    steps_    = 0;
};
