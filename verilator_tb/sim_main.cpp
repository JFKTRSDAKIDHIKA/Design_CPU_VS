// Verilator C++ testbench targeting the new C-class instruction `CALLA addr16`.
//
// CALLA encoding (32-bit, two memory words):
//   word0: 16'hF000  (opcode 8'hF0, 8'h00 ignored)
//   word1: addr16    (absolute call target)
//
// Architectural effect:
//   R15 <- PC of the instruction following CALLA  (i.e., addr_calla + 2)
//   PC  <- addr16
//   FLAGS unchanged.
//
// The DUT is a multi-cycle CPU, so a single CALLA flows through stages:
//   FETCH_ADDRESS (000) -> FETCH_DECODE (001) -> FETCH_SECOND_WORD (101)
//   -> SAVE_RETURN_ADDRESS (010) -> LOAD_CALL_TARGET (110)
//   -> next instruction's FETCH_ADDRESS (000)
//
// This testbench runs several directed scenarios, each loading a small program
// into a 64K-word memory model and checking R15/PC/FLAGS at well-defined points.
//
// Usage:
//   make -C verilator_tb run

#include "Vverilator_top.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

constexpr int    kMemWords   = 65536;
constexpr int    kResetCycles = 4;
constexpr int    kMaxCycles   = 2000;

// Stage codes that mark instruction retirement (matches tb_top.sv).
constexpr uint8_t kStageExecuteSingle = 0b011;
constexpr uint8_t kStageExecuteDouble = 0b111;
// Last execute beat of the C-group (CALLA) flow.
constexpr uint8_t kStageLoadCallTarget = 0b110;

struct TestResult {
    std::string name;
    bool        pass;
    std::string detail;
};

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

    ~Tb() {
        if (trace_) {
            trace_->close();
            delete trace_;
        }
        delete dut_;
    }

    void enable_trace(const std::string& path) {
        Verilated::traceEverOn(true);
        trace_ = new VerilatedVcdC;
        dut_->trace(trace_, 99);
        trace_->open(path.c_str());
    }

    void load_program(const std::vector<std::pair<uint16_t, uint16_t>>& patches) {
        std::fill(mem_.begin(), mem_.end(), 0);
        for (auto& p : patches) {
            mem_[p.first] = p.second;
        }
    }

    void apply_reset() {
        dut_->reset = 0;
        for (int i = 0; i < kResetCycles; i++) {
            tick();
        }
        dut_->reset = 1;
        // Allow FSM to leave state0.
        tick();
    }

    // Drive one full clock cycle (low->high->low) and update the C++ memory.
    void tick() {
        // Phase 1: clk low; provide read data based on current address_bus.
        dut_->clk = 0;
        dut_->mem_to_cpu = mem_[dut_->address_bus];
        dut_->eval();
        dump();

        // Capture the values that will be sampled at the rising edge BEFORE
        // we let the DUT update its registers.
        uint16_t bus_addr   = dut_->address_bus;
        uint16_t bus_data   = dut_->cpu_to_mem;
        bool     bus_write  = (dut_->wr == 0);

        // Phase 2: rising edge.
        dut_->clk = 1;
        dut_->mem_to_cpu = mem_[dut_->address_bus];
        dut_->eval();

        // Memory model: mirror `always @(posedge clk) if (wr==0) mem<=data`.
        if (bus_write) {
            mem_[bus_addr] = bus_data;
        }

        // Refresh read data after register updates so the DUT sees the new
        // value on the next combinational settle.
        dut_->mem_to_cpu = mem_[dut_->address_bus];
        dut_->eval();
        dump();

        cycle_count_++;
    }

    // Read register value through the existing reg_out debug mux.
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
    bool     flag_c() const { return dut_->c; }
    bool     flag_z() const { return dut_->z; }
    bool     flag_v() const { return dut_->v; }
    bool     flag_s() const { return dut_->s; }

    uint64_t cycles() const { return cycle_count_; }

    // Step until execution_stage transitions FROM `target_stage` (i.e., the DUT
    // just spent one cycle in target_stage and is now leaving it).  Returns
    // false on timeout.
    bool run_until_just_after_stage(uint8_t target_stage, int max_cycles = kMaxCycles) {
        bool seen = false;
        for (int i = 0; i < max_cycles; i++) {
            if (stage() == target_stage) {
                seen = true;
            } else if (seen) {
                return true;
            }
            tick();
        }
        return false;
    }

    // Tick until PC equals `target_pc` at the start of a fetch (state 000).
    bool run_until_pc(uint16_t target_pc, int max_cycles = kMaxCycles) {
        for (int i = 0; i < max_cycles; i++) {
            if (stage() == 0b000 && pc() == target_pc) return true;
            tick();
        }
        return false;
    }

    // Tick until CPU reaches the LOAD_CALL_TARGET stage and just leaves it,
    // i.e. the CALLA has fully retired but the next fetch hasn't yet
    // incremented PC.  Useful for checking PC right after CALLA.
    bool run_through_calla(int max_cycles = kMaxCycles) {
        bool in_state7 = false;
        for (int i = 0; i < max_cycles; i++) {
            if (stage() == kStageLoadCallTarget) {
                in_state7 = true;
            }
            if (in_state7 && stage() != kStageLoadCallTarget) {
                // CALLA has finished the LOAD_CALL_TARGET beat and is now
                // entering the next fetch's state1.  The PC register holds
                // the call target.
                return true;
            }
            tick();
        }
        return false;
    }

