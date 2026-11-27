`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// biomed_soc_top [synthesizable] : complete digital core of the reconfigurable biomedical SoC.
//
//   ADC (analog macro pins or direct injection) -> input_formatter -> sample_buffer / quality_est / FIR
//   fir_engine (T2) + nn_engine (T4) share ONE mac_unit through task_scheduler (inside the scheduler)
//   quality_est (T3 helper) + result_manager (T5) -> output_fifo -> host / result pins
//   host_regs : memory-mapped configuration, coefficient/weight/bias/feature loading, status, IRQ
//
// Configurations
//   A (MODE.adc_bypass = 0): the SAR controller drives the analog macro pins
//        adc_sample_en / adc_dac_code[9:0] and reads the comparator decision adc_cmp_in.
//        A conversion starts every ADC_CFG.div clocks while CTRL.run = 1.
//        In simulation the analog side is the behavioural S&H / CDAC / comparator (tb_soc).
//   B (MODE.adc_bypass = 1, reset default): samples enter on adc_bypass_valid / adc_bypass_data[9:0]
//        (direct digital injection, used to verify the digital core independently).
//
// Single clock domain. Reset: rst_n pin, async assert / sync release (reset_sync).
//   Hard domain  : host_regs (configuration survives a soft reset).
//   Core domain  : everything else; also reset by CTRL.soft_reset. Coefficient/weight memories have
//                  no reset at all (regfile_sync RESET_CLEAR=0) and keep their contents.
// adc_cmp_in is assumed synchronous to clk (the comparator is clocked by the SAR clock in the analog macro).
// Register map: 10_Documentation/06_register_map.md
// -----------------------------------------------------------------------------
module biomed_soc_top (
    input  wire        clk,
    input  wire        rst_n,
    // host bus
    input  wire        host_we,
    input  wire        host_re,
    input  wire [11:0] host_addr,
    input  wire [31:0] host_wdata,
    output wire [31:0] host_rdata,
    output wire        host_rvalid,
    // analog SAR macro interface (configuration A)
    input  wire        adc_cmp_in,
    output wire        adc_sample_en,
    output wire [9:0]  adc_dac_code,
    // direct digital sample injection (configuration B)
    input  wire        adc_bypass_valid,
    input  wire [9:0]  adc_bypass_data,
    // status
    output wire        irq,
    output wire        busy,
    output wire        done,
    output wire        abnormal,
    output wire        uncertain,
    output wire        result_valid,
    output wire [15:0] result_data
);
    // ================= resets
    wire hrst_n, crst_n, soft_rst;
    reset_sync u_rst_hard (.clk(clk), .rst_in_n(rst_n),             .rst_out_n(hrst_n));
    reset_sync u_rst_core (.clk(clk), .rst_in_n(rst_n & ~soft_rst), .rst_out_n(crst_n));

    // ================= configuration
    wire        nn_start_p, stat_clr, flag_clr, run, adc_bypass, fir_out_en, q_out_en, mode_sel, preempt_en;
    wire [1:0]  mode, policy;
    wire [2:0]  prio0, prio1;
    wire [7:0]  quantum, q_clip_max, q_noise_k;
    wire [4:0]  fir_taps, fir_shift, nn_shift;
    wire [15:0] adc_div, conf_thr, deadline0, deadline1;
    wire [3:0]  q_win_log2, irq_en, irq_status;
    wire [10:0] q_amp_min;
    wire [9:0]  q_base_max;
    wire        coef_we, w_we, b_we, f_we;
    wire [7:0]  mem_waddr;
    wire [23:0] mem_wdata;

    // ================= ADC: sample-rate divider + SAR controller (configuration A)
    reg  [15:0] div_cnt;
    wire        tick = run && !adc_bypass && (adc_div != 16'd0) && (div_cnt == adc_div - 16'd1);
    always @(posedge clk or negedge crst_n) begin
        if (!crst_n)                             div_cnt <= 16'd0;
        else if (!run || adc_bypass || tick)     div_cnt <= 16'd0;
        else                                     div_cnt <= div_cnt + 16'd1;
    end

    wire       sar_busy, sar_done;
    wire [9:0] sar_data;
    sar_controller #(.N(10), .SAMPLE_CYCLES(1)) u_sar (
        .clk(clk), .rst_n(crst_n), .start(tick), .cmp_out(adc_cmp_in),
        .sample_en(adc_sample_en), .dac_code(adc_dac_code), .busy(sar_busy),
        .done(sar_done), .data_out(sar_data));

    wire       code_v = adc_bypass ? (adc_bypass_valid && run) : sar_done;
    wire [9:0] code   = adc_bypass ? adc_bypass_data : sar_data;

    // ================= T1: formatting and sample memory
    wire               xv;
    wire signed [10:0] x;
    input_formatter #(.ADC_BITS(10)) u_fmt (.clk(clk), .rst_n(crst_n), .in_valid(code_v),
        .adc_code(code), .out_valid(xv), .x_signed(x));

    wire [5:0]  sb_off;
    wire [10:0] sb_data;
    wire        sb_valid;
    wire [6:0]  sb_count;
    sample_buffer #(.W(11), .DEPTH(64)) u_sbuf (.clk(clk), .rst_n(crst_n), .wr_en(xv), .wr_data(x),
        .rd_offset(sb_off), .rd_data(sb_data), .rd_valid(sb_valid), .count(sb_count));

    // ================= T3: signal quality
    wire        q_v;
    wire [1:0]  q_class;
    wire [3:0]  q_flags;
    wire [7:0]  q_score;
    wire [10:0] q_p2p, q_mad;
    wire signed [10:0] q_mean;
    quality_est u_q (.clk(clk), .rst_n(crst_n), .clr(1'b0), .in_valid(xv), .x(x),
        .win_log2(q_win_log2), .clip_max(q_clip_max), .amp_min(q_amp_min), .noise_k(q_noise_k),
        .base_max(q_base_max), .q_valid(q_v), .q_class(q_class), .q_flags(q_flags), .q_score(q_score),
        .q_p2p(q_p2p), .q_mad(q_mad), .q_mean(q_mean));

    // ================= memories (host-loaded, engine-read)
    wire [3:0]         coef_addr;
    wire signed [11:0] coef_data;
    regfile_sync #(.WIDTH(12), .DEPTH(16)) u_coef (.clk(clk), .rst_n(hrst_n), .we(coef_we),
        .waddr(mem_waddr[3:0]), .wdata(mem_wdata[11:0]), .raddr(coef_addr), .rdata(coef_data));

    wire [2:0]         feat_addr;
    wire [7:0]         w_addr;
    wire [4:0]         b_addr;
    wire signed [7:0]  feat_data, w_data;
    wire signed [23:0] b_data;
    regfile_sync #(.WIDTH(8),  .DEPTH(160)) u_wmem (.clk(clk), .rst_n(hrst_n), .we(w_we),
        .waddr(mem_waddr), .wdata(mem_wdata[7:0]), .raddr(w_addr), .rdata(w_data));
    regfile_sync #(.WIDTH(24), .DEPTH(32))  u_bmem (.clk(clk), .rst_n(hrst_n), .we(b_we),
        .waddr(mem_waddr[4:0]), .wdata(mem_wdata), .raddr(b_addr), .rdata(b_data));
    regfile_sync #(.WIDTH(8),  .DEPTH(8))   u_fmem (.clk(clk), .rst_n(hrst_n), .we(f_we),
        .waddr(mem_waddr[2:0]), .wdata(mem_wdata[7:0]), .raddr(feat_addr), .rdata(feat_data));

    // ================= T2: FIR engine (scheduler client 0)
    wire               fir_sv = xv && (mode != 2'd1);
    wire               f_req, f_clr, f_en, f_bnd, f_grant, f_accv, f_ovf;
    wire signed [10:0] f_a;
    wire signed [11:0] f_b;
    wire               y_valid, y_sat, y_ovf, fir_busy, fir_overrun;
    wire signed [10:0] y_data;
    wire [7:0]         fir_lat;
    wire signed [31:0] acc_out;
    fir_engine u_fir (.clk(clk), .rst_n(crst_n), .sample_valid(fir_sv), .sample_in(x),
        .taps_cfg(fir_taps), .shift_cfg(fir_shift), .coef_addr(coef_addr), .coef_data(coef_data),
        .mac_req(f_req), .mac_grant(f_grant), .mac_clear(f_clr), .mac_en(f_en), .mac_a(f_a), .mac_b(f_b),
        .mac_acc(acc_out), .mac_acc_valid(f_accv), .mac_overflow(f_ovf),
        .y_valid(y_valid), .y_data(y_data), .y_sat(y_sat), .y_ovf(y_ovf), .busy(fir_busy),
        .at_boundary(f_bnd), .overrun(fir_overrun), .last_latency(fir_lat));

    // ================= T4: NN engine (scheduler client 1)
    wire               nn_go = nn_start_p && (mode != 2'd0);
    wire               n_req, n_load, n_en, n_bnd, n_grant, n_accv, n_ovf;
    wire signed [31:0] n_lv;
    wire signed [10:0] n_a;
    wire signed [11:0] n_b;
    wire               nn_valid, nn_class, nn_lowconf, nn_ovf, nn_busy;
    wire signed [31:0] nn_s0, nn_s1;
    wire [15:0]        nn_margin, nn_lat;
    nn_engine u_nn (.clk(clk), .rst_n(crst_n), .start(nn_go), .shift_cfg(nn_shift), .conf_thr(conf_thr),
        .feat_addr(feat_addr), .feat_data(feat_data), .w_addr(w_addr), .w_data(w_data),
        .b_addr(b_addr), .b_data(b_data),
        .mac_req(n_req), .mac_grant(n_grant), .mac_load(n_load), .mac_load_val(n_lv), .mac_en(n_en),
        .mac_a(n_a), .mac_b(n_b), .mac_acc(acc_out), .mac_acc_valid(n_accv), .mac_overflow(n_ovf),
        .nn_valid(nn_valid), .nn_class(nn_class), .nn_score0(nn_s0), .nn_score1(nn_s1),
        .nn_margin(nn_margin), .nn_lowconf(nn_lowconf), .nn_ovf(nn_ovf), .busy(nn_busy),
        .at_boundary(n_bnd), .last_latency(nn_lat));

    // ================= scheduler + the single shared MAC
    wire [1:0]  sst;
    wire        sowner;
    wire [31:0] m_total, m_ops, m_ovh, m_wsum0, m_wsum1, m_esum0, m_esum1;
    wire [15:0] m_pre, m_t0, m_t1, m_wmax0, m_wmax1, m_lmax0, m_lmax1, m_miss0, m_miss1;
    task_scheduler #(.ACC_W(32), .A_W(11), .B_W(12), .PIPE(0)) u_sched (
        .clk(clk), .rst_n(crst_n), .policy(policy), .mode_sel(mode_sel), .preempt_en(preempt_en),
        .prio0(prio0), .prio1(prio1), .quantum(quantum), .deadline0(deadline0), .deadline1(deadline1),
        .stat_clr(stat_clr),
        .req0(f_req), .bnd0(f_bnd), .clr0(f_clr), .load0(1'b0), .en0(f_en), .a0(f_a), .b0(f_b), .lv0(32'sd0), .grant0(f_grant),
        .req1(n_req), .bnd1(n_bnd), .clr1(1'b0),  .load1(n_load), .en1(n_en), .a1(n_a), .b1(n_b), .lv1(n_lv), .grant1(n_grant),
        .acc_out(acc_out), .acc_valid0(f_accv), .acc_valid1(n_accv), .ovf0(f_ovf), .ovf1(n_ovf),
        .sched_state(sst), .owner_o(sowner),
        .m_total_cycles(m_total), .m_mac_ops(m_ops), .m_preempts(m_pre), .m_ovh_cycles(m_ovh),
        .m_tasks0(m_t0), .m_tasks1(m_t1), .m_wait_sum0(m_wsum0), .m_wait_sum1(m_wsum1),
        .m_wait_max0(m_wmax0), .m_wait_max1(m_wmax1), .m_lat_max0(m_lmax0), .m_lat_max1(m_lmax1),
        .m_exec_sum0(m_esum0), .m_exec_sum1(m_esum1), .m_miss0(m_miss0), .m_miss1(m_miss1));

    // ================= T5: result manager + output FIFO
    wire        rm_push, fifo_full, fifo_empty, fifo_ovf, fifo_udf, fifo_pop;
    wire [15:0] rm_din, fifo_dout;
    wire [4:0]  fifo_count;
    wire        dec_valid, dec_unc, dec_abn, rm_lost;
    wire [1:0]  q_last;
    result_manager u_rm (.clk(clk), .rst_n(crst_n),
        .fir_v(y_valid), .fir_y(y_data), .fir_sat(y_sat), .fir_out_en(fir_out_en),
        .q_v(q_v), .q_class(q_class), .q_flags(q_flags), .q_score(q_score), .q_out_en(q_out_en),
        .nn_v(nn_valid), .nn_class(nn_class), .nn_lowconf(nn_lowconf), .nn_ovf(nn_ovf), .nn_margin(nn_margin),
        .fifo_full(fifo_full), .push(rm_push), .din(rm_din),
        .dec_valid(dec_valid), .dec_uncertain(dec_unc), .dec_abnormal(dec_abn), .q_last(q_last),
        .lost(rm_lost), .lost_clr(flag_clr));

    output_fifo #(.W(16), .DEPTH(16)) u_fifo (.clk(clk), .rst_n(crst_n), .push(rm_push), .din(rm_din),
        .pop(fifo_pop), .clr_flags(flag_clr), .dout(fifo_dout), .full(fifo_full), .empty(fifo_empty),
        .count(fifo_count), .overflow(fifo_ovf), .underflow(fifo_udf));

    // ================= events, status, host interface
    reg  [16:0] miss_q;
    wire [16:0] miss_sum = {1'b0, m_miss0} + {1'b0, m_miss1};
    always @(posedge clk or negedge crst_n) begin
        if (!crst_n) miss_q <= 17'd0; else miss_q <= miss_sum;
    end
    wire ev_miss = (miss_sum > miss_q);
    wire ev_poor = q_v && (q_class == 2'd2);

    wire [31:0] status_w = {8'd0, sowner, sst, fifo_count, 3'd0, q_last, dec_unc, dec_abn, rm_lost,
                            fir_overrun, fifo_udf, fifo_ovf, fifo_full, fifo_empty, sar_busy, nn_busy, fir_busy};
    wire [31:0] nn_res_w = {nn_margin, 11'd0, dec_abn, dec_unc, nn_ovf, nn_lowconf, nn_class};
    wire [31:0] q_res_w  = {5'd0, q_p2p, q_score, q_flags, 2'd0, q_class};
    wire [31:0] lat_w    = {nn_lat, 8'd0, fir_lat};
    wire [383:0] metrics_w = {{m_miss1, m_miss0}, m_esum1, m_esum0, {m_lmax1, m_lmax0}, {m_wmax1, m_wmax0},
                              m_wsum1, m_wsum0, {m_t1, m_t0}, m_ovh, {16'd0, m_pre}, m_ops, m_total};

    host_regs u_host (.clk(clk), .rst_n(hrst_n),
        .host_we(host_we), .host_re(host_re), .host_addr(host_addr), .host_wdata(host_wdata),
        .host_rdata(host_rdata), .host_rvalid(host_rvalid),
        .soft_rst(soft_rst), .nn_start(nn_start_p), .stat_clr(stat_clr), .flag_clr(flag_clr), .run(run),
        .mode(mode), .adc_bypass(adc_bypass), .fir_out_en(fir_out_en), .q_out_en(q_out_en),
        .policy(policy), .mode_sel(mode_sel), .preempt_en(preempt_en), .prio0(prio0), .prio1(prio1), .quantum(quantum),
        .fir_taps(fir_taps), .fir_shift(fir_shift), .adc_div(adc_div),
        .q_win_log2(q_win_log2), .q_clip_max(q_clip_max), .q_amp_min(q_amp_min), .q_noise_k(q_noise_k), .q_base_max(q_base_max),
        .nn_shift(nn_shift), .conf_thr(conf_thr), .deadline0(deadline0), .deadline1(deadline1),
        .coef_we(coef_we), .w_we(w_we), .b_we(b_we), .f_we(f_we), .mem_waddr(mem_waddr), .mem_wdata(mem_wdata),
        .status_in(status_w), .nn_result_in(nn_res_w), .nn_score0_in(nn_s0), .nn_score1_in(nn_s1),
        .q_result_in(q_res_w), .lat_in(lat_w), .metrics_in(metrics_w),
        .fifo_dout(fifo_dout), .fifo_empty(fifo_empty), .fifo_pop(fifo_pop),
        .sb_rd_offset(sb_off), .sb_rd_data(sb_data), .sb_rd_valid(sb_valid),
        .ev_nn_done(nn_valid), .ev_miss(ev_miss), .ev_poor(ev_poor),
        .irq_en(irq_en), .irq(irq), .irq_status(irq_status));

    assign busy         = fir_busy | nn_busy | sar_busy;
    assign done         = irq_status[1];          // NN decision ready (sticky until W1C of IRQ_STATUS[1])
    assign abnormal     = dec_abn;
    assign uncertain    = dec_unc;
    assign result_valid = !fifo_empty;
    assign result_data  = fifo_dout;
endmodule
