# `cpu_core` — 16-bit 多周期教学型 CPU

本仓库包含一颗 16-bit 多周期教学型 CPU 的 **完整微架构 RTL**、**ISA 扩展
（A/B/C 类指令）实现**，以及 **两套互补的功能验证流水**（VCS+UVM 与
Verilator+C++ Golden 差分）。

按 "微架构 → ISA → 测试 → 结果" 顺序组织本文档。

---

## 第一部分：微架构与 ISA

### 1.1 整体微架构

CPU 是一颗 **单总线、多周期** 的教学型 16-bit 机：

- **数据宽度**：16 bit；地址宽度 16 bit（64 K word 寻址）。
- **存储模型**：单一三态总线 `data_bus[15:0]`；`wr=1` 表示读、`wr=0` 表示写。
- **寄存器堆**：16 个通用寄存器 `R0..R15`，其中 `R15` 在 ISA 扩展中约定为
  *link register*。
- **执行模型**：每条指令分多个 *拍*（FSM stage）顺序完成，无流水重叠。

顶层结构（[`vsrc/cpu_top.sv`](vsrc/cpu_top.sv) → [`vsrc/cpu_core.sv`](vsrc/cpu_core.sv)）：

```
                       ┌──────────────────────────────────┐
                       │           cpu_core               │
   address_bus ◄──────┤  ┌─────────┐    ┌──────────────┐  │
                       │  │   PC    ├───►│              │  │
                       │  └─────────┘    │              │  │
   data_bus  ◄──┐      │  ┌─────────┐    │     ALU      │  │
                ├─────►│  │   IR    ├──┐ │              │  │
                │      │  └─────────┘  │ │              │  │
   wr        ◄──┤      │       │       │ └──────┬───────┘  │
                │      │       ▼       │        │          │
   c,z,v,s   ◄──┤      │  ┌─────────┐  │        ▼          │
                │      │  │Controller│  │  ┌──────────┐    │
                │      │  └─────────┘──┴─►│ Reg File │    │
                │      │       │          │ R0..R15  │    │
                │      │       ▼          └──────────┘    │
                │      │  ┌──────────┐    ┌──────────┐    │
                │      │  │FSM stage │    │ Flag Reg │    │
                │      │  │ (8 state)│    │ C/Z/V/S  │    │
                │      │  └──────────┘    └──────────┘    │
                       └──────────────────────────────────┘
```

主要 RTL 文件：

| 文件 | 作用 |
|---|---|
| [`vsrc/cpu_top.sv`](vsrc/cpu_top.sv) | 顶层封装、调试观察口 (`reg_out`/`reg_testa`) |
| [`vsrc/cpu_core.sv`](vsrc/cpu_core.sv) | 数据通路 + 各子模块互联 |
| [`vsrc/controller.sv`](vsrc/controller.sv) | 指令译码 + 各拍控制信号生成（节拍真值表） |
| [`vsrc/execution_stage_fsm.sv`](vsrc/execution_stage_fsm.sv) | 指令执行节拍 FSM（8 状态） |
| [`vsrc/alu.sv`](vsrc/alu.sv) | 16-bit ALU + flag 生成（C/Z/V/S） |
| [`vsrc/reg_file.sv`](vsrc/reg_file.sv) | 16×16 通用寄存器堆，单口写双口读 |
| [`vsrc/flag_reg.sv`](vsrc/flag_reg.sv) | 标志寄存器，受 `sst` 控制（HOLD/WRITE/CLR_C/SET_C） |
| [`vsrc/pc.sv`](vsrc/pc.sv) | 程序计数器 |
| [`vsrc/instruction_reg.sv`](vsrc/instruction_reg.sv) | 指令寄存器（IR），译码阶段锁存 |

### 1.2 执行节拍 FSM

`execution_stage_fsm` 共 8 个状态，编码为 3 位 `stage_code`：

