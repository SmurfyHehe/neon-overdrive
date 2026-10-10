#!/usr/bin/env python3
"""Import hand-downloaded Treblo WAVs into the radio station folders.

Roy drops WAVs into the inbox (default C:\\SmurfyHehe\\treblo-inbox\\). For each:

  name check -> prompt-sheet check -> automatic quality checks -> trim silence,
  short fade out, -16 LUFS (ffmpeg loudnorm, two pass) -> Ogg Vorbis into
  assets/radio/<station>/ -> licence log + credits + station track list ->
  WAV moved to <inbox>/done/.

File name:  <station>_<NN>_<song-slug>_<band>.wav
            e.g. afterglow_01_harlow-drive_dusk.wav
Stations:   slipstream, undertow, afterglow, greyhour
Bands:      dusk, late, dead, dawn

Needs only Python 3 and ffmpeg/ffprobe on PATH (no pip packages, no Godot).
Nothing is ever deleted: rejects stay in the inbox, accepted WAVs are moved.

Examples:
  python tools/radio_import/import_treblo.py              # import everything
  python tools/radio_import/import_treblo.py --dry-run    # checks only, no writes
  python tools/radio_import/import_treblo.py --ab         # import + blind-test copies
  python tools/radio_import/import_treblo.py --ab-only    # only the blind-test copies
"""
import argparse
import array
import csv
import datetime
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_REPO = HERE.parents[1]
DEFAULT_INBOX = Path(r"C:\SmurfyHehe\treblo-inbox")

BANDS = ("dusk", "late", "dead", "dawn")
NAME_RE = re.compile(
    r"^(?P<station>[a-z]+)_(?P<nn>\d{2})_(?P<slug>[a-z0-9]+(?:-[a-z0-9]+)*)"
    r"_(?P<band>dusk|late|dead|dawn)\.wav$"
)

# ---- defaults, all overridable on the command line --------------------------
MIN_SECONDS = 120.0        # spec: 2:00 or longer
TARGET_LUFS = -16.0
TRUE_PEAK = -1.5
FADE_SECONDS = 2.0
BITRATE = "112k"           # spec: about 96-112 kbps
SILENT_PEAK_DB = -50.0     # whole file quieter than this = silent
SILENCE_DB = -50.0         # "silence" threshold for trim and gap detection
MAX_GAP_SECONDS = 3.0      # internal silence this long = reject
CLIP_DB = -0.1             # peak at/above this ...
CLIP_PEAK_COUNT = 20       # ... reached this many times = clipped
ABRUPT_END_RATIO = 0.5     # last 100 ms RMS vs track median RMS (0.5 = -6 dB)
AB_SECONDS = 45.0

TERMS_NAME = "Treblo free plan terms"
SOURCE_NAME = "Treblo (free plan)"
LICENCE_HEADER = (
    "| id | file path | title | artist | source URL | licence (name and URL) | "
    "date downloaded | proof | modifications | exact attribution text | "
    "commercial OK | Content ID notes | approved by |"
)
CREDITS_SECTION = "## Treblo imports"
CREDITS_HEADER = "| File | Station | Title | Hour band | Source | Source WAV sha256 |"
TRACKS_HEADER = "| NN | File | Title | Hour band | Length | Loudness |"


class Reject(Exception):
    pass


# ---- ffmpeg helpers ----------------------------------------------------------
def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return p.returncode, p.stdout, p.stderr


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


