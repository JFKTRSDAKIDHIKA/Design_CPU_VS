source [file join [file dirname [file normalize [info script]]] "config.tcl"]

flow_report_banner "Design Compiler 综合阶段"

flow_mkdirs [list $DC_LOG_DIR $DC_REPORT_DIR $DC_OUT_DIR]

flow_require_non_placeholder "TOP_MODULE" $TOP_MODULE
flow_require_non_placeholder "CLOCK_PORT" $CLOCK_PORT
flow_require_non_placeholder "RESET_PORT" $RESET_PORT
flow_require_non_placeholder "CLK_PERIOD_NS" $CLK_PERIOD_NS

flow_require_file $RTL_DIR "RTL 目录"
flow_require_file $STD_LIB_DB "标准单元 DB 库"
flow_require_file $STD_LIB_LIBERTY "标准单元 Liberty 库"
flow_require_file $TOP_SDC_FILE "顶层 SDC 约束"

set io_libs [flow_filter_placeholders $IO_LIB_FILES]
set mem_libs [flow_filter_placeholders $MEMORY_LIB_FILES]
flow_require_files $io_libs "IO 库文件"
flow_require_files $mem_libs "Memory 库文件"

if {[file exists $FILELIST_FILE]} {
    set rtl_files [flow_collect_rtl_files_from_filelist $FILELIST_FILE]
} else {
    set rtl_files [flow_collect_rtl_files $RTL_DIR]
}
if {[llength $rtl_files] == 0} {
    puts stderr "ERROR: 未在 $RTL_DIR 下找到任何 .sv/.v RTL 文件"
    exit 1
}
flow_require_files $rtl_files "RTL 源文件"

set_app_var sh_continue_on_error false
set_host_options -max_cores $DC_MAX_CORES

# 搜索路径中加入 RTL 目录和各类库目录，避免 link 阶段找不到依赖。
set search_path [list . $RTL_DIR [file dirname $STD_LIB_DB] [file dirname $STD_LIB_LIBERTY]]
foreach lib_file [concat $io_libs $mem_libs] {
    lappend search_path [file dirname $lib_file]
}
set_app_var search_path $search_path

set target_library [concat [list $STD_LIB_DB] $io_libs $mem_libs]
set_app_var target_library $target_library
set_app_var synthetic_library dw_foundation.sldb
set_app_var link_library [concat [list "*"] $target_library $synthetic_library]

if {$DC_TOPographical_MODE} {
    set_app_var alib_library_analysis_path [file join $DC_OUT_DIR "alib"]
}

proc dc_step {step_name command_body} {
    puts "INFO: 开始步骤 -> $step_name"
    if {[catch {uplevel 1 $command_body} err]} {
        puts stderr "ERROR: DC 步骤失败 -> $step_name"
        puts stderr $err
        exit 1
    }
    puts "INFO: 完成步骤 -> $step_name"
}

dc_step "分析 RTL" {
    analyze -format sverilog $rtl_files
}

dc_step "展开设计" {
    elaborate $TOP_MODULE
    current_design $TOP_MODULE
    link
}

dc_step "基本一致性检查" {
    redirect -tee [file join $DC_REPORT_DIR "check_design.rpt"] {check_design}
}

dc_step "读取约束" {
    source $TOP_SDC_FILE
}

dc_step "综合前环境设置" {
    set_fix_multiple_port_nets -all -buffer_constants
    if {$DC_TOPographical_MODE} {
        # 开启 topographical 模式后，DC 会更贴近后端物理实现结果。
        set_app_var compile_topographical_mode true
    }
}

dc_step "compile_ultra 综合" {
    eval compile_ultra $DC_ULTRA_EFFORT
}

dc_step "综合后检查" {
    redirect -tee [file join $DC_REPORT_DIR "check_timing.rpt"] {check_timing}
    redirect -tee [file join $DC_REPORT_DIR "report_timing_max.rpt"] {report_timing -delay_type max -max_paths 10 -nworst 1}
    redirect -tee [file join $DC_REPORT_DIR "report_timing_min.rpt"] {report_timing -delay_type min -max_paths 10 -nworst 1}
    redirect -tee [file join $DC_REPORT_DIR "report_area.rpt"] {report_area -hierarchy}
    redirect -tee [file join $DC_REPORT_DIR "report_power.rpt"] {report_power -analysis_effort medium -hierarchy}
    redirect -tee [file join $DC_REPORT_DIR "report_qor.rpt"] {report_qor}
}

dc_step "导出综合结果" {
    write_file -format verilog -hierarchy -output [file join $DC_OUT_DIR "${TOP_MODULE}_syn.v"]
    write_file -format ddc -hierarchy -output [file join $DC_OUT_DIR "${TOP_MODULE}.ddc"]
    write_sdc [file join $DC_OUT_DIR "${TOP_MODULE}_syn.sdc"]
}

flow_report_banner "Design Compiler 综合完成"
exit 0
