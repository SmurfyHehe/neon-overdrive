#!/usr/bin/env python3
"""Save chaos runner (stress layer D, 2026-10-13).

Starts tests/save/save_chaos_life.gd again and again and kills each life with
SIGKILL (kill -9) at a random moment; the next life checks what the save holds
against the ledger the killed one wrote (see the header of
save_chaos_life.gd). After the last kill one more life only checks.

Each chain gets its own XDG_DATA_HOME, so user:// is a fresh temporary folder
and a real player's saves are never touched. Linux only (kill -9).

  python3 tests/save/save_chaos.py --mode game --lives 40 --jobs 2 --out /tmp/chaos
  python3 tests/save/save_chaos.py --mode core --lives 50 --jobs 4 --out /tmp/chaos

Exit code 1 when any check failed, a life died on its own, or the game printed
a script error. Results: <out>/<mode>-<chain>/{verdicts.jsonl,ledger.jsonl,
life-N.log} and <out>/summary-<mode>.json.
"""
import argparse
import json
import os
import random
import signal
import subprocess
import sys
import tempfile
import threading
import time
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# Seconds from start to the kill, per mode. The script runs about 3 s after
# the start; the game scene is up about 5 s after that (cloud, 4 cores).
KILL_WINDOW = {"game": (9.0, 40.0), "core": (3.5, 8.0), "upgrade": (4.0, 7.0)}
ERROR_MARKS = ("SCRIPT ERROR", "Parse Error", "Invalid call", "Invalid access", "Invalid assignment")


def godot() -> str:
    g = os.environ.get("GODOT", "")
    if not g:
        sys.exit("set GODOT to the Godot 4.7.2 Linux binary")
    return g


def run_life(mode, chain_dir, data_home, life, seed, kill_at, verify_only=False):
    env = dict(os.environ)
    env.update({
        "XDG_DATA_HOME": data_home,
        "CHAOS_DIR": chain_dir,
        "CHAOS_MODE": mode,
        "CHAOS_SEED": str(seed),
        "CHAOS_LIFE": str(life),
        "CHAOS_VERIFY_ONLY": "1" if verify_only else "",
        "NEON_TRAFFIC": "0",
    })
    cmd = [godot(), "--headless", "--audio-driver", "Dummy", "--path", ROOT,
           "-s", "res://tests/save/save_chaos_life.gd"]
    log_path = os.path.join(chain_dir, "life-%03d.log" % life)
    with open(log_path, "w") as log:
        p = subprocess.Popen(cmd, env=env, stdout=log, stderr=subprocess.STDOUT)
        killed = False
        try:
            p.wait(timeout=120 if verify_only else kill_at)
        except subprocess.TimeoutExpired:
            p.send_signal(signal.SIGKILL)
            p.wait()
            killed = True
    with open(log_path, errors="replace") as f:
        text = f.read()
    errors = [l for l in text.splitlines() if any(m in l for m in ERROR_MARKS)]
    step_fails = [l for l in text.splitlines() if l.startswith("CHAOS STEP FAIL")]
    return {"life": life, "kill_at": round(kill_at, 2), "killed": killed,
            "exit": p.returncode, "errors": errors[:5], "step_fails": step_fails}


def chain(mode, n, lives, out, seed, results):
    chain_dir = os.path.join(out, "%s-%d" % (mode, n))
    os.makedirs(chain_dir, exist_ok=True)
    data_home = tempfile.mkdtemp(prefix="chaos-%s-%d-" % (mode, n))
    rng = random.Random("%s:%d:%s" % (mode, n, seed))
    lo, hi = KILL_WINDOW[mode]
    rows = []
    for life in range(1, lives + 1):
        r = run_life(mode, chain_dir, data_home, life, seed, rng.uniform(lo, hi))
        rows.append(r)
        print("[%s-%d] life %d killed at %.1fs%s%s" % (mode, n, life, r["kill_at"],
              "" if r["killed"] else " (EXITED %s)" % r["exit"],
              " STEP FAIL" if r["step_fails"] else ""), flush=True)
    final = run_life(mode, chain_dir, data_home, lives + 1, seed, 0, verify_only=True)
    rows.append(final)
    results[n] = {"chain_dir": chain_dir, "data_home": data_home, "rows": rows}


def summarise(mode, results, out):
    verdicts, rows = [], []
    for n, r in sorted(results.items()):
        rows += r["rows"]
        p = os.path.join(r["chain_dir"], "verdicts.jsonl")
        if os.path.exists(p):
            for line in open(p):
                line = line.strip()
                if line:
                    v = json.loads(line)
                    v["chain"] = n
                    verdicts.append(v)
    kills = [r for r in rows if r["killed"]]
    died = [r for r in rows if not r["killed"] and r["exit"] not in (0,)]
    bad = [v for v in verdicts if not v.get("ok")]
    cases = Counter(v.get("case", "?").split(":")[0] + ":" + str(v.get("phase") or v.get("case", "?").split(":")[-1]) for v in verdicts)
    ops = Counter(v.get("case", "?") for v in verdicts)
    tmp = sum(1 for v in verdicts if v.get("files", {}).get("tmp", 0) > 0)
    torn_tmp = sum(1 for v in verdicts if v.get("files", {}).get("torn_tmp", 0) > 0)
    errs = sorted({e for r in rows for e in r["errors"]})
    step_fails = [f for r in rows for f in r["step_fails"]]
    s = {
        "mode": mode, "kills": len(kills), "checks": len(verdicts),
        "checks_failed": len(bad), "lives_died_on_their_own": len(died),
        "kills_inside_a_write": tmp, "kills_mid_tmp_write": torn_tmp,
        "kill_points": dict(sorted(ops.items())), "kill_phases": dict(sorted(cases.items())),
        "step_fails": step_fails[:40], "step_fail_count": len(step_fails),
        "script_errors": errs[:40], "failed_checks": bad[:40],
    }
    with open(os.path.join(out, "summary-%s.json" % mode), "w") as f:
        json.dump(s, f, indent=1)
    print(json.dumps({k: s[k] for k in ("mode", "kills", "checks", "checks_failed", "lives_died_on_their_own",
                                         "kills_inside_a_write", "kills_mid_tmp_write", "step_fail_count")}))
    return not bad and not died and not errs and not step_fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=sorted(KILL_WINDOW), default="game")
    ap.add_argument("--lives", type=int, default=20, help="kills per chain")
    ap.add_argument("--jobs", type=int, default=1, help="chains side by side")
    ap.add_argument("--out", default=os.path.join(tempfile.gettempdir(), "save-chaos"))
    ap.add_argument("--seed", default="1")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    results = {}
    threads = [threading.Thread(target=chain, args=(a.mode, n, a.lives, a.out, a.seed, results)) for n in range(1, a.jobs + 1)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    sys.exit(0 if summarise(a.mode, results, a.out) else 1)


if __name__ == "__main__":
    main()