class Ff:
    def __init__(self, ffmpeg="ffmpeg", ffprobe="ffprobe"):
        self.ffmpeg, self.ffprobe = ffmpeg, ffprobe

    def duration(self, path):
        rc, out, err = run([self.ffprobe, "-v", "error", "-show_entries", "format=duration",
                            "-of", "default=nw=1:nk=1", str(path)])
        if rc != 0 or not out.strip():
            raise Reject("cannot decode file (%s)" % (err.strip().splitlines() or ["unknown"])[-1])
        return float(out.strip())

    def filter_stderr(self, path, af):
        rc, _, err = run([self.ffmpeg, "-hide_banner", "-nostats", "-i", str(path),
                          "-vn", "-af", af, "-f", "null", "-"])
        if rc != 0:
            raise Reject("ffmpeg failed: " + (err.strip().splitlines() or ["?"])[-1])
        return err

    def peak_and_clips(self, path):
        err = self.filter_stderr(path, "astats=metadata=0:reset=0")
        # the last "Overall" block carries the whole-file numbers
        overall = err[err.rfind("Overall"):] if "Overall" in err else err
        peak = re.search(r"Peak level dB:\s*(-?[\d.]+|-inf)", overall)
        cnt = re.search(r"Peak count:\s*(\d+)", overall)
        pk = float(peak.group(1)) if peak and peak.group(1) != "-inf" else -200.0
        return pk, int(cnt.group(1)) if cnt else 0

    def silences(self, path, db, min_len):
        err = self.filter_stderr(path, "silencedetect=noise=%gdB:d=%g" % (db, min_len))
        starts = [float(x) for x in re.findall(r"silence_start:\s*(-?[\d.]+)", err)]
        ends = [float(x) for x in re.findall(r"silence_end:\s*(-?[\d.]+)", err)]
        return list(zip(starts, ends + [None] * (len(starts) - len(ends))))

    def decode_mono(self, path, rate, start=None, length=None):
        cmd = [self.ffmpeg, "-v", "error", "-nostdin"]
        if start is not None:
            cmd += ["-ss", "%.3f" % start]
        if length is not None:
            cmd += ["-t", "%.3f" % length]
        cmd += ["-i", str(path), "-vn", "-ac", "1", "-ar", str(rate), "-f", "s16le", "-"]
        p = subprocess.run(cmd, capture_output=True)
        a = array.array("h")
        a.frombytes(p.stdout[: len(p.stdout) // 2 * 2])
        return a

    def loudnorm_measure(self, path, af_pre=""):
        pre = af_pre + "," if af_pre else ""
        err = self.filter_stderr(
            path, pre + "loudnorm=I=%g:TP=%g:LRA=11:print_format=json" % (TARGET_LUFS, TRUE_PEAK))
        j = err[err.rfind("{"): err.rfind("}") + 1]
        try:
            return json.loads(j)
        except ValueError:
            raise Reject("loudness measurement failed")


# ---- analysis ----------------------------------------------------------------
def tempo_bpm(samples, rate=4000):
    """Rough tempo from the onset envelope's autocorrelation. Returns BPM or None."""
    frame = rate // 50                        # 20 ms -> 50 envelope frames/s
    n = len(samples) // frame
    if n < 400:
        return None
    env = []
    for i in range(n):
        seg = samples[i * frame:(i + 1) * frame]
        env.append(sum(abs(s) for s in seg) / frame)
    onset = [max(0.0, env[i] - env[i - 1]) for i in range(1, n)]
    mean = sum(onset) / len(onset)
    onset = [o - mean for o in onset]
    if max(abs(o) for o in onset) == 0:
        return None
    scores = {}
    for lag in range(8, 101):                 # 375 BPM .. 30 BPM
        s = 0.0
        for i in range(lag, len(onset)):
            s += onset[i] * onset[i - lag]
        scores[lag] = s / (len(onset) - lag)
    top = max(scores.values())
    if top <= 0:
        return None
    # shortest lag that is a local peak and close to the best: prefers the beat over its multiples
    best_lag = None
    for lag in range(9, 100):
        if (scores[lag] >= 0.8 * top and scores[lag] >= scores[lag - 1]
                and scores[lag] >= scores[lag + 1]):
            best_lag = lag
            break
    if best_lag is None:
        return None
    bpm = 3000.0 / best_lag
    while bpm < 70:                           # fold into a musical range
        bpm *= 2
    while bpm > 170:
        bpm /= 2
    return bpm


def tempo_ok(bpm, lo, hi):
    if bpm is None or lo is None or hi is None:
        return True
    for k in (0.5, 1.0, 2.0):                 # halved/doubled tempo is fine
        if lo * 0.93 <= bpm * k <= hi * 1.07:
            return True
    return False


def ends_abruptly(samples, rate=4000):
    """True if the last 100 ms is about as loud as the track's typical level."""
    win = rate // 10
    if len(samples) < rate * 10:
        return False
    def rms(seg):
        return math.sqrt(sum(s * s for s in seg) / max(1, len(seg)))
    tail = rms(samples[-win:])
    chunks = [rms(samples[i:i + rate]) for i in range(0, len(samples) - rate, rate)]
    chunks.sort()
    median = chunks[len(chunks) // 2]
    return median > 0 and tail > ABRUPT_END_RATIO * median and tail > 32768 * 10 ** (-40 / 20)


# ---- prompt sheet / proof ------------------------------------------------------
def load_sheet(path):
    """id -> {station, band, length, prompt, instrumental}; only table rows whose id
    looks like a file stem are read, so the format notes and examples are ignored."""
    rows = {}
    if not path.exists():
        return rows
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 6:
            continue
        m = NAME_RE.match(cells[0] + ".wav")
        if m:
            rows[cells[0]] = {"station": cells[1].lower(), "band": cells[2].lower(),
                              "length": cells[3], "prompt": cells[4], "instrumental": cells[5]}
    return rows


def find_proof_dir(repo):
    base = repo / "docs" / "audio-licences-proof"
    dirs = sorted(d for d in base.glob("treblo-*") if d.is_dir()) if base.exists() else []
    for d in reversed(dirs):
        if any(p.is_file() for p in d.rglob("*")):
            return d
    return None


# ---- log writers -----------------------------------------------------------------
def pretty_title(slug):
    return " ".join(w.capitalize() for w in slug.split("-"))


def append_row(path, row, header=None, section=None):
    """Append a table row to the end of the file; create the section if absent."""
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    if not text.endswith("\n") and text:
        text += "\n"
    if section and section not in text:
        text += "\n%s\n\n%s\n%s\n" % (section, header, "|" + "---|" * (header.count("|") - 1))
    path.write_text(text + row + "\n", encoding="utf-8")


def update_tracks(path, label, entry):
    entries = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            c = [x.strip() for x in line.strip().strip("|").split("|")]
            if line.startswith("|") and len(c) >= 6 and c[0].isdigit():
                entries[c[0]] = c
    entries[entry[0]] = entry
    out = ["# %s - Treblo tracks" % label, "",
           "Written by tools/radio_import/import_treblo.py. Hour band: dusk, late, dead, dawn.", "",
           TRACKS_HEADER, "|---|---|---|---|---|---|"]
    for nn in sorted(entries):
        out.append("| " + " | ".join(entries[nn]) + " |")
    path.write_text("\n".join(out) + "\n", encoding="utf-8")
    return len(entries)


# ---- the work ----------------------------------------------------------------------
def check_file(ff, wav, info, sheet, stations, args):
    """Run every automatic check. Returns (warnings, facts). Raises Reject."""
    warns = []
    dur = ff.duration(wav)
    if dur < args.min_seconds:
        raise Reject("too short (%d:%02d, need %d:%02d)" % (
            dur // 60, dur % 60, args.min_seconds // 60, args.min_seconds % 60))
    peak, clips = ff.peak_and_clips(wav)
    if peak < SILENT_PEAK_DB:
        raise Reject("silent (peak %.1f dBFS)" % peak)
    if peak >= CLIP_DB and clips >= CLIP_PEAK_COUNT:
        raise Reject("clipped (peak %.1f dBFS reached %d times)" % (peak, clips))
    for s, e in ff.silences(wav, SILENCE_DB, MAX_GAP_SECONDS):
        if s > 0.5 and e is not None and e < dur - 0.5:
            raise Reject("%.1f s of silence at %d:%02d" % (e - s, s // 60, s % 60))
    pcm = ff.decode_mono(wav, 4000)
    if ends_abruptly(pcm):
        raise Reject("ends mid-note (no decay or silence at the end)")
    bpm = tempo_bpm(pcm)
    st = stations.get(info["station"], {})
    if not tempo_ok(bpm, st.get("bpm_min"), st.get("bpm_max")):
        msg = "tempo %.0f BPM outside %s-%s" % (bpm, st.get("bpm_min"), st.get("bpm_max"))
        if args.strict_tempo:
            raise Reject(msg)
        warns.append(msg)
    return warns, {"duration": dur, "peak": peak, "bpm": bpm}


def encode(ff, wav, out_ogg, args):
    """Trim silence, fade out, two-pass loudnorm, Ogg Vorbis. Returns (seconds, lufs)."""
    with tempfile.TemporaryDirectory(prefix="treblo_") as tmp:
        trimmed = Path(tmp) / "trim.wav"
        sil = "silenceremove=start_periods=1:start_threshold=%gdB:start_silence=0.05" % SILENCE_DB
        af = "aresample=44100,%s,areverse,%s,areverse" % (sil, sil)
        rc, _, err = run([ff.ffmpeg, "-v", "error", "-y", "-i", str(wav), "-vn", "-ac", "2",
                          "-af", af, str(trimmed)])
        if rc != 0:
            raise Reject("trim failed: " + err.strip())
        dur = ff.duration(trimmed)
        if dur < args.min_seconds - args.fade:
            raise Reject("under 2:00 after trimming silence (%.0f s)" % dur)
        fade = "afade=t=out:st=%.3f:d=%g" % (dur - args.fade, args.fade)
        m = ff.loudnorm_measure(trimmed, fade)
        ln = ("loudnorm=I=%g:TP=%g:LRA=11:measured_I=%s:measured_TP=%s:measured_LRA=%s:"
              "measured_thresh=%s:offset=%s:linear=true" % (
                  TARGET_LUFS, TRUE_PEAK, m["input_i"], m["input_tp"], m["input_lra"],
                  m["input_thresh"], m["target_offset"]))
        out_ogg.parent.mkdir(parents=True, exist_ok=True)
        rc, _, err = run([ff.ffmpeg, "-v", "error", "-y", "-i", str(trimmed), "-vn",
                          "-af", fade + "," + ln + ",aresample=44100", "-ac", "2", "-ar", "44100",
                          "-c:a", "libvorbis", "-b:a", args.bitrate, "-map_metadata", "-1",
                          str(out_ogg)])
        if rc != 0:
            raise Reject("encode failed: " + err.strip())
    check = ff.loudnorm_measure(out_ogg)
    return ff.duration(out_ogg), float(check["input_i"])


def write_ab(ff, wav, inbox, today):
    """45 s, loudness matched, unlabelled copy for blind testing + a key file."""
    dur = ff.duration(wav)
    start = max(0.0, min(dur * 0.25, dur - AB_SECONDS))
    length = min(AB_SECONDS, dur)
    digest = sha256(wav)[:8]
    out = inbox / "ab" / ("ab_%s.wav" % digest)
    out.parent.mkdir(parents=True, exist_ok=True)
    seg = "atrim=start=%.3f:duration=%.3f,asetpts=PTS-STARTPTS" % (start, length)
    m = ff.loudnorm_measure(wav, seg)
    ln = ("loudnorm=I=%g:TP=%g:LRA=11:measured_I=%s:measured_TP=%s:measured_LRA=%s:"
          "measured_thresh=%s:offset=%s:linear=true" % (
              TARGET_LUFS, TRUE_PEAK, m["input_i"], m["input_tp"], m["input_lra"],
              m["input_thresh"], m["target_offset"]))
    rc, _, err = run([ff.ffmpeg, "-v", "error", "-y", "-i", str(wav), "-vn",
                      "-af", seg + "," + ln + ",aresample=44100", "-ac", "2", "-ar", "44100",
                      "-c:a", "pcm_s16le", "-map_metadata", "-1", str(out)])
    if rc != 0:
        raise Reject("ab copy failed: " + err.strip())
    key = inbox / "ab-key.csv"
    new = not key.exists()
    with open(key, "a", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["ab_file", "source_wav", "section_start_s", "written"])
        w.writerow([out.name, wav.name, "%.1f" % start, today])
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--inbox", default=None, help="WAV inbox (default %s or $TREBLO_INBOX)" % DEFAULT_INBOX)
    ap.add_argument("--repo-root", default=str(DEFAULT_REPO))
    ap.add_argument("--date", default=None, help="download date for the log, YYYY-MM-DD (default today)")
    ap.add_argument("--dry-run", action="store_true", help="run every check, write nothing")
    ap.add_argument("--ab", action="store_true", help="also write 45 s blind-test copies to <inbox>/ab/")
    ap.add_argument("--ab-only", action="store_true", help="only write blind-test copies, no import")
    ap.add_argument("--strict-tempo", action="store_true", help="tempo outside the station range = reject")
    ap.add_argument("--bitrate", default=BITRATE)
    ap.add_argument("--min-seconds", type=float, default=MIN_SECONDS, help="minimum track length")
    ap.add_argument("--fade", type=float, default=FADE_SECONDS, help="fade-out seconds")
    ap.add_argument("--ffmpeg", default="ffmpeg")
    ap.add_argument("--ffprobe", default="ffprobe")
    args = ap.parse_args(argv)

    import os
    inbox = Path(args.inbox or os.environ.get("TREBLO_INBOX") or DEFAULT_INBOX)
    repo = Path(args.repo_root)
    today = args.date or datetime.date.today().isoformat()
    ff = Ff(args.ffmpeg, args.ffprobe)
    for tool in (args.ffmpeg, args.ffprobe):
        if not shutil.which(tool):
            print("ERROR: %s not found on PATH" % tool)
            return 2
    if not inbox.is_dir():
        print("ERROR: inbox %s does not exist" % inbox)
        return 2

    importing = not args.ab_only
    proof = None
    if importing and not args.dry_run:
        proof = find_proof_dir(repo)
        if proof is None:
            print("REFUSING TO RUN: docs/audio-licences-proof/treblo-<date>/ is missing or empty.")
            print("Save the Treblo terms page (screenshot or PDF) there first, then run again.")
            return 3
    elif importing:
        proof = find_proof_dir(repo)
        print("(dry run) proof folder: %s" % (proof.relative_to(repo).as_posix() if proof else
              "MISSING - a real run would refuse"))

    stations = {k: v for k, v in json.loads(
        (HERE / "stations.json").read_text(encoding="utf-8")).items() if not k.startswith("_")}
    sheet = load_sheet(repo / "docs" / "audio" / "treblo-prompts.md")
    licence_log = repo / "docs" / "audio-licences.md"
    logged = licence_log.read_text(encoding="utf-8") if licence_log.exists() else ""

    wavs = sorted(p for p in inbox.glob("*.wav") if p.is_file())
    if not wavs:
        print("Inbox is empty: %s" % inbox)
        return 0

    imported, rejected = [], []
    for wav in wavs:
        name = wav.name
        try:
            if args.ab or args.ab_only:
                if not args.dry_run:
                    ab = write_ab(ff, wav, inbox, today)
                    print("AB      %-48s -> ab/%s" % (name, ab.name))
            if not importing:
                continue
            m = NAME_RE.match(name)
            if not m:
                raise Reject("name must be <station>_<NN>_<song-slug>_<band>.wav")
            station, nn, slug, band = m["station"], m["nn"], m["slug"], m["band"]
            if station not in stations:
                raise Reject("unknown station '%s' (use %s)" % (station, ", ".join(stations)))
            stem = wav.stem
            if stem not in sheet:
                raise Reject("not in docs/audio/treblo-prompts.md (add a row with id %s)" % stem)
            row = sheet[stem]
            if row["station"] != station or row["band"] != band:
                raise Reject("sheet says %s/%s but the name says %s/%s" % (
                    row["station"], row["band"], station, band))
            if "| %s |" % stem in logged or ("%s.ogg" % stem) in logged:
                raise Reject("already imported (id %s is in docs/audio-licences.md)" % stem)
            warns, facts = check_file(ff, wav, m.groupdict(), sheet, stations, args)
            if args.dry_run:
                print("OK      %-48s %d:%02d  peak %.1f dBFS  ~%s BPM%s" % (
                    name, facts["duration"] // 60, facts["duration"] % 60, facts["peak"],
                    "%.0f" % facts["bpm"] if facts["bpm"] else "?",
                    ("  WARN: " + "; ".join(warns)) if warns else ""))
                imported.append(station)
                continue
            src_hash = sha256(wav)
            out_ogg = repo / "assets" / "radio" / station / ("%s_%s_%s.ogg" % (nn, slug, band))
            length, lufs = encode(ff, wav, out_ogg, args)
            ogg_hash = sha256(out_ogg)
            rel = out_ogg.relative_to(repo).as_posix()
            title = pretty_title(slug)
            proof_rel = proof.relative_to(repo).as_posix()
            append_row(licence_log,
                "| %s | %s | %s | generated with Treblo | %s | %s, saved at %s | %s | %s | "
                "trimmed silence, %gs fade out, normalised to %g LUFS, Ogg Vorbis %s; "
                "source WAV sha256 %s; ogg sha256 %s | none known | PENDING: Roy to confirm the "
                "free plan allows commercial use | not checked | pending Roy |" % (
                    stem, rel, title, SOURCE_NAME, TERMS_NAME, proof_rel, today, proof_rel,
                    args.fade, TARGET_LUFS, args.bitrate, src_hash, ogg_hash))
            append_row(repo / "assets" / "radio" / "CREDITS.md",
                "| %s | %s | %s | %s | %s | %s |" % (
                    out_ogg.name, stations[station]["label"], title, band, SOURCE_NAME, src_hash[:16]),
                CREDITS_HEADER, CREDITS_SECTION)
            update_tracks(out_ogg.parent / "tracks.md", stations[station]["label"],
                          [nn, out_ogg.name, title, band, "%d:%02d" % (length // 60, length % 60),
                           "%.1f LUFS" % lufs])
            done = inbox / "done"
            done.mkdir(exist_ok=True)
            dest = done / name
            if dest.exists():
                dest = done / ("%s_%s" % (today, name))
            shutil.move(str(wav), str(dest))
            logged += "| %s |" % stem
            print("IMPORT  %-48s %d:%02d  %.1f LUFS  -> %s%s" % (
                name, length // 60, length % 60, lufs, rel,
                ("  WARN: " + "; ".join(warns)) if warns else ""))
            imported.append(station)
        except Reject as e:
            rejected.append((name, str(e)))
            print("REJECT  %-48s %s" % (name, e))

    if importing:
        print()
        verb = "ready" if not args.dry_run else "would be ready"
        for st in stations:
            wanted = sum(1 for r in sheet.values() if r["station"] == st)
            have = 0
            tracks = repo / "assets" / "radio" / st / "tracks.md"
            if tracks.exists():
                have = len([l for l in tracks.read_text(encoding="utf-8").splitlines()
                            if re.match(r"\|\s*\d+\s*\|", l)])
            have += imported.count(st) if args.dry_run else 0
            if wanted or have:
                print("%d of %d %s for %s" % (have, wanted or have, verb, stations[st]["label"]))
        if rejected:
            print("\nRejects (still in the inbox):")
            for n, why in rejected:
                print("  %s: %s" % (n, why))
    return 1 if rejected and importing and not imported else 0


if __name__ == "__main__":
    sys.exit(main())
