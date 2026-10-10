#!/usr/bin/env python3
"""Make radio songs through Treblo's official API (v3), two versions per row.

Reads tools/radio_import/prompts.csv (id, station, title, band, prompt, file) and
for each row asks the API for an instrumental song twice. Files land in the inbox
(default C:\\SmurfyHehe\\treblo-inbox\\) as <file>.wav and <file>_b.wav, ready for
import_treblo.py (it ignores the _b file; it never matches its name pattern).

The game never calls the API. This is an offline tool run by hand.

Safety:
  * Key comes from the TREBLO_API_KEY environment variable only. It is never
    written to disk, to the log, or to git.
  * Hard credit cap (--credit-cap, default 15000). Every call counts 100 credits
    the moment it is sent (worst case) and is refunded in the count only when the
    API reports FAILURE (the docs say failures cost nothing). The count is read
    back from batch-log.txt, so a restart cannot reset it.
  * Restart-safe: finished files are skipped, and an in-flight task id is kept
    in <inbox>/batch-state.json so a crash never re-submits (and re-pays) a task.
  * Sequential: one task at a time, a pause between submits, 10 s polls.
  * Nothing is deleted. Songs that fail the hard-fault checks are moved to
    <inbox>/rejected/ with the reason in the log.

Hard-fault checks (reject only these): silence, clipping, shorter than 2:30,
ends mid-note. There is NO automatic voice detector (no honest way to do one
with the standard library); instrumental mode + negative tags are the guard and
the blind test is the check.

Usage:
  set TREBLO_API_KEY=...            (cmd)   /   $env:TREBLO_API_KEY = "..."  (PowerShell)
  python tools/radio_import/treblo_batch.py --dry-run          # plan only, no key needed
  python tools/radio_import/treblo_batch.py --only afterglow_01  # first export check
  python tools/radio_import/treblo_batch.py                    # all 12 rows x 2
"""
import argparse
import csv
import datetime
import json
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import import_treblo as imp  # noqa: E402  (reuses the ffmpeg helpers and the same checks)

API = "https://api.treblo.com/v1"
CREDITS_PER_CALL = 100
DEFAULT_CAP = 15000
DEFAULT_INBOX = imp.DEFAULT_INBOX
LENGTH_RANGE = [150, 210]            # "about 3:00" (multiples of 30 per the docs)
MIN_SECONDS = 150.0                  # hard fault: shorter than 2:30
NEGATIVE_TAGS = ["vocal", "male vocalist", "female vocalist"]   # all in Treblo's tag list
POLL_SECONDS = 10
TASK_TIMEOUT = 15 * 60
FAILED_STATES = ("FAILURE",)
UA = "neon-overdrive-radio-batch/1 (+https://github.com/SmurfyHehe/neon-overdrive)"


class StopBatch(Exception):
    pass


# ---- log ------------------------------------------------------------------------
class Log:
    """Append-only text log. Credit accounting is read back from it."""

    def __init__(self, path):
        self.path = path

    def write(self, kind, msg):
        line = "%s  %-8s %s" % (datetime.datetime.now().isoformat(timespec="seconds"), kind, msg)
        with open(self.path, "a", encoding="utf-8") as f:
            f.write(line + "\n")
        print(line)

    def credits_spent(self):
        total = 0
        if self.path.exists():
            for line in self.path.read_text(encoding="utf-8").splitlines():
                m = re.search(r"\bcredits ([+-]\d+)\b", line)
                if m:
                    total += int(m.group(1))
        return total


# ---- HTTP -----------------------------------------------------------------------
def http_json(method, path, key, body=None, timeout=60):
    req = urllib.request.Request(
        API + path, method=method,
        data=json.dumps(body).encode("utf-8") if body is not None else None,
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json",
                 "User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:400]
        raise ApiError(e.code, detail)
    return json.loads(raw) if raw.strip() else None


class ApiError(Exception):
    def __init__(self, code, detail):
        super().__init__("HTTP %s: %s" % (code, detail))
        self.code = code
        self.detail = detail


def download(url, dest):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    tmp = dest.with_suffix(dest.suffix + ".part")
    with urllib.request.urlopen(req, timeout=300) as r, open(tmp, "wb") as f:
        shutil.copyfileobj(r, f)
    tmp.replace(dest)


# ---- state ----------------------------------------------------------------------
def load_state(path):
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except ValueError:
            pass
    return {}


def save_state(path, state):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=1), encoding="utf-8")
    tmp.replace(path)