| State | Code | 名称 | 说明 |
|---|---|---|---|
| `state0` | `100` | RESET_INIT | 复位初态，进入 `state1` |
| `state1` | `000` | FETCH_ADDRESS | 取指拍 1：`addr_bus ← PC, PC ← PC+1` |
| `state2` | `001` | FETCH_DECODE | 取指拍 2：`IR ← mem[addr_bus]`，依据 `IR[15]` 分流 |
| `state3` | `011` | EXECUTE_SINGLE | A 类（单字）指令的执行拍 ⇒ **退休** |
| `state4` | `101` | FETCH_SECOND_WORD | B/C 类双字指令取第二字（立即数 / 目标地址） |
| `state5` | `111` | EXECUTE_DOUBLE | B 类双字指令的执行拍 ⇒ **退休** |
| `state6` | `010` | SAVE_RETURN_ADDRESS | C 类（CALLA）保存返回地址到 `R15` |
| `state7` | `110` | LOAD_CALL_TARGET | C 类（CALLA）将目标字写入 PC ⇒ **退休** |

分流策略由 `state2` 末尾完成：

```
IR[15] == 0  →  state3   (A 类，单字)
IR[15] == 1  ┬→ state5   (B 类，双字 ALU/访存/跳转)
             └→ state7   (C 类，CALLA：经过 state6→state7)
其中 IR[15:8] == 8'hF0 时判定为 C 类
```

退休点定义（与 verification 对齐）：

- A 类：`state3 (011)` 离开拍
- B 类：`state5 (111)` 离开拍
- C 类（CALLA）：`state7 (110)` 离开拍

### 1.3 ALU 与 flag 生成

ALU 输入由 `alu_in_sel`（3 bit）选择 7 条通路：

| `alu_in_sel` | A 端 | B 端 | 用途 |
|---|---|---|---|
| `000 ALU_IN_REGS`   | `SR` | `DR` | 寄存器-寄存器运算 |
| `001 ALU_IN_SR`     | `SR` | `0`  | MVRR / 间接寻址源 |
| `010 ALU_IN_DR`     | `0`  | `DR` | 单寄存器运算 |
| `011 ALU_IN_BR`     | `imm8` (符号扩展) | `PC` | 相对分支 |
| `100 ALU_IN_PC`     | `0`  | `PC` | PC 自增、保存返回地址 |
| `101 ALU_IN_MEM`    | `0`  | `MEM` | 立即数装载、PC 跳转目标 |
| `110 ALU_IN_DR_MEM` | `MEM` | `DR` | **B 类 ADDI/ANDI 专用**：DR ⊕ 立即数 |

ALU 功能（`alu_func` 4 bit）：`ADD/SUB/AND/OR/XOR/SHL/SHR/NOT/ASR`，
其中 `NOT/ASR` 是 A 类扩展新增的功能码。

Flag 寄存器更新由 `sst` 控制：

| `sst` | 行为 |
|---|---|
| `00 SST_WRITE` | 全部由 ALU 计算结果更新 C/Z/V/S |
| `11 SST_HOLD`  | 保持（CALLA、MVRR、JR/JMPA 等不更新 flags） |
| `01 SST_CLR_C` | `CLC`：强制 C ← 0 |
| `10 SST_SET_C` | `STC`：强制 C ← 1 |

### 1.4 ISA 总览

CPU 的 ISA 通过 `IR[15]` 分为 **A 类（单字）** 和 **B/C 类（双字）**；双字
指令第二字紧跟第一字存放，由 `state4` 的额外取数拍读入。

#### A 类（单字，`IR[15]=0`）

