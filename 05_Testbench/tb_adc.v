`timescale 1ns/1ps
// Self-checking test of the BEHAVIOURAL SAR ADC (real-valued models + sar_controller).
// Reference: D = clamp(floor(vin/LSB), 0, 1023), LSB = VREF/1024  (decision D1-B).
// dut      : ideal comparator.   dut_off : comparator offset = +1 LSB  -> code shifts by -1.
module tb_adc;
    localparam N = 10;
    localparam real VREF = 2.0;
    localparam real LSB  = VREF / 1024.0;
    localparam LAT_EXP   = 1 + N + 1;

    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, start = 0, bypass = 0, bypass_valid = 0; reg [N-1:0] bypass_data = 0;
    real vin = 0.0;
    wire [N-1:0] d0, d1; wire v0, v1, b0, b1;

    adc_frontend_behav #(.N(N), .VREF(VREF)) dut (.clk(clk), .rst_n(rst_n), .vin(vin), .start(start),
        .bypass(bypass), .bypass_data(bypass_data), .bypass_valid(bypass_valid),
        .adc_data(d0), .adc_valid(v0), .busy(b0));
    adc_frontend_behav #(.N(N), .VREF(VREF), .CMP_OFFSET(LSB)) dut_off (.clk(clk), .rst_n(rst_n), .vin(vin),
        .start(start), .bypass(bypass), .bypass_data(bypass_data), .bypass_valid(bypass_valid),
        .adc_data(d1), .adc_valid(v1), .busy(b1));

    integer errors = 0, nconv = 0, lat, i, k, seed = 12345;
    real maxerr = 0.0, err_v;
    integer codes_seen [0:1023];

    function integer refcode(input real v, input real off);
        real x;
        begin
            x = $floor((v - off) * 1024.0 / VREF);
            if (x < 0.0) refcode = 0; else if (x > 1023.0) refcode = 1023; else refcode = $rtoi(x);
        end
    endfunction

    task fail(input [255:0] msg, input real v, input integer got, input integer exp);
        begin errors = errors + 1; if (errors < 12) $display("  FAIL %0s vin=%f got=%0d exp=%0d", msg, v, got, exp); end
    endtask

    // one conversion; optionally disturb vin after the sample phase (hold test)
    task conv(input real v, input real v_after_sample);
        integer n;
        begin
            vin = v; start = 1; @(posedge clk); #1; start = 0;
            @(posedge clk); #1;                 // SAMP edge done -> in CONV now
            vin = v_after_sample;
            n = 1;
            while (!v0 && n < 60) begin @(posedge clk); #1; n = n + 1; end
            lat = n; nconv = nconv + 1;
            if (n !== LAT_EXP) fail("latency", v, n, LAT_EXP);
            if (d0 !== refcode(v, 0.0))  fail("code", v, d0, refcode(v, 0.0));
            if (d1 !== refcode(v, LSB))  fail("code(offset)", v, d1, refcode(v, LSB));
            if (v >= 0.0 && v < VREF) begin
                err_v = v - (d0 + 0.5) * LSB; if (err_v < 0.0) err_v = -err_v;
                if (err_v > maxerr) maxerr = err_v;
            end
            codes_seen[d0] = codes_seen[d0] + 1;
            @(posedge clk); #1;
            if (v0 !== 1'b0 || b0 !== 1'b0) fail("done/busy after", v, v0, 0);
        end
    endtask
    task c(input real v); begin conv(v, v); end endtask

    real r, s;
    initial begin
        for (i = 0; i < 1024; i = i + 1) codes_seen[i] = 0;
        repeat (3) @(posedge clk); #1; rst_n = 1; @(posedge clk); #1;

        // 1) zero / mid / full scale and over-range saturation
        c(0.0); c(1.0); c(VREF - 1e-9); c(VREF); c(-0.3); c(VREF + 0.3);
        if (d0 !== 1023) fail("overrange sat", VREF+0.3, d0, 1023);
        $display("[scale points + overrange] errors=%0d", errors);
        // 2) boundaries: exactly k*LSB -> k ; just below -> k-1
        for (k = 1; k < 1024; k = k + 1) begin c(k * LSB); c(k * LSB - 1e-9); end
        $display("[boundary transitions 2046 pts] errors=%0d", errors);
        // 3) ramp, 3 points per LSB (also tracks quantization error)
        for (k = 0; k < 3 * 1024; k = k + 1) c(k * LSB / 3.0);
        $display("[ramp 3072 pts] errors=%0d max|err|=%f mV (LSB/2=%f mV) latency=%0d clk", errors, maxerr*1e3, LSB*0.5e3, lat);
        if (maxerr > LSB * 0.5 + 1e-12) begin errors = errors + 1; $display("  FAIL quantization error exceeds LSB/2"); end
        k = 0; for (i = 0; i < 1024; i = i + 1) if (codes_seen[i] == 0) k = k + 1;
        if (k != 0) begin errors = errors + 1; $display("  FAIL missing codes: %0d", k); end
        // 4) sine, 360 points, 0.5..1.5 V
        for (k = 0; k < 360; k = k + 1) c(1.0 + 0.5 * $sin(6.283185307179586 * k / 360.0));
        $display("[sine 360 pts] errors=%0d", errors);
        // 5) random, includes out-of-range
        for (k = 0; k < 3000; k = k + 1) begin
            r = ($random(seed) & 32'h7fffffff) / 2147483648.0;
            c(r * VREF * 1.1 - 0.05 * VREF);
        end
        $display("[random 3000 pts incl. out-of-range] errors=%0d", errors);
        // 6) hold: input changes wildly after sampling, result must follow sampled value
        conv(0.7, 1.9); conv(1.3, 0.0); conv(0.123, 1.999);
        $display("[hold behaviour] errors=%0d", errors);
        // 7) bypass: data passes through, SAR idle, start ignored
        bypass = 1; bypass_data = 10'h2A5; bypass_valid = 1; start = 1; vin = 1.7;
        @(posedge clk); #1; start = 0;
        if (d0 !== 10'h2A5 || v0 !== 1'b1 || b0 !== 1'b0) fail("bypass", 1.7, d0, 10'h2A5);
        bypass_valid = 0; repeat (20) begin @(posedge clk); #1; if (v0 !== 1'b0 || b0 !== 1'b0) fail("bypass idle", 0.0, v0, 0); end
        bypass = 0; @(posedge clk); #1; c(1.5);
        $display("[bypass] errors=%0d", errors);
        // 8) reset during conversion
        vin = 1.2; start = 1; @(posedge clk); #1; start = 0; repeat (4) @(posedge clk); #1;
        rst_n = 0; @(posedge clk); #1; rst_n = 1; if (b0 !== 1'b0 || v0 !== 1'b0) fail("mid reset", 1.2, b0, 0);
        @(posedge clk); #1; c(0.9);
        $display("[reset during conversion] errors=%0d", errors);

        $display("conversions=%0d  latency=%0d clk  quantization max|err|=%f mV", nconv, lat, maxerr*1e3);
        if (errors == 0) $display("\n*** ALL TESTS PASSED (behavioural SAR ADC, %0d conversions x 2 DUTs) ***", nconv);
        else             $display("\n*** FAILED: %0d errors ***", errors);
        $finish;
    end
    initial begin #(900_000_000); $display("TIMEOUT"); $finish; end
endmodule
