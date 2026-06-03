# backend_flow/config.tcl
# --------------------------------------------------------------------
# 说明：
# 1. 这是整个 RTL-to-GDSII 流程的唯一配置入口。
# 2. 请优先修改本文件中的占位符，而不是直接改各阶段脚本。
# 3. 当前默认路径对齐本仓库结构：RTL 在 ../vsrc，PDK 在 ../USC-3N-2D。
# --------------------------------------------------------------------

set FLOW_ROOT [file dirname [file normalize [info script]]]
set PROJECT_ROOT [file normalize [file join $FLOW_ROOT ".."]]

# --------------------------------------------------------------------
# 设计级占位符：这些变量必须按你的项目真实情况填写。
# --------------------------------------------------------------------
set TOP_MODULE "cpu_pnr_top"
set CLOCK_PORT "clk"
set RESET_PORT "reset"
set CLK_PERIOD_NS "10.0"

# 约束模板路径。建议把最终 SDC 放在 constraints/ 目录下集中管理。
set CONSTRAINTS_DIR [file join $FLOW_ROOT "constraints"]
set TOP_SDC_FILE [file join $CONSTRAINTS_DIR "${TOP_MODULE}.sdc"]

# --------------------------------------------------------------------
# 输入与输出目录
# --------------------------------------------------------------------
set RTL_DIR [file join $PROJECT_ROOT "vsrc"]
set FILELIST_FILE [file join $RTL_DIR "files.f"]

set LOG_ROOT [file join $FLOW_ROOT "logs"]
set REPORT_ROOT [file join $FLOW_ROOT "reports"]
set OUT_ROOT [file join $FLOW_ROOT "out"]

set DC_LOG_DIR [file join $LOG_ROOT "dc"]
set ICC2_LOG_DIR [file join $LOG_ROOT "icc2"]
set PT_LOG_DIR [file join $LOG_ROOT "pt"]

set DC_REPORT_DIR [file join $REPORT_ROOT "dc"]
set ICC2_REPORT_DIR [file join $REPORT_ROOT "icc2"]
set PT_REPORT_DIR [file join $REPORT_ROOT "pt"]

set DC_OUT_DIR [file join $OUT_ROOT "dc"]
set ICC2_OUT_DIR [file join $OUT_ROOT "icc2"]
set PT_OUT_DIR [file join $OUT_ROOT "pt"]

# --------------------------------------------------------------------
# PDK 与库文件
# --------------------------------------------------------------------
set PDK_ROOT [file join $PROJECT_ROOT "USC-3N-2D"]
set SYNOPSYS_PDK_ROOT [file join $PDK_ROOT "PnR-Synopsys" "Front-side Version"]
set PDK_CACHE_DIR [file join $FLOW_ROOT "pdk_cache"]

set STD_LIB_DB [file join $FLOW_ROOT "libcache" "3nm_GAA_FSPR_rvt_nldm.db"]
set STD_LIB_LIBERTY [file join $PDK_CACHE_DIR "3nm_GAA_FSPR_rvt_nldm.lib"]
set TECH_FILE [file join $PDK_CACHE_DIR "3nm_GAA_FSPR.tf"]
set TECH_LEF_FILE [file join $PDK_CACHE_DIR "3nm_GAA_FSPR.tech.lef"]
set STD_CELL_LEF_FILE [file join $PDK_CACHE_DIR "3nm_GAA_FSPR.lef"]
set TLU_PLUS_MAX_FILE [file join $PDK_CACHE_DIR "3nm_GAA_FSPR.tluplus"]
set TLU_PLUS_MIN_FILE [file join $PDK_CACHE_DIR "3nm_GAA_FSPR.tluplus"]
set PARASITIC_TECH_FILE [file join $PDK_CACHE_DIR "3nm_GAA_FSPR.nxtgrd"]
set MAP_FILE ""
set NDM_LIBRARY_DIR [file join $PDK_CACHE_DIR "3nm_GAA_FSPR.ndm"]