| 助记符 | Opcode | 编码 | 语义 |
|---|---|---|---|
| `ADD  dr,sr`  | `00` | `00000000 dddd ssss` | `dr ← dr + sr`，flags=ADD |
| `SUB  dr,sr`  | `01` | `00000001 dddd ssss` | `dr ← dr - sr`，flags=SUB |
| `AND  dr,sr`  | `02` | `00000010 dddd ssss` | `dr ← dr & sr`，flags=LOGIC |
| `CMP  dr,sr`  | `03` | `00000011 dddd ssss` | flags=SUB（不写回） |
| `XOR  dr,sr`  | `04` | `00000100 dddd ssss` | `dr ← dr ^ sr`，flags=LOGIC |
| `TEST dr,sr`  | `05` | `00000101 dddd ssss` | flags=AND（不写回） |
| `OR   dr,sr`  | `06` | `00000110 dddd ssss` | `dr ← dr \| sr`，flags=LOGIC |
| `MVRR dr,sr`  | `07` | `00000111 dddd ssss` | `dr ← sr`（不更新 flags） |
| `DEC  dr`     | `08` | `00001000 dddd 0000` | `dr ← dr - 1`，flags=SUB |
| `INC  dr`     | `09` | `00001001 dddd 0000` | `dr ← dr + 1`，flags=ADD |
| `SHL  dr`     | `0A` | `00001010 dddd 0000` | `dr ← dr << 1`，C=old bit15 |
| `SHR  dr`     | `0B` | `00001011 dddd 0000` | `dr ← dr >> 1`，C=old bit0 |
| `ADC  dr,sr`  | `0C` | `00001100 dddd ssss` | `dr ← dr + sr + C`，flags=ADD |
| `SBB  dr,sr`  | `0D` | `00001101 dddd ssss` | `dr ← dr - sr - C`，flags=SUB |
| **`NOT  dr`** | **`0E`** | `00001110 dddd 0000` | **`dr ← ~dr`，C=0,V=0,Z,S（A 类扩展）** |
| **`ASR  dr`** | **`0F`** | `00001111 dddd 0000` | **`dr ← {dr[15], dr[15:1]}`，C=old dr[0]（A 类扩展）** |
| `JR   off`    | `40` | `01000000 oooooooo` | 无条件相对跳转，offset=signed8 |
| `JRS  off`    | `41` | `01000001 oooooooo` | S=1 时分支 |
| `JRNS off`    | `43` | `01000011 oooooooo` | S=0 时分支 |
| `JRC  off`    | `44` | `01000100 oooooooo` | C=1 时分支 |
| `JRNC off`    | `45` | `01000101 oooooooo` | C=0 时分支 |
| `JRZ  off`    | `46` | `01000110 oooooooo` | Z=1 时分支 |
| `JRNZ off`    | `47` | `01000111 oooooooo` | Z=0 时分支 |
| `CLC`         | `78` | `01111000 0000 0000` | C ← 0 |
| `STC`         | `7A` | `01111010 0000 0000` | C ← 1 |

#### B 类（双字，`IR[15]=1` 且 `IR[15:8] != 8'hF0`）

| 助记符 | Opcode | 第 1 字 | 第 2 字 | 语义 |
|---|---|---|---|---|
| `JMPA addr16`     | `80` | `10000000 0000 0000` | `addr16` | `PC ← addr16`（不更新 flags） |
| `MVRD dr,imm16`   | `81` | `10000001 dddd 0000` | `imm16`  | `dr ← imm16`（不更新 flags） |
| `LDRR dr,sr`      | `82` | `10000010 dddd ssss` | —        | `dr ← mem[sr]`（单字两拍） |
| `STRR dr,sr`      | `83` | `10000011 dddd ssss` | —        | `mem[dr] ← sr`（单字两拍） |
| **`ADDI dr,imm16`** | **`84`** | `10000100 dddd 0000` | `imm16` | **`dr ← dr + imm16`，flags=ADD（B 类扩展）** |
| **`ANDI dr,imm16`** | **`85`** | `10000101 dddd 0000` | `imm16` | **`dr ← dr & imm16`，flags=LOGIC（B 类扩展）** |

#### C 类（双字 + 三拍执行，`IR[15:8] == 8'hF0`）

| 助记符 | Opcode | 第 1 字 | 第 2 字 | 语义 |
|---|---|---|---|---|
| **`CALLA addr16`** | **`F0`** | `11110000 0000 0000` | `addr16` | **`R15 ← PC_after_calla; PC ← addr16`，flags 保持** |

