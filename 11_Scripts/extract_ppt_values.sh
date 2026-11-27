#!/bin/bash
cd "$(dirname "$0")/.."
OUT=10_Documentation/ppt_values
mkdir -p $OUT
EX='-not -path ./.venv/* -not -path ./.git/*'

# ---------- 1. MATLAB / dataset ----------
{
echo "# 1. MATLAB processing values (MIT-BIH)"
echo "## Dataset files"; ls -la 01_Dataset 2>/dev/null | head -30
echo; echo "## MATLAB scripts"; ls 02_MATLAB 2>/dev/null
echo; echo "## Record / sampling / filter parameters (grep from MATLAB code)"
grep -rnEi "record|rec_id|\bfs\b|Fs *=|cutoff|fc|order|notch|50 *Hz|lowcut|highcut|bandpass|butter|fir1|firpm|window|taps|ntaps|baseline|medfilt|Vref|vcm|nbits|scale|norm" 02_MATLAB --include=*.m 2>/dev/null | grep -v "^\s*%" | head -150
echo; echo "## Any config/summary/log files MATLAB produced"
find . -type f \( -name "*summary*" -o -name "*config*.txt" -o -name "*params*" -o -name "*.log" \) $EX 2>/dev/null | grep -Ei "matlab|result|dataset|mem|02_|09_" | head -20
} > $OUT/01_matlab_values.md

# ---------- 2. FIR coefficients ----------
{
echo "# 2. FIR coefficient data (16-tap requirement)"
CF=$(find . -type f \( -name "*coef*" -o -name "*coeff*" -o -name "*fir*h*" -o -name "*taps*" \) \( -name "*.mem" -o -name "*.hex" -o -name "*.csv" -o -name "*.txt" \) $EX 2>/dev/null)
echo "Files found:"; echo "$CF"
echo
[ -n "$CF" ] && python3 11_Scripts/decode_coeffs.py $CF
echo "## taps in RTL / testbench"
grep -rnE "taps_cfg|TAPS|N_TAPS|NTAPS|16" 04_RTL/fir 05_Testbench/tb_fir*.v 2>/dev/null | head -30
echo "## fir_engine parameters"
grep -nE "parameter|localparam" 04_RTL/fir/fir_engine.v
} > $OUT/02_fir_coefficients.md

# ---------- 3. SAR ADC ----------
{
echo "# 3. SAR ADC values"
echo "## RTL parameters"
grep -rnE "parameter|localparam" 04_RTL/adc 2>/dev/null
echo; echo "## ADC files"; find 04_RTL/adc 05_Testbench -iname "*adc*" -o -iname "*sar*" 2>/dev/null
echo; echo "## Quantization code in MATLAB"
grep -nE "" 02_MATLAB/quantize_adc.m 02_MATLAB/scale_to_adc.m 2>/dev/null | head -80
echo; echo "## Derived (D = round(Vin/Vref*1023), Vref=2.0 V, 10 bit)"
python3 - <<'PY'
vref=2.0; n=10; fs=2**n-1
print(f"LSB = Vref/(2^N-1) = {vref/fs*1000:.4f} mV")
print(f"Full-scale codes: 0..{fs}; signed = D-512 -> {-512}..{fs-512}")
print(f"Ideal quantization error: +/-{vref/fs/2*1000:.4f} mV (+/-0.5 LSB)")
print(f"Ideal SNR = 6.02*N+1.76 = {6.02*n+1.76:.2f} dB")
print(f"Conditioned range 0.5-1.5 V -> codes {round(0.5/vref*fs)}..{round(1.5/vref*fs)} ({round(1.5/vref*fs)-round(0.5/vref*fs)+1} codes used)")
for v in (0.92,1.04,1.14,1.0): print(f"Vin={v} V -> D={round(v/vref*fs)}  signed={round(v/vref*fs)-512}")
PY
echo; echo "## ADC testbench result lines"
grep -rhiE "adc|sar" 10_Documentation/03_verification_report.md 2>/dev/null | head -20
} > $OUT/03_sar_adc_values.md

# ---------- 4. SoC digital block (no scheduler detail) ----------
{
echo "# 4. Digital SoC block: widths, parameters, interfaces"
for f in $(find 04_RTL -name "*.v" | sort | grep -v scheduler); do
  echo; echo "## $f"
  grep -nE "^\s*(parameter|localparam)" $f
  sed -n '/^module/,/^);/p' $f | grep -E "input|output" | sed 's/^\s*//'
done
echo; echo "## Register map"; cat 10_Documentation/*register* 2>/dev/null | head -80
echo; echo "## NN / quality specs"; ls 03_AI_Model 2>/dev/null; cat 10_Documentation/*quality* 2>/dev/null | head -60
} > $OUT/04_soc_block_values.md

# ---------- 5. Verified results + pipeline ----------
{
echo "# 5. Verification results and pipeline status"
echo "## Regression"
bash 11_Scripts/regress.sh 2>&1 | tail -40
echo; echo "## Verification report"; cat 10_Documentation/03_verification_report.md 2>/dev/null
echo; echo "## Milestone history (git)"; git log --date=short --pretty="%ad  %s" | head -30
echo; echo "## Module/testbench inventory"
echo "RTL: $(find 04_RTL -name '*.v' | wc -l) files, $(cat $(find 04_RTL -name '*.v') | wc -l) lines"
echo "TB : $(ls 05_Testbench | wc -l) files"
echo "OpenLane dir: $(ls 07_OpenLane 2>/dev/null | wc -l) files (0 = not started, no GDS)"
} > $OUT/05_verification_pipeline.md

# ---------- combined ----------
cat $OUT/0[1-5]_*.md > $OUT/REPORT.md
echo "Done -> $OUT/REPORT.md ($(wc -l < $OUT/REPORT.md) lines)"
