# Stage 2 flow
Vin -> sample&hold -> comparator vs CDAC trial -> SAR controller (10 trials, MSB first) -> 10-bit code + done
-> input_formatter (signed = code - 512, 11-bit) -> sample buffer. Bypass path injects digital codes directly.
Status: behavioural + digital controller verified in RTL simulation. Transistor-level analog not done (next semester).
