"""Procedural radio tracks for Neon Overdrive. numpy/scipy only, deterministic by seed."""
import numpy as np
from scipy import signal

SR = 44100


# ---------- helpers ----------
def midi(n):
    return 440.0 * 2 ** ((np.asarray(n, dtype=float) - 69) / 12)


def sos_filter(x, kind, fc, order=2):
    sos = signal.butter(order, fc, kind, fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def lp(x, fc, order=2):
    return sos_filter(x, "low", fc, order)


def hp(x, fc, order=2):
    return sos_filter(x, "high", fc, order)


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], "band", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def sat(x, drive):
    return np.tanh(x * drive) / np.tanh(drive)


def saw_from_phase(ph):
    return 2.0 * ((ph / (2 * np.pi)) % 1.0) - 1.0


def square_from_phase(ph):
    return np.sign(np.sin(ph))


def fade_out(x, ms=15):
    n = min(len(x), int(SR * ms / 1000))
    if n > 0:
        x = x.copy()
        x[-n:] *= np.linspace(1, 0, n)
    return x


def pan_gains(p):
    a = (p + 1) * np.pi / 4
    return np.cos(a), np.sin(a)


class Bus:
    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.buf = np.zeros((self.n, 2))

    def put(self, x, start_s, gain=1.0, pan=0.0):
        s = int(start_s * SR)
        if s >= self.n:
            return
        x = np.asarray(x)
        if x.ndim == 1:
            gl, gr = pan_gains(pan)
            x = np.stack([x * gl, x * gr], axis=1)
        e = min(self.n, s + len(x))
        self.buf[s:e] += x[: e - s] * gain


def reverb_ir(seconds=1.6, decay=0.45, seed=7, hp_hz=200, lp_hz=7000):
    r = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = np.stack([r.standard_normal(n), r.standard_normal(n)], axis=1)
    ir *= np.exp(-t / decay)[:, None]
    ir = hp(ir, hp_hz)
    ir = lp(ir, lp_hz)
    ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))[:, None]
    return ir / np.sqrt(np.sum(ir ** 2, axis=0, keepdims=True))


def apply_reverb(bus_buf, ir, wet=1.0):
    out = np.zeros_like(bus_buf)
    for ch in range(2):
        out[:, ch] = signal.fftconvolve(bus_buf[:, ch], ir[:, ch])[: len(bus_buf)]
    return out * wet


def pingpong(buf, delay_s, fb=0.45, taps=5):
    d = int(delay_s * SR)
    out = buf.copy()
    for k in range(1, taps + 1):
        sh = np.zeros_like(buf)
        if k * d < len(buf):
            sh[k * d:] = buf[: len(buf) - k * d]
        g = fb ** k
        if k % 2 == 1:
            out[:, 0] += sh[:, 1] * g
            out[:, 1] += sh[:, 0] * g
        else:
            out += sh * g
    return out


def sidechain(n, hits, depth=0.7, release=0.18):
    g = np.ones(n)
    for h in hits:
        s = int(h * SR)
        if s >= n:
            continue
        m = min(n - s, int(release * 4 * SR))
        t = np.arange(m) / SR
        dip = 1 - depth * np.exp(-t / release)
        g[s:s + m] = np.minimum(g[s:s + m], dip)
    return g[:, None]


# ---------- instruments ----------
def kick(f0=150, f1=48, dur=0.45, body=0.2, drive=2.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t / 0.028)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) * np.exp(-t / body)
    click = np.random.default_rng(3).standard_normal(n) * np.exp(-t / 0.003)
    x += 0.25 * hp(click, 1500)
    return fade_out(sat(x, drive))


def snare(dur=0.28, tone=185, noise_lo=1500, noise_hi=9000, body_decay=0.07, noise_decay=0.10, seed=5):
    n = int(dur * SR)
    t = np.arange(n) / SR
    r = np.random.default_rng(seed)
    nz = bp(r.standard_normal(n), noise_lo, noise_hi) * np.exp(-t / noise_decay)
    body = np.sin(2 * np.pi * tone * t * (1 + 0.3 * np.exp(-t / 0.02))) * np.exp(-t / body_decay)
    return fade_out(sat(0.9 * nz + 0.6 * body, 1.6))


