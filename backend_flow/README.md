# backend_flow

这套目录是当前工程的 Synopsys 数字后端实现 flow，覆盖：

`RTL -> DC 综合 -> ICC2 布局布线 -> PT 时序分析`

它已经针对本仓库当前的 CPU 设计做过一轮适配，默认顶层是 `cpu_pnr_top`，并且已经处理过原始 `inout data_bus` 不适合直接做后端的问题。

## 当前版图预览

下面这张图不是随手画的示意图，而是基于 ICC2 `route_final` 数据库里的真实 cell bbox 和 routing shape 渲染出来的 viewer 风格预览：

![cpu_pnr_top layout](docs/layout_viewer_style.jpg)

如果你想看原始产物：

- GDS: [cpu_pnr_top.gds](/home/3dic/Design_CPU_VS/backend_flow/out/icc2/cpu_pnr_top.gds)
- DEF: [cpu_pnr_top.def](/home/3dic/Design_CPU_VS/backend_flow/out/icc2/cpu_pnr_top.def)
- ICC2 库: [cpu_pnr_top.dlib](/home/3dic/Design_CPU_VS/backend_flow/out/icc2/cpu_pnr_top.dlib)

## 目录说明

```text
backend_flow/
├── README.md
├── config.tcl
├── synth_dc.tcl
├── pnr_icc2.tcl
├── signoff_pt.tcl
├── run_all.sh
├── run_icc2_until_export_pass.sh
├── constraints/
│   ├── cpu_pnr_top.sdc
│   └── cpu_top.sdc
├── docs/
│   └── layout_viewer_style.jpg
├── out/
├── logs/
└── reports/
```

核心文件：

- [config.tcl](/home/3dic/Design_CPU_VS/backend_flow/config.tcl): 全局配置入口，优先修改这里
- [synth_dc.tcl](/home/3dic/Design_CPU_VS/backend_flow/synth_dc.tcl): DC 综合脚本
- [pnr_icc2.tcl](/home/3dic/Design_CPU_VS/backend_flow/pnr_icc2.tcl): ICC2 布局布线脚本
- [signoff_pt.tcl](/home/3dic/Design_CPU_VS/backend_flow/signoff_pt.tcl): PT 分析脚本
- [run_all.sh](/home/3dic/Design_CPU_VS/backend_flow/run_all.sh): 一键串行跑三阶段
- [run_icc2_until_export_pass.sh](/home/3dic/Design_CPU_VS/backend_flow/run_icc2_until_export_pass.sh): ICC2 重试包装脚本，方便调导出阶段

## 这套 flow 的当前默认值

当前默认配置已经对齐本仓库结构：

- 工程根目录: `/home/3dic/Design_CPU_VS`
- RTL 目录: `/home/3dic/Design_CPU_VS/vsrc`
- PDK 根目录: `/home/3dic/Design_CPU_VS/USC-3N-2D`
- 后端顶层: `cpu_pnr_top`
- 默认时钟端口: `clk`
- 默认复位端口: `reset`
- 默认时钟周期: `10.0 ns`

注意：

- `cpu_pnr_top` 和 `cpu_pnr_core` 是为了后端 flow 新增的顶层封装。
- 如果你切回原始 `cpu_top`，原设计里的 `inout data_bus` 会重新带来 tri-state / PnR 映射问题。

## 第一次使用前要做什么

### 1. 确认 Synopsys 工具环境

先保证这些命令可用：

```bash
which dc_shell
which icc2_shell
which pt_shell
which lc_shell
```

如果找不到，就先加载你本机的 Synopsys 环境，例如：

```bash
source /home/3dic/synopsys.setup
```

### 2. 检查 `config.tcl`

优先检查这些变量：

- `TOP_MODULE`
- `CLOCK_PORT`
- `RESET_PORT`
- `CLK_PERIOD_NS`
- `TOP_SDC_FILE`
- `STD_LIB_DB`
- `STD_LIB_LIBERTY`
- `TECH_FILE`
- `TECH_LEF_FILE`
- `STD_CELL_LEF_FILE`
- `TLU_PLUS_MAX_FILE`
- `PARASITIC_TECH_FILE`
- `NDM_LIBRARY_DIR`
- `GDS_MAP_FILE`

当前这套工程已经把这些路径默认指向本仓库里的 USC 3nm 数据和本地缓存文件，但你换机器后仍然建议重新核对一遍。

### 3. 检查约束文件

当前默认约束文件是：

- [cpu_pnr_top.sdc](/home/3dic/Design_CPU_VS/backend_flow/constraints/cpu_pnr_top.sdc)

如果你换顶层或换时序目标，记得同步改：

- `config.tcl` 里的 `TOP_MODULE`
- 对应的 `constraints/<top>.sdc`

## 推荐运行方式

不要一开始就盲目跑 `run_all.sh`。更稳的方式是分阶段执行，并且每一步都看日志。

### Phase A: DC 综合

```bash
cd /home/3dic/Design_CPU_VS/backend_flow
dc_shell -f synth_dc.tcl | tee logs/dc_synth.log
```

综合完成后检查：

```bash
tail -n 50 logs/dc_synth.log
ls -lh out/dc
```

你应该至少看到：

- `out/dc/cpu_pnr_top_syn.v`
- `out/dc/cpu_pnr_top_syn.sdc`
- `out/dc/cpu_pnr_top.ddc`

### Phase B: ICC2 布局布线

正常跑法：

```bash
cd /home/3dic/Design_CPU_VS/backend_flow
icc2_shell -f pnr_icc2.tcl | tee logs/icc2_pnr.log
```

