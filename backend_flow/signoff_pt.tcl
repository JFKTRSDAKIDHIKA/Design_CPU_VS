source [file join [file dirname [file normalize [info script]]] "config.tcl"]

flow_report_banner "PrimeTime 时序签核阶段"

flow_mkdirs [list $PT_LOG_DIR $PT_REPORT_DIR $PT_OUT_DIR]

flow_require_non_placeholder "TOP_MODULE" $TOP_MODULE
flow_require_non_placeholder "CLOCK_PORT" $CLOCK_PORT
flow_require_non_placeholder "CLK_PERIOD_NS" $CLK_PERIOD_NS

set routed_netlist [file join $ICC2_OUT_DIR "${TOP_MODULE}_routed.v"]
set routed_spef [file join $ICC2_OUT_DIR "${TOP_MODULE}.spef"]
set dc_sdc [file join $DC_OUT_DIR "${TOP_MODULE}_syn.sdc"]

flow_require_file $routed_netlist "ICC2 导出的后布线网表"
flow_require_file $routed_spef "ICC2 导出的 SPEF"
flow_require_file $dc_sdc "DC/ICC2 使用的 SDC"
flow_require_file $STD_LIB_DB "标准单元 DB"

set io_libs [flow_filter_placeholders $IO_LIB_FILES]
set mem_libs [flow_filter_placeholders $MEMORY_LIB_FILES]
flow_require_files $io_libs "IO 库文件"
flow_require_files $mem_libs "Memory 库文件"

proc pt_step {step_name command_body} {
    puts "INFO: 开始步骤 -> $step_name"
    if {[catch {uplevel 1 $command_body} err]} {
        puts stderr "ERROR: PrimeTime 步骤失败 -> $step_name"
        puts stderr $err
        exit 1
    }
    puts "INFO: 完成步骤 -> $step_name"
}

set search_path [list . $RTL_DIR [file dirname $STD_LIB_DB]]
foreach lib_file [concat $io_libs $mem_libs] {
    lappend search_path [file dirname $lib_file]
}
set_app_var search_path $search_path
set_app_var link_path [concat [list "*"] [list $STD_LIB_DB] $io_libs $mem_libs]

pt_step "读取设计" {
    read_verilog $routed_netlist
    current_design $TOP_MODULE
    link_design $TOP_MODULE
    read_sdc $dc_sdc
}

pt_step "回标寄生参数" {
    read_parasitics -format spef $routed_spef
}

pt_step "更新时序" {
    update_timing
}

pt_step "生成 setup/hold 报告" {
    redirect -tee [file join $PT_REPORT_DIR "report_timing_setup.rpt"] {
        report_timing -delay_type max -max_paths $PT_MAX_PATHS -nworst 1
    }
    if {$PT_ENABLE_HOLD} {
        redirect -tee [file join $PT_REPORT_DIR "report_timing_hold.rpt"] {
            report_timing -delay_type min -max_paths $PT_MAX_PATHS -nworst 1
        }
    }
    redirect -tee [file join $PT_REPORT_DIR "report_constraints.rpt"] {report_constraints -all_violators}
    redirect -tee [file join $PT_REPORT_DIR "report_qor.rpt"] {report_qor}
}

pt_step "签核总结" {
    set setup_paths [get_timing_paths -delay_type max -slack_lesser_than 0.0 -max_paths 1]
    if {[sizeof_collection $setup_paths] > 0} {
        puts stderr "ERROR: 仍存在 setup 违例，请检查 $PT_REPORT_DIR/report_timing_setup.rpt"
        exit 1
    }

    if {$PT_ENABLE_HOLD} {
        set hold_paths [get_timing_paths -delay_type min -slack_lesser_than 0.0 -max_paths 1]
        if {[sizeof_collection $hold_paths] > 0} {
            puts stderr "ERROR: 仍存在 hold 违例，请检查 $PT_REPORT_DIR/report_timing_hold.rpt"
            exit 1
        }
    }

    set summary_fd [open [file join $PT_OUT_DIR "signoff_summary.txt"] "w"]
    puts $summary_fd "PrimeTime signoff passed for $TOP_MODULE"
    puts $summary_fd "Netlist : $routed_netlist"
    puts $summary_fd "SPEF    : $routed_spef"
    puts $summary_fd "SDC     : $dc_sdc"
    close $summary_fd
}

flow_report_banner "PrimeTime 时序签核完成"
exit 0