def clap(dur=0.35, seed=6):
    n = int(dur * SR)
    r = np.random.default_rng(seed)
    nz = bp(r.standard_normal(n), 900, 5500)
    t = np.arange(n) / SR
    env = np.zeros(n)
    for off in (0.0, 0.011, 0.023):
        s = int(off * SR)
        env[s:] += np.exp(-(t[: n - s]) / 0.008)
    env += 0.8 * np.exp(-np.maximum(t - 0.03, 0) / 0.09) * (t > 0.03)
    return fade_out(nz * env * 0.7)


def hat(open_=False, seed=1, bright=7500):
    dur = 0.30 if open_ else 0.07
    n = int(dur * SR)
    t = np.arange(n) / SR
    r = np.random.default_rng(seed)
    nz = hp(r.standard_normal(n), bright, 3)
    return fade_out(nz * np.exp(-t / (0.09 if open_ else 0.017)) * 0.5)


def s808(freq, dur, glide_from=None, drive=3.5, decay_frac=0.75):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = np.full(n, float(freq))
    if glide_from:
        f = freq + (glide_from - freq) * np.exp(-t / 0.045)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) * np.minimum(1.0, t / 0.002) * np.exp(-t / (dur * decay_frac))
    x = sat(x, drive)
    return fade_out(x, 25)


def cowbell(note, dur=0.32, drive=2.0):
    f1 = float(midi(note))
    f2 = f1 * (800.0 / 540.0)
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = square_from_phase(2 * np.pi * f1 * t) + square_from_phase(2 * np.pi * f2 * t)
    x = bp(x, f1 * 1.2, f2 * 2.4)
    env = 0.7 * np.exp(-t / 0.03) + 0.3 * np.exp(-t / 0.14)
    return fade_out(sat(x * env * 0.8, drive), 20)


def pad_voice(freq, dur, detune=0.12, voices=3, lp_hz=1800, attack=0.15, release=0.4, seed=0):
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    r = np.random.default_rng(seed)
    out = np.zeros((n, 2))
    for v in range(voices):
        cents = (v - (voices - 1) / 2) * detune * 100 / 100.0
        f = freq * 2 ** (cents / 12 * 0.1 * 10 / 10)
        f = freq * (1 + (v - (voices - 1) / 2) * detune * 0.01)
        ph = 2 * np.pi * f * t + r.uniform(0, 2 * np.pi)
        w = saw_from_phase(ph)
        p = -1 + 2 * v / max(1, voices - 1)
        gl, gr = pan_gains(p * 0.8)
        out[:, 0] += w * gl
        out[:, 1] += w * gr
    env = np.minimum(1.0, t / attack) * np.where(t < dur, 1.0, np.exp(-(t - dur) / (release * 0.35)))
    out = lp(out, lp_hz)
    return out * env[:, None] / voices


def formant_choir(freq, dur, vowel="ah", attack=0.25, release=0.5, seed=0):
    forms = {"ah": (800, 1150, 2800), "oo": (350, 800, 2700), "oh": (450, 800, 2830)}[vowel]
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    r = np.random.default_rng(seed)
    src = np.zeros(n)
    for dt in (-0.07, 0.0, 0.08):
        ph = 2 * np.pi * freq * (1 + dt * 0.1) * t + r.uniform(0, 6.28) + 0.8 * np.sin(2 * np.pi * 4.8 * t)
        src += saw_from_phase(ph)
    out = np.zeros(n)
    for i, fc in enumerate(forms):
        out += bp(src, fc * 0.9, fc * 1.1, 2) * (1.0, 0.7, 0.3)[i]
    env = np.minimum(1.0, t / attack) * np.where(t < dur, 1.0, np.exp(-(t - dur) / (release * 0.3)))
    return out * env * 0.5


def pluck_bass(freq, dur, lp_hz=700, drive=1.5):
    n = int(dur * SR)
    t = np.arange(n) / SR
    ph = 2 * np.pi * freq * t
    x = saw_from_phase(ph) + 0.6 * saw_from_phase(ph * 1.005)
    env = np.exp(-t / (dur * 0.9))
    cutoff_env = 0.35 + 0.65 * np.exp(-t / 0.08)
    # time-varying lowpass approximated by two static filters crossfaded
    lo = lp(x, lp_hz * 0.45)
    hi = lp(x, lp_hz * 1.6)
    y = lo * (1 - cutoff_env) + hi * cutoff_env
    return fade_out(sat(y * env, drive), 10)