private:
    void dump() {
        if (trace_) {
            trace_->dump(static_cast<vluint64_t>(time_));
            time_++;
        }
    }

    Vverilator_top* dut_   = nullptr;
    VerilatedVcdC*  trace_ = nullptr;
    uint64_t        time_  = 0;
    uint64_t        cycle_count_ = 0;
    std::vector<uint16_t> mem_;
};

// ---- Individual tests ---------------------------------------------------

TestResult test_basic_calla_at_zero() {
    Tb tb;
    // CALLA 0x0050 located at PC=0; arbitrary harmless instruction at target.
    tb.load_program({
        {0x0000, 0xF000}, // CALLA opcode word
        {0x0001, 0x0050}, // target address
        {0x0050, 0x40FE}, // JR -2 (busy loop) at the target
    });

    tb.apply_reset();
    bool ok_run = tb.run_through_calla(kMaxCycles);
    TestResult r{"basic_calla_at_zero", false, ""};
    if (!ok_run) {
        r.detail = "timeout waiting for CALLA to retire";
        return r;
    }
    uint16_t pc  = tb.pc();
    uint16_t r15 = tb.r15();
    bool flags_unchanged = (!tb.flag_c() && !tb.flag_z() && !tb.flag_v() && !tb.flag_s());
    char buf[256];
    std::snprintf(buf, sizeof(buf),
        "PC=0x%04X (exp 0x0050), R15=0x%04X (exp 0x0002), flags czvs=%d%d%d%d",
        pc, r15, tb.flag_c(), tb.flag_z(), tb.flag_v(), tb.flag_s());
    r.detail = buf;
    r.pass = (pc == 0x0050) && (r15 == 0x0002) && flags_unchanged;
    return r;
}

