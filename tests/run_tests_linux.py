#!/usr/bin/env python3
"""Run the tests from tests/run_tests.bat on Linux, in parallel, optionally as one
slice ("shard") of the list so several cloud sessions can split a full pass.

The test list is read from tests/run_tests.bat itself (the main list, not the
"ci" list), with the same flags and environment each test gets there, so the
two never drift apart. Nothing is skipped: the union of all shards is the
whole list, and every shard computes the same split from the same inputs.

  python3 tests/run_tests_linux.py plan  [--set S] [--shards N] [--times F]
  python3 tests/run_tests_linux.py run   [--set S] [--shard K/N] [--jobs J]
                                         [--times F] [--out DIR] [--only a,b]

  --set     quick (headless, before the heavy block), heavy (headless, inside it),
            windowed (no --headless; needs a display, e.g. xvfb-run), headless
            (quick + heavy, the default), all.
  --shard   K/N, 1-based: run slice K of N. Shards are balanced by the times file
            (longest test first onto the least-loaded shard), so pass the SAME
            --times file to every session.
  --jobs    tests at once in this container (default: CPU count). The tests in
            SOLO below run alone, after the others.
  --times   a times file from an earlier run (out/times.tsv); unknown tests get
            a default guess. Longest tests start first.
  --only    run just these ids (comma list), e.g. to re-run the failures.

Each test gets its own XDG_DATA_HOME (tests share user:// otherwise and break
each other, see notes/cloud-godot-tests-2026-10-11.md) and GODOT is set for the
Auto-Tune worker. Godot comes from $GODOT. Logs go to <out>/logs/<id>.log, one
line per test to <out>/results.tsv, and <out>/times.tsv merges new timings into
the --times file. Exit 0 only when every test in the slice passed.
"""
import argparse
import concurrent.futures as cf
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BAT = os.path.join(ROOT, "tests", "run_tests.bat")

# Tests that measure their own frame or tick cost: other Godot processes on the
# same cores would skew them, so they run one at a time after the rest.
SOLO = {"low_fps_watch", "core/perf_ladder", "traffic/traffic_perf",
        "audio/synth_perf", "world/chunk_rebuild_perf", "core/perf_probe",
        "traffic/near_miss_cost", "fx/tyre_smoke_perf"}

# Guessed seconds for a test with no recorded time (4-core cloud container).
DEFAULT_SECS = {"quick": 45, "heavy": 400, "windowed": 120}

# Variables run_tests.bat uses for its own bookkeeping, not passed to tests.
BOOKKEEPING = {"GODOT", "AUDIO", "TIMES", "FAILED", "CRASHED", "TT_SAVED",
               "TEST_TIMEOUT", "RC"}
BASE_ENV = {"NEON_TICKS": "60", "NEON_TRAFFIC": "0", "NEON_SHOP": "0",
            "NEON_POLICE": "0", "NEON_CURVES": "0", "NEON_HILLS": "0",
            "TEST_TIMEOUT": "600"}

SET_RE = re.compile(r'set "([A-Za-z_][A-Za-z0-9_]*)=([^"]*)"')
RUN_RE = re.compile(r'call :run (\S+)(?:\s+(?:"([^"]*)"|(\S+)))?\s*$')
FOR_RE = re.compile(r'for %%(\w) in \(([^)]*)\) do \($')


def _expand(value, env):
    return re.sub(r"%(\w+)%", lambda m: env.get(m.group(1), ""), value)


