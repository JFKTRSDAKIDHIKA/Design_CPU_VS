// Differential testbench: drives the cpu_top RTL via Verilator and a
// pure-C++ ISA-level golden model in lock-step, comparing the full
// architectural state (R0..R15, PC, flags) at every instruction
// retirement boundary.
//
// Usage:
//   ./Vverilator_top_diff <hex_path>
//
// The hex file format is one 16-bit word per line in hex (matches
// model/assembler.py output).

#include "Vverilator_top.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include "golden_isa.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace {

constexpr int    kMemWords     = 65536;
constexpr int    kResetCycles  = 4;
constexpr int    kMaxCycles    = 200000;
constexpr int    kMaxRetires   = 4000;

// FSM stage codes (must match controller.sv localparams).
constexpr uint8_t kStageFetchAddress     = 0b000;
constexpr uint8_t kStageFetchDecode      = 0b001;
constexpr uint8_t kStageExecuteSingle    = 0b011;
constexpr uint8_t kStageFetchSecondWord  = 0b101;
constexpr uint8_t kStageExecuteDouble    = 0b111;
constexpr uint8_t kStageSaveReturnAddr   = 0b010;
constexpr uint8_t kStageLoadCallTarget   = 0b110;

bool load_hex(const std::string& path, std::vector<uint16_t>& out) {
    std::ifstream f(path);
    if (!f) {
        std::fprintf(stderr, "ERROR: cannot open %s\n", path.c_str());
        return false;
    }
    std::string line;
    while (std::getline(f, line)) {
        // strip whitespace
        size_t b = line.find_first_not_of(" \t\r\n");
        if (b == std::string::npos) continue;
        size_t e = line.find_last_not_of(" \t\r\n");
        line = line.substr(b, e - b + 1);
        if (line.empty()) continue;
        unsigned long w = std::stoul(line, nullptr, 16);
        out.push_back(uint16_t(w));
    }
    return true;
}

class Tb {
public:
    Tb() {
        dut_ = new Vverilator_top;
        mem_.assign(kMemWords, 0);
        dut_->clk        = 0;
        dut_->reset      = 0;
        dut_->sel        = 0;
        dut_->reg_sel    = 0;
        dut_->mem_to_cpu = 0;
    }
    ~Tb() { delete dut_; }

    void load(const std::vector<uint16_t>& image) {
        std::fill(mem_.begin(), mem_.end(), 0);
        for (size_t i = 0; i < image.size() && i < mem_.size(); i++) {
            mem_[i] = image[i];
        }
    }

    void apply_reset() {
        dut_->reset = 0;
        for (int i = 0; i < kResetCycles; i++) tick();
        dut_->reset = 1;
        // FSM leaves STAGE_RESET_INIT at the next edge.
        tick();
    }

    void tick() {
        dut_->clk = 0;
        dut_->mem_to_cpu = mem_[dut_->address_bus];
        dut_->eval();

        uint16_t bus_addr  = dut_->address_bus;
        uint16_t bus_data  = dut_->cpu_to_mem;
        bool     bus_write = (dut_->wr == 0);

        dut_->clk = 1;
        dut_->mem_to_cpu = mem_[dut_->address_bus];
        dut_->eval();

        if (bus_write) mem_[bus_addr] = bus_data;

        dut_->mem_to_cpu = mem_[dut_->address_bus];
        dut_->eval();
        cycle_count_++;
    }

    uint16_t read_reg(int idx) {
        dut_->sel     = 0;
        dut_->reg_sel = idx & 0xF;
        dut_->eval();
        return dut_->reg_data;
    }

    uint16_t pc()    const { return dut_->pc_value; }
    uint16_t r15()   const { return dut_->r15_value; }
    uint16_t ir()    const { return dut_->ir_value; }
    uint8_t  stage() const { return dut_->execution_stage & 0x7; }
    uint8_t  flag_c() const { return dut_->c; }
    uint8_t  flag_z() const { return dut_->z; }
    uint8_t  flag_v() const { return dut_->v; }
    uint8_t  flag_s() const { return dut_->s; }
    uint64_t cycles() const { return cycle_count_; }
    uint16_t mem(uint16_t addr) const { return mem_[addr]; }

private:
    Vverilator_top* dut_ = nullptr;
    uint64_t cycle_count_ = 0;
    std::vector<uint16_t> mem_;
};

// Determine whether a given stage is the "last execute beat" for
// whichever instruction is currently in IR. After spending one cycle
// in such a stage the architectural state is final; the next cycle
// will be the next instruction's fetch.
bool is_retire_stage(uint8_t stage, uint16_t ir) {
    uint8_t op = (ir >> 8) & 0xFF;
    if (op == 0xF0) {
        return stage == kStageLoadCallTarget;  // C-class: 3 execute beats
    }
    // B-class double-word ops retire after STAGE_EXECUTE_DOUBLE (111).
    // A-class / branches / flag ops retire after STAGE_EXECUTE_SINGLE (011).
    // We use the IR opcode to choose, since at retire time IR holds the
    // first word of the instruction.
    if (op == 0x80 || op == 0x81 || op == 0x82 || op == 0x83 ||
        op == 0x84 || op == 0x85) {
        return stage == kStageExecuteDouble;
    }
    return stage == kStageExecuteSingle;
}

struct Snapshot {
    uint16_t regs[16];
    uint16_t pc;
    uint8_t  c, z, v, s;
};

