`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// fir_block : standalone FIR = coef regfile + fir_engine + a private mac_unit (grant=1).
// Used for unit verification and as the "dedicated MAC" reference in the shared-vs-dedicated
// experiment. In the SoC the engine is wired to the shared MAC through the scheduler instead.
// Host writes coefficients with cfg_we/cfg_addr/cfg_wdata (12-bit two's complement, Q1.11).
// -----------------------------------------------------------------------------
module fir_block #(parameter PIPE = 0) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                cfg_we,
    input  wire [3:0]          cfg_addr,
    input  wire [11:0]         cfg_wdata,
    input  wire [4:0]          taps_cfg,
    input  wire [4:0]          shift_cfg,
    input  wire                sample_valid,
    input  wire signed [10:0]  sample_in,
    output wire                y_valid,
    output wire signed [10:0]  y_data,
    output wire                y_sat,
    output wire                y_ovf,
    output wire                busy,
    output wire                overrun,
    output wire [7:0]          last_latency
);
    wire [3:0] coef_addr; wire [11:0] coef_data;
    wire mac_req, mac_clear, mac_en, mac_acc_valid, mac_overflow;
    wire signed [10:0] mac_a; wire signed [11:0] mac_b; wire signed [31:0] mac_acc;

    regfile_sync #(.WIDTH(12), .DEPTH(16)) u_coef (.clk(clk), .rst_n(rst_n), .we(cfg_we),
        .waddr(cfg_addr), .wdata(cfg_wdata), .raddr(coef_addr), .rdata(coef_data));

    fir_engine u_fir (.clk(clk), .rst_n(rst_n), .sample_valid(sample_valid), .sample_in(sample_in),
        .taps_cfg(taps_cfg), .shift_cfg(shift_cfg), .coef_addr(coef_addr), .coef_data($signed(coef_data)),
        .mac_req(mac_req), .mac_grant(1'b1), .mac_clear(mac_clear), .mac_en(mac_en),
        .mac_a(mac_a), .mac_b(mac_b), .mac_acc(mac_acc), .mac_acc_valid(mac_acc_valid),
        .mac_overflow(mac_overflow), .y_valid(y_valid), .y_data(y_data), .y_sat(y_sat),
        .y_ovf(y_ovf), .busy(busy), .overrun(overrun), .last_latency(last_latency));

    mac_unit #(.A_W(11), .B_W(12), .ACC_W(32), .SATURATE(1), .PIPE(PIPE)) u_mac (
        .clk(clk), .rst_n(rst_n), .en(mac_en), .clear(mac_clear), .load(1'b0),
        .a(mac_a), .b(mac_b), .load_val(32'sd0), .acc(mac_acc),
        .acc_valid(mac_acc_valid), .overflow(mac_overflow));
endmodule
