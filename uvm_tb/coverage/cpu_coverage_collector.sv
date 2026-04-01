`uvm_analysis_imp_decl(_retire)
`uvm_analysis_imp_decl(_mem)

class cpu_coverage_collector extends uvm_component;
    typedef struct {
        string category;
        string instruction;
    } bin_meta_t;

    uvm_analysis_imp_retire #(cpu_retire_item, cpu_coverage_collector) retire_imp;
    uvm_analysis_imp_mem    #(cpu_mem_item, cpu_coverage_collector)    mem_imp;
    cpu_env_cfg cfg;

    bit [7:0]   current_opcode;
    bit [1:0]   current_dst_class;
    bit [1:0]   current_src_class;
    bit         current_same_reg;
    bit         current_c;
    bit         current_z;
    bit         current_v;
    bit         current_s;
    bit         current_branch_taken;
    bit [1:0]   current_instr_words;
    bit [15:0]  current_extra_word;
    bit [15:0]  current_mem_addr;
    bit [1:0]   current_mem_kind;

    bit [15:0] last_store_addr;
    bit        have_last_store;
    bit        have_r10_mem_access;
    bit        have_r11_mem_access;
    bit        seen_clc;
    bit        seen_stc;

    int unsigned bin_hits[string];
    bin_meta_t   bin_meta[string];
    string       ordered_bins[$];

    covergroup retire_cg;
        option.per_instance = 1;
        opcode_cp: coverpoint current_opcode {
            bins add    = {8'h00};
            bins sub    = {8'h01};
            bins and_op = {8'h02};
            bins cmp    = {8'h03};
            bins xor_op = {8'h04};
            bins testop = {8'h05};
            bins or_op  = {8'h06};
            bins mvrr   = {8'h07};
            bins dec    = {8'h08};
            bins inc    = {8'h09};
            bins shl    = {8'h0A};
            bins shr    = {8'h0B};
            bins adc    = {8'h0C};
            bins sbb    = {8'h0D};
            bins jr     = {8'h40};
            bins jrs    = {8'h41};
            bins jrns   = {8'h43};
            bins jrc    = {8'h44};
            bins jrnc   = {8'h45};
            bins jrz    = {8'h46};
            bins jrnz   = {8'h47};
            bins clc    = {8'h78};
            bins stc    = {8'h7A};
            bins jmpa   = {8'h80};
            bins mvrd   = {8'h81};
            bins ldrr   = {8'h82};
            bins strr   = {8'h83};
        }
        dst_class_cp: coverpoint current_dst_class { bins low = {0}; bins r9 = {1}; bins high = {2}; }
        src_class_cp: coverpoint current_src_class { bins low = {0}; bins r9 = {1}; bins high = {2}; }
        same_reg_cp: coverpoint current_same_reg { bins same = {1}; bins diff = {0}; }
        carry_cp: coverpoint current_c { bins clr = {0}; bins set = {1}; }
        zero_cp: coverpoint current_z { bins clr = {0}; bins set = {1}; }
        sign_cp: coverpoint current_s { bins clr = {0}; bins set = {1}; }
        overflow_cp: coverpoint current_v { bins clr = {0}; bins set = {1}; }
        branch_taken_cp: coverpoint current_branch_taken { bins taken = {1}; bins not_taken = {0}; }
        instr_words_cp: coverpoint current_instr_words { bins one = {1}; bins two = {2}; }
        dst_x_opcode: cross opcode_cp, dst_class_cp;
        src_x_opcode: cross opcode_cp, src_class_cp;
    endgroup

    covergroup mem_cg;
        option.per_instance = 1;
        mem_addr_cp: coverpoint current_mem_addr {
            bins low_addr = {[16'h0000:16'h004F]};
            bins mid_addr = {[16'h0100:16'h0110]};
            bins high_addr = {[16'hFF00:16'hFFFF]};
        }
        mem_kind_cp: coverpoint current_mem_kind {
            bins read = {1};
            bins write = {2};
        }
        mem_cross: cross mem_addr_cp, mem_kind_cp;
    endgroup

    `uvm_component_utils(cpu_coverage_collector)

    function new(string name = "cpu_coverage_collector", uvm_component parent = null);
        super.new(name, parent);
        retire_imp = new("retire_imp", this);
        mem_imp    = new("mem_imp", this);
        retire_cg  = new();
        mem_cg     = new();
        define_bins();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        void'(uvm_config_db#(cpu_env_cfg)::get(this, "", "cfg", cfg));
    endfunction

    function automatic bit [1:0] classify_reg(bit [3:0] reg_idx);
        if (reg_idx == 4'd9) begin
            return 2'd1;
        end
        if (reg_idx <= 4'd4) begin
            return 2'd0;
        end
        return 2'd2;
    endfunction

    function automatic bit is_flag_instruction(bit [7:0] opcode);
        return opcode inside {8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h08, 8'h09, 8'h0A, 8'h0B, 8'h0C, 8'h0D};
    endfunction

    function automatic bit is_branch_opcode(bit [7:0] opcode);
        return opcode inside {8'h40, 8'h41, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47, 8'h80};
    endfunction

    function automatic bit [15:0] sign_extend8(bit [7:0] value);
        return {{8{value[7]}}, value};
    endfunction

    function automatic string opcode_name(bit [7:0] opcode);
        case (opcode)
            8'h00: return "ADD";
            8'h01: return "SUB";
            8'h02: return "AND";
            8'h03: return "CMP";
            8'h04: return "XOR";
            8'h05: return "TEST";
            8'h06: return "OR";
            8'h07: return "MVRR";
            8'h08: return "DEC";
            8'h09: return "INC";
            8'h0A: return "SHL";
            8'h0B: return "SHR";
            8'h0C: return "ADC";
            8'h0D: return "SBB";
            8'h40: return "JR";
            8'h41: return "JRS";
            8'h43: return "JRNS";
            8'h44: return "JRC";
            8'h45: return "JRNC";
            8'h46: return "JRZ";
            8'h47: return "JRNZ";
            8'h78: return "CLC";
            8'h7A: return "STC";
            8'h80: return "JMPA";
            8'h81: return "MVRD";
            8'h82: return "LDRR";
            8'h83: return "STRR";
            default: return $sformatf("OP_%02h", opcode);
        endcase
    endfunction

    function void add_bin(string name, string category, string instruction = "");
        ordered_bins.push_back(name);
        bin_hits[name] = 0;
        bin_meta[name].category = category;
        bin_meta[name].instruction = instruction;
    endfunction

    function void hit_bin(string name);
        if (!bin_hits.exists(name)) begin
            `uvm_error(get_type_name(), $sformatf("unknown coverage bin %s", name))
            return;
        end
        bin_hits[name]++;
    endfunction

    function void define_bins();
        add_bin("opcode_ADD", "opcode", "ADD");
        add_bin("opcode_SUB", "opcode", "SUB");
        add_bin("opcode_AND", "opcode", "AND");
        add_bin("opcode_CMP", "opcode", "CMP");
        add_bin("opcode_XOR", "opcode", "XOR");
        add_bin("opcode_TEST", "opcode", "TEST");
        add_bin("opcode_OR", "opcode", "OR");
        add_bin("opcode_MVRR", "opcode", "MVRR");
        add_bin("opcode_DEC", "opcode", "DEC");
        add_bin("opcode_INC", "opcode", "INC");
        add_bin("opcode_SHL", "opcode", "SHL");
        add_bin("opcode_SHR", "opcode", "SHR");
        add_bin("opcode_ADC", "opcode", "ADC");
        add_bin("opcode_SBB", "opcode", "SBB");
        add_bin("opcode_JR", "opcode", "JR");
        add_bin("opcode_JRS", "opcode", "JRS");
        add_bin("opcode_JRNS", "opcode", "JRNS");
        add_bin("opcode_JRC", "opcode", "JRC");
        add_bin("opcode_JRNC", "opcode", "JRNC");
        add_bin("opcode_JRZ", "opcode", "JRZ");
        add_bin("opcode_JRNZ", "opcode", "JRNZ");
        add_bin("opcode_CLC", "opcode", "CLC");
        add_bin("opcode_STC", "opcode", "STC");
        add_bin("opcode_JMPA", "opcode", "JMPA");
        add_bin("opcode_MVRD", "opcode", "MVRD");
        add_bin("opcode_LDRR", "opcode", "LDRR");
        add_bin("opcode_STRR", "opcode", "STRR");

        add_bin("dst_low", "register");
        add_bin("dst_r9", "register");
        add_bin("dst_high", "register");
        add_bin("src_low", "register");
        add_bin("src_r9", "register");
        add_bin("src_high", "register");
        add_bin("same_reg", "register");
        add_bin("different_reg", "register");

        add_bin("flag_c_clear", "flags");
        add_bin("flag_c_set", "flags");
        add_bin("flag_z_clear", "flags");
        add_bin("flag_z_set", "flags");
        add_bin("flag_s_clear", "flags");
        add_bin("flag_s_set", "flags");
        add_bin("flag_v_clear", "flags");
        add_bin("flag_v_set", "flags");

        add_bin("add_zero", "scenario", "ADD");
        add_bin("add_carry", "scenario", "ADD");
        add_bin("add_overflow", "scenario", "ADD");
        add_bin("sub_zero", "scenario", "SUB");
        add_bin("sub_borrow", "scenario", "SUB");
        add_bin("sub_overflow", "scenario", "SUB");
        add_bin("adc_carry_in_clear", "scenario", "ADC");
        add_bin("adc_carry_in_set", "scenario", "ADC");
        add_bin("sbb_carry_in_clear", "scenario", "SBB");
        add_bin("sbb_carry_in_set", "scenario", "SBB");
        add_bin("inc_wrap_to_zero", "scenario", "INC");
        add_bin("dec_wrap_to_ffff", "scenario", "DEC");
        add_bin("shl_sets_carry", "scenario", "SHL");
        add_bin("shr_sets_carry", "scenario", "SHR");
        add_bin("and_zero", "scenario", "AND");
        add_bin("or_nonzero", "scenario", "OR");
        add_bin("xor_zero", "scenario", "XOR");
        add_bin("cmp_zero", "scenario", "CMP");
        add_bin("cmp_negative", "scenario", "CMP");
        add_bin("test_zero", "scenario", "TEST");
        add_bin("test_nonzero", "scenario", "TEST");
        add_bin("mvrr_same", "scenario", "MVRR");
        add_bin("mvrr_diff", "scenario", "MVRR");
        add_bin("mvrd_imm_zero", "scenario", "MVRD");
        add_bin("mvrd_imm_high", "scenario", "MVRD");

        add_bin("jr_forward", "branch", "JR");
        add_bin("jr_backward", "branch", "JR");
        add_bin("jrs_taken", "branch", "JRS");
        add_bin("jrs_not_taken", "branch", "JRS");
        add_bin("jrns_taken", "branch", "JRNS");
        add_bin("jrns_not_taken", "branch", "JRNS");
        add_bin("jrc_taken", "branch", "JRC");
        add_bin("jrc_not_taken", "branch", "JRC");
        add_bin("jrnc_taken", "branch", "JRNC");
        add_bin("jrnc_not_taken", "branch", "JRNC");
        add_bin("jrz_taken", "branch", "JRZ");
        add_bin("jrz_not_taken", "branch", "JRZ");
        add_bin("jrnz_taken", "branch", "JRNZ");
        add_bin("jrnz_not_taken", "branch", "JRNZ");
        add_bin("jmpa_absolute", "branch", "JMPA");

        add_bin("clc_clears_carry", "flag_ctrl", "CLC");
        add_bin("stc_sets_carry", "flag_ctrl", "STC");
        add_bin("carry_control_chain", "flag_ctrl");

        add_bin("ldrr_read", "memory", "LDRR");
        add_bin("strr_write", "memory", "STRR");
        add_bin("mem_addr_low", "memory");
        add_bin("mem_addr_mid", "memory");
        add_bin("mem_addr_high", "memory");
        add_bin("mem_store_then_load", "memory");
        add_bin("mem_read_after_write_same_addr", "memory");
        add_bin("mem_addr_from_r10", "memory");
        add_bin("mem_addr_from_r11", "memory");
        add_bin("two_cycle_mem_instr", "memory");

        add_bin("single_word_pc_step", "encoding");
        add_bin("double_word_pc_step", "encoding");
        add_bin("two_cycle_single_word_pc_step", "encoding");
    endfunction

    function void sample_common_bins(cpu_retire_item item);
        current_opcode      = item.opcode;
        current_dst_class   = classify_reg(item.dr);
        current_src_class   = classify_reg(item.sr);
        current_same_reg    = (item.dr == item.sr);
        current_c           = item.c;
        current_z           = item.z;
        current_v           = item.v;
        current_s           = item.s;
        current_branch_taken = item.branch_taken;
        current_instr_words = item.instr_words;
        current_extra_word  = item.extra_word;

        retire_cg.sample();

        hit_bin($sformatf("opcode_%s", opcode_name(item.opcode)));

        case (current_dst_class)
            2'd0: hit_bin("dst_low");
            2'd1: hit_bin("dst_r9");
            default: hit_bin("dst_high");
        endcase

        case (current_src_class)
            2'd0: hit_bin("src_low");
            2'd1: hit_bin("src_r9");
            default: hit_bin("src_high");
        endcase

        if (current_same_reg) begin
            hit_bin("same_reg");
        end else begin
            hit_bin("different_reg");
        end

        if (item.c) hit_bin("flag_c_set"); else hit_bin("flag_c_clear");
        if (item.z) hit_bin("flag_z_set"); else hit_bin("flag_z_clear");
        if (item.s) hit_bin("flag_s_set"); else hit_bin("flag_s_clear");
        if (item.v) hit_bin("flag_v_set"); else hit_bin("flag_v_clear");

        if ((item.opcode inside {8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07, 8'h08, 8'h09, 8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h78, 8'h7A}) &&
            (item.pc == (item.instr_addr + 16'h0001))) begin
            hit_bin("single_word_pc_step");
        end
        if ((item.opcode inside {8'h82, 8'h83}) && (item.pc == (item.instr_addr + 16'h0001))) begin
            hit_bin("two_cycle_single_word_pc_step");
            hit_bin("two_cycle_mem_instr");
        end
        if (item.opcode inside {8'h80, 8'h81}) begin
            hit_bin("double_word_pc_step");
        end
    endfunction

    function void sample_scenario_bins(cpu_retire_item item);
        bit [15:0] result_value;

        result_value = item.regs[item.dr];
        case (item.opcode)
            8'h00: begin
                if (item.z) hit_bin("add_zero");
                if (item.c) hit_bin("add_carry");
                if (item.v) hit_bin("add_overflow");
            end
            8'h01: begin
                if (item.z) hit_bin("sub_zero");
                if (item.c) hit_bin("sub_borrow");
                if (item.v) hit_bin("sub_overflow");
            end
            8'h0C: begin
                if (item.pre_c) hit_bin("adc_carry_in_set");
                else hit_bin("adc_carry_in_clear");
            end
            8'h0D: begin
                if (item.pre_c) hit_bin("sbb_carry_in_set");
                else hit_bin("sbb_carry_in_clear");
            end
            8'h09: if (result_value == 16'h0000) hit_bin("inc_wrap_to_zero");
            8'h08: if (result_value == 16'hFFFF) hit_bin("dec_wrap_to_ffff");
            8'h0A: if (item.c) hit_bin("shl_sets_carry");
            8'h0B: if (item.c) hit_bin("shr_sets_carry");
            8'h02: if (item.z) hit_bin("and_zero");
            8'h06: if (!item.z) hit_bin("or_nonzero");
            8'h04: if (item.z) hit_bin("xor_zero");
            8'h03: begin
                if (item.z) hit_bin("cmp_zero");
                if (item.s) hit_bin("cmp_negative");
            end
            8'h05: begin
                if (item.z) hit_bin("test_zero");
                else hit_bin("test_nonzero");
            end
            8'h07: begin
                if (item.dr == item.sr) hit_bin("mvrr_same");
                else hit_bin("mvrr_diff");
            end
            8'h81: begin
                if (item.regs[item.dr] == 16'h0000) hit_bin("mvrd_imm_zero");
                if (item.regs[item.dr][15]) hit_bin("mvrd_imm_high");
            end
            8'h78: begin
                seen_clc = 1'b1;
                if (!item.c) hit_bin("clc_clears_carry");
            end
            8'h7A: begin
                seen_stc = 1'b1;
                if (item.c) hit_bin("stc_sets_carry");
            end
            default: begin end
        endcase

        if (seen_clc && seen_stc) begin
            hit_bin("carry_control_chain");
        end
    endfunction

    function void sample_branch_bins(cpu_retire_item item);
        bit signed [8:0] offset;

        offset = $signed({item.ir[7], item.ir[7:0]});
        case (item.opcode)
            8'h40: begin
                if (offset > 0) hit_bin("jr_forward");
                if (offset < 0) hit_bin("jr_backward");
            end
            8'h41: if (item.branch_taken) hit_bin("jrs_taken"); else hit_bin("jrs_not_taken");
            8'h43: if (item.branch_taken) hit_bin("jrns_taken"); else hit_bin("jrns_not_taken");
            8'h44: if (item.branch_taken) hit_bin("jrc_taken"); else hit_bin("jrc_not_taken");
            8'h45: if (item.branch_taken) hit_bin("jrnc_taken"); else hit_bin("jrnc_not_taken");
            8'h46: if (item.branch_taken) hit_bin("jrz_taken"); else hit_bin("jrz_not_taken");
            8'h47: if (item.branch_taken) hit_bin("jrnz_taken"); else hit_bin("jrnz_not_taken");
            8'h80: hit_bin("jmpa_absolute");
            default: begin end
        endcase
    endfunction

    function void write_retire(cpu_retire_item item);
        sample_common_bins(item);
        sample_scenario_bins(item);
        if (is_branch_opcode(item.opcode)) begin
            sample_branch_bins(item);
        end
    endfunction

    function void write_mem(cpu_mem_item item);
        current_mem_addr = item.addr;
        current_mem_kind = (item.kind == cpu_mem_item::MEM_READ) ? 2'd1 : 2'd2;
        mem_cg.sample();

        if (item.kind == cpu_mem_item::MEM_READ) begin
            hit_bin("ldrr_read");
            if (have_last_store && (last_store_addr == item.addr)) begin
                hit_bin("mem_store_then_load");
                hit_bin("mem_read_after_write_same_addr");
            end
        end else begin
            hit_bin("strr_write");
            last_store_addr = item.addr;
            have_last_store = 1'b1;
        end

        if (item.addr <= 16'h004F) hit_bin("mem_addr_low");
        if ((item.addr >= 16'h0100) && (item.addr <= 16'h0110)) hit_bin("mem_addr_mid");
        if (item.addr >= 16'hFF00) hit_bin("mem_addr_high");

        if (item.addr == 16'h0100) begin
            have_r10_mem_access = 1'b1;
            hit_bin("mem_addr_from_r10");
        end
        if (item.addr == 16'h0101) begin
            have_r11_mem_access = 1'b1;
            hit_bin("mem_addr_from_r11");
        end
    endfunction

    function real compute_coverage();
        int covered;
        foreach (ordered_bins[idx]) begin
            if (bin_hits[ordered_bins[idx]] > 0) begin
                covered++;
            end
        end
        if (ordered_bins.size() == 0) begin
            return 100.0;
        end
        return (100.0 * covered) / ordered_bins.size();
    endfunction

    function void report_phase(uvm_phase phase);
        int fd;
        int covered;
        real coverage_pct;

        super.report_phase(phase);
        foreach (ordered_bins[idx]) begin
            if (bin_hits[ordered_bins[idx]] > 0) begin
                covered++;
            end
        end
        coverage_pct = compute_coverage();

        if (cfg.coverage_report != "") begin
            fd = $fopen(cfg.coverage_report, "w");
            if (fd != 0) begin
                $fwrite(fd, "{\n");
                $fwrite(fd, "  \"summary\": {\n");
                $fwrite(fd, "    \"covered_bins\": %0d,\n", covered);
                $fwrite(fd, "    \"total_bins\": %0d,\n", ordered_bins.size());
                $fwrite(fd, "    \"functional_coverage\": %.2f\n", coverage_pct);
                $fwrite(fd, "  },\n");
                $fwrite(fd, "  \"bins\": [\n");
                for (int idx = 0; idx < ordered_bins.size(); idx++) begin
                    string name;
                    name = ordered_bins[idx];
                    $fwrite(
                        fd,
                        "    {\"name\":\"%s\",\"category\":\"%s\",\"instruction\":\"%s\",\"hits\":%0d,\"covered\":%s}%s\n",
                        name,
                        bin_meta[name].category,
                        bin_meta[name].instruction,
                        bin_hits[name],
                        (bin_hits[name] > 0) ? "true" : "false",
                        (idx == (ordered_bins.size() - 1)) ? "" : ","
                    );
                end
                $fwrite(fd, "  ],\n");
                $fwrite(fd, "  \"uncovered_bins\": [\n");
                begin
                    int pending;
                    pending = 0;
                    foreach (ordered_bins[idx]) begin
                        if (bin_hits[ordered_bins[idx]] == 0) begin
                            pending++;
                        end
                    end
                    for (int idx = 0; idx < ordered_bins.size(); idx++) begin
                        string name;
                        if (bin_hits[ordered_bins[idx]] != 0) begin
                            continue;
                        end
                        name = ordered_bins[idx];
                        pending--;
                        $fwrite(
                            fd,
                            "    {\"name\":\"%s\",\"category\":\"%s\",\"instruction\":\"%s\"}%s\n",
                            name,
                            bin_meta[name].category,
                            bin_meta[name].instruction,
                            (pending == 0) ? "" : ","
                        );
                    end
                end
                $fwrite(fd, "  ]\n");
                $fwrite(fd, "}\n");
                $fclose(fd);
            end
        end
        `uvm_info(get_type_name(), $sformatf("functional closure coverage = %.2f%% (%0d/%0d bins)", coverage_pct, covered, ordered_bins.size()), UVM_LOW)
    endfunction
endclass