# 如果你的设计包含 IO / SRAM 等硬核，请在这里补齐真实路径。
set IO_LIB_FILES [list]
set MEMORY_LIB_FILES [list]
set IO_LEF_FILES [list]
set MEMORY_LEF_FILES [list]
set GDS_MAP_FILE [file join $PDK_CACHE_DIR "sccad_3nm.layermap"]

# --------------------------------------------------------------------
# 逻辑综合常用参数
# --------------------------------------------------------------------
set DC_TOPographical_MODE false
set DC_MAX_CORES 8
set DC_ULTRA_EFFORT "-timing_high_effort_script"

# --------------------------------------------------------------------
# 物理设计常用参数
# --------------------------------------------------------------------
set CORE_UTILIZATION 0.60
set CORE_ASPECT_RATIO 1.0
set CORE_OFFSET_UM 5.0
set PLACE_CONGESTION_EFFORT "high"
set CTS_TARGET_SKEW_NS 0.05
set CTS_TARGET_LATENCY_NS 0.20
set MAX_ROUTING_LAYER "M8"
set MIN_ROUTING_LAYER "M1"

# 3nm 设计中，PG 需尽早规划；以下参数需要按真实功耗网络替换。
set POWER_NET "VDD"
set GROUND_NET "VSS"
set POWER_PORT "VDD"
set GROUND_PORT "VSS"

# 天线/多重曝光相关开关保留为显式配置，便于后续接入真实 foundry recipe。
set ENABLE_ANTENNA_FIX true
set ENABLE_COLOR_AWARE_ROUTING true

# --------------------------------------------------------------------
# PrimeTime 签核参数
# --------------------------------------------------------------------
set PT_MAX_PATHS 20
set PT_ENABLE_HOLD true

# --------------------------------------------------------------------
# 可选环境脚本：如果你有统一的 Synopsys 环境初始化脚本，可在此填写。
# 留空则由外层 shell 自行保证 dc_shell / icc2_shell / pt_shell 可用。
# --------------------------------------------------------------------
set SYNOPSYS_ENV_SCRIPT ""

# --------------------------------------------------------------------
# 公共工具过程
# --------------------------------------------------------------------
proc flow_mkdirs {dirs} {
    foreach dir_path $dirs {
        if {![file exists $dir_path]} {
            file mkdir $dir_path
        }
    }
}

proc flow_is_placeholder {value} {
    return [expr {
        $value eq "" ||
        [string match "YOUR_*" $value]
    }]
}

proc flow_require_non_placeholder {var_name value} {
    if {[flow_is_placeholder $value]} {
        puts stderr "ERROR: 配置项 $var_name 仍然是占位符，请先修改 backend_flow/config.tcl"
        exit 1
    }
}

proc flow_require_file {path description} {
    if {![file exists $path]} {
        puts stderr "ERROR: 缺少${description}: $path"
        exit 1
    }
}

proc flow_require_files {paths description} {
    foreach path $paths {
        flow_require_file $path $description
    }
}

proc flow_filter_placeholders {items} {
    set result [list]
    foreach item $items {
        if {![flow_is_placeholder $item]} {
            lappend result $item
        }
    }
    return $result
}

proc flow_collect_rtl_files {rtl_dir} {
    set rtl_files [list]
    foreach pattern [list "*.sv" "*.v"] {
        foreach file_path [lsort [glob -nocomplain -directory $rtl_dir $pattern]] {
            lappend rtl_files $file_path
        }
    }
    return $rtl_files
}

proc flow_collect_rtl_files_from_filelist {filelist_path} {
    global PROJECT_ROOT
    set rtl_files [list]
    set fd [open $filelist_path r]
    while {[gets $fd line] >= 0} {
        set trimmed [string trim $line]
        if {$trimmed eq "" || [string match "#*" $trimmed]} {
            continue
        }
        if {[file pathtype $trimmed] eq "relative"} {
            set candidate [file join $PROJECT_ROOT $trimmed]
        } else {
            set candidate $trimmed
        }
        lappend rtl_files [file normalize $candidate]
    }
    close $fd
    return $rtl_files
}

proc flow_report_banner {title} {
    puts ""
    puts "=================================================================="
    puts $title
    puts "=================================================================="
}
