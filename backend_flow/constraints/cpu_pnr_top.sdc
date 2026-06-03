set CLK_PORT_NAME clk
set RST_PORT_NAME reset
set CLK_PERIOD_NS 10.0

create_clock -name core_clk -period $CLK_PERIOD_NS [get_ports $CLK_PORT_NAME]

set_clock_uncertainty 0.10 [get_clocks core_clk]
set_clock_transition 0.10 [get_clocks core_clk]
set_max_transition 0.20 [current_design]
set_max_fanout 16 [current_design]
set_false_path -from [get_ports $RST_PORT_NAME]

set all_data_inputs [remove_from_collection [all_inputs] [get_ports $CLK_PORT_NAME]]
set_input_transition 0.10 $all_data_inputs
set_input_delay 0.20 -clock [get_clocks core_clk] $all_data_inputs
set_output_delay 0.20 -clock [get_clocks core_clk] [all_outputs]
set_load 0.01 [all_outputs]