# ---- checks ---------------------------------------------------------------------
def hard_faults(ff, wav):
    """Return a reason string, or None if the file passes. Hard faults only."""
    try:
        dur = ff.duration(wav)
        if dur < MIN_SECONDS:
            return "shorter than 2:30 (%d:%02d)" % (dur // 60, dur % 60)
        peak, clips = ff.peak_and_clips(wav)
        if peak < imp.SILENT_PEAK_DB:
            return "silent (peak %.1f dBFS)" % peak
        if peak >= imp.CLIP_DB and clips >= imp.CLIP_PEAK_COUNT:
            return "clipped (peak %.1f dBFS reached %d times)" % (peak, clips)
        for s, e in ff.silences(wav, imp.SILENCE_DB, imp.MAX_GAP_SECONDS):
            if s > 0.5 and e is not None and e < dur - 0.5:
                return "%.1f s of silence at %d:%02d" % (e - s, s // 60, s % 60)
        if imp.ends_abruptly(ff.decode_mono(wav, 4000)):
            return "ends mid-note"
    except imp.Reject as e:
        return str(e)
    return None


def wav_facts(ff, wav):
    """Container facts for the export check (format, rate, channels, tags)."""
    rc, out, _ = imp.run([ff.ffprobe, "-v", "error", "-show_entries",
                          "stream=codec_name,sample_rate,channels,bits_per_sample:format=format_name,duration:format_tags",
                          "-of", "json", str(wav)])
    try:
        return json.loads(out)
    except ValueError:
        return {"error": "ffprobe gave no JSON"}


def is_riff_wav(path):
    with open(path, "rb") as f:
        head = f.read(12)
    return head[:4] == b"RIFF" and head[8:12] == b"WAVE"


# ---- one generation ----------------------------------------------------------------
def build_body(prompt, args):
    body = {"prompt": prompt, "instrumental": True, "output_format": "wav",
            "length_range": LENGTH_RANGE}
    if not args.no_negative_tags:
        body["negative_tags"] = NEGATIVE_TAGS
    return body


def reserve(log, cap, what):
    spent = log.credits_spent()
    if spent + CREDITS_PER_CALL > cap:
        raise StopBatch("credit cap %d reached (%d counted); %s not sent" % (cap, spent, what))


def wait_for(key, task_id, log, label):
    t0 = time.time()
    last = None
    while True:
        st = http_json("GET", "/generations/status/" + task_id, key)
        st = st if isinstance(st, str) else (st or {}).get("status")
        if st != last:
            log.write("STATUS", "%s task %s %s" % (label, task_id, st))
            last = st
        if st == "SUCCESS":
            return True
        if st in FAILED_STATES:
            return False
        if time.time() - t0 > TASK_TIMEOUT:
            raise StopBatch("task %s still %s after %d min; stopping, state kept" % (
                task_id, st, TASK_TIMEOUT // 60))
        time.sleep(POLL_SECONDS)


def song_url(key, task_id):
    info = http_json("GET", "/generations/" + task_id, key)
    paths = (info or {}).get("song_paths") or []
    if not paths:
        raise StopBatch("task %s succeeded but has no song_paths" % task_id)
    return paths[0], info


def run_task(key, state, state_path, log, cap, label, endpoint, body, ident):
    """Submit (or resume) one task. Returns (ok, task_id, url)."""
    entry = state.get(ident) or {}
    task_id = entry.get("task_id")
    if not task_id:
        reserve(log, cap, label)
        try:
            resp = http_json("POST", endpoint, key, body)
        except ApiError as e:
            raise StopBatch("%s rejected by the API (%s); nothing charged" % (label, e))
        task_id = resp["task_id"]
        log.write("SUBMIT", "%s task %s credits +%d (counted %d of cap %d) prompt: %s" % (
            label, task_id, CREDITS_PER_CALL, log.credits_spent() + CREDITS_PER_CALL, cap,
            body.get("prompt", "(extend)")))
        state[ident] = {"task_id": task_id, "label": label}
        save_state(state_path, state)
    else:
        log.write("RESUME", "%s task %s (found in batch-state.json, not re-sent)" % (label, task_id))
    ok = wait_for(key, task_id, log, label)
    if not ok:
        log.write("FAILED", "%s task %s credits -%d (API: failures are not charged)" % (
            label, task_id, CREDITS_PER_CALL))
        state.pop(ident, None)
        save_state(state_path, state)
        return False, task_id, None
    url, _ = song_url(key, task_id)
    return True, task_id, url


def make_one(key, ff, row, version, args, state, state_path, log, inbox, budget):
    """Make one wav. budget is a dict with 'extends' left. Returns a short result word."""
    suffix = "" if version == "a" else "_b"
    out = inbox / (row["file"] + suffix + ".wav")
    label = "%s%s" % (row["id"], suffix or "")
    if out.exists():
        log.write("SKIP", "%s already made (%s)" % (label, out.name))
        return "have"
    done_dir = inbox / "done"
    if (done_dir / out.name).exists():
        log.write("SKIP", "%s already imported (done/%s)" % (label, out.name))
        return "have"
    ok, task_id, url = run_task(key, state, state_path, log, args.credit_cap, label,
                                "/generations/v3", build_body(row["prompt"], args), label)
    if not ok:
        return "failed"
    raw = inbox / (out.name + ".part-download")
    download(url, raw)
    if not is_riff_wav(raw):
        # The API was asked for wav; if it sent something else, convert once, keep both.
        conv = inbox / (out.name + ".converted")
        rc, _, err = imp.run([args.ffmpeg, "-v", "error", "-y", "-i", str(raw), "-c:a", "pcm_s16le",
                              "-f", "wav", str(conv)])
        if rc != 0:
            raise StopBatch("download for %s is not WAV and ffmpeg could not convert it" % label)
        log.write("NOTE", "%s: API sent a non-WAV file; converted to wav with ffmpeg" % label)
        shutil.move(str(raw), str(inbox / (out.name + ".original")))
        raw = conv
    why = hard_faults(ff, raw)
    if why and why.startswith("shorter than 2:30") and budget["extends"] > 0:
        why = try_extend(key, ff, row, label, url, raw, args, state, state_path, log, budget)
    if why:
        rej = inbox / "rejected"
        rej.mkdir(exist_ok=True)
        dest = rej / out.name
        shutil.move(str(raw), str(dest))
        log.write("REJECT", "%s task %s: %s -> rejected/%s" % (label, task_id, why, dest.name))
        state.pop(label, None)
        save_state(state_path, state)
        return "rejected"
    shutil.move(str(raw), str(out))
    meta = {"task_id": task_id, "prompt": row["prompt"], "endpoint": "/v1/generations/v3",
            "made": datetime.date.today().isoformat(),
            "terms": "Treblo API Terms dated 2026-08-20 (https://treblo.com/api-terms)",
            "source": "Treblo API", "version": version, "sha256": imp.sha256(out)}
    (inbox / (out.name[:-4] + ".api.json")).write_text(json.dumps(meta, indent=1), encoding="utf-8")
    dur = ff.duration(out)
    log.write("SAVED", "%s -> %s (%d:%02d) task %s" % (label, out.name, dur // 60, dur % 60, task_id))
    state.pop(label, None)
    save_state(state_path, state)
    return "made"


def try_extend(key, ff, row, label, parent_url, raw, args, state, state_path, log, budget):
    """One extend call on a too-short song. Returns a fault reason or None."""
    budget["extends"] -= 1
    body = {"audio_url": parent_url, "prompt": row["prompt"], "instrumental": True,
            "output_format": "wav", "context_seconds": 90, "length_range": LENGTH_RANGE}
    ident = label + "#extend"
    log.write("EXTEND", "%s was too short; one extend call (worst case counted)" % label)
    ok, task_id, url = run_task(key, state, state_path, log, args.credit_cap, label + " extend",
                                "/generations/v3/extend", body, ident)
    if not ok:
        return "shorter than 2:30 and the extend call failed"
    ext = raw.with_name(raw.name + ".extended")
    download(url, ext)
    if not is_riff_wav(ext):
        return "shorter than 2:30 and the extension did not come back as WAV"
    why = hard_faults(ff, ext)
    state.pop(ident, None)
    save_state(state_path, state)
    if why:
        shutil.move(str(ext), str(raw.with_name(raw.name + ".extend-failed")))
        return "after extend: " + why
    shutil.move(str(ext), str(raw))
    log.write("NOTE", "%s extended task %s" % (label, task_id))
    return None


# ---- main -----------------------------------------------------------------------
def load_rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f) if r.get("id")]
    for r in rows:
        if not imp.NAME_RE.match(r["file"] + ".wav"):
            raise SystemExit("prompts.csv: %r is not a <station>_<NN>_<slug>_<band> name" % r["file"])
        if not r["prompt"].strip():
            raise SystemExit("prompts.csv: row %s has an empty prompt" % r["id"])
    return rows


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--csv", default=str(HERE / "prompts.csv"))
    ap.add_argument("--inbox", default=os.environ.get("TREBLO_INBOX") or str(DEFAULT_INBOX))
    ap.add_argument("--credit-cap", type=int, default=DEFAULT_CAP,
                    help="hard stop; 1 call = %d credits (default %d)" % (CREDITS_PER_CALL, DEFAULT_CAP))
    ap.add_argument("--versions", type=int, choices=(1, 2), default=2)
    ap.add_argument("--only", action="append", default=[], help="row id (repeatable)")
    ap.add_argument("--max-extends", type=int, default=6, help="extend calls allowed per run")
    ap.add_argument("--pause", type=float, default=10.0, help="seconds between submits")
    ap.add_argument("--no-negative-tags", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="print the plan, send nothing")
    ap.add_argument("--ffmpeg", default="ffmpeg")
    ap.add_argument("--ffprobe", default="ffprobe")
    args = ap.parse_args(argv)

    rows = load_rows(Path(args.csv))
    if args.only:
        rows = [r for r in rows if r["id"] in args.only]
        if not rows:
            raise SystemExit("no row matches --only %s" % args.only)
    inbox = Path(args.inbox)
    inbox.mkdir(parents=True, exist_ok=True)
    log = Log(inbox / "batch-log.txt")
    state_path = inbox / "batch-state.json"
    versions = ["a", "b"][: args.versions]
    todo = [(r, v) for r in rows for v in versions
            if not (inbox / (r["file"] + ("" if v == "a" else "_b") + ".wav")).exists()]
    spent = log.credits_spent()
    worst = len(todo) * CREDITS_PER_CALL + args.max_extends * CREDITS_PER_CALL
    print("%d song(s) to make, %d credits for those, up to %d more for extends. Counted so far: %d. Cap: %d." % (
        len(todo), len(todo) * CREDITS_PER_CALL, args.max_extends * CREDITS_PER_CALL, spent, args.credit_cap))
    if args.dry_run:
        for r, v in todo:
            print("  would make %s%s.wav  [%s]" % (r["file"], "" if v == "a" else "_b", r["id"]))
        print("worst case this run: %d credits (cap leaves %d)" % (worst, max(0, args.credit_cap - spent)))
        return 0
    key = os.environ.get("TREBLO_API_KEY", "").strip()
    if not key:
        print("TREBLO_API_KEY is not set. Set it in this shell only; it is never saved.")
        return 2
    ff = imp.Ff(args.ffmpeg, args.ffprobe)
    state = load_state(state_path)
    budget = {"extends": args.max_extends}
    try:
        bal = http_json("GET", "/credits/balance", key)
        log.write("BALANCE", "sub %s, payg %s" % (bal.get("num_credits"), bal.get("num_credits_payg")))
        have = (bal.get("num_credits") or 0) + (bal.get("num_credits_payg") or 0)
        if have < CREDITS_PER_CALL:
            raise StopBatch("balance %d is below one call (%d); is the trial verified?" % (have, CREDITS_PER_CALL))
        results = {}
        for i, (row, v) in enumerate(todo):
            res = make_one(key, ff, row, v, args, state, state_path, log, inbox, budget)
            results[res] = results.get(res, 0) + 1
            if res != "have" and i < len(todo) - 1:
                time.sleep(args.pause)
        log.write("DONE", "results %s; credits counted %d" % (results, log.credits_spent()))
    except StopBatch as e:
        log.write("STOP", str(e))
        return 1
    except ApiError as e:
        log.write("STOP", "API error: %s" % e)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
