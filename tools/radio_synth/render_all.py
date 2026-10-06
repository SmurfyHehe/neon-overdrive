"""Render all radio tracks. Usage: python3 render_all.py [station ...]  (drift dark synthwave). Needs numpy, scipy, ffmpeg."""
import sys, os, subprocess, time, tempfile, shutil, numpy as np
from scipy import signal
from scipy.io import wavfile
import synth, synth2, synth3

BASE, OS = 44100, 2
# The radio always plays through a speaker low-pass (7.5 kHz cockpit, 3.2 kHz chase),
# so 32 kHz / q3 loses nothing audible and keeps the files small enough for plain git.
OUT_SR, OUT_Q = 32000, "3"
FFMPEG = os.environ.get("FFMPEG", shutil.which("ffmpeg") or "ffmpeg")
OUT = os.environ.get("RADIO_OUT", "out")
PLANS = {
    "A": "IIVVVVVVVVBBDDDDDDDDVVVVBBDDDDDDDDDDDDOO",
    "B": "IIVVVVVVBBDDDDDDDDVVVVBBDDDDDDDDOO",
    "C": "IVVVVVVVBBDDDDDDDDBBDDDDDDDDDDOO",
}
STATIONS = {
    "drift": ("s1_drift", synth3.drift3, [
        ("Apex Hour",   dict(seed=1, bpm=140, t=0,  prog=("i","VI","VII","i"),  motifs=(0,1), kicks=(0,1), plan=PLANS["A"])),
        ("Tire Smoke",  dict(seed=2, bpm=144, t=2,  prog=("i","iv","VII","VI"), motifs=(2,0), kicks=(1,3), plan=PLANS["B"])),
        ("Late Shift",  dict(seed=3, bpm=138, t=-2, prog=("i","VII","VI","VII"),motifs=(1,3), kicks=(0,2), plan=PLANS["C"])),
        ("Sodium Haze", dict(seed=4, bpm=148, t=3,  prog=("i","III","VII","VI"),motifs=(4,2), kicks=(3,0), plan=PLANS["A"])),
        ("Hairpin",     dict(seed=5, bpm=142, t=5,  prog=("i","v","VI","VII"),  motifs=(3,1), kicks=(2,1), plan=PLANS["B"])),
        ("Overpass",    dict(seed=6, bpm=136, t=-1, prog=("i","iv","i","VII"),  motifs=(0,4), kicks=(4,0), plan=PLANS["C"])),
        ("Last Lap",    dict(seed=7, bpm=146, t=1,  prog=("i","VI","III","VII"),motifs=(2,4), kicks=(1,3), plan=PLANS["A"])),
    ]),
    "dark": ("s2_dark", synth3.dark3, [
        ("Graveyard Shift", dict(seed=11, bpm=130, t=0,  prog=("i","i","VI","V"),   kicks=(0,1), plan=PLANS["A"])),
        ("Cold Asphalt",    dict(seed=12, bpm=126, t=-2, prog=("i","VI","VII","V"), kicks=(2,3), plan=PLANS["B"])),
        ("Lowlight",        dict(seed=13, bpm=134, t=3,  prog=("i","iv","i","V"),   kicks=(1,4), plan=PLANS["C"])),
        ("Undertow",        dict(seed=14, bpm=128, t=5,  prog=("i","i","iv","V"),   kicks=(0,3), plan=PLANS["A"])),
        ("Black Ice",       dict(seed=15, bpm=132, t=-4, prog=("i","III","VI","V"), kicks=(1,2), plan=PLANS["B"])),
        ("Dead Lights",     dict(seed=16, bpm=124, t=2,  prog=("i","VII","VI","V"), kicks=(4,0), plan=PLANS["C"])),
        ("Hollow Street",   dict(seed=17, bpm=136, t=-1, prog=("i","VI","iv","V"),  kicks=(3,1), plan=PLANS["A"])),
    ]),
    "synthwave": ("s4_synthwave", synth3.synth3, [
        ("Harlow Drive",    dict(seed=21, bpm=108, t=0,  prog=("i","VI","III","VII"), lead_t=(0,1), plan=PLANS["B"])),
        ("Night Overpass",  dict(seed=22, bpm=104, t=-2, prog=("i","VII","VI","VII"), lead_t=(1,2), plan=PLANS["A"])),
        ("Sodium Skyline",  dict(seed=23, bpm=112, t=3,  prog=("i","iv","VII","III"), lead_t=(0,2), plan=PLANS["C"])),
        ("Last Exit",       dict(seed=24, bpm=100, t=5,  prog=("VI","VII","i","i"),   lead_t=(1,0), plan=PLANS["B"])),
        ("Dusk Pursuit",    dict(seed=25, bpm=116, t=-4, prog=("i","VI","iv","VII"),  lead_t=(2,1), plan=PLANS["A"])),
        ("Canyon Lights",   dict(seed=26, bpm=106, t=2,  prog=("i","III","VII","VI"), lead_t=(0,1), plan=PLANS["C"])),
        ("Midnight Garage", dict(seed=27, bpm=110, t=-1, prog=("i","VII","III","VI"), lead_t=(1,2), plan=PLANS["B"])),
    ]),
}

def set_sr(sr):
    synth.SR = sr; synth2.SR = sr

def main():
    names = sys.argv[1:] or list(STATIONS)
    for st in names:
        folder, fn, tracks = STATIONS[st]
        os.makedirs(f"{OUT}/{folder}", exist_ok=True)
        for i, (title, kw) in enumerate(tracks, 1):
            t0 = time.time()
            set_sr(BASE * OS)
            x = fn(**kw)
            x = signal.resample_poly(x, 1, OS, axis=0)
            x = x / max(1e-9, np.abs(x).max()) * 0.89
            assert np.isfinite(x).all(), title
            slug = title.lower().replace(" ", "_")
            wav = os.path.join(tempfile.gettempdir(), f"_r_{st}_{i}.wav")
            wavfile.write(wav, BASE, (x * 32767).astype(np.int16))
            ogg = f"{OUT}/{folder}/{i:02d}_{slug}.ogg"
            subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", wav, "-af", "loudnorm=I=-16:TP=-1.5:LRA=9",
                            "-ar", str(OUT_SR), "-c:a", "libvorbis", "-q:a", OUT_Q,
                            "-metadata", f"title={title}", "-metadata", "artist=Neon Overdrive (original, generated)",
                            ogg], check=True)
            os.remove(wav)
            print(f"{ogg}  {len(x)/BASE:.0f}s  {os.path.getsize(ogg)/1e6:.1f}MB  ({time.time()-t0:.1f}s)", flush=True)

if __name__ == "__main__":
    main()