def parse_bat(path=BAT):
    """Return the main test list as dicts: id, name, flags, env, group, timeout."""
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = [l.rstrip("\r\n") for l in f]
    start = next(i for i, l in enumerate(lines) if 'goto ci' in l) + 1
    end = next(i for i, l in enumerate(lines) if l.strip() == ":report")
    body = lines[start:end]

    env = dict(BASE_ENV)
    tests = []
    heavy = False
    seen = {}

    def handle(line):
        nonlocal heavy
        s = line.strip()
        if not s or s.lower().startswith("rem ") or s.lower() == "rem":
            return
        if s.lower().startswith('if /i not "%~1"=="quick"'):
            heavy = True
            return
        if s.startswith("if ") and "LSS" in s:
            # if %TEST_TIMEOUT% LSS 1200 set "TEST_TIMEOUT=1200"
            m = re.match(r'if %(\w+)% LSS (\d+) set "(\w+)=(\d+)"', s)
            if m and int(env.get(m.group(1), "0") or 0) < int(m.group(2)):
                env[m.group(3)] = m.group(4)
            return
        m = SET_RE.match(s)
        if m and s.startswith("set "):
            k, v = m.group(1), _expand(m.group(2), env)
            if v == "":
                env.pop(k, None)
            else:
                env[k] = v
            return
        m = RUN_RE.match(s)
        if m:
            name = m.group(1)
            flags = (m.group(2) if m.group(2) is not None else m.group(3)) or ""
            test_env = {k: v for k, v in env.items() if k not in BOOKKEEPING}
            windowed = "--headless" not in flags.split()
            group = "windowed" if windowed else ("heavy" if heavy else "quick")
            # The same script can run twice with different settings; give each run its own id.
            extra = {k: v for k, v in test_env.items() if BASE_ENV.get(k) != v}
            tid = name
            n = seen.get(name, 0)
            seen[name] = n + 1
            if n:
                tag = ",".join(f"{k}={v}" for k, v in sorted(extra.items())) or str(n + 1)
                tid = f"{name}[{tag}]"
            if "NEON_CAR" in extra and tid == name:
                tid = f"{name}[NEON_CAR={extra['NEON_CAR']}]"
            tests.append({"id": tid, "name": name, "flags": flags, "env": test_env,
                          "group": group, "timeout": int(env.get("TEST_TIMEOUT", "600"))})
            return
        if s == ")":
            heavy = False
            return
        # Anything else (echo, goto) is not a test.

    i = 0
    while i < len(body):
        m = FOR_RE.match(body[i].strip())
        if m:
            var, items = m.group(1), m.group(2).split()
            j = i + 1
            block = []
            while body[j].strip() != ")":
                block.append(body[j])
                j += 1
            for item in items:
                for b in block:
                    handle(b.replace(f"%%{var}", item))
            i = j + 1
            continue
        handle(body[i])
        i += 1
    # Ids must be unique.
    ids = [t["id"] for t in tests]
    dup = {x for x in ids if ids.count(x) > 1}
    if dup:
        sys.exit(f"duplicate test ids from run_tests.bat: {sorted(dup)}")
    return tests


def select(tests, which):
    if which == "all":
        return tests
    if which == "headless":
        return [t for t in tests if t["group"] != "windowed"]
    return [t for t in tests if t["group"] == which]


def load_times(path):
    times = {}
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 2 and parts[0] and not parts[0].startswith("#"):
                    try:
                        times[parts[1]] = float(parts[0])
                    except ValueError:
                        pass
    return times


def est(t, times):
    return times.get(t["id"], DEFAULT_SECS[t["group"]])


def split(tests, n, times):
    """Longest-first onto the least-loaded shard. Deterministic for equal inputs."""
    order = sorted(tests, key=lambda t: (-est(t, times), t["id"]))
    shards = [[] for _ in range(n)]
    load = [0.0] * n
    for t in order:
        k = min(range(n), key=lambda i: (load[i], i))
        shards[k].append(t)
        load[k] += est(t, times)
    return shards, load


