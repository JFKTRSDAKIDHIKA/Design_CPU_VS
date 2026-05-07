# Verilator C++ Testbench: `CALLA rel8`

针对 C 类指令 `CALLA rel8`（第一字 `F0<signed rel8>`，第二字 reserved 且忽略）
完成 Verilator 闭环验证。

## 文件

- [verilator_top.sv](verilator_top.sv) —— Verilator 顶层包装：拆开
  `cpu_top` 的三态 `data_bus`，并把 `pc_bus` / `instruction` / `regs[15]` /
  `execution_stage` 引出，方便 C++ 直接观测体系结构状态。
- [sim_main.cpp](sim_main.cpp) —— C++ 仿真主程序，内部维护 64K-word 存储模型，
  按 `tb/memory_model.sv` 的语义在时钟上升沿采样写数据，组合式提供读数据。
- [Makefile](Makefile) —— `make build` / `make run` / `make clean`。

## 用法

```bash
cd verilator_tb
make build      # 调用 verilator + g++ 生成 obj_dir/Vverilator_top
make run        # 执行测试，控制台打印 PASS/FAIL 摘要
```

## 验证用例

每条用例都跟踪 FSM 进入 `STAGE_LOAD_CALL_TARGET (3'b110)` 这一拍并在其结束时
读取 `R15` / `PC` / 标志位。

| 用例 | 目的 |
| --- | --- |
| `forward_calla_reserved_ignored` | 复位后立即执行前向 `CALLA 0x0050`，校验 `R15=0x0002`，`PC=0x0050`，且非零 reserved 第二字被忽略 |
| `calla_after_some_setup` | 先 `MVRD R0,#42` 与 `STC` 设置上下文，再 `CALLA 0x0040`：校验 `R0=0x002A` 不被破坏，`R15=0x0005`，`PC=0x0040`，`C` 标志保留为 1 |
| `backward_calla` | 从 `0x0003` 反向调用到 `0x0000`，验证 signed rel8 负偏移 |
| `nested_calla` | 连续两次 `CALLA`，校验内层调用后 `R15` 被新返回地址覆盖，`PC` 指向最内层目标 |
| `calla_preserves_flags` | `STC` + `CALLA`，校验 `c=1, z=0, v=0, s=0` 全部保持 |
| `calla_then_use_link_register` | 调用目标处用 `ADD R1,R15` 验证 `R15` 可正常作为源寄存器使用 |

## 当前结果

```
[PASS] forward_calla_reserved_ignored
[PASS] calla_after_some_setup
[PASS] backward_calla
[PASS] nested_calla
[PASS] calla_preserves_flags
[PASS] calla_then_use_link_register
Total: 6  Passed: 6  Failed: 0
```

## 已检查的 CALLA 行为约束（来自 ISA 规格）

- 取指 1 拍 (`state1` = 3'b000) → 译码 1 拍 (`state2` = 3'b001) → 取第二字 1 拍
  (`state4` = 3'b101) → 保存返回地址 1 拍 (`state6` = 3'b010) → 写回 PC 1 拍
  (`state7` = 3'b110)。共 3 个执行拍，与「至少 3 个执行拍」一致。
- `R15 <- PC + 2`：CALLA 占两个字 `[A, A+1]`，下一条指令在 `A+2`，
  `state4` 已把 PC 推进到 `A+2`，`state6` 通过 `ALU_IN_PC + cin=0` 把
  `A+2` 写入 R15。
- `PC <- (A+2) + signext(rel8)`：`state4` 仍取第二字并把 PC 推进到 `A+2`；
  `state7` 通过 `ALU_IN_BR + cin=0` 使用 IR 低 8 位相对偏移写回 PC。
- 标志位不变：所有 CALLA 相关阶段都使用 `sst = SST_HOLD`，标志寄存器保持。

## 复用范围

C++ testbench 通过现有的 `reg_out` 调试 mux（`sel`/`reg_sel`/`reg_data`）
读取通用寄存器；对 `R15` / `PC` / `IR` / `execution_stage` 直接通过包装
端口输出，避免依赖编译器的层级访问导出（兼容旧版本 Verilator 4.038）。