Snapshot snap_rtl(Tb& tb) {
    Snapshot s{};
    for (int i = 0; i < 16; i++) s.regs[i] = tb.read_reg(i);
    s.pc = tb.pc();
    s.c = tb.flag_c();
    s.z = tb.flag_z();
    s.v = tb.flag_v();
    s.s = tb.flag_s();
    return s;
}

Snapshot snap_golden(const GoldenIsa& g) {
    Snapshot s{};
    for (int i = 0; i < 16; i++) s.regs[i] = g.reg(i);
    s.pc = g.pc();
    s.c = g.flags().c;
    s.z = g.flags().z;
    s.v = g.flags().v;
    s.s = g.flags().s;
    return s;
}

void dump_snapshot(const char* tag, const Snapshot& s) {
    std::printf("  %-7s PC=%04X  C=%d Z=%d V=%d S=%d\n",
                tag, s.pc, s.c, s.z, s.v, s.s);
    for (int i = 0; i < 16; i += 8) {
        std::printf("          ");
        for (int j = 0; j < 8; j++) {
            std::printf("R%-2d=%04X ", i + j, s.regs[i + j]);
        }
        std::printf("\n");
    }
}

bool snapshots_equal(const Snapshot& a, const Snapshot& b, std::string& diff) {
    std::ostringstream oss;
    bool ok = true;
    for (int i = 0; i < 16; i++) {
        if (a.regs[i] != b.regs[i]) {
            oss << "R" << i << "(rtl=" << std::hex << a.regs[i]
                << " gold=" << b.regs[i] << ") ";
            ok = false;
        }
    }
    if (a.pc != b.pc) { oss << "PC(rtl=" << std::hex << a.pc << " gold=" << b.pc << ") "; ok = false; }
    if (a.c  != b.c ) { oss << "C(rtl="  << int(a.c)  << " gold=" << int(b.c) << ") "; ok = false; }
    if (a.z  != b.z ) { oss << "Z(rtl="  << int(a.z)  << " gold=" << int(b.z) << ") "; ok = false; }
    if (a.v  != b.v ) { oss << "V(rtl="  << int(a.v)  << " gold=" << int(b.v) << ") "; ok = false; }
    if (a.s  != b.s ) { oss << "S(rtl="  << int(a.s)  << " gold=" << int(b.s) << ") "; ok = false; }
    diff = oss.str();
    return ok;
}

} // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 2) {
        std::fprintf(stderr, "Usage: %s <hex_path>\n", argv[0]);
        return 1;
    }

    std::vector<uint16_t> image;
    if (!load_hex(argv[1], image)) return 1;
    std::printf("[diff] loaded %zu words from %s\n", image.size(), argv[1]);

    Tb tb;
    tb.load(image);
    GoldenIsa golden;
    golden.load_words(image);

    tb.apply_reset();

    int retires       = 0;
    int mismatches    = 0;
    uint16_t prev_ir  = 0;
    bool was_retire   = false;
    uint64_t halt_streak = 0;

    for (uint64_t cyc = 0; cyc < kMaxCycles; cyc++) {
        // Detect the leaving edge of a retire stage: we were in a retire
        // stage last cycle and have moved to a different stage now.
        uint8_t cur_stage = tb.stage();
        uint16_t cur_ir   = tb.ir();
        bool cur_retire   = is_retire_stage(cur_stage, cur_ir);

        if (was_retire && !cur_retire) {
            // RTL just finished one instruction; advance golden once.
            uint16_t pc_before = golden.pc();
            uint16_t ir_g      = golden.step();
            (void)ir_g;

            Snapshot a = snap_rtl(tb);
            Snapshot b = snap_golden(golden);
            std::string diff;
            if (!snapshots_equal(a, b, diff)) {
                std::printf("\n[FAIL] mismatch after retire #%d (golden_pc_before=%04X ir=%04X)\n",
                            retires, pc_before, ir_g);
                std::printf("  diff: %s\n", diff.c_str());
                dump_snapshot("RTL",    a);
                dump_snapshot("GOLDEN", b);
                mismatches++;
                if (mismatches >= 5) {
                    std::printf("[diff] aborting after %d mismatches\n", mismatches);
                    return 1;
                }
            } else {
                if (retires < 64 || (retires % 8) == 0) {
                    std::printf("[ok ] retire #%-3d  pc=%04X ir=%04X  %s\n",
                                retires, pc_before, ir_g,
                                ir_g == 0x40FF ? "(halt)" : "");
                }
            }

            // Halt detection: golden hit JR -1 self-loop.
            if (ir_g == 0x40FF) {
                halt_streak++;
                if (halt_streak >= 3) {
                    std::printf("[diff] golden settled into JR -1 halt loop after %d retires\n", retires + 1);
                    if (mismatches == 0) {
                        std::printf("\n[PASS] %d retires, 0 mismatches over %llu cycles\n",
                                    retires + 1, (unsigned long long)tb.cycles());
                        return 0;
                    } else {
                        std::printf("\n[FAIL] %d mismatches\n", mismatches);
                        return 1;
                    }
                }
            } else {
                halt_streak = 0;
            }
            retires++;
            if (retires >= kMaxRetires) {
                std::printf("[diff] hit retire cap %d\n", kMaxRetires);
                break;
            }
        }

        was_retire = cur_retire;
        prev_ir    = cur_ir;
        tb.tick();
    }

    std::printf("\n[diff] simulation cycle cap reached: cycles=%llu retires=%d mismatches=%d\n",
                (unsigned long long)tb.cycles(), retires, mismatches);
    return mismatches == 0 ? 0 : 1;
}
