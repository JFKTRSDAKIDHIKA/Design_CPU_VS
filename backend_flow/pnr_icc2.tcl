source [file join [file dirname [file normalize [info script]]] "config.tcl"]

set ICC2_FAST_DEBUG 0
if {[info exists ::env(ICC2_FAST_DEBUG)] && $::env(ICC2_FAST_DEBUG) ne "" && $::env(ICC2_FAST_DEBUG) ne "0"} {
    set ICC2_FAST_DEBUG 1
}

flow_report_banner "IC Compiler II 布局布线阶段"
puts "INFO: ICC2_FAST_DEBUG = $ICC2_FAST_DEBUG"

flow_mkdirs [list $ICC2_LOG_DIR $ICC2_REPORT_DIR $ICC2_OUT_DIR]

flow_require_non_placeholder "TOP_MODULE" $TOP_MODULE
flow_require_non_placeholder "CLOCK_PORT" $CLOCK_PORT
flow_require_non_placeholder "CLK_PERIOD_NS" $CLK_PERIOD_NS
flow_require_non_placeholder "POWER_NET" $POWER_NET
flow_require_non_placeholder "GROUND_NET" $GROUND_NET

set dc_netlist [file join $DC_OUT_DIR "${TOP_MODULE}_syn.v"]
set dc_sdc [file join $DC_OUT_DIR "${TOP_MODULE}_syn.sdc"]

flow_require_file $dc_netlist "DC 导出的网表"
flow_require_file $dc_sdc "DC 导出的 SDC"
flow_require_file $TECH_FILE "ICC2 Tech File"
flow_require_file $NDM_LIBRARY_DIR "ICC2 参考 NDM 库"
flow_require_file $STD_CELL_LEF_FILE "标准单元 LEF"
flow_require_file $TECH_LEF_FILE "Tech LEF"
flow_require_file $STD_LIB_DB "标准单元 DB"
flow_require_file $TLU_PLUS_MAX_FILE "TLU+ 文件"
flow_require_file $PARASITIC_TECH_FILE "ICC2 寄生技术文件"

set io_lefs [flow_filter_placeholders $IO_LEF_FILES]
set mem_lefs [flow_filter_placeholders $MEMORY_LEF_FILES]
set io_libs [flow_filter_placeholders $IO_LIB_FILES]
set mem_libs [flow_filter_placeholders $MEMORY_LIB_FILES]
flow_require_files $io_lefs "IO LEF 文件"
flow_require_files $mem_lefs "Memory LEF 文件"
flow_require_files $io_libs "IO 库文件"
flow_require_files $mem_libs "Memory 库文件"

proc icc2_step {step_name command_body} {
    puts "INFO: 开始步骤 -> $step_name"
    if {[catch {uplevel 1 $command_body} err opts]} {
        puts stderr "ERROR: ICC2 步骤失败 -> $step_name"
        puts stderr $err
        if {[dict exists $opts -errorinfo]} {
            puts stderr "ERROR INFO:"
            puts stderr [dict get $opts -errorinfo]
        }
        exit 1
    }
    puts "INFO: 完成步骤 -> $step_name"
}

set link_libs [concat [list $STD_LIB_DB] $io_libs $mem_libs]
set lef_files [concat [list $TECH_LEF_FILE $STD_CELL_LEF_FILE] $io_lefs $mem_lefs]

# 这里使用显式 create_lib，便于后续替换为真实 SRAM/IO NDM。
icc2_step "创建 Milkyway/NDM 工作库" {
    if {[file exists [file join $ICC2_OUT_DIR "${TOP_MODULE}.dlib"]]} {
        file delete -force [file join $ICC2_OUT_DIR "${TOP_MODULE}.dlib"]
    }
    create_lib [file join $ICC2_OUT_DIR "${TOP_MODULE}.dlib"] \
        -technology $TECH_FILE \
        -ref_libs $NDM_LIBRARY_DIR
}