TestResult test_calla_after_some_setup() {
    Tb tb;
    // Setup R0=42, set carry, then CALLA 0x0100. Verify CALLA preserves carry
    // and writes the right return address.
    // Program layout:
    //   0x0000: MVRD R0, #imm   (opcode 0x81: load mem[PC+1] into R0; double-word)
    //           Encoding: instruction[7:4] = R0 = 0x0, [3:0] = src(unused) = 0x0
    //   0x0001: 0x002A           (immediate 42)
    //   0x0002: STC               (opcode 0x7A, single word)
    //   0x0003: CALLA 0x0100      (opcode 0xF0)
    //   0x0004: 0x0100            (call target)
    //   0x0100: JR -2             (halt loop at target)
    tb.load_program({
        {0x0000, 0x8100}, // MVRD R0, #imm
        {0x0001, 0x002A}, // 42
        {0x0002, 0x7A00}, // STC
        {0x0003, 0xF000}, // CALLA opcode
        {0x0004, 0x0100}, // target
        {0x0100, 0x40FE}, // JR -2
    });

    tb.apply_reset();

    // Step until we observe CALLA retire (state 110 followed by state transition).
    // To make it deterministic, just keep running while observing.
    bool ok_run = false;
    bool saw_state7 = false;
    for (int i = 0; i < kMaxCycles; i++) {
        // Watch for IR == 0xF000 entering state7.
        if (tb.stage() == kStageLoadCallTarget && tb.ir() == 0xF000) {
            saw_state7 = true;
        }
        if (saw_state7 && tb.stage() != kStageLoadCallTarget) {
            ok_run = true;
            break;
        }
        tb.tick();
    }

    TestResult r{"calla_after_some_setup", false, ""};
    if (!ok_run) {
        r.detail = "timeout waiting for CALLA at PC=0x0003 to retire";
        return r;
    }

    uint16_t r0  = tb.read_reg(0);
    uint16_t r15 = tb.r15();
    uint16_t pc  = tb.pc();
    bool c_after = tb.flag_c();

    char buf[256];
    std::snprintf(buf, sizeof(buf),
        "R0=0x%04X (exp 0x002A), R15=0x%04X (exp 0x0005), PC=0x%04X (exp 0x0100), C=%d (exp 1)",
        r0, r15, pc, c_after);
    r.detail = buf;
    r.pass = (r0 == 0x002A) && (r15 == 0x0005) && (pc == 0x0100) && c_after;
    return r;
}

TestResult test_nested_calla() {
    Tb tb;
    // CALLA from main to subroutine A, then CALLA from A to B.
    // Expect R15 to hold the inner-most return address (B's caller).
    //   0x0000: CALLA 0x0050    (call A)
    //   0x0001: 0x0050
    //   0x0050: CALLA 0x0080    (A immediately calls B)
    //   0x0051: 0x0080
    //   0x0080: JR -2           (loop at B)
    tb.load_program({
        {0x0000, 0xF000}, {0x0001, 0x0050},
        {0x0050, 0xF000}, {0x0051, 0x0080},
        {0x0080, 0x40FE},
    });

    tb.apply_reset();

    // Run two CALLAs.
    int calla_seen = 0;
    bool in_state7 = false;
    for (int i = 0; i < kMaxCycles; i++) {
        if (tb.stage() == kStageLoadCallTarget && tb.ir() == 0xF000) {
            in_state7 = true;
        }
        if (in_state7 && tb.stage() != kStageLoadCallTarget) {
            calla_seen++;
            in_state7 = false;
            if (calla_seen == 2) break;
        }
        tb.tick();
    }

    TestResult r{"nested_calla", false, ""};
    if (calla_seen < 2) {
        r.detail = "did not observe two CALLA retirements";
        return r;
    }

    uint16_t r15 = tb.r15();
    uint16_t pc  = tb.pc();

    char buf[256];
    std::snprintf(buf, sizeof(buf),
        "after second CALLA: PC=0x%04X (exp 0x0080), R15=0x%04X (exp 0x0052)",
        pc, r15);
    r.detail = buf;
    r.pass = (pc == 0x0080) && (r15 == 0x0052);
    return r;
}