`R15` 写入的是 *CALLA 后续指令地址*（即 `addr_calla + 2`），方便子程序返回。
注意 PDF 第 8 节预留 `RET` 候选，但当前 ISA 中**无 RET**，子程序通过显式
`JMPA <return_label>` 完成返回。

### 1.5 ISA 扩展（A/B/C 方案）的设计取舍

详见 [`Isa扩展设计说明 A B C指令方案.pdf`](Isa扩展设计说明%20A%20B%20C指令方案.pdf)。
五条扩展指令的分类依据：

- **A 类**（`NOT`/`ASR`）：单拍 ALU 一元操作，复用现有数据通路，仅 ALU
  增加 `ALU_NOT/ALU_ASR` 功能码 + controller 增加两条 opcode 译码即可。
- **B 类**（`ADDI`/`ANDI`）：双字立即数 ALU 操作，复用 B 类 "先取第二字、
  再执行" 的现有路径（与 `MVRD/JMPA` 同风格），ALU 通过 `ALU_IN_DR_MEM`
  把 DR 与第二字立即数喂给加法器/与门。
- **C 类**（`CALLA`）：唯一一条多拍控制流指令，需要 *先写 R15、再写 PC*
  两步顺序写回，因此必须新增 `state6/state7` 两个 FSM 状态；不引入栈、
  不引入乘法器等新硬件。

**改动范围严格限定在 controller / execution_stage_fsm / ALU**，与 PDF
"低硬件代价" 设计原则一致。

---

## 第二部分：测试

围绕 ISA 的功能正确性，本仓库提供 **两条互补的验证流水**：

| 流水 | 仿真器 | Oracle | 用途 |
|---|---|---|---|
| **UVM block-level** | VCS V-2023.12-SP2 | [`model/reference_model.py`](model/reference_model.py) | smoke / directed / random 回归 |
| **Verilator 差分** | Verilator 4.038 | [`verilator_tb/golden_isa.h`](verilator_tb/golden_isa.h) | A/B/C 扩展指令的逐指令对拍 |

### 2.1 UVM 流水（VCS）

[`uvm_tb/`](uvm_tb/) 下的 UVM 环境围绕 `cpu_core_if` 构建。

**架构**：

- `cpu_core_if`：统一封装 `reset/clk/wr/address_bus/data_bus`，提供 debug 采样任务。
- `cpu_memory_agent`：active driver 加载程序、responder 写回；monitor 采集
  总线事务和退休事件。
- `cpu_scoreboard`：从 Python reference 的 trace/summary 载入 golden，对
  RTL 做逐退休架构态比较，并在测试结束时做末态校验。
- `cpu_coverage_collector`：覆盖 opcode、寄存器、flags、branch taken/not-taken、
  memory read/write、地址区间。
- `cpu_base_test`：plusargs 接收 `program_hex/ref_trace/ref_summary/coverage_report`，
  派生出 smoke / directed / random 测试。

**退休语义假设**（与 RTL FSM 节拍对齐）：

- 单字指令：`execution_stage == 3'b011` 之后下一时钟沿。
- 双字指令：`execution_stage == 3'b111` 之后下一时钟沿。
- CALLA：`execution_stage == 3'b110` 之后下一时钟沿。

**使用**：

```bash
# 编译
./scripts/compile_vcs.sh

# 单测
./scripts/run_single_test.sh mult8 cpu_smoke_test sw/mult8.asm 1

# 完整回归
./scripts/run_regression.sh
```

回归输出：

- [`reports/regression_summary.txt`](reports/regression_summary.txt)
- [`reports/coverage/`](reports/coverage)
- `logs/uvm/`

### 2.2 Verilator 差分流水

针对 A/B/C 扩展指令构造的轻量级闭环：**RTL 跑 Verilator，C++ Golden 跑同一份
hex，按指令退休边界逐拍对拍**。Golden 直接映射 PDF 4.x 节的指令语义，与
RTL 数据通路独立实现，可以交叉佐证 controller / FSM / ALU 的修改是否正确。

