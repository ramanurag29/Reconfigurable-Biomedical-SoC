# Stage 3 flow
sample buffer -> fir_engine (16 taps, 11-bit x, 12-bit h, 32-bit acc, round + saturate) -> y -> features -> nn_engine 8->16->2 (ReLU, argmax, margin, low-confidence flag)
Both engines request the single shared MAC (mac_unit, 11x12 -> 32-bit acc). Scheduler details intentionally omitted here (workflow only).
