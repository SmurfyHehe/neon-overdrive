#!/usr/bin/env python3
"""Stress layer B: many seeded whole-game fuzz runs (tests/core/fuzz_play.gd),
side by side, one Godot process per seed.

  python3 tools/fuzz_runs.py --seeds 1-200 --jobs 4 --out /tmp/fuzz
  python3 tools/fuzz_runs.py --seeds 17,42 --out /tmp/fuzz_rerun   # replay failures

Godot comes from $GODOT. Each run gets its own XDG_DATA_HOME (tests share
user:// otherwise). Per run: <out>/logs/<seed>.log; one JSON line per run in
<out>/results.jsonl (the test's FUZZ_RESULT plus exit code, wall time and the
process's peak RSS); <out>/summary.txt at the end. A run that dies on a signal
is a crash, one past --timeout a hang; both keep their log. Exit 0 only when
every run passed.
"""
import argparse
import concurrent.futures as cf
import json
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def parse_seeds(text):
    out = []
    for part in text.split(","):
        if "-" in part:
            a, b = part.split("-")
            out.extend(range(int(a), int(b) + 1))
        elif part:
            out.append(int(part))
    return out


def peak_rss_mb(pid):
    try:
        with open("/proc/%d/status" % pid) as f:
            for line in f:
                if line.startswith("VmHWM:"):
                    return int(line.split()[1]) // 1024
    except OSError:
        pass
    return 0


def run_one(seed, args, lock):
    log_path = os.path.join(args.out, "logs", "%d.log" % seed)
    env = dict(os.environ)
    env.update({"FUZZ_SEED": str(seed), "FUZZ_SECS": str(args.secs),
                "XDG_DATA_HOME": tempfile.mkdtemp(prefix="fuzz%d_" % seed)})
    cmd = [args.godot, "--audio-driver", "Dummy", "--headless", "--path", ROOT,
           "-s", "res://tests/core/fuzz_play.gd"]
    t0 = time.time()
    peak = 0
    with open(log_path, "w") as log:
        proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, env=env,
                                start_new_session=True)
        hung = False
        while proc.poll() is None:
            peak = max(peak, peak_rss_mb(proc.pid))
            if time.time() - t0 > args.timeout:
                hung = True
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
                break
            time.sleep(1.0)
    wall = time.time() - t0
    rc = proc.returncode
    result = None
    with open(log_path, errors="replace") as f:
        for line in f:
            if line.startswith("FUZZ_RESULT "):
                result = json.loads(line[len("FUZZ_RESULT "):])
    if result is None:
        result = {"seed": seed, "pass": False, "fails": []}
    if hung:
        result["pass"] = False
        result["fails"].append("seed %d: hung, killed after %d s" % (seed, args.timeout))
    elif rc is not None and rc < 0:
        result["pass"] = False
        result["fails"].append("seed %d: crashed on signal %d" % (seed, -rc))
    elif rc != 0 and result.get("pass", False):
        result["pass"] = False
        result["fails"].append("seed %d: exit code %d" % (seed, rc))
    elif "FUZZ_RESULT" not in open(log_path, errors="replace").read():
        result["fails"].append("seed %d: no result line (exit %s)" % (seed, rc))
        result["pass"] = False
    result.update({"exit": rc, "wall_s": round(wall, 1), "peak_rss_mb": peak})
    with lock:
        with open(os.path.join(args.out, "results.jsonl"), "a") as f:
            f.write(json.dumps(result) + "\n")
        print("seed %4d %s %5.0f s  rss %4d MB  %s %s" % (
            seed, "PASS" if result["pass"] else "FAIL", wall, peak, result.get("car", "?"),
            "; ".join(result["fails"])[:200]), flush=True)
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", default="1-200")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--secs", type=float, default=60.0)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--out", default="/tmp/fuzz")
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    args = ap.parse_args()
    os.makedirs(os.path.join(args.out, "logs"), exist_ok=True)
    seeds = parse_seeds(args.seeds)
    lock = threading.Lock()
    t0 = time.time()
    with cf.ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(lambda s: run_one(s, args, lock), seeds))
    failed = [r for r in results if not r["pass"]]
    lines = ["%d runs, %d passed, %d failed, %.0f min wall" % (
        len(results), len(results) - len(failed), len(failed), (time.time() - t0) / 60)]
    for r in failed:
        lines.append("  " + "; ".join(r["fails"]))
    with open(os.path.join(args.out, "summary.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
