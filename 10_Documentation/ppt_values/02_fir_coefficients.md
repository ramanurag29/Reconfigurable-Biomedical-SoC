# 2. FIR coefficient data (16-tap requirement)
Files found:


## taps in RTL / testbench
04_RTL/fir/fir_block.v:14:    input  wire [4:0]          taps_cfg,
04_RTL/fir/fir_block.v:30:    regfile_sync #(.WIDTH(12), .DEPTH(16)) u_coef (.clk(clk), .rst_n(rst_n), .we(cfg_we),
04_RTL/fir/fir_block.v:34:        .taps_cfg(taps_cfg), .shift_cfg(shift_cfg), .coef_addr(coef_addr), .coef_data($signed(coef_data)),
04_RTL/fir/fir_engine.v:4://   y[n] = sat( (sum_{k<T} h[k]*x[n-k] + 2^(S-1)) >>> S ),  T = taps (1..16), S = shift
04_RTL/fir/fir_engine.v:18:    parameter MAX_TAPS = 16
04_RTL/fir/fir_engine.v:24:    input  wire [4:0]               taps_cfg,
04_RTL/fir/fir_engine.v:49:    localparam [4:0] TMAX = MAX_TAPS;
04_RTL/fir/fir_engine.v:59:    reg signed [X_W-1:0] x_hist [0:MAX_TAPS-1];
04_RTL/fir/fir_engine.v:62:    wire [4:0] taps_eff = (taps_cfg == 5'd0) ? 5'd1 : (taps_cfg > TMAX) ? TMAX : taps_cfg;
04_RTL/fir/fir_engine.v:89:            for (i = 0; i < MAX_TAPS; i = i + 1) x_hist[i] <= 0;
04_RTL/fir/fir_engine.v:98:                    for (i = MAX_TAPS-1; i > 0; i = i - 1) x_hist[i] <= x_hist[i-1];
05_Testbench/tb_fir.v:5://  P1 ECG, 16 taps vs Python golden   P2 ECG, 8 taps vs Python golden
05_Testbench/tb_fir.v:7://     (random taps 1..16, shift 0..12, full-range coefficients/samples -> rounding + saturation)
05_Testbench/tb_fir.v:13:    reg [4:0] taps = 16, shift = 11; reg signed [10:0] sample_in = 0;
05_Testbench/tb_fir.v:87:        // ---------------- P1: ECG 16 taps
05_Testbench/tb_fir.v:88:        $readmemh(`FIR_COEF16_FILE, cmem); for (i = 0; i < 16; i = i + 1) wr_coef(i, cmem[i]);
05_Testbench/tb_fir.v:89:        $readmemh(`FIR_Y16_FILE, ex); taps = 16; shift = `FIR_SHIFT;
05_Testbench/tb_fir.v:94:        if (lat0 !== 16 + 3 || lat1 !== 16 + 4 || ll0 !== 16 + 2 || ll1 !== 16 + 3) begin errors = errors + 1; $display("  latency got %0d/%0d (busy %0d/%0d)", lat0, lat1, ll0, ll1); end
05_Testbench/tb_fir.v:95:        $display("[latency 16 taps] sample->y: PIPE0=%0d clk, PIPE1=%0d clk; MAC-busy cycles %0d/%0d -> %0s", lat0, lat1, ll0, ll1, errors == 0 ? "PASS" : "FAIL");
05_Testbench/tb_fir.v:97:        do_reset; c0 = 0; c1 = 0; mon_en = 1; stream(40); mon_en = 0; phase_result("ECG 16-tap vs Python golden", c0, c1);
05_Testbench/tb_fir.v:104:            do_reset; mT = 1 + ({$random(seed)} % 16); mshift = {$random(seed)} % 13;
05_Testbench/tb_fir.v:106:            for (i = 0; i < 16; i = i + 1) begin
05_Testbench/tb_fir.v:111:            for (i = 0; i < 16; i = i + 1) mh[i] = 0;
05_Testbench/tb_fir.v:121:        do_reset; taps = 16; shift = 11; for (i = 0; i < 16; i = i + 1) wr_coef(i, 12'h040);
## fir_engine parameters
15:    parameter X_W      = 11,
16:    parameter H_W      = 12,
17:    parameter ACC_W    = 32,
18:    parameter MAX_TAPS = 16
48:    localparam [2:0] S_IDLE = 3'd0, S_CLR = 3'd1, S_MAC = 3'd2, S_DRAIN = 3'd3;
49:    localparam [4:0] TMAX = MAX_TAPS;
50:    localparam signed [ACC_W:0] YMAX =  (1 <<< (X_W-1)) - 1;
51:    localparam signed [ACC_W:0] YMIN = -(1 <<< (X_W-1));
