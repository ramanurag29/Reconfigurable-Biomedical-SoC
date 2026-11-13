`timescale 1ns/1ps
`include "06_Simulation/mem/ecg_params.vh"
// Full-chain test: real ECG voltages (ecg_vin.pwl) -> behavioural SAR ADC -> input_formatter
// compared with the Python golden codes (ecg_adc_10b.hex) and signed samples (ecg_signed_11b.hex).
module tb_adc_ecg;
    localparam N = `ECG_N;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, start = 0; real vin = 1.0;
    wire [9:0] adc_data; wire adc_valid, busy;
    wire fv; wire signed [10:0] xs;

    adc_frontend_behav #(.N(10), .VREF(2.0)) adc (.clk(clk), .rst_n(rst_n), .vin(vin), .start(start),
        .bypass(1'b0), .bypass_data(10'd0), .bypass_valid(1'b0),
        .adc_data(adc_data), .adc_valid(adc_valid), .busy(busy));
    input_formatter #(.ADC_BITS(10)) fmt (.clk(clk), .rst_n(rst_n), .in_valid(adc_valid),
        .adc_code(adc_data), .out_valid(fv), .x_signed(xs));

    reg [9:0]  code_mem [0:N-1];
    reg [10:0] sgn_mem  [0:N-1];
    integer fd, r, i, errors = 0, got = 0, sum = 0;
    real t, v;

    always @(posedge clk) if (fv) begin
        if (xs !== sgn_mem[got]) begin errors = errors + 1; if (errors < 8) $display("  signed mismatch idx=%0d got=%0d", got, xs); end
        sum = sum + xs; got = got + 1;
    end
    always @(posedge clk) if (adc_valid && got < N) begin
        if (adc_data !== code_mem[got]) begin errors = errors + 1; if (errors < 8) $display("  code mismatch idx=%0d got=%0d exp=%0d", got, adc_data, code_mem[got]); end
    end

    initial begin
        $readmemh(`ECG_CODE_FILE, code_mem); $readmemh(`ECG_SIGNED_FILE, sgn_mem);
        fd = $fopen(`ECG_VIN_FILE, "r");
        if (fd == 0) begin $display("cannot open vin file"); $finish; end
        repeat (3) @(posedge clk); #1; rst_n = 1; @(posedge clk); #1;
        for (i = 0; i < N; i = i + 1) begin
            r = $fscanf(fd, "%f %f\n", t, v);
            vin = v; start = 1; @(posedge clk); #1; start = 0;
            while (!adc_valid) begin @(posedge clk); #1; end
            @(posedge clk); #1;
        end
        repeat (4) @(posedge clk);
        if (got !== N) begin errors = errors + 1; $display("  got %0d of %0d samples", got, N); end
        if (sum !== `ECG_SUM_SIGNED) begin errors = errors + 1; $display("  checksum got %0d exp %0d", sum, `ECG_SUM_SIGNED); end
        $display("[ECG %0d samples: PWL volts -> SAR ADC -> formatter vs Python golden] checksum=%0d errors=%0d", N, sum, errors);
        if (errors == 0) $display("\n*** ALL TESTS PASSED (ECG through behavioural ADC) ***");
        else             $display("\n*** FAILED ***");
        $finish;
    end
    initial begin #(900_000_000); $display("TIMEOUT"); $finish; end
endmodule