#### 关键文件

- [`verilator_tb/verilator_top.sv`](verilator_tb/verilator_top.sv)：
  把 `cpu_top` 三态 `data_bus` 拆成单向端口，并把
  `pc_bus`、`instruction`、`regs[15]`、`execution_stage` 引出，便于 C++
  直接观测体系结构状态（无需依赖 Verilator 4.038 的内部信号导出）。
- [`verilator_tb/golden_isa.h`](verilator_tb/golden_isa.h)：纯 C++ ISA 级
  模拟器，覆盖原 ISA 全集 + 5 条新指令；`step()` 推进一条指令，
  暴露 `regs[16]/pc/flags/mem[64K]`。
- [`verilator_tb/diff_main.cpp`](verilator_tb/diff_main.cpp)：差分 testbench；
  按 FSM stage 边沿（`011/111/110` 离开）作为退休点，
  对 RTL 与 Golden 逐条比对全部 `R0..R15/PC/C/Z/V/S`。
- [`verilator_tb/sim_main.cpp`](verilator_tb/sim_main.cpp)：CALLA 单点
  定向 testbench（5 个用例）。
- [`sw/abc_diff.asm`](sw/abc_diff.asm)：133-word 长测试程序，覆盖 A/B/C
  指令边界条件和交叉路径（详见下节）。

#### 差分 testbench 工作机制

1. 加载 hex 进 Verilator 内存模型 + Golden 内存模型。
2. 跑 reset。
3. 每个时钟沿采样 RTL 当前 stage 与 IR：
   - 当 IR opcode 决定的 *退休 stage* "刚刚离开"（`was_retire && !cur_retire`）
     时，认为 RTL 完成了一条指令。
   - 此时把 Golden `step()` 一次，再读 RTL 的 R0..R15 / PC / C/Z/V/S，
     与 Golden 比对。
   - 任一字段不一致：打印 RTL/GOLDEN 双侧完整快照，记录 mismatch。
4. Golden 连续 3 次退休 IR=`0x40FF`（`JR -1` 自循环）则视为程序结束。
5. 累计 mismatch ≥ 5 或循环超 200 K 周期则停掉。

#### `sw/abc_diff.asm` 覆盖范围

| 测试段 | 关键覆盖 |
|---|---|
| **NOT** 全位模式 | `0x0000 / 0xAAAA / 0x8000 / 0xFFFF` 验证 `~`、Z/S 标志 |
| **ASR** 正负 + bit0 | 验证符号位保持与 `C = old bit0` |
| **ADDI** 标志触发 | `+0x0001` 翻越 `0x7FFF→0x8000`（V=1, S=1）；carry-out；Z=1 |
| **ANDI** 掩码 | 全清零、全通过、半字掩码，验证 `C=0,V=0,Z,S` |
| **NOT/ASR 链** | 在 ANDI 结果上做 NOT 再做 ASR，跨指令路径 |
| **CALLA 嵌套链** | `main → outer → inner` 多次 R15 覆盖；通过 `JMPA <ret_label>` 返回 |
| **R15 sample** | 在子程序入口用 `MVRR R13/R14, R15` 取出 link，事后比对 |
| **Flag-sensitive 分支** | `JRS/JRZ/JRC/JRNC` 紧跟 ADDI/ANDI/NOT/ASR，精确捕捉单 bit flag 错误 |
| **内存路径协同** | `STRR → LDRR → ADDI → ANDI → STRR → LDRR`，新指令与现有访存交叉 |
| **R15 作为源** | `CALLA after_link; ADD R7, R15` 验证 link register 可读 |

#### 构建与运行

```bash
cd verilator_tb

# CALLA 定向 testbench
make build      # 生成 obj_dir/Vverilator_top
make run

# A/B/C 差分长测试（一键完成 汇编→编译→运行）
make run-diff
```

`run-diff` 输出末尾形如：

```
[diff] golden settled into JR -1 halt loop after 78 retires
[PASS] 78 retires, 0 mismatches over 295 cycles
```

