# RTL-to-GDSII 自动化流程

本目录提供一套面向 Synopsys 工具链的参考脚本，覆盖 `RTL -> DC 综合 -> ICC2 布局布线 -> PT 时序签核` 的完整流程。

脚本默认按当前仓库组织方式寻找 RTL 与 USC 3nm PDK，同时把关键设计参数保留为醒目占位符，方便你替换成自己的项目配置。

## 推荐目录结构

```text
backend_flow/
├── config.tcl                  # 集中式配置入口
├── run_all.sh                  # 总控脚本
├── synth_dc.tcl                # Design Compiler 综合脚本
├── pnr_icc2.tcl                # IC Compiler II 布局布线脚本
├── signoff_pt.tcl              # PrimeTime 签核脚本
├── constraints/
│   └── YOUR_TOP_MODULE.sdc     # 约束模板，需按设计修改
├── logs/
│   ├── dc/
│   ├── icc2/
│   └── pt/
├── out/
│   ├── dc/
│   ├── icc2/
│   └── pt/
└── reports/
    ├── dc/
    ├── icc2/
    └── pt/
```

## 使用前需要填写

先修改 [config.tcl](/home/3dic/Design_CPU_VS/backend_flow/config.tcl) 中这些占位符：

- `TOP_MODULE`
- `CLK_PERIOD_NS`
- `CLOCK_PORT`
- `RESET_PORT`
- `IO_LIB_FILES` / `MEMORY_LIB_FILES`
- `IO_LEF_FILES` / `MEMORY_LEF_FILES`
- `GDS_MAP_FILE`
- `MAX_ROUTING_LAYER` 与电源网络参数

然后按你的时序目标补充 [constraints/YOUR_TOP_MODULE.sdc](/home/3dic/Design_CPU_VS/backend_flow/constraints/YOUR_TOP_MODULE.sdc)。

## 运行方式

```bash
cd backend_flow
bash run_all.sh
```

如只想跑单阶段：

```bash
dc_shell -64 -f synth_dc.tcl
icc2_shell -f pnr_icc2.tcl
pt_shell -f signoff_pt.tcl
```

## 说明

- 所有阶段都会把终端输出写入独立日志。
- 脚本内包含 `catch` / 显式检查，关键步骤失败会退出非零状态。
- ICC2 部分重点保留了 3nm 工艺下 PG 早规划、多重曝光与天线修复提示位，便于你后续替换成真实 foundry deck / signoff recipe。
