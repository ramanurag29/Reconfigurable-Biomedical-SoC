# Stage 1 flow
MIT-BIH record -> read signal + annotations -> preprocessing (baseline removal, band-pass, optional 50 Hz notch)
-> normalize -> scale to 0.5-1.5 V (Vcm 1.0 V) -> PWL volts / 10-bit codes (hex) -> testbench.
Exact filter parameters: see 04_preprocessing_parameters_grep.txt. Real signal numbers: 01_ecg_input_stats.txt.
