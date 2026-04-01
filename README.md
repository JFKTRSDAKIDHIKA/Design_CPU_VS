# `cpu_core` UVM Verification Environment

这个仓库现在包含一套基于 VCS + UVM 的 block-level CPU 功能验证环境，围绕 [`cpu_core`](/home/3dic/Design_CPU_VS/vsrc/cpu_core.sv) 建立了可回归、可扩展、可对拍的验证闭环。

## 当前状态

- 主仿真器：`VCS V-2023.12-SP2`
- 验证架构：UVM memory agent + retire monitor + scoreboard + functional coverage
- reference oracle：复用并扩展 [`model/reference_model.py`](/home/3dic/Design_CPU_VS/model/reference_model.py)
- 回归状态：9/9 tests PASS
- 最近一次回归日期：2026-03-31

## 目录结构

- [`uvm_tb/interfaces/`](/home/3dic/Design_CPU_VS/uvm_tb/interfaces) DUT interface、debug 访问、三态总线封装。
- [`uvm_tb/agents/`](/home/3dic/Design_CPU_VS/uvm_tb/agents) memory responder driver、bus/retire monitor、transaction 类型。
- [`uvm_tb/scoreboard/`](/home/3dic/Design_CPU_VS/uvm_tb/scoreboard) 逐退休对拍与末态校验。
- [`uvm_tb/coverage/`](/home/3dic/Design_CPU_VS/uvm_tb/coverage) ISA 功能覆盖。
- [`uvm_tb/tests/`](/home/3dic/Design_CPU_VS/uvm_tb/tests) `base/smoke/directed/random` tests。
- [`model/`](/home/3dic/Design_CPU_VS/model) assembler、reference model、随机程序生成器。
- [`sw/tests/`](/home/3dic/Design_CPU_VS/sw/tests) directed / corner / random 程序。
- [`scripts/`](/home/3dic/Design_CPU_VS/scripts) 编译、单测、回归入口。
- [`reports/`](/home/3dic/Design_CPU_VS/reports) coverage、reference 输出、回归汇总、最终报告。

## UVM 架构

- `cpu_core_if`
  统一封装 `reset/clk/wr/address_bus/data_bus`，并提供 debug 采样任务。
- `cpu_memory_agent`
  active driver 负责程序加载与 memory responder 写回；monitor 负责总线事务和退休事件采集。
- `cpu_scoreboard`
  从 Python reference trace/summary 读入 golden 数据，对 RTL 做逐退休架构态比较，并在测试结束时做末态校验。
- `cpu_coverage_collector`
  覆盖 opcode、寄存器、flags、branch taken/not-taken、memory read/write、地址区间。
- `cpu_base_test`
  通过 plusargs 接收 `program_hex/ref_trace/ref_summary/coverage_report`，支持 smoke、directed、random 派生测试。

提交语义假设：

- 单字指令在 `execution_stage == 3'b011` 结束后的下一个时钟沿视为退休。
- 双周期指令在 `execution_stage == 3'b111` 结束后的下一个时钟沿视为退休。
- UVM monitor 在这个粒度采样架构态并与 reference model 对齐。

## 使用方式

编译 UVM 环境：

```bash
./scripts/compile_vcs.sh
```

运行单个测试：

```bash
./scripts/run_single_test.sh mult8 cpu_smoke_test sw/mult8.asm 1
```

运行完整回归：

```bash
./scripts/run_regression.sh
```

回归结果写入：

- [`reports/regression_summary.txt`](/home/3dic/Design_CPU_VS/reports/regression_summary.txt)
- [`reports/coverage/`](/home/3dic/Design_CPU_VS/reports/coverage)
- [`logs/uvm/`](/home/3dic/Design_CPU_VS/logs/uvm)

## 当前验证范围

已完成 directed + random 验证的 ISA 子集：

- `ADD SUB AND CMP XOR TEST OR MVRR`
- `DEC INC SHL SHR ADC SBB`
- `JR JRC JRNC JRZ JRNZ JRS JRNS`
- `CLC STC`
- `JMPA`
- `LDRR STRR`
- `MVRD`

## 已修复问题

详见：

- [`reports/bug_list.md`](/home/3dic/Design_CPU_VS/reports/bug_list.md)
- [`reports/final_verification_summary.md`](/home/3dic/Design_CPU_VS/reports/final_verification_summary.md)

本轮关键修复包括：

- 修复 assembler 将 `LDRR/STRR` 误判为双字指令的问题。
- 去掉 [`controller.sv`](/home/3dic/Design_CPU_VS/vsrc/controller.sv) 中 `always_comb` 调 task 的写法，消除 `TBIFASL` 风险点。
- 修复 UVM memory responder 在写周期三态释放过慢导致的 `STRR/LDRR` 伪失效。

## 已知限制

- 当前只做功能覆盖，未集成 VCS code coverage 汇总脚本。
- 尚未加入中途 reset 注入测试。
- retire trace 中的 `instr_addr` 主要用于调试，不参与最终 signoff 级状态对拍。