#### testbench 自身的有效性自检

差分 testbench 自带一次 sanity 校验：在 `golden_isa.h` 临时把 NOT 改成
`~b ^ 0x0001`（差一位）后重跑，testbench 立刻在 retire #1 报告：

```
[FAIL] mismatch after retire #1 (golden_pc_before=0002 ir=0E00)
  diff: R0(rtl=ffff gold=fffe)
  RTL     PC=0003  C=0 Z=0 V=0 S=1
          R0 =FFFF R1 =0000 ...
  GOLDEN  PC=0003  C=0 Z=0 V=0 S=1
          R0 =FFFE R1 =0000 ...
```

证明对拍机制不是平凡 PASS。

### 2.3 工具链

| 命令 | 作用 |
|---|---|
| `python3 model/assembler.py <asm> --hex-out <hex> --layout-out <layout>` | 汇编（已支持 NOT/ASR/ADDI/ANDI/CALLA） |
| `python3 model/reference_model.py --hex <hex> --trace-out … --summary-out …` | Python 参考模型（UVM oracle，**暂未支持 A/B/C**） |
| `bash scripts/compile_basic_vcs.sh; bash scripts/run_basic_vcs.sh <hex> cycle 1` | 不走 UVM 的 VCS 单步调试 |
| `make debug-build; make debug-run` | VCS + DPI-C 交互式调试 REPL |

汇编器扩展助记符语法：

```
NOT   dr
ASR   dr
ADDI  dr, imm16
ANDI  dr, imm16
CALLA addr16            ; addr16 可以是数值或 label
```

---

## 第三部分：结果

### 3.1 UVM 回归结果

| 项目 | 值 |
|---|---|
| 仿真器 | VCS V-2023.12-SP2 |
| 测试数 | 9 |
| PASS | **9 / 9** |
| 最近回归日期 | 2026-03-31 |

详见 [`reports/regression_summary.txt`](reports/regression_summary.txt) 与
[`reports/final_verification_summary.md`](reports/final_verification_summary.md)。

### 3.2 Verilator 差分回归结果

`make run-diff` 在 [`sw/abc_diff.asm`](sw/abc_diff.asm) 上的最新结果：

| 项目 | 值 |
|---|---|
| 程序长度 | 133 words |
| 指令退休次数 | **78** |
| Mismatch | **0** |
| 仿真周期 | 295 |
| 验证结论 | **PASS** |

逐条覆盖确认：

- ✅ `NOT` 跨 4 种位模式（含 `0x0000 → 0xFFFF`、`0x8000 → 0x7FFF` 翻转）
- ✅ `ASR` 在 `bit0=0/1` 与 `bit15=0/1` 4 种组合下的 C 标志
- ✅ `ADDI` 触发 carry-out / signed overflow / Z=1
- ✅ `ANDI` 清零、全通、半字掩码三种语义
- ✅ `CALLA → CALLA` 嵌套链（main→outer→inner）下 R15 的正确覆盖
- ✅ `MVRR R13, R15`、`ADD R7, R15` 验证 link register 既可写又可读
- ✅ 紧跟 ADDI/ANDI/NOT/ASR 的 `JRS/JRZ/JRC/JRNC` 全部按预期分支
- ✅ `STRR/LDRR` 与 ADDI/ANDI 交叉的内存往返

### 3.3 当前 ISA 验证矩阵

| 类别 | 指令 | UVM | 差分 |
|---|---|---|---|
| 寄存器-寄存器 ALU | `ADD SUB AND CMP XOR TEST OR MVRR ADC SBB` | ✅ | ✅ |
| 单寄存器 ALU      | `DEC INC SHL SHR`                            | ✅ | ✅ |
| 分支              | `JR JRC JRNC JRZ JRNZ JRS JRNS`              | ✅ | ✅ |
| 标志控制          | `CLC STC`                                    | ✅ | ✅ |
| 双字              | `JMPA MVRD LDRR STRR`                        | ✅ | ✅ |
| **A 类（新增）**  | **`NOT ASR`**                                | ⚠️* | ✅ |
| **B 类（新增）**  | **`ADDI ANDI`**                              | ⚠️* | ✅ |
| **C 类（新增）**  | **`CALLA`**                                  | ⚠️* | ✅ |

