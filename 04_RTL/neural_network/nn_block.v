`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// nn_block : standalone NN = weight/bias/feature regfiles + nn_engine + a private mac_unit.
// Host load port: cfg_sel 0=weights(8b, addr 0..159) 1=bias(24b, addr 0..17) 2=features(8b, addr 0..7).
// Used for unit verification and as the "dedicated MAC" reference. In the SoC the engine is
// wired to the shared MAC through the scheduler instead.
// -----------------------------------------------------------------------------
module nn_block #(parameter PIPE = 0) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               cfg_we,
    input  wire [1:0]         cfg_sel,
    input  wire [7:0]         cfg_addr,
    input  wire [23:0]        cfg_wdata,
    input  wire               start,
    input  wire [4:0]         shift_cfg,
    input  wire [15:0]        conf_thr,
    output wire               nn_valid,
    output wire               nn_class,
    output wire signed [31:0] nn_score0,
    output wire signed [31:0] nn_score1,
    output wire [15:0]        nn_margin,
    output wire               nn_lowconf,
    output wire               nn_ovf,
    output wire               busy,
    output wire [15:0]        last_latency
);
    wire [2:0] feat_addr; wire [7:0] w_addr; wire [4:0] b_addr;
    wire [7:0] feat_data, w_data; wire [23:0] b_data;
    wire mac_req, mac_load, mac_en, mac_acc_valid, mac_overflow;
    wire signed [31:0] mac_load_val, mac_acc; wire signed [10:0] mac_a; wire signed [11:0] mac_b;

    regfile_sync #(.WIDTH(8),  .DEPTH(160)) u_w (.clk(clk), .rst_n(rst_n), .we(cfg_we && cfg_sel == 2'd0),
        .waddr(cfg_addr), .wdata(cfg_wdata[7:0]), .raddr(w_addr), .rdata(w_data));
    regfile_sync #(.WIDTH(24), .DEPTH(32))  u_b (.clk(clk), .rst_n(rst_n), .we(cfg_we && cfg_sel == 2'd1),
        .waddr(cfg_addr[4:0]), .wdata(cfg_wdata), .raddr(b_addr), .rdata(b_data));
    regfile_sync #(.WIDTH(8),  .DEPTH(8))   u_f (.clk(clk), .rst_n(rst_n), .we(cfg_we && cfg_sel == 2'd2),
        .waddr(cfg_addr[2:0]), .wdata(cfg_wdata[7:0]), .raddr(feat_addr), .rdata(feat_data));

    nn_engine u_nn (.clk(clk), .rst_n(rst_n), .start(start), .shift_cfg(shift_cfg), .conf_thr(conf_thr),
        .feat_addr(feat_addr), .feat_data($signed(feat_data)), .w_addr(w_addr), .w_data($signed(w_data)),
        .b_addr(b_addr), .b_data($signed(b_data)),
        .mac_req(mac_req), .mac_grant(1'b1), .mac_load(mac_load), .mac_load_val(mac_load_val), .mac_en(mac_en),
        .mac_a(mac_a), .mac_b(mac_b), .mac_acc(mac_acc), .mac_acc_valid(mac_acc_valid), .mac_overflow(mac_overflow),
        .nn_valid(nn_valid), .nn_class(nn_class), .nn_score0(nn_score0), .nn_score1(nn_score1),
        .nn_margin(nn_margin), .nn_lowconf(nn_lowconf), .nn_ovf(nn_ovf), .busy(busy), .last_latency(last_latency));

    mac_unit #(.A_W(11), .B_W(12), .ACC_W(32), .SATURATE(1), .PIPE(PIPE)) u_mac (
        .clk(clk), .rst_n(rst_n), .en(mac_en), .clear(1'b0), .load(mac_load),
        .a(mac_a), .b(mac_b), .load_val(mac_load_val), .acc(mac_acc),
        .acc_valid(mac_acc_valid), .overflow(mac_overflow));
endmodule