def lead_voice(freq, dur, vib=5.2, vib_depth=0.006, lp_hz=4200, attack=0.02, release=0.25):
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    vibrato = 1 + vib_depth * np.sin(2 * np.pi * vib * t) * np.minimum(1.0, t / 0.35)
    ph = 2 * np.pi * np.cumsum(freq * vibrato) / SR
    x = saw_from_phase(ph) + 0.5 * saw_from_phase(ph * 1.004) + 0.4 * square_from_phase(ph * 0.5)
    env = np.minimum(1.0, t / attack) * np.where(t < dur, 1.0, np.exp(-(t - dur) / (release * 0.35)))
    return lp(x, lp_hz) * env * 0.35


def arp_voice(freq, dur=0.14, lp_hz=3600):
    n = int(dur * SR)
    t = np.arange(n) / SR
    ph = 2 * np.pi * freq * t
    x = saw_from_phase(ph) + 0.7 * square_from_phase(ph * 1.003)
    env = np.exp(-t / (dur * 0.5))
    return fade_out(lp(x, lp_hz) * env * 0.4, 6)


# ---------- master ----------
def master(mix, peak=0.89):
    mix = hp(mix, 34, 4)
    mix = sat(mix * 1.1, 1.5)
    mix /= max(1e-9, np.max(np.abs(mix)))
    return mix * peak