\* UVM 流水的 Python reference oracle (`model/reference_model.py`) 暂未补
A/B/C 扩展的语义；当前新指令的功能签收主要靠 Verilator 差分流水。

### 3.4 历史已修复问题

详见 [`reports/bug_list.md`](reports/bug_list.md) 与
[`reports/final_verification_summary.md`](reports/final_verification_summary.md)。

主要修复：

- 修复 [`model/assembler.py`](model/assembler.py) 将 `LDRR/STRR` 误判为
  双字指令的问题。
- 去掉 [`vsrc/controller.sv`](vsrc/controller.sv) 中 `always_comb` 调 task
  的写法，消除 `TBIFASL` 风险点。
- 修复 UVM memory responder 在写周期三态释放过慢导致的 `STRR/LDRR`
  伪失效。

### 3.5 已知限制 / 后续工作

- **Python ref 与新 ISA 不同步**：[`model/reference_model.py`](model/reference_model.py)
  暂未补 A/B/C 语义；UVM 流水若要把新指令纳入随机回归，需要把
  [`verilator_tb/golden_isa.h`](verilator_tb/golden_isa.h) 的实现回移到 Python。
- **Code coverage 未汇总**：当前只跑 functional coverage，未集成 VCS
  code coverage 的合并脚本。
- **无中途 reset 注入测试**。
- **无随机扩展指令 fuzzing**：差分流水当前是定向长测试；可与
  [`model/generate_random_tests.py`](model/generate_random_tests.py) 联动
  扩展为带 NOT/ASR/ADDI/ANDI/CALLA 的随机 fuzzing 回归。
- **CALLA 暂无配套 RET**：当前测试通过 `JMPA <return_label>` 完成调用返回，
  与 PDF 第 8 节"后续工作"一致。
- retire trace 中的 `instr_addr` 主要用于调试，不参与最终 signoff 级状态对拍。

---

## 附录：仓库结构

```
.
├── vsrc/                  # CPU RTL（cpu_core, controller, alu, fsm, …）
├── tb/                    # 共用 testbench fixture（memory_model 等）
├── uvm_tb/                # UVM 验证环境
│   ├── interfaces/        # cpu_core_if、debug 访问、三态总线封装
│   ├── agents/            # memory responder driver / bus / retire monitor
│   ├── scoreboard/        # 逐退休对拍 + 末态校验
│   ├── coverage/          # ISA 功能覆盖
│   └── tests/             # base / smoke / directed / random tests
├── verilator_tb/          # Verilator 差分验证
│   ├── verilator_top.sv   # cpu_top 包装：拆三态总线 + 引出观测信号
│   ├── golden_isa.h       # 纯 C++ ISA 级 Golden 模拟器
│   ├── sim_main.cpp       # CALLA 定向 testbench
│   ├── diff_main.cpp      # 长程差分 testbench (RTL ↔ Golden 逐指令对拍)
│   └── Makefile           # build / run / diff target
├── model/                 # Python 工具链
│   ├── assembler.py       # 汇编器（已扩展支持 A/B/C 新指令）
│   ├── reference_model.py # Python 参考模型（UVM oracle）
│   ├── generate_random_tests.py
│   └── compare_results.py
├── sw/                    # 汇编测试程序
│   ├── abc_diff.asm       # A/B/C 差分长测试
│   ├── tests/             # directed / corner / random
│   └── build/             # 汇编产物 (*.hex, *.layout)
├── scripts/               # 编译 / 单测 / 回归入口
├── reports/               # 覆盖率、回归汇总、bug list、最终报告
├── Isa扩展设计说明 A B C指令方案.pdf   # ISA 扩展设计规格
└── Makefile               # 顶层 (debug-build / debug-run 等)
```
