import sys, glob, re
files = sys.argv[1:]
for f in files:
    toks = []
    for line in open(f):
        line = line.split('//')[0].strip()
        if not line or line.startswith('@'): continue
        toks += line.split()
    vals = []
    for t in toks:
        try:
            if re.fullmatch(r'-?\d+', t) and not re.fullmatch(r'[0-9a-fA-F]{3}', t):
                vals.append(int(t))
            else:
                v = int(t, 16)
                vals.append(v - 4096 if v >= 2048 else v)   # 12-bit two's complement
        except ValueError:
            pass
    print(f"## {f}: {len(vals)} values")
    print("raw int :", vals)
    print("Q1.11   :", [round(v/2048, 6) for v in vals], "(assumes Q1.11; check your fixed-point spec)")
    print("sum(h)  :", sum(vals), "-> DC gain", round(sum(vals)/2048, 6))
    print()
