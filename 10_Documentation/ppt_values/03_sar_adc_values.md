# 3. SAR ADC values
## RTL parameters
04_RTL/adc/comparator_behav.v:4:module comparator_behav #(parameter real OFFSET = 0.0) (
04_RTL/adc/sar_controller.v:14:    parameter N             = 10,
04_RTL/adc/sar_controller.v:15:    parameter SAMPLE_CYCLES = 1
04_RTL/adc/sar_controller.v:27:    localparam [1:0] S_IDLE = 2'd0, S_SAMP = 2'd1, S_CONV = 2'd2, S_FIN = 2'd3;
04_RTL/adc/adc_frontend_behav.v:10:    parameter N             = 10,
04_RTL/adc/adc_frontend_behav.v:11:    parameter real VREF     = 2.0,
04_RTL/adc/adc_frontend_behav.v:12:    parameter real CMP_OFFSET = 0.0,
04_RTL/adc/adc_frontend_behav.v:13:    parameter SAMPLE_CYCLES = 1
04_RTL/adc/cdac_behav.v:4:module cdac_behav #(parameter N = 10, parameter real VREF = 2.0) (

## ADC files
04_RTL/adc
04_RTL/adc/sar_controller.v
04_RTL/adc/adc_frontend_behav.v
05_Testbench/tb_sar_controller.v
05_Testbench/tb_adc_ecg.v
05_Testbench/tb_adc.v

## Quantization code in MATLAB

## Derived (D = round(Vin/Vref*1023), Vref=2.0 V, 10 bit)
LSB = Vref/(2^N-1) = 1.9550 mV
Full-scale codes: 0..1023; signed = D-512 -> -512..511
Ideal quantization error: +/-0.9775 mV (+/-0.5 LSB)
Ideal SNR = 6.02*N+1.76 = 61.96 dB
Conditioned range 0.5-1.5 V -> codes 256..767 (512 codes used)
Vin=0.92 V -> D=471  signed=-41
Vin=1.04 V -> D=532  signed=20
Vin=1.14 V -> D=583  signed=71
Vin=1.0 V -> D=512  signed=0

## ADC testbench result lines
| tb_sar_controller | sar_controller | all 1024 target codes through an ideal integer comparator, SAMPLE_CYCLES 1 and 3; extra start while busy; mid-conversion reset; continuous start | code = target, latency = SC+N+1, sample_en width = SC, period SC+N+2 | - |
| tb_adc | behavioural SAR ADC (S&H, comparator, CDAC, controller, bypass) | zero/mid/full scale, over-range, 2046 boundary points, 3072-pt ramp, 360-pt sine, 3000 random, hold test, bypass, reset; second DUT with +1 LSB comparator offset | D = clamp(floor(vin/LSB),0,1023); |error| <= LSB/2; latency 12 | - |
| tb_adc_ecg | ADC -> input_formatter chain | 3600 PWL volts from the ECG pipeline | Python golden codes and signed samples, checksum | - |
| tb_sar_controller | sar_controller SC=1 exhaustive 1024 codes — errors=0 | PASS |
| tb_sar_controller | sar_controller SC=3 exhaustive 1024 codes — errors=0 | PASS |
| tb_sar_controller | **overall** | **PASS** |
| tb_adc | scale points + overrange — errors=0 | info |
| tb_adc | boundary transitions 2046 pts — errors=0 | info |
| tb_adc | ramp 3072 pts — errors=0 max|err|=0.976562 mV (LSB/2=0.976562 mV) latency=12 clk | info |
| tb_adc | sine 360 pts — errors=0 | info |
| tb_adc | random 3000 pts incl. out-of-range — errors=0 | info |
| tb_adc | hold behaviour — errors=0 | info |
| tb_adc | bypass — errors=0 | info |
| tb_adc | reset during conversion — errors=0 | info |
| tb_adc | **overall** | **PASS** |
| tb_adc_ecg | ECG 3600 samples: PWL volts -> SAR ADC -> formatter vs Python golden — checksum=-2289 errors=0 | info |
| tb_adc_ecg | **overall** | **PASS** |
