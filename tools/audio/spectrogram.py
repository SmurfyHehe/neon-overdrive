"""Spectrogram and level sheet for the engine-voice WAVs (kei rework, 2026-10-09).

Reads the WAVs tests/audio/kei_voice.gd wrote (one folder, mono 16-bit) and
draws one PNG: a row per WAV, time left to right, 40 Hz to 12 kHz bottom to
top on a log scale, level as colour (navy -> amber -> white, the game's
palette). Needs only numpy and the standard library; the PNG is written by
hand so nothing else has to be installed.

    python tools/audio/spectrogram.py "<folder with the WAVs>" out.png [name ...]

With no names every WAV in the folder is drawn, sorted. Prints a table of RMS
and the loudest band per file as well.
"""
import os
import struct
import sys
import wave
import zlib

import numpy as np

WIN = 2048
HOP = 256
F_LO, F_HI, ROWS = 40.0, 12000.0, 160
DB_FLOOR = -90.0


def read_wav(path):
    with wave.open(path, "rb") as w:
        sr = w.getframerate()
        ch = w.getnchannels()
        raw = w.readframes(w.getnframes())
    x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch)[:, 0]
    return sr, x


def spectrogram(sr, x):
    """Rows: log-spaced bands F_LO..F_HI; columns: frames. Values in dBFS."""
    win = np.hanning(WIN)
    n = max(1, (len(x) - WIN) // HOP + 1)
    frames = np.lib.stride_tricks.as_strided(
        x, shape=(n, WIN), strides=(x.strides[0] * HOP, x.strides[0]))
    spec = np.abs(np.fft.rfft(frames * win, axis=1)) / (WIN / 4)
    freqs = np.fft.rfftfreq(WIN, 1.0 / sr)
    edges = np.geomspace(F_LO, F_HI, ROWS + 1)
    out = np.full((ROWS, n), DB_FLOOR)
    for r in range(ROWS):
        sel = (freqs >= edges[r]) & (freqs < edges[r + 1])
        if not sel.any():
            sel = [int(np.argmin(np.abs(freqs - edges[r])))]
        p = np.sqrt(np.mean(spec[:, sel] ** 2, axis=1))
        out[r] = 20 * np.log10(np.maximum(p, 1e-9))
    return out[::-1], edges  # high frequencies on top


def colour(db):
    """Navy (#0E1424) through sodium orange (#FF8A1F) and amber (#FFC066) to white."""
    t = np.clip((db - DB_FLOOR) / (0.0 - DB_FLOOR), 0, 1)
    stops = np.array([[0x0E, 0x14, 0x24], [0x1B, 0x2A, 0x4A], [0xFF, 0x8A, 0x1F],
                      [0xFF, 0xC0, 0x66], [0xFF, 0xFF, 0xFF]], dtype=float)
    pos = np.array([0.0, 0.35, 0.65, 0.85, 1.0])
    rgb = np.stack([np.interp(t, pos, stops[:, c]) for c in range(3)], axis=-1)
    return rgb.astype(np.uint8)


def write_png(path, img):
    h, w, _ = img.shape
    raw = b"".join(b"\x00" + img[y].tobytes() for y in range(h))

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


# A tiny 3x5 pixel font for the row labels, so the sheet reads on its own.
FONT = {
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
    "4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001001001001",
    "8": "111101111101111", "9": "111101111001111", "a": "000111101101111", "b": "100111101101111",
    "c": "000111100100111", "d": "001111101101111", "e": "111101111100111", "f": "011010111010010",
    "g": "111101111001111", "h": "100111101101101", "i": "010000010010010", "k": "100101110101101",
    "l": "010010010010011", "m": "000110111101101", "n": "000110101101101", "o": "000111101101111",
    "p": "111101111100100", "r": "000111100100100", "s": "000111100001111", "t": "010111010010011",
    "u": "000101101101111", "w": "000101101111111", "x": "000101010010101", "y": "101101111001111",
    "z": "111001010100111", "_": "000000000000111", " ": "000000000000000", "-": "000000111000000",
    ".": "000000000000010", "H": "101101111101101", "k": "100101110101101",
}


def stamp(img, x0, y0, text, scale=2):
    for ch in text:
        bits = FONT.get(ch, FONT[" "])
        for i, b in enumerate(bits):
            if b == "1":
                y, x = divmod(i, 3)
                img[y0 + y * scale:y0 + (y + 1) * scale, x0 + x * scale:x0 + (x + 1) * scale] = (255, 255, 255)
        x0 += 4 * scale


def main():
    folder, out = sys.argv[1], sys.argv[2]
    names = sys.argv[3:] or sorted(f[:-4] for f in os.listdir(folder) if f.endswith(".wav"))
    panels = []
    gap = 6
    width = 0
    print("%-24s %8s %8s %10s" % ("file", "rms dB", "peak", "loudest Hz"))
    for name in names:
        sr, x = read_wav(os.path.join(folder, name + ".wav"))
        sg, edges = spectrogram(sr, x)
        rms = 20 * np.log10(max(np.sqrt(np.mean(x ** 2)), 1e-9))
        mean = sg.mean(axis=1)[::-1]
        loud = int(np.sqrt(edges[np.argmax(mean)] * edges[np.argmax(mean) + 1]))
        print("%-24s %8.1f %8.3f %10d" % (name, rms, np.max(np.abs(x)), loud))
        panels.append((name, colour(sg)))
        width = max(width, sg.shape[1])
    height = sum(p[1].shape[0] + gap for p in panels) + 14
    img = np.zeros((height, width + 64, 3), dtype=np.uint8)
    img[:] = (0x0E, 0x14, 0x24)
    y = 7
    for name, pic in panels:
        h, w, _ = pic.shape
        img[y:y + h, 64:64 + w] = pic
        stamp(img, 2, y + 2, name[:12], 1)
        y += h + gap
    write_png(out, img)
    print("wrote", out)


if __name__ == "__main__":
    main()