# ---------- tracks ----------
def drift_phonk(seed=1, bpm=140, bars=16):
    r = np.random.default_rng(seed)
    beat = 60.0 / bpm
    step = beat / 4
    bar_s = beat * 4
    total = bars * bar_s + 2.5
    drums, bass, mel, pad = Bus(total), Bus(total), Bus(total), Bus(total)
    # F# minor: i VI VII i  -> roots (bass midi), triads (cowbell tones)
    chords = [
        (30, [66, 69, 73]),  # F# A C#
        (26, [62, 66, 69]),  # D F# A
        (28, [64, 68, 71]),  # E G# B
        (30, [66, 69, 73]),
    ]
    motifs = [
        {0: 3, 3: 3, 6: 2, 8: 1, 10: 2, 12: 3, 14: 4},
        {0: 4, 2: 3, 4: 3, 7: 2, 10: 3, 12: 2, 13: 3, 15: 4},
    ]
    kick_s = kick(f0=160, f1=46, body=0.16)
    sn = clap()
    kick_times = []
    for b in range(bars):
        t0 = b * bar_s
        root, tri = chords[b % 4]
        tones = tri + [tri[0] + 12, tri[1] + 12, tri[2] + 12]
        intro = b < 2
        breakdown = b in (8, 9)
        full = not intro and not breakdown
        # drums
        if not intro:
            kpat = [0, 6, 10] if b % 2 == 0 else [0, 3, 6, 10]
            if breakdown:
                kpat = []
            for s_ in kpat:
                drums.put(kick_s, t0 + s_ * step, 1.0)
                kick_times.append(t0 + s_ * step)
            if not breakdown:
                for s_ in (4, 12):
                    drums.put(sn, t0 + s_ * step, 0.8, pan=0.05)
            # hats: 8ths + 16th rolls at bar end
            hat_steps = list(range(0, 16, 2))
            if b % 2 == 1:
                hat_steps += [13, 15]
            for s_ in hat_steps:
                drums.put(hat(seed=int(r.integers(0, 999))), t0 + s_ * step, 0.45 + 0.1 * (s_ % 4 == 0), pan=r.uniform(-0.3, 0.3))
            if full and b % 4 == 3:
                for k in range(6):  # roll
                    drums.put(hat(seed=int(r.integers(0, 999))), t0 + (12 + k * 0.66) * step, 0.35 + 0.08 * k)
            drums.put(hat(open_=True, seed=11), t0 + 14 * step, 0.4)
            # 808
            if not breakdown:
                for s_ in kpat:
                    d = step * (3 if s_ in (0, 10) else 2)
                    drums.put  # keep linter quiet
                    bass.put(s808(midi(root), d * 1.1, glide_from=midi(root) * 1.5 if s_ == 0 else None), t0 + s_ * step, 0.95)
                if b % 4 == 3:
                    bass.put(s808(midi(root + 7), step * 2.5, glide_from=midi(root + 12)), t0 + 13 * step, 0.8)
        # cowbell melody
        m = motifs[(b // 4) % 2] if not breakdown else {0: 3, 8: 1}
        for s_, idx in m.items():
            note = tones[idx] + 12
            mel.put(cowbell(note), t0 + s_ * step, 0.5 + 0.12 * (s_ % 4 == 0), pan=0.15)
        # dark pad
        for tn in tri:
            pad.put(pad_voice(midi(tn - 12), bar_s, lp_hz=1100, attack=0.4, release=0.8, voices=3, seed=int(tn)), t0, 0.28)
    # riser into the drop
    n = int(bar_s * 2 * SR)
    ris = hp(np.random.default_rng(9).standard_normal(n), 2000) * np.linspace(0, 1, n) ** 2 * 0.25
    mel.put(ris, 6 * bar_s)
    ir = reverb_ir(1.3, 0.35, seed=4)
    rev = apply_reverb(mel.buf * 0.7 + drums.buf * 0.12, ir)
    sc = sidechain(drums.n, kick_times, depth=0.55, release=0.14)
    mix = drums.buf + bass.buf * 0.7 + (mel.buf * 0.9 + pad.buf * 0.8) * sc + rev * 0.5
    mix = sat(mix, 1.2)
    return master(mix)


def dark_phonk(seed=2, bpm=130, bars=16):
    r = np.random.default_rng(seed)
    beat = 60.0 / bpm
    step = beat / 4
    bar_s = beat * 4
    total = bars * bar_s + 3.0
    drums, bass, mel, pad = Bus(total), Bus(total), Bus(total), Bus(total)
    # A minor: i i VI V(major)
    chords = [
        (33, [57, 60, 64]),  # A C E
        (33, [57, 60, 64]),
        (29, [53, 57, 60]),  # F A C
        (28, [52, 56, 59]),  # E G# B
    ]
    kick_s = kick(f0=130, f1=42, body=0.24, drive=2.8)
    sn = snare(noise_decay=0.14, tone=170)
    kick_times = []
    for b in range(bars):
        t0 = b * bar_s
        root, tri = chords[b % 4]
        intro = b < 2
        breakdown = b in (10, 11)
        if not intro and not breakdown:
            kpat = [0, 7, 10] if b % 2 == 0 else [0, 7, 9, 14]
            for s_ in kpat:
                drums.put(kick_s, t0 + s_ * step, 1.0)
                kick_times.append(t0 + s_ * step)
            for s_ in (4, 12):
                drums.put(sn, t0 + s_ * step, 0.75)
            # memphis triplet hats: 8ths plus a triplet burst on beat 4
            for k in range(8):
                drums.put(hat(seed=int(r.integers(0, 999)), bright=6500), t0 + k * 2 * step, 0.4)
            for k in range(3):
                drums.put(hat(seed=int(r.integers(0, 999)), bright=6500), t0 + 3 * beat + k * beat / 3, 0.45)
            if b % 4 == 3:
                for k in range(3):
                    drums.put(hat(seed=int(r.integers(0, 999)), bright=6500), t0 + 2.5 * beat + k * beat / 6, 0.4)
            for s_ in kpat:
                d = step * (4 if s_ == 0 else 3)
                bass.put(s808(midi(root), d, glide_from=midi(root) * 1.35 if s_ in (0, 7) else None, drive=5.0, decay_frac=0.9), t0 + s_ * step, 1.0)
        # sparse dark cowbell
        for s_, idx in ({0: 0, 6: 2, 10: 1} if not breakdown else {0: 0}).items():
            mel.put(cowbell(tri[idx] + 12, dur=0.4, drive=2.6), t0 + s_ * step, 0.55, pan=-0.2)
        # choir
        vowel = ("oo", "ah", "oh", "oo")[b % 4]
        for i, tn in enumerate(tri):
            pad.put(formant_choir(float(midi(tn + 12)), bar_s * 0.98, vowel=vowel, seed=int(tn)), t0, 0.5, pan=(-0.3, 0.0, 0.3)[i])
    # vinyl-ish noise bed
    n = int(total * SR)
    nz = hp(np.random.default_rng(12).standard_normal(n), 3000) * 0.01
    crackle = (np.random.default_rng(13).random(n) > 0.9997) * np.random.default_rng(14).standard_normal(n) * 0.25
    bed = np.stack([nz + crackle, nz[::-1] + crackle[::-1]], axis=1)
    ir = reverb_ir(2.0, 0.7, seed=8, lp_hz=5000)
    rev = apply_reverb(pad.buf * 0.8 + mel.buf * 0.8 + drums.buf * 0.1, ir)
    sc = sidechain(drums.n, kick_times, depth=0.5, release=0.16)
    mix = drums.buf * 1.0 + bass.buf * 0.7 + (mel.buf + pad.buf) * 0.85 * sc + rev * 0.5 + bed[: drums.n]
    mix = lp(mix, 11000)
    mix = sat(mix, 1.6)
    return master(mix)


def synthwave(seed=3, bpm=108, bars=12):
    r = np.random.default_rng(seed)
    beat = 60.0 / bpm
    step = beat / 4
    bar_s = beat * 4
    total = bars * bar_s + 3.0
    drums, bass, arp, pad, lead = Bus(total), Bus(total), Bus(total), Bus(total), Bus(total)
    # A minor: Am F C G
    chords = [
        (33, [57, 60, 64], "Am"),
        (29, [53, 57, 60], "F"),
        (36, [60, 64, 67], "C"),
        (31, [55, 59, 62], "G"),
    ]
    lead_lines = {
        0: [(0, 81, 6), (8, 84, 4), (12, 81, 4)],
        1: [(0, 84, 6), (8, 81, 4), (12, 77, 4)],
        2: [(0, 84, 6), (8, 88, 4), (12, 84, 4)],
        3: [(0, 83, 6), (8, 86, 4), (12, 79, 4)],
    }
    kick_s = kick(f0=120, f1=52, body=0.2, drive=1.8)
    sn = snare(noise_decay=0.16, tone=200, noise_lo=1200)
    kick_times = []
    for b in range(bars):
        t0 = b * bar_s
        root, tri, _ = chords[b % 4]
        intro = b < 2
        # drums
        for beat_i in range(4):
            drums.put(kick_s, t0 + beat_i * beat, 0.95)
            kick_times.append(t0 + beat_i * beat)
        if not intro:
            for s_ in (4, 12):
                drums.put(sn, t0 + s_ * step, 0.8)
        for s_ in range(16):
            if s_ % 4 == 2:
                drums.put(hat(open_=True, seed=int(r.integers(0, 999))), t0 + s_ * step, 0.28)
            elif not intro:
                drums.put(hat(seed=int(r.integers(0, 999))), t0 + s_ * step, 0.18)
        if b % 4 == 3 and not intro:
            for k, f in enumerate((220, 180, 150, 120)):
                n = int(0.25 * SR)
                tt = np.arange(n) / SR
                tom = np.sin(2 * np.pi * f * tt * (1 + 0.2 * np.exp(-tt / 0.04))) * np.exp(-tt / 0.09)
                drums.put(fade_out(tom), t0 + (12 + k) * step, 0.5, pan=-0.4 + 0.25 * k)
        # bass: 16th pulse, octave accents
        for s_ in range(16):
            nt = root + (12 if s_ % 8 in (3, 6) else 0)
            bass.put(pluck_bass(float(midi(nt)), step * 0.95), t0 + s_ * step, 0.55)
        # pad
        for tn in tri:
            pad.put(pad_voice(float(midi(tn + 12)), bar_s, detune=0.35, voices=3, lp_hz=1600, attack=0.5, release=0.9, seed=int(tn)), t0, 0.3)
        # arp (enters bar 2)
        if b >= 2:
            up = [tri[0], tri[1], tri[2], tri[0] + 12, tri[2], tri[1], tri[0] + 12, tri[1] + 12]
            for s_ in range(16):
                nt = up[s_ % 8] + 12
                arp.put(arp_voice(float(midi(nt))), t0 + s_ * step, 0.4 if s_ % 2 == 0 else 0.3, pan=-0.2 if s_ % 2 else 0.2)
        # lead (enters bar 4), octave up in the last section
        if b >= 4:
            for s_, nt, ln in lead_lines[b % 4]:
                nt2 = nt + (12 if b >= 8 else 0)
                lead.put(lead_voice(float(midi(nt2)), ln * step * 0.95), t0 + s_ * step, 0.8)
    arp.buf = pingpong(arp.buf, step * 3, fb=0.4)
    lead.buf = pingpong(lead.buf, step * 3, fb=0.35, taps=4)
    ir = reverb_ir(2.2, 0.8, seed=21, lp_hz=6000)
    snare_only = Bus(total)
    rev = apply_reverb(pad.buf * 0.5 + lead.buf * 0.6 + arp.buf * 0.3 + drums.buf * 0.18, ir)
    sc = sidechain(drums.n, kick_times, depth=0.6, release=0.2)
    mix = drums.buf + bass.buf * sc * 0.9 + (pad.buf + arp.buf + lead.buf) * sc + rev * 0.55
    mix = sat(mix, 1.1)
    return master(mix)


TRACKS = {"drift": drift_phonk, "dark": dark_phonk, "synthwave": synthwave}