如果你是在调“导出结果”阶段，推荐用带自动重试和 fast debug 的脚本：

```bash
cd /home/3dic/Design_CPU_VS/backend_flow
ICC2_FAST_DEBUG=1 MAX_ITERS=1 ./run_icc2_until_export_pass.sh
```

跑完重点检查：

```bash
tail -n 80 logs/icc2_pnr.log
ls -lh out/icc2
```

理想情况下会生成：

- `cpu_pnr_top_routed.v`
- `cpu_pnr_top.def`
- `cpu_pnr_top.spef.nomTLU_25.spef`
- `cpu_pnr_top.gds`
- `cpu_pnr_top.dlib`

### Phase C: PT 分析

只有在 ICC2 已经产出 SPEF 后再跑：

```bash
cd /home/3dic/Design_CPU_VS/backend_flow
pt_shell -f signoff_pt.tcl | tee logs/pt_signoff.log
```

然后检查：

```bash
tail -n 80 logs/pt_signoff.log
grep -n "slack\\|WNS\\|TNS" logs/pt_signoff.log | tail -n 20
```

## 一键运行方式

如果你已经确认配置没问题，也可以直接串起来跑：

```bash
cd /home/3dic/Design_CPU_VS/backend_flow
./run_all.sh
```

这个脚本会按顺序调用：

1. `dc_shell -f synth_dc.tcl`
2. `icc2_shell -f pnr_icc2.tcl`
3. `pt_shell -f signoff_pt.tcl`

对应日志分别写到：

- `logs/dc/run_all_dc.log`
- `logs/icc2/run_all_icc2.log`
- `logs/pt/run_all_pt.log`

## 当前脚本里已经修过的兼容性问题

这套脚本不是模板状态，而是已经针对当前工具版本修过几轮：

- `write_def` 改成了位置参数写法，不再使用 `-output`
- `write_gds` 改成了位置参数写法，不再使用有歧义的 `-output`
- 后布线报告阶段已经把多个 report 分开执行，便于定位报错
- ICC2 导出阶段显式创建输出目录
- 增加了 `ICC2_FAST_DEBUG` 模式，便于先打通导出链路
- 保存了多个 block checkpoint，例如：
  - `cpu_pnr_top_after_place`
  - `cpu_pnr_top_after_cts`
  - `cpu_pnr_top_after_route`
  - `cpu_pnr_top_after_post_route`
  - `cpu_pnr_top_route_final`

## 怎么看版图

### 看 GDS

直接打开：

- [cpu_pnr_top.gds](/home/3dic/Design_CPU_VS/backend_flow/out/icc2/cpu_pnr_top.gds)

如果你机器上有 KLayout：

```bash
klayout /home/3dic/Design_CPU_VS/backend_flow/out/icc2/cpu_pnr_top.gds
```

### 看 ICC2 数据库

```bash
cd /home/3dic/Design_CPU_VS/backend_flow
icc2_shell -gui
```

然后在 GUI 里打开：

- library: `out/icc2/cpu_pnr_top.dlib`
- block: `cpu_pnr_top_route_final`

## 常见问题

### 1. `dc_shell` / `icc2_shell` / `pt_shell` 找不到

说明工具环境没加载，先 `source` 你的 Synopsys 环境脚本。

### 2. DC 报 `.db` 不可用

当前工程用的是本地编译后的：

- [3nm_GAA_FSPR_rvt_nldm.db](/home/3dic/Design_CPU_VS/backend_flow/libcache/3nm_GAA_FSPR_rvt_nldm.db)

它是由：

- [compile_stdlib_to_db.tcl](/home/3dic/Design_CPU_VS/backend_flow/libcache/compile_stdlib_to_db.tcl)

配合 `lc_shell` 从 Liberty 编译出来的。如果你换环境后缺这个文件，需要重新编。

### 3. ICC2 卡在 place/clock/route 优化很久

这是当前 academic 3nm PDK 比较常见的情况。建议先：

- 用 `ICC2_FAST_DEBUG=1` 打通导出链路
- 先确认 `DEF/SPEF/GDS` 能落盘
- 再逐步恢复更重的 `place_opt` / `clock_opt` / `route_opt`

### 4. GDS 能写出来，但 layer map 仍可能有 warning

当前 flow 已经能导出 GDS，但 `GDS_MAP_FILE` 的正确性仍建议后续单独核验，不能只看“文件存在”就默认完全正确。

### 5. 功耗数字很大，clock network 占比很夸张

这不是 README 里的主要问题，但当前 flow 里确实观察到过 `clock_network` 功耗占比异常高的情况。后续建议单独检查：

- clock constraint
- switching activity 来源
- 是否缺 SAIF/VCD
- clock tree 设置
- 库和报表单位

## 建议的日常工作流

最推荐的顺序是：

1. 先改 `config.tcl`
2. 跑 `dc_shell -f synth_dc.tcl`
3. 看 `logs/dc_synth.log`
4. 跑 `icc2_shell -f pnr_icc2.tcl`
5. 看 `logs/icc2_pnr.log`
6. 导出 `DEF/GDS/SPEF`
7. 最后再跑 `pt_shell -f signoff_pt.tcl`

如果只是想快速确认这套 flow 还活着，最短路径是：

```bash
cd /home/3dic/Design_CPU_VS/backend_flow
ICC2_FAST_DEBUG=1 MAX_ITERS=1 ./run_icc2_until_export_pass.sh
```

它更适合调脚本兼容性和导出阶段，不适合作为最终 QoR 结果。
