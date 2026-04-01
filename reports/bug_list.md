# Bug List / Fix Log

## BUG-001 Assembler mis-sized `LDRR/STRR`

- 标题：`LDRR/STRR` 被 assembler 误算成 2-word 指令
- 现象：访存类 directed test 的布局地址会整体漂移，导致程序空间与 branch/layout 分析失真。
- 复现方式：查看 [`model/assembler.py`](/home/3dic/Design_CPU_VS/model/assembler.py) 中 `instruction_size()`，原实现把 `LDRR/STRR` 放进 `DOUBLE_WORD`。
- 根因分析：这两条指令是单字编码、双周期执行，而不是双字指令。
- 修复方案：新增 `TWO_CYCLE_SINGLE_WORD` 分类，保持编码 1 word、执行仍由 RTL 的 B-group 两周期处理。
- 修复影响范围：assembler、程序布局、随机测试生成。
- 修复前后验证结果：修复后 directed / random / smoke 全部回归通过。

## BUG-002 Controller style hazard in `always_comb`

- 标题：`controller.sv` 在 `always_comb` 里调用 task
- 现象：VCS 对该写法报 `TBIFASL` 风格 warning。
- 复现方式：编译原 RTL。
- 根因分析：组合逻辑块内调用 task 容易引入工具语义歧义。
- 修复方案：将 task 展开为显式赋值。
- 修复影响范围：RTL 可读性、工具兼容性。
- 修复前后验证结果：修复后 UVM 回归保持全通过。

## BUG-003 UVM memory responder drive-release timing

- 标题：UVM memory responder 在写周期仍残留读驱动
- 现象：`memory_access.asm` 初次回归失败，`STRR/LDRR` 路径读取到旧值。
- 复现方式：运行 `./scripts/run_single_test.sh memory_access cpu_directed_test sw/tests/direct/memory_access.asm 13`
- 根因分析：driver 用时钟任务更新三态方向，释放时机晚于 DUT 的写周期切换。
- 修复方案：在 [`cpu_core_if.sv`](/home/3dic/Design_CPU_VS/uvm_tb/interfaces/cpu_core_if.sv) 中改为组合式读驱动，保持与原始 [`memory_model.sv`](/home/3dic/Design_CPU_VS/tb/memory_model.sv) 一致。
- 修复影响范围：UVM verification environment 的 store/load 行为。
- 修复前后验证结果：`memory_access` 由 FAIL 变为 PASS，完整回归 9/9 PASS。
