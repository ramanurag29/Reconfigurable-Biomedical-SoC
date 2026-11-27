`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// host_regs [synthesizable] : simple memory-mapped host interface + configuration registers.
// Bus (single clock domain, word addressed, 32-bit data):
//   write : host_we=1 with host_addr/host_wdata for one cycle -> applied at that clock edge
//   read  : host_re=1 with host_addr for one cycle -> host_rdata valid with host_rvalid=1 next cycle
//           (a read of RESULT_POP pops the output FIFO in the same cycle as host_re)
// Full register map: 10_Documentation/06_register_map.md
//   0x000-0x01F control/status   0x100 COEF[16]   0x200 WEIGHT[160]   0x300 BIAS[18]
//   0x400 FEATURE[8]   0x500 RESULT_POP   0x600 SAMPLE_BUF[64] (0 = newest)
// Coefficient/weight/bias/feature memories are write-only from the host (they are read by the engines).
// This block is on the HARD reset only: a soft reset (CTRL[0]) restarts the datapath but keeps
// configuration, coefficients and weights.
// -----------------------------------------------------------------------------
module host_regs (
    input  wire        clk,
    input  wire        rst_n,
    // host bus
    input  wire        host_we,
    input  wire        host_re,
    input  wire [11:0] host_addr,
    input  wire [31:0] host_wdata,
    output reg  [31:0] host_rdata,
    output reg         host_rvalid,
    // control pulses / levels
    output reg         soft_rst,       // 1-cycle pulse
    output reg         nn_start,       // 1-cycle pulse
    output reg         stat_clr,       // 1-cycle pulse
    output reg         flag_clr,       // 1-cycle pulse (FIFO / lost / overrun sticky flags)
    output reg         run,
    // MODE
    output reg  [1:0]  mode,           // 0 FIR only, 1 NN only, 2 FIR + NN
    output reg         adc_bypass,
    output reg         fir_out_en,
    output reg         q_out_en,
    // SCHED
    output reg  [1:0]  policy,
    output reg         mode_sel,
    output reg         preempt_en,
    output reg  [2:0]  prio0,
    output reg  [2:0]  prio1,
    output reg  [7:0]  quantum,
    // FIR / ADC / quality / NN
    output reg  [4:0]  fir_taps,
    output reg  [4:0]  fir_shift,
    output reg  [15:0] adc_div,
    output reg  [3:0]  q_win_log2,
    output reg  [7:0]  q_clip_max,
    output reg  [10:0] q_amp_min,
    output reg  [7:0]  q_noise_k,
    output reg  [9:0]  q_base_max,
    output reg  [4:0]  nn_shift,
    output reg  [15:0] conf_thr,
    output reg  [15:0] deadline0,
    output reg  [15:0] deadline1,
    // memory write port (shared address/data, one strobe per memory)
    output wire        coef_we,
    output wire        w_we,
    output wire        b_we,
    output wire        f_we,
    output wire [7:0]  mem_waddr,
    output wire [23:0] mem_wdata,
    // read-back sources
    input  wire [31:0] status_in,
    input  wire [31:0] nn_result_in,
    input  wire [31:0] nn_score0_in,
    input  wire [31:0] nn_score1_in,
    input  wire [31:0] q_result_in,
    input  wire [31:0] lat_in,
    input  wire [383:0] metrics_in,    // 12 words, word i -> address 0x011 + i
    // output FIFO
    input  wire [15:0] fifo_dout,
    input  wire        fifo_empty,
    output wire        fifo_pop,
    // sample buffer read
    output wire [5:0]  sb_rd_offset,
    input  wire [10:0] sb_rd_data,
    input  wire        sb_rd_valid,
    // interrupts
    input  wire        ev_nn_done,
    input  wire        ev_miss,
    input  wire        ev_poor,
    output reg  [3:0]  irq_en,
    output wire        irq,
    output wire [3:0]  irq_status
);
    localparam [31:0] CHIP_ID = 32'hB10C_0001;

    wire [3:0] region = host_addr[11:8];
    wire [7:0] off    = host_addr[7:0];
    wire       reg_wr = host_we && region == 4'h0;

    assign coef_we   = host_we && region == 4'h1 && off < 8'd16;
    assign w_we      = host_we && region == 4'h2 && off < 8'd160;
    assign b_we      = host_we && region == 4'h3 && off < 8'd18;
    assign f_we      = host_we && region == 4'h4 && off < 8'd8;
    assign mem_waddr = off;
    assign mem_wdata = host_wdata[23:0];
    assign fifo_pop  = host_re && region == 4'h5 && !fifo_empty;
    assign sb_rd_offset = off[5:0];

    // interrupts: bit0 data ready (level = FIFO not empty), bits 1..3 sticky, write-1-to-clear
    reg [3:1] irq_sticky;
    assign irq_status = {irq_sticky, !fifo_empty};
    assign irq        = |(irq_status & irq_en);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            soft_rst <= 1'b0; nn_start <= 1'b0; stat_clr <= 1'b0; flag_clr <= 1'b0; run <= 1'b0;
            mode <= 2'd2; adc_bypass <= 1'b1; fir_out_en <= 1'b1; q_out_en <= 1'b1;
            policy <= 2'd0; mode_sel <= 1'b1; preempt_en <= 1'b1; prio0 <= 3'd3; prio1 <= 3'd4; quantum <= 8'd8;
            fir_taps <= 5'd16; fir_shift <= 5'd11; adc_div <= 16'd100;
            q_win_log2 <= 4'd9; q_clip_max <= 8'd4; q_amp_min <= 11'd40; q_noise_k <= 8'd1; q_base_max <= 10'd64;
            nn_shift <= 5'd6; conf_thr <= 16'd1220; deadline0 <= 16'd0; deadline1 <= 16'd0;
            irq_en <= 4'd0; irq_sticky <= 3'd0;
        end else begin
            soft_rst <= 1'b0; nn_start <= 1'b0; stat_clr <= 1'b0; flag_clr <= 1'b0;
            // W1C clear and new events in the same cycle: the new event wins
            irq_sticky <= (irq_sticky & ~((reg_wr && off == 8'h0B) ? host_wdata[3:1] : 3'b000))
                        | {ev_poor, ev_miss, ev_nn_done};
            if (reg_wr) case (off)
                8'h00: begin soft_rst <= host_wdata[0]; nn_start <= host_wdata[1]; stat_clr <= host_wdata[2];
                             flag_clr <= host_wdata[3]; run <= host_wdata[4]; end
                8'h02: begin mode <= host_wdata[1:0]; adc_bypass <= host_wdata[2]; fir_out_en <= host_wdata[3];
                             q_out_en <= host_wdata[4]; end
                8'h03: begin policy <= host_wdata[1:0]; mode_sel <= host_wdata[2]; preempt_en <= host_wdata[3];
                             prio0 <= host_wdata[6:4]; prio1 <= host_wdata[10:8]; quantum <= host_wdata[23:16]; end
                8'h04: begin fir_taps <= host_wdata[4:0]; fir_shift <= host_wdata[12:8]; end
                8'h05: adc_div <= host_wdata[15:0];
                8'h06: begin q_win_log2 <= host_wdata[3:0]; q_clip_max <= host_wdata[15:8]; q_amp_min <= host_wdata[26:16]; end
                8'h07: begin q_noise_k <= host_wdata[7:0]; q_base_max <= host_wdata[17:8]; end
                8'h08: begin nn_shift <= host_wdata[4:0]; conf_thr <= host_wdata[31:16]; end
                8'h09: begin deadline0 <= host_wdata[15:0]; deadline1 <= host_wdata[31:16]; end
                8'h0A: irq_en <= host_wdata[3:0];
                default: ;
            endcase
        end
    end

    // ---------------- read-back
    reg [31:0] rmux;
    always @* begin
        rmux = 32'd0;
        case (region)
            4'h0: begin
                if (off >= 8'h11 && off <= 8'h1C) rmux = metrics_in[(off - 8'h11) * 32 +: 32];
                else case (off)
                    8'h00: rmux = {27'd0, run, 4'd0};
                    8'h01: rmux = status_in;
                    8'h02: rmux = {27'd0, q_out_en, fir_out_en, adc_bypass, mode};
                    8'h03: rmux = {8'd0, quantum, 5'd0, prio1, 1'b0, prio0, preempt_en, mode_sel, policy};
                    8'h04: rmux = {19'd0, fir_shift, 3'd0, fir_taps};
                    8'h05: rmux = {16'd0, adc_div};
                    8'h06: rmux = {5'd0, q_amp_min, q_clip_max, 4'd0, q_win_log2};
                    8'h07: rmux = {14'd0, q_base_max, q_noise_k};
                    8'h08: rmux = {conf_thr, 11'd0, nn_shift};
                    8'h09: rmux = {deadline1, deadline0};
                    8'h0A: rmux = {28'd0, irq_en};
                    8'h0B: rmux = {28'd0, irq_status};
                    8'h0C: rmux = nn_result_in;
                    8'h0D: rmux = nn_score0_in;
                    8'h0E: rmux = nn_score1_in;
                    8'h0F: rmux = q_result_in;
                    8'h10: rmux = lat_in;
                    8'h1F: rmux = CHIP_ID;
                    default: rmux = 32'd0;
                endcase
            end
            4'h5: rmux = {15'd0, !fifo_empty, fifo_dout};
            4'h6: rmux = {sb_rd_valid, 20'd0, sb_rd_data};
            default: rmux = 32'd0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin host_rdata <= 32'd0; host_rvalid <= 1'b0; end
        else begin
            host_rvalid <= host_re;
            if (host_re) host_rdata <= rmux;
        end
    end
endmodule
