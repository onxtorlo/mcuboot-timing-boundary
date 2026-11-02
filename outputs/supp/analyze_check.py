#!/usr/bin/env python3
"""analyze_check.py — check_*.csv에 논문 2.2절 판정 규칙을 적용하고 FP/FN 표를 출력.
라벨: pair_id가 'F'로 시작하면 허위(음성), 그 외 실제(양성).
판정: d = gap(T=5ms). (i) |d| > 10ms, (ii) T <= |d|/2 인 모든 T에서 sign(d)*gap >= |d|/2 이면 통과.
baseline: 스캔과 같은 T=50ms 단일 해상도에서 |gap(50ms)| > 10ms 이면 '차이(경계) 존재'로 판정.
"""
import csv, glob, os, sys
from collections import defaultdict
from statistics import mean

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
files = sys.argv[1:] or sorted(glob.glob(os.path.join(D, "check_*.csv")))
rows = [r for f in files for r in csv.DictReader(open(f))]
# 음수 경과시간은 물리적으로 불가능(WSL realtime 시계의 동기화 계단 보정이 측정 중 발생) -> 무효 표본으로 제외
# 무효 기준(P10): 경과 < 0 또는 > 3000ms(캡처 창 3초), 또는 valid=0(수신 바이트 < 391B, S4R부터 기록)
def invalid(r):
    e = float(r["elapsed_ms"])
    return e < 0 or e > 3000 or r.get("valid") == "0"
for r in rows:
    if invalid(r):
        print("INVALID(excluded):", ",".join(str(v) for v in r.values()))
rows = [r for r in rows if not invalid(r)]
pairs = {}
for r in rows:
    pairs.setdefault((r["session"], r["pair_id"]), []).append(r)

THR = 10.0
res = []
for (sess, pid), rs in pairs.items():
    sizes = []
    for r in rs:
        if int(r["img_size"]) not in sizes:
            sizes.append(int(r["img_size"]))
    a, b = sizes[0], sizes[1]
    gap = {}
    base = False
    for T in sorted({float(r["T"]) for r in rs}):
        va = [float(r["elapsed_ms"]) for r in rs if float(r["T"]) == T and int(r["img_size"]) == a]
        vb = [float(r["elapsed_ms"]) for r in rs if float(r["T"]) == T and int(r["img_size"]) == b]
        gap[T] = mean(va) - mean(vb)
        if abs(T - 0.05) < 1e-9:
            for rep in {r["rep"] for r in rs}:
                ca = [r["class"] for r in rs if float(r["T"]) == T and r["rep"] == rep and int(r["img_size"]) == a]
                cb = [r["class"] for r in rs if float(r["T"]) == T and r["rep"] == rep and int(r["img_size"]) == b]
                if ca and cb and ca[0] != cb[0]:
                    base = True
    # baseline 2: 스캔 해상도(T=50ms) 단일 측정에서 |gap| > 10ms 이면 차이 존재로 판정
    base = abs(gap[0.05]) > THR
    d = gap[0.005]
    ok_i = abs(d) > THR
    judged = [T for T in gap if T * 1000 <= abs(d) / 2]
    ok_ii = ok_i and all((1 if d > 0 else -1) * gap[T] >= abs(d) / 2 for T in judged)
    real = not pid.startswith("F")
    res.append((sess, pid, a, b, real, d, gap, ok_i and ok_ii, base, judged))

Ts = [0.005, 0.02, 0.05, 0.1, 0.2]
print("sess pair a b label d | gaps(T=5,20,50,100,200) | judgedT | pass | baseline50")
for s, pid, a, b, real, d, gap, ok, base, judged in sorted(res, key=lambda x: (not x[4], x[0], x[1])):
    g = " ".join("%7.1f" % gap.get(T, float("nan")) for T in Ts)
    print(f"{s} {pid:6s} {a:>7d} {b:>7d} {'REAL' if real else 'SPUR'} d={d:7.1f} | {g} | {len(judged)} | {'PASS' if ok else 'rej '} | {'bnd' if base else '-'}")
R = [x for x in res if x[4]]; F = [x for x in res if not x[4]]
print(f"\nREAL: pass {sum(x[7] for x in R)}/{len(R)}  (FN {sum(not x[7] for x in R)})  baseline50 flagged {sum(x[8] for x in R)}/{len(R)}")
print(f"SPUR: pass {sum(x[7] for x in F)}/{len(F)}  (FP)  baseline50 flagged {sum(x[8] for x in F)}/{len(F)}")
