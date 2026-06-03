# backend_flow/constraints/cpu_top.sdc
# 面向当前教学 CPU 顶层的最小可运行约束。

set CLK_PORT_NAME clk
set RST_PORT_NAME reset
set CLK_PERIOD_NS 10.0

create_clock -name core_clk -period $CLK_PERIOD_NS [get_ports $CLK_PORT_NAME]

set_clock_uncertainty 0.10 [get_clocks core_clk]
set_clock_transition 0.10 [get_clocks core_clk]

# reset 不作为正常数据路径参与时序收敛。
set_false_path -from [get_ports $RST_PORT_NAME]

# 对顶层输入/输出采用保守模板约束，避免依赖缺失的 IO cell。
set_input_transition 0.10 [remove_from_collection [all_inputs] [get_ports $CLK_PORT_NAME]]
set_input_delay 0.20 -clock [get_clocks core_clk] [remove_from_collection [all_inputs] [get_ports $CLK_PORT_NAME]]
set_output_delay 0.20 -clock [get_clocks core_clk] [all_outputs]
set_load 0.01 [all_outputs]
