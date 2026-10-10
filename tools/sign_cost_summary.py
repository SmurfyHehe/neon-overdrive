"""Summarises the JSON lines written by tools/sign_cost_bench.gd.

    python tools/sign_cost_summary.py drive.jsonl [baseline-variant]

Per variant: the draw-call / object / primitive means (the same in every run
when the drive is deterministic; the spread column says if they were not) and
the median over runs of each time, as a delta against the baseline variant
("off" by default) with the lowest and highest per-run delta. Deltas are
taken pairwise, run k of a variant against run k of the baseline, because
neighbouring runs share the machine's mood.
"""
import json
import statistics as st
import sys

path = sys.argv[1]
base = sys.argv[2] if len(sys.argv) > 2 else "off"
runs = {}
for line in open(path, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    d = json.loads(line)
    if d.get("mode") == "build":
        continue
    runs.setdefault(d["signs"], []).append(d)

COUNTS = ["draw", "objects", "prims"]
TIMES = [("process", "p50"), ("process", "mean"), ("process_plain", "p50"), ("rebuild_process", "mean"),
         ("physics", "p50"), ("render_cpu", "p50"), ("setup_cpu", "p50"), ("gpu", "p50"), ("wall", "p50"),
         ("monitor_process", "p50")]


def val(d, k, f):
    return d.get(k, {}).get(f)


for v, rs in runs.items():
    print(f"== {v}: {len(rs)} runs, frames {sorted(set(r['frames'] for r in rs))}, rebuilds {sorted(set(r['rebuilds'] for r in rs))}")
    for k in COUNTS:
        means = [val(r, k, "mean") for r in rs]
        maxes = [val(r, k, "max") for r in rs]
        line = f"   {k:8s} mean {st.median(means):10.2f} (runs {min(means):.2f}..{max(means):.2f})  max {max(maxes):.0f}"
        if v != base and base in runs:
            b = st.median([val(r, k, "mean") for r in runs[base]])
            bm = max(val(r, k, "max") for r in runs[base])
            line += f"   vs {base}: mean {st.median(means) - b:+.2f}, max {max(maxes) - bm:+.0f}"
        print(line)
    for k, f in TIMES:
        xs = [val(r, k, f) for r in rs if val(r, k, f) is not None]
        if not xs:
            continue
        line = f"   {k + '.' + f:22s} median {st.median(xs):8.3f} ms (runs {min(xs):.3f}..{max(xs):.3f})"
        if v != base and base in runs:
            bs = [val(r, k, f) for r in runs[base] if val(r, k, f) is not None]
            n = min(len(xs), len(bs))
            ds = [xs[i] - bs[i] for i in range(n)]
            if ds:
                line += f"   delta vs {base}: median {st.median(ds):+.3f} (runs {min(ds):+.3f}..{max(ds):+.3f})"
        print(line)