icc2_step "读取网表与约束" {
    open_lib [file join $ICC2_OUT_DIR "${TOP_MODULE}.dlib"]
    read_verilog $dc_netlist
    current_block $TOP_MODULE
    link_block
    read_sdc $dc_sdc
    set_max_transition 0.20 [current_design]
    set_max_fanout 16 [current_design]
}

icc2_step "设置工艺与 RC 环境" {
    read_parasitic_tech -tlup $PARASITIC_TECH_FILE -name nomTLU
    set_parasitic_parameters -late_spec nomTLU -early_spec nomTLU
    set_app_options -name route.common.global_min_layer_mode -value soft
    set_app_options -name route.common.global_max_layer_mode -value soft
    set_ignored_layers -min_routing_layer $MIN_ROUTING_LAYER -max_routing_layer $MAX_ROUTING_LAYER
}

icc2_step "Floorplan" {
    # 3nm 工艺下，PG 规划必须尽早完成，否则后续 placement/routing 很容易在拥塞、
    # IR drop、EM 与 DRC 上反复返工。这里先搭建一个可扩展的基础 floorplan。
    initialize_floorplan \
        -shape R \
        -side_ratio "1 $CORE_ASPECT_RATIO" \
        -core_utilization $CORE_UTILIZATION \
        -core_offset "$CORE_OFFSET_UM $CORE_OFFSET_UM $CORE_OFFSET_UM $CORE_OFFSET_UM"
}

icc2_step "建立基础 PG 网络" {
    catch {create_net -power $POWER_NET}
    catch {create_net -ground $GROUND_NET}
    set power_pins [get_pins -quiet -physical_context "*${POWER_PORT}*"]
    set ground_pins [get_pins -quiet -physical_context "*${GROUND_PORT}*"]
    if {[sizeof_collection $power_pins] > 0} {
        connect_pg_net -net $POWER_NET $power_pins
    } else {
        puts "WARN: 未找到可连接的电源 pin，请按真实封装/宏单元补充 PG 策略。"
    }
    if {[sizeof_collection $ground_pins] > 0} {
        connect_pg_net -net $GROUND_NET $ground_pins
    } else {
        puts "WARN: 未找到可连接的地 pin，请按真实封装/宏单元补充 PG 策略。"
    }
}

icc2_step "初始布局与自动布 pin" {
    create_placement -floorplan -effort high -timing_driven
    place_pins -self
}

icc2_step "Placement" {
    # 使用 congestion-driven 放置，尽量在早期缓解 3nm 高密度设计的可布线性问题。
    if {$ICC2_FAST_DEBUG} {
        puts "INFO: FAST_DEBUG 模式下跳过 place_opt，保留 create_placement 结果用于快速脚本/导出验证。"
    } else {
        set_app_options -name place_opt.congestion.effort -value $PLACE_CONGESTION_EFFORT
        place_opt
    }
    redirect -tee [file join $ICC2_REPORT_DIR "place_utilization.rpt"] {report_utilization}
    save_block -as "${TOP_MODULE}_after_place"
}

icc2_step "CTS" {
    # CTS 目标明确约束 skew / insertion delay，避免后期 hold 修复代价过高。
    if {$ICC2_FAST_DEBUG} {
        puts "INFO: FAST_DEBUG 模式下跳过 clock_opt，保留后续 route/report/export 以快速验证脚本兼容性。"
    } else {
        set_clock_tree_options -target_skew $CTS_TARGET_SKEW_NS -target_latency $CTS_TARGET_LATENCY_NS
        set_app_options -name route.common.net_max_layer_mode -value hard
        clock_opt
        redirect -tee [file join $ICC2_REPORT_DIR "cts_clock_summary.rpt"] {report_clock_qor -type summary}
        redirect -tee [file join $ICC2_REPORT_DIR "cts_clock_latency.rpt"] {report_clock_qor -type latency}
        redirect -tee [file join $ICC2_REPORT_DIR "cts_clock_area.rpt"] {report_clock_qor -type area}
    }
    save_block -as "${TOP_MODULE}_after_cts"
}