def run_one(t, godot, out, lock, results):
    tid = t["id"]
    safe = re.sub(r"[^A-Za-z0-9_.=,-]", "_", tid)
    log_path = os.path.join(out, "logs", safe + ".log")
    data = tempfile.mkdtemp(prefix="neon_xdg_")
    env = dict(os.environ)
    env.update(t["env"])
    env["XDG_DATA_HOME"] = data
    env["GODOT"] = godot
    args = [godot, "--audio-driver", "Dummy"] + t["flags"].split() + \
        ["--path", ROOT, "-s", f"res://tests/{t['name']}.gd"]
    start = time.time()
    with open(log_path, "w", encoding="utf-8") as log:
        log.write("$ " + " ".join(args) + "\n")
        log.flush()
        p = subprocess.Popen(args, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
                             start_new_session=True)
        try:
            code = p.wait(timeout=t["timeout"])
            status = "PASS" if code == 0 else ("FAIL" if code > 0 else "CRASH")
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
            p.wait()
            code, status = 124, "TIMEOUT"
    secs = time.time() - start
    shutil.rmtree(data, ignore_errors=True)
    with lock:
        results.append((secs, status, tid, code))
        with open(os.path.join(out, "results.tsv"), "a", encoding="utf-8") as f:
            f.write(f"{secs:.0f}\t{status}\t{tid}\t{code}\n")
        print(f"{time.strftime('%H:%M:%S')} {status:7} {secs:6.0f} s  {tid}", flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("cmd", choices=["plan", "run"])
    ap.add_argument("--set", default="headless",
                    choices=["quick", "heavy", "windowed", "headless", "all"])
    ap.add_argument("--shard", default="1/1")
    ap.add_argument("--shards", type=int, default=0, help="plan: show an N-way split")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--times", default=os.path.join(ROOT, "tests", "linux_test_times.tsv"))
    ap.add_argument("--out", default=os.path.join(tempfile.gettempdir(), "neon_tests"))
    ap.add_argument("--only", default="")
    a = ap.parse_args()

    tests = select(parse_bat(), a.set)
    times = load_times(a.times)
    if a.only:
        want = set(x.strip() for x in a.only.split(",") if x.strip())
        unknown = want - {t["id"] for t in tests}
        if unknown:
            sys.exit(f"not in the {a.set} list: {sorted(unknown)}")
        tests = [t for t in tests if t["id"] in want]

    if a.cmd == "plan":
        n = a.shards or 1
        shards, load = split(tests, n, times)
        groups = {g: sum(1 for t in tests if t["group"] == g) for g in DEFAULT_SECS}
        print(f"{len(tests)} tests ({groups}); {len(times)} with recorded times")
        for k, (s, l) in enumerate(zip(shards, load), 1):
            print(f"shard {k}/{n}: {len(s)} tests, {l/60:.0f} min of test time, "
                  f"longest {est(s[0], times)/60 if s else 0:.0f} min")
        if n == 1:
            for t in sorted(tests, key=lambda t: -est(t, times)):
                env = " ".join(f"{k}={v}" for k, v in t["env"].items() if BASE_ENV.get(k) != v)
                print(f"{est(t, times):6.0f}\t{t['group']}\t{t['id']}\t{t['flags']}\t{env}")
        return 0

    k, n = (int(x) for x in a.shard.split("/"))
    if not 1 <= k <= n:
        sys.exit("--shard must be K/N with 1 <= K <= N")
    godot = os.environ.get("GODOT", "")
    if not godot or not os.path.exists(godot):
        sys.exit("Set GODOT to the Linux Godot 4.7.2 binary.")
    if a.set in ("windowed", "all") and not os.environ.get("DISPLAY"):
        sys.exit("Windowed tests need a display: run under xvfb-run, or use --set headless.")
    mine, _ = split(tests, n, times)
    mine = mine[k - 1]
    if not os.path.isdir(os.path.join(ROOT, ".godot")):
        print("No .godot yet: importing the project once.", flush=True)
        subprocess.run([godot, "--headless", "--editor", "--quit", "--path", ROOT],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    os.makedirs(os.path.join(a.out, "logs"), exist_ok=True)
    open(os.path.join(a.out, "results.tsv"), "w").close()
    pool_tests = [t for t in mine if t["name"] not in SOLO]
    solo_tests = [t for t in mine if t["name"] in SOLO]
    pool_tests.sort(key=lambda t: (-est(t, times), t["id"]))
    total = sum(est(t, times) for t in mine)
    print(f"shard {k}/{n}: {len(mine)} tests ({len(solo_tests)} alone at the end), "
          f"about {total/60:.0f} min of test time, {a.jobs} at once", flush=True)

    lock = threading.Lock()
    results = []
    t0 = time.time()
    with cf.ThreadPoolExecutor(max_workers=max(1, a.jobs)) as ex:
        list(ex.map(lambda t: run_one(t, godot, a.out, lock, results), pool_tests))
    for t in solo_tests:
        run_one(t, godot, a.out, lock, results)

    merged = dict(times)
    for secs, status, tid, _ in results:
        if status in ("PASS", "FAIL"):
            merged[tid] = round(secs)
    with open(os.path.join(a.out, "times.tsv"), "w", encoding="utf-8") as f:
        f.write("#secs\tid  (Linux, 4-core cloud container; feed back in with --times)\n")
        for tid, secs in sorted(merged.items(), key=lambda x: -x[1]):
            f.write(f"{secs:.0f}\t{tid}\n")

    bad = [r for r in results if r[1] in ("FAIL", "TIMEOUT")]
    crashed = [r for r in results if r[1] == "CRASH"]
    print(f"\nshard {k}/{n} done in {(time.time()-t0)/60:.1f} min: "
          f"{len(results) - len(bad) - len(crashed)} passed, {len(bad)} failed, "
          f"{len(crashed)} crashed")
    if crashed:
        print("CRASHED (exit by signal; run_tests.bat does not count these):",
              ",".join(r[2] for r in crashed))
    if bad:
        print("FAILED:", ",".join(r[2] + ("(TIMEOUT)" if r[1] == "TIMEOUT" else "") for r in bad))
        return 1
    return 3 if crashed else 0


if __name__ == "__main__":
    sys.exit(main())
