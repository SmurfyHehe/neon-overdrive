"""Spectrogram and seam check for the engine loop test's WAV files.

Usage: python tools/engine_loops_spectrogram.py <wav> [<wav> ...] [--out DIR]

For every WAV: writes <name>_spec.png (0-8 kHz spectrogram, time left to right)
and prints the loudest sample-to-sample step and how much the spectrum changes
from frame to frame ("flux") at its worst against its median. A click or a loop
seam shows as a vertical bright line in the PNG and as a spike in the flux.

Files named *_x3.wav hold one loop three times, so the two seams sit at 1/3 and
2/3. For those the step at each seam is reported against the loudest step found
anywhere inside a single loop.
"""
import os
import sys
import wave

import numpy as np
from PIL import Image


def read(path):
    with wave.open(path, "rb") as w:
        n, ch, rate = w.getnframes(), w.getnchannels(), w.getframerate()
        a = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float32) / 32768.0
    if ch > 1:
        a = a.reshape(-1, ch).mean(axis=1)
    return a, rate


def stft(x, win=1024, hop=256):
    w = np.hanning(win).astype(np.float32)
    n = 1 + max(0, (len(x) - win) // hop)
    frames = np.stack([x[i * hop:i * hop + win] * w for i in range(n)])
    return np.abs(np.fft.rfft(frames, axis=1)) / (win / 4.0)  # a full-scale sine reads about 1.0


def main():
    args = sys.argv[1:]
    out = "."
    if "--out" in args:
        i = args.index("--out")
        out = args[i + 1]
        del args[i:i + 2]
    os.makedirs(out, exist_ok=True)
    for path in args:
        x, rate = read(path)
        spec = stft(x)
        db = 20 * np.log10(spec + 1e-6)
        top = int(spec.shape[1] * 8000 / (rate / 2))
        img = np.clip((db[:, :top] + 100) / 100, 0, 1)[:, ::-1].T  # low frequencies at the bottom
        png = (img * 255).astype(np.uint8)
        name = os.path.splitext(os.path.basename(path))[0]
        Image.fromarray(png).resize((min(png.shape[1], 1600), 400)).save(os.path.join(out, name + "_spec.png"))
        step = np.abs(np.diff(x))
        flux = np.maximum(np.diff(spec, axis=0), 0).sum(axis=1)
        print("%s: %.2f s, loudest step %.4f (median %.5f), flux max/median %.1f" % (
            name, len(x) / rate, step.max(), np.median(step),
            flux.max() / max(float(np.median(flux)), 1e-9)))
        if name.endswith("_x3"):
            third = len(x) // 3
            inner = np.abs(np.diff(x[third // 2:third // 2 + third])).max()
            for k in (1, 2):
                c = k * third
                s = step[c - 2:c + 2].max()
                print("   seam %d: step %.4f vs loudest inner step %.4f -> %.2fx" % (k, s, inner, s / inner))


main()