icc2_step "Routing" {
    # 对 3nm 而言，多重曝光友好布线与天线规避都应在此阶段显式启用或保留挂钩。
    if {$ENABLE_COLOR_AWARE_ROUTING} {
        catch {set_app_options -name route.detail.color_aware -value true}
    }
    if {$ICC2_FAST_DEBUG} {
        puts "INFO: FAST_DEBUG 模式下使用 route_global，避免 detail routing 长时间收敛。"
        route_global
    } else {
        route_auto
    }
    if {$ENABLE_ANTENNA_FIX && !$ICC2_FAST_DEBUG} {
        catch {route_detail -incremental true -antenna true}
    }
    save_block -as "${TOP_MODULE}_after_route"
}

icc2_step "后布线优化与报告" {
    if {$ICC2_FAST_DEBUG} {
        puts "INFO: FAST_DEBUG 模式下跳过 route_opt，直接生成关键报告并验证导出流程。"
    } else {
        route_opt
    }
    puts "INFO: before report_qor"
    redirect -tee [file join $ICC2_REPORT_DIR "report_qor.rpt"] {report_qor}
    puts "INFO: after report_qor"

    puts "INFO: before report_timing_max"
    redirect -tee [file join $ICC2_REPORT_DIR "report_timing_max.rpt"] {report_timing -delay_type max -max_paths 10}
    puts "INFO: after report_timing_max"

    puts "INFO: before report_timing_min"
    redirect -tee [file join $ICC2_REPORT_DIR "report_timing_min.rpt"] {report_timing -delay_type min -max_paths 10}
    puts "INFO: after report_timing_min"

    puts "INFO: before report_power"
    redirect -tee [file join $ICC2_REPORT_DIR "report_power.rpt"] {report_power}
    puts "INFO: after report_power"

    puts "INFO: before check_routes"
    redirect -tee [file join $ICC2_REPORT_DIR "report_drc.rpt"] {check_routes}
    puts "INFO: after check_routes"

    puts "INFO: before report_design_routing"
    redirect -tee [file join $ICC2_REPORT_DIR "report_routing.rpt"] {report_design -routing}
    puts "INFO: after report_design_routing"
    save_block -as "${TOP_MODULE}_after_post_route"
}

icc2_step "导出结果" {
    file mkdir $ICC2_OUT_DIR

    puts "INFO: before write_verilog"
    write_verilog -include all [file join $ICC2_OUT_DIR "${TOP_MODULE}_routed.v"]
    puts "INFO: after write_verilog"

    puts "INFO: before write_def"
    # 当前 ICC2 版本的 write_def 将 DEF 文件名作为位置参数传入，不支持 -output。
    write_def [file join $ICC2_OUT_DIR "${TOP_MODULE}.def"]
    puts "INFO: after write_def"

    puts "INFO: before write_parasitics"
    write_parasitics -output [file join $ICC2_OUT_DIR "${TOP_MODULE}.spef"]
    puts "INFO: after write_parasitics"
    if {![flow_is_placeholder $GDS_MAP_FILE]} {
        puts "INFO: before write_gds"
        # 当前 ICC2 版本的 write_gds 将 GDS 文件名作为位置参数传入，不使用 -output。
        write_gds -layer_map $GDS_MAP_FILE [file join $ICC2_OUT_DIR "${TOP_MODULE}.gds"]
        puts "INFO: after write_gds"
    } else {
        puts "WARN: GDS_MAP_FILE 仍是占位符，跳过 GDSII 导出。"
    }
    puts "INFO: before save_block"
    save_block -as "${TOP_MODULE}_route_final"
    puts "INFO: after save_block"
}

flow_report_banner "IC Compiler II 布局布线完成"
exit 0