TestResult test_calla_preserves_flags() {
    Tb tb;
    // Set flags via STC, then CALLA, then verify flags after the call.
    //   0x0000: STC
    //   0x0001: CALLA 0x0040
    //   0x0002: 0x0040
    //   0x0040: JR -2
    tb.load_program({
        {0x0000, 0x7A00},
        {0x0001, 0xF000},
        {0x0002, 0x0040},
        {0x0040, 0x40FE},
    });

    tb.apply_reset();

    bool in_state7 = false;
    bool ok_run = false;
    for (int i = 0; i < kMaxCycles; i++) {
        if (tb.stage() == kStageLoadCallTarget && tb.ir() == 0xF000) {
            in_state7 = true;
        }
        if (in_state7 && tb.stage() != kStageLoadCallTarget) {
            ok_run = true;
            break;
        }
        tb.tick();
    }

    TestResult r{"calla_preserves_flags", false, ""};
    if (!ok_run) { r.detail = "timeout"; return r; }

    bool c = tb.flag_c();
    bool z = tb.flag_z();
    bool v = tb.flag_v();
    bool s = tb.flag_s();
    char buf[256];
    std::snprintf(buf, sizeof(buf),
        "flags after CALLA: c=%d z=%d v=%d s=%d  (expected c=1, others=0)", c, z, v, s);
    r.detail = buf;
    r.pass = (c == 1) && (z == 0) && (v == 0) && (s == 0);
    return r;
}

TestResult test_calla_then_use_link_register() {
    Tb tb;
    // After CALLA, use R15 as an operand of an ADD to verify it really got the
    // correct return address (and is generally usable by other instructions).
    //   0x0000: CALLA 0x0030
    //   0x0001: 0x0030
    //   0x0002: <not executed; would have been the return point>
    //   0x0030: ADD R1, R15     ; R1 <- R1 + R15.  Opcode 0x00, dest=1, src=F
    //   0x0031: JR -2
    tb.load_program({
        {0x0000, 0xF000}, {0x0001, 0x0030},
        {0x0030, 0x001F},  // ADD R1, R15  (opcode 0x00, [7:4]=1, [3:0]=F)
        {0x0031, 0x40FE},
    });

    tb.apply_reset();

    // Run until JR -2 has been executed at least once, meaning everything before it ran.
    bool ok_run = false;
    int  jr_retires = 0;
    for (int i = 0; i < kMaxCycles; i++) {
        if (tb.stage() == kStageExecuteSingle && tb.ir() == 0x40FE) {
            jr_retires++;
            if (jr_retires >= 1) { ok_run = true; break; }
        }
        tb.tick();
    }

    TestResult r{"calla_then_use_link_register", false, ""};
    if (!ok_run) { r.detail = "timeout waiting for halt loop"; return r; }

    uint16_t r1  = tb.read_reg(1);
    uint16_t r15 = tb.r15();
    char buf[256];
    std::snprintf(buf, sizeof(buf),
        "R15=0x%04X (exp 0x0002), R1=0x%04X (exp 0x0002 = 0+R15)", r15, r1);
    r.detail = buf;
    r.pass = (r15 == 0x0002) && (r1 == 0x0002);
    return r;
}

} // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    std::vector<TestResult (*)()> tests = {
        test_basic_calla_at_zero,
        test_calla_after_some_setup,
        test_nested_calla,
        test_calla_preserves_flags,
        test_calla_then_use_link_register,
    };

    int passed = 0;
    int failed = 0;
    std::printf("================================================================\n");
    std::printf(" Verilator CALLA testbench\n");
    std::printf("================================================================\n");
    for (auto& fn : tests) {
        TestResult r = fn();
        std::printf("[%s] %s\n        %s\n",
            r.pass ? "PASS" : "FAIL",
            r.name.c_str(),
            r.detail.c_str());
        if (r.pass) passed++; else failed++;
    }
    std::printf("----------------------------------------------------------------\n");
    std::printf("Total: %zu  Passed: %d  Failed: %d\n", tests.size(), passed, failed);

    return failed == 0 ? 0 : 1;
}
