// -----------------------------------------------------------------------------
// tb_input_formatter_ecg  (Milestone 1)
// Self-checking. Drives real MIT-BIH ECG codes (from ecg_adc_10b.hex) into
// input_formatter and compares every output against an INDEPENDENT golden file
// (ecg_signed_11b.hex, produced by the Python/MATLAB reference), plus an
// aggregate checksum (sum of signed samples).
// Tests: 1) reset state  2) gapped stream (junk data while valid=0)
//        3) back-to-back stream  4) mid-stream reset recovery
// Run from the repository root (paths are relative to it).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`include "06_Simulation/mem/ecg_params.vh"

module tb_input_formatter_ecg;
    localparam N = `ECG_N;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg                 in_valid = 0;
    reg  [`ECG_BITS-1:0] adc_code = 0;
    wire                out_valid;
    wire signed [`ECG_BITS:0] x_signed;

    input_formatter #(.ADC_BITS(`ECG_BITS)) dut (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .adc_code(adc_code),
        .out_valid(out_valid), .x_signed(x_signed));

    reg [`ECG_BITS-1:0]   code_mem [0:N-1];
    reg [`ECG_BITS:0]     exp_mem  [0:N-1];

    integer errors = 0, checked = 0, rd_idx = 0, sum_dut = 0, total_errors = 0;
    integer pass_no = 0;

    // output monitor
    always @(posedge clk) begin
        if (out_valid && rd_idx < N) begin
            if (x_signed !== exp_mem[rd_idx]) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("  MISMATCH idx=%0d got=%0d exp=%0d", rd_idx, x_signed, $signed(exp_mem[rd_idx]));
            end
            sum_dut = sum_dut + x_signed;
            rd_idx  = rd_idx + 1;
            checked = checked + 1;
        end
    end

    task send_all(input integer gap);
        integer i, g;
        begin
            for (i = 0; i < N; i = i + 1) begin
                @(posedge clk); #1;
                in_valid = 1; adc_code = code_mem[i];
                for (g = 1; g < gap; g = g + 1) begin
                    @(posedge clk); #1;
                    in_valid = 0; adc_code = $random;      // junk must be ignored
                end
            end
            @(posedge clk); #1; in_valid = 0;
            repeat (4) @(posedge clk);
        end
    endtask

    task finish_pass(input [255:0] name);
        begin
            if (checked !== N)            begin errors = errors + 1; $display("  %0s: checked %0d of %0d samples", name, checked, N); end
            if (sum_dut !== `ECG_SUM_SIGNED) begin errors = errors + 1; $display("  %0s: checksum got %0d exp %0d", name, sum_dut, `ECG_SUM_SIGNED); end
            $display("[%0s] samples=%0d checksum=%0d errors=%0d -> %0s", name, checked, sum_dut, errors, (errors==0) ? "PASS" : "FAIL");
            total_errors = total_errors + errors;
            errors = 0; checked = 0; rd_idx = 0; sum_dut = 0;
        end
    endtask

    initial begin
        $dumpfile("06_Simulation/tb_input_formatter_ecg.vcd");
        $dumpvars(0, tb_input_formatter_ecg);
        $readmemh(`ECG_CODE_FILE,   code_mem);
        $readmemh(`ECG_SIGNED_FILE, exp_mem);

        // 1) reset state
        repeat (3) @(posedge clk); #1;
        if (out_valid !== 1'b0 || x_signed !== 0) begin errors = errors + 1; $display("  reset state wrong"); end
        rst_n = 1; repeat (2) @(posedge clk);
        $display("[reset_state] errors=%0d -> %0s", errors, (errors==0) ? "PASS" : "FAIL");
        total_errors = total_errors + errors; errors = 0;

        // 2) gapped stream
        send_all(8);  finish_pass("gapped_stream");
        // 3) back-to-back stream
        send_all(1);  finish_pass("back_to_back");

        // 4) reset while valid asserted -> outputs must clear, then stream again
        @(posedge clk); #1; in_valid = 1; adc_code = 10'h3FF;
        @(posedge clk); #1; rst_n = 0;
        @(posedge clk); #1;
        if (out_valid !== 1'b0 || x_signed !== 0) begin errors = errors + 1; $display("  reset-during-valid not cleared"); end
        in_valid = 0; rst_n = 1; repeat (2) @(posedge clk);
        checked = 0; rd_idx = 0; sum_dut = 0;
        send_all(1);  finish_pass("reset_recovery");

        if (total_errors == 0) $display("\n*** ALL TESTS PASSED (%0d ECG samples, 3 streams) ***", N);
        else                   $display("\n*** FAILED: %0d errors ***", total_errors);
        $finish;
    end

    initial begin #(20_000_000); $display("TIMEOUT"); $finish; end
endmodule
