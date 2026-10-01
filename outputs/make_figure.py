import csv
import os
import statistics as st
from datetime import datetime
from collections import defaultdict
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

B = os.path.dirname(os.path.abspath(__file__)) + "/"


def rows(name):
    return list(csv.DictReader(open(B + name)))


# (a) size curve at T=5ms (rejection path) + capacity cliff
t1 = defaultdict(list)
for r in rows("table1_remeasure.csv"):
    if r["poll_t"] == "0.005" and r["label"] != "A":
        t1[int(r["img_size"])].append(int(r["external_ms"]))
xs = sorted(t1)
ys = [st.mean(t1[x]) for x in xs]
inv = defaultdict(list)
for r in rows("resolution_invariance.csv"):
    inv[(r["kind"], r["poll_t"], int(r["img_size"]))].append(int(r["external_ms"]))
cliff = st.mean(inv[("real", "0.005", 785920)])

# (b) normalized gap vs T/d
Ts = ["0.005", "0.02", "0.05", "0.1", "0.2"]
real = [(float(T), st.mean(inv[("real", T, 785919)]) - st.mean(inv[("real", T, 785920)])) for T in Ts]
hc = defaultdict(list)
for r in rows("hard_case.csv"):
    hc[(r["poll_t"], int(r["img_size"]))].append(int(r["external_ms"]))
series = [("real: capacity boundary (d = 640 ms)", real, 640.0, "k", "o")]
for size, d, c, m in ((200000, 79.5, "tab:green", "s"), (140000, 31.8, "tab:blue", "^"), (112288, 9.8, "tab:orange", "D")):
    pts = [(float(T), st.mean(hc[(T, size)]) - st.mean(hc[(T, 100000)]))
           for T in ["0.005", "0.02", "0.05", "0.1"] if (T, size) in hc and (T, 100000) in hc]
    series.append(("real: continuous difference (d = %.1f ms)" % d, pts, d, c, m))
fake = [(float(T), st.mean(inv[("fake", T, 76628)]) - st.mean(inv[("fake", T, 76629)])) for T in Ts]

fig, ax = plt.subplots(2, 1, figsize=(3.3, 4.3), dpi=300, gridspec_kw={"height_ratios": [1, 1.25]})
fig.subplots_adjust(left=0.17, right=0.96, top=0.95, bottom=0.26, hspace=0.5)

a = ax[0]
a.plot([x / 1024 for x in xs], ys, "o-", color="k", ms=3.5, lw=1.0)
a.plot([785920 / 1024], [cliff], "v", color="r", ms=6)
a.annotate("", xy=(785920 / 1024, cliff), xytext=(500, cliff),
           arrowprops=dict(arrowstyle="->", lw=0.7, color="r"))
a.text(630, cliff + 25, "785,920 B:\nimmediate reject", fontsize=7, color="r", ha="center", va="bottom")
a.text(0.10, 0.62, "0.81 ms/KB\n(R$^2$ = 0.997)\nT = 5 ms", transform=a.transAxes, fontsize=7, color="0.25")
a.set_xlim(0, 830)
a.set_ylim(0, 760)
a.set_xlabel("Image size (KB)", fontsize=7.5)
a.set_ylabel("Response time (ms)", fontsize=7.5)
a.tick_params(labelsize=7)
a.set_title("(a) Time grows with size; cliff at capacity", fontsize=8)

b = ax[1]
b.axvspan(0.5, 30, color="0.92", zorder=0)
b.text(0.6, -0.44, "excluded (T > d/2)", fontsize=6.5, color="0.35", va="bottom")
for label, pts, d, c, m in series:
    b.plot([T * 1000 / d for T, g in pts], [g / d for T, g in pts], marker=m, ms=4, lw=0.9, color=c, label=label)
b.plot([T * 1000 / 51.0 for T, g in fake], [g / 51.0 for T, g in fake], marker="x", ms=5, lw=0.9,
       color="tab:red", label="artifact: 77,473 B boundary (apparent d = 51 ms)")
b.axhline(1.0, color="gray", lw=0.6, ls="--")
b.axvline(0.5, color="gray", lw=0.6, ls=":")
b.set_xscale("log")
b.set_xlim(0.004, 30)
b.set_ylim(-0.5, 2.4)
b.set_xlabel("T / d  (polling interval / effect size)", fontsize=7.5)
b.set_ylabel("gap / d", fontsize=7.5)
b.tick_params(labelsize=7)
b.set_title("(b) The gap is kept only while T $\\leq$ d/2", fontsize=8)
h, l = b.get_legend_handles_labels()
fig.legend(h, l, loc="lower center", bbox_to_anchor=(0.5, 0.005), ncol=1, fontsize=6.3, frameon=False)
out = B + "figure1_%s.png" % datetime.now().strftime("%Y%m%d_%H%M%S")
plt.savefig(out)
print("saved:", out)
