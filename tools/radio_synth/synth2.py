"""Lap 2: better mix balance, laptop-speaker-friendly bass, real song structure."""
import numpy as np
from synth import *  # noqa
import synth as S


# ---------- mastering ----------
def master2(mix, peak=0.89, low_gain=0.8, air_gain=1.0, wobble=0.0):
    mix = hp(mix, 32, 4)
    low = lp(mix, 140, 4)
    rest = mix - low
    air = hp(mix, 5500, 2)
    mix = low * low_gain + rest + air * air_gain
    if wobble > 0:  # tape wobble: slow pitch drift via fractional delay
        n = len(mix)
        idx = np.arange(n) + wobble * SR * 0.0008 * np.sin(2 * np.pi * 0.55 * np.arange(n) / SR) \
            + wobble * SR * 0.0003 * np.sin(2 * np.pi * 3.1 * np.arange(n) / SR)
        idx = np.clip(idx, 0, n - 1)
        mix = np.stack([np.interp(idx, np.arange(n), mix[:, c]) for c in range(2)], axis=1)
    mix = np.tanh(mix * 1.15)
    mix /= max(1e-9, np.max(np.abs(mix)))
    return mix * peak


# ---------- instruments ----------
def s808h(freq, dur, glide_from=None, drive=4.5, decay_frac=0.8, harm=0.38):
    """808 with a parallel harmonic layer so it still reads on laptop speakers."""
    x = S.s808(freq, dur, glide_from=glide_from, drive=drive, decay_frac=decay_frac)
    h = hp(sat(x * 3.0, 7.0), 140, 2) * harm
    return fade_out(x + h, 20)


def cowbell2(note, dur=0.34, drive=2.6):
    f1 = float(midi(note))
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for ratio, g in ((1.0, 1.0), (800 / 540, 1.0), (1.48 * 1.5, 0.35)):
        x += g * square_from_phase(2 * np.pi * f1 * ratio * t)
    x = bp(x, f1 * 1.1, f1 * 4.0)
    env = 0.75 * np.exp(-t / 0.028) + 0.25 * np.exp(-t / 0.16)
    body = np.sin(2 * np.pi * f1 * 0.5 * t) * np.exp(-t / 0.05) * 0.35
    return fade_out(sat((x * 0.8 + body) * env, drive), 20)


def stab(freq, dur=0.28, vowel="ah"):
    n = int((dur + 0.25) * SR)
    t = np.arange(n) / SR
    forms = {"ah": (800, 1150, 2800), "oh": (450, 800, 2830), "ee": (270, 2300, 3000)}[vowel]
    src = np.zeros(n)
    for dt in (-0.06, 0.0, 0.07):
        src += saw_from_phase(2 * np.pi * freq * (1 + dt * 0.08) * t)
    out = np.zeros(n)
    for i, fc in enumerate(forms):
        out += bp(src, fc * 0.88, fc * 1.12, 2) * (1.0, 0.65, 0.3)[i]
    env = np.minimum(1, t / 0.01) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.06))
    return sat(out * env * 0.9, 2.0) * 0.5


def impact(dur=1.4):
    n = int(dur * SR)
    t = np.arange(n) / SR
    sub = np.sin(2 * np.pi * (48 + 40 * np.exp(-t / 0.25)) * t) * np.exp(-t / 0.5)
    nz = lp(np.random.default_rng(4).standard_normal(n), 2500) * np.exp(-t / 0.35) * 0.5
    return fade_out(sat(sub + nz, 1.6), 40)


def gated_snare():
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    r = np.random.default_rng(31)
    nz = bp(r.standard_normal(n), 700, 8000) * 0.9
    tone = np.sin(2 * np.pi * 190 * t * (1 + 0.25 * np.exp(-t / 0.02))) * np.exp(-t / 0.09)
    gate = np.where(t < 0.2, 1.0, np.exp(-(t - 0.2) / 0.012))
    body = nz * (0.45 + 0.55 * np.exp(-t / 0.09)) * gate + tone * 0.8
    return fade_out(sat(body, 1.5), 15)


def bass2(freq, dur, lp_hz=800):
    x = S.pluck_bass(freq, dur, lp_hz=lp_hz, drive=1.7)
    n = len(x)
    t = np.arange(n) / SR
    sub = np.sin(2 * np.pi * freq * t) * np.exp(-t / (dur * 1.2)) * 0.6
    return fade_out(x + sub, 8)


def hat_h(r, open_=False, bright=7500, vel=1.0):
    h = S.hat(open_=open_, seed=int(r.integers(0, 9999)), bright=bright) * vel
    lag = int(r.uniform(0, 0.005) * S.SR)  # late-only micro-timing so hats don't machine-gun
    return np.concatenate([np.zeros(lag), h]) if lag else h


# ---------- tracks ----------
def drift_phonk2(seed=1, bpm=140, bars=16):
    r = np.random.default_rng(seed)
    beat = 60.0 / bpm
    step = beat / 4
    bar_s = beat * 4
    total = bars * bar_s + 3.0
    drums, bass, mel, pad, vox, fx = Bus(total), Bus(total), Bus(total), Bus(total), Bus(total), Bus(total)
    chords = [(30, [66, 69, 73]), (26, [62, 66, 69]), (28, [64, 68, 71]), (30, [66, 69, 73])]
    motifs = [
        {0: 3, 3: 3, 6: 2, 8: 1, 10: 2, 12: 3, 14: 4},
        {0: 4, 2: 3, 4: 3, 7: 2, 10: 3, 12: 2, 13: 3, 15: 4},
    ]
    kick_s = S.kick(f0=165, f1=46, body=0.15)
    cl = S.clap()
    sn = S.snare(noise_decay=0.09, tone=210)
    kick_times = []
    prev_root = None
    INTRO, VERSE, BREAK, DROP = range(4)

    def section(b):
        return INTRO if b < 2 else VERSE if b < 8 else BREAK if b < 10 else DROP

    for b in range(bars):
        t0 = b * bar_s
        root, tri = chords[b % 4]
        tones = tri + [x + 12 for x in tri]
        sec = section(b)
        # pad
        for tn in tri:
            pad.put(S.pad_voice(float(midi(tn - 12)), bar_s, lp_hz=1100 + (500 if sec == DROP else 0), attack=0.4,
                                release=0.8, voices=3, seed=int(tn)), t0, 0.26)
        if sec in (VERSE, DROP):
            kpat = [0, 6, 10] if b % 2 == 0 else [0, 3, 6, 10]
            if sec == DROP and b % 4 == 3:
                kpat = [0, 3, 6, 10, 13]
            for s_ in kpat:
                tt = t0 + s_ * step
                drums.put(kick_s, tt, 1.0)
                kick_times.append(tt)
            for s_ in (4, 12):
                drums.put(cl, t0 + s_ * step, 0.8, pan=0.05)
                if sec == DROP:
                    drums.put(sn, t0 + s_ * step, 0.45)
            # swung hats with velocity variation and rolls
            for s_ in range(0, 16, 2):
                sw = 0.0
                drums.put(hat_h(r, bright=7800), t0 + (s_ + sw) * step, 0.35 + 0.2 * r.random() + 0.1 * (s_ % 4 == 0),
                          pan=r.uniform(-0.35, 0.35))
            if b % 2 == 1:
                for k in range(4):
                    drums.put(hat_h(r), t0 + (12 + k) * step + 0.0, 0.3 + 0.07 * k)
            if b % 4 == 3:
                for k in range(8):
                    drums.put(hat_h(r), t0 + (12 + k * 0.5) * step, 0.25 + 0.06 * k)
            drums.put(hat_h(r, open_=True), t0 + 14 * step, 0.35)
            # 808 with slides
            for s_ in kpat:
                d = step * (3 if s_ in (0, 10) else 2)
                gf = None
                if s_ == 0 and prev_root is not None and prev_root != root:
                    gf = float(midi(prev_root))
                elif s_ == 0:
                    gf = float(midi(root)) * 1.5
                bass.put(s808h(float(midi(root)), d * 1.1, glide_from=gf), t0 + s_ * step, 0.95)
            if b % 4 == 3:
                bass.put(s808h(float(midi(root + 7)), step * 2.5, glide_from=float(midi(root + 12))), t0 + 13 * step, 0.8)
            prev_root = root
        # cowbell
        if sec == BREAK:
            m = {0: 3, 8: 1}
        else:
            m = motifs[1 if sec == DROP and (b // 2) % 2 else 0]
        for s_, idx in m.items():
            mel.put(cowbell2(tones[idx] + 12), t0 + s_ * step, 0.5 + 0.12 * (s_ % 4 == 0), pan=0.15)
        # vocal-style stabs on accents
        if sec in (DROP,) or (sec == VERSE and b >= 6):
            for s_, idx in ((0, 1), (6, 2), (11, 1)):
                vox.put(stab(float(midi(tones[idx])), 0.22), t0 + s_ * step, 0.38, pan=-0.25)
        if sec == BREAK:
            for s_, idx in ((0, 2), (4, 1), (8, 0), (12, 1)):
                vox.put(stab(float(midi(tones[idx])), 0.5, vowel="oh"), t0 + s_ * step, 0.35)
        # riser into the drop + impact on the drop
        if b == 8:
            n = int(bar_s * 2 * SR)
            ris = hp(np.random.default_rng(9).standard_normal(n), 1800) * np.linspace(0, 1, n) ** 2 * 0.3
            fx.put(ris, t0)
        if b == 10 or b == 2:
            fx.put(impact(), t0, 0.7)
    ir = reverb_ir(1.3, 0.35, seed=4)
    rev = apply_reverb(mel.buf * 0.6 + vox.buf * 1.0 + cl_sum(drums) * 0.15, ir)
    sc = sidechain(drums.n, kick_times, depth=0.5, release=0.14)
    mix = drums.buf + bass.buf * 0.9 + (mel.buf * 0.9 + pad.buf * 0.8 + vox.buf) * sc + fx.buf + rev * 0.5
    return master2(mix)


def cl_sum(bus):
    return bus.buf


def dark_phonk2(seed=2, bpm=130, bars=16):
    r = np.random.default_rng(seed)
    beat = 60.0 / bpm
    step = beat / 4
    bar_s = beat * 4
    total = bars * bar_s + 3.5
    drums, bass, mel, pad, vox, fx = Bus(total), Bus(total), Bus(total), Bus(total), Bus(total), Bus(total)
    chords = [(33, [57, 60, 64]), (33, [57, 60, 64]), (29, [53, 57, 60]), (28, [52, 56, 59])]
    kick_s = S.kick(f0=135, f1=42, body=0.22, drive=2.8)
    sn = S.snare(noise_decay=0.15, tone=170)
    cl = S.clap()
    kick_times = []
    for b in range(bars):
        t0 = b * bar_s
        root, tri = chords[b % 4]
        intro = b < 2
        brk = b in (10, 11)
        main = not intro and not brk
        vowel = ("oo", "ah", "oh", "oo")[b % 4]
        for i, tn in enumerate(tri):
            pad.put(S.formant_choir(float(midi(tn + 12)), bar_s * 0.98, vowel=vowel, seed=int(tn)), t0, 0.5,
                    pan=(-0.35, 0.0, 0.35)[i])
        # low drone pad for weight
        pad.put(S.pad_voice(float(midi(tri[0] - 12)), bar_s, lp_hz=500, attack=0.6, release=1.0, voices=2, seed=1), t0, 0.35)
        if main:
            kpat = [0, 7, 10] if b % 2 == 0 else [0, 7, 9, 14]
            for s_ in kpat:
                tt = t0 + s_ * step
                drums.put(kick_s, tt, 1.0)
                kick_times.append(tt)
            for s_ in (4, 12):
                drums.put(sn, t0 + s_ * step, 0.75)
                drums.put(cl, t0 + s_ * step, 0.35)
            for k in range(8):
                drums.put(hat_h(r, bright=6500), t0 + k * 2 * step, 0.28 + 0.15 * r.random())
            for k in range(3):
                drums.put(hat_h(r, bright=6500), t0 + 3 * beat + k * beat / 3, 0.4)
            if b % 4 == 3:
                for k in range(6):
                    drums.put(hat_h(r, bright=6500), t0 + 2.5 * beat + k * beat / 6, 0.32 + 0.05 * k)
            for s_ in kpat:
                d = step * (4 if s_ == 0 else 3)
                gf = float(midi(root)) * 1.35 if s_ in (0, 7) else None
                bass.put(s808h(float(midi(root)), d, glide_from=gf, drive=5.5, decay_frac=0.9, harm=0.45),
                         t0 + s_ * step, 1.0)
        # sparse cowbell + bell-like dark stabs
        pat = {0: 0, 6: 2, 10: 1} if not brk else {0: 0}
        for s_, idx in pat.items():
            mel.put(cowbell2(tri[idx] + 12, dur=0.42, drive=3.0), t0 + s_ * step, 0.55, pan=-0.2)
        if main and b >= 4:
            for s_, idx in ((3, 1), (13, 2)):
                vox.put(stab(float(midi(tri[idx] + 12)), 0.3, vowel="oh"), t0 + s_ * step, 0.3, pan=0.3)
        if b == 10:
            n = int(bar_s * 2 * SR)
            fx.put(hp(np.random.default_rng(15).standard_normal(n), 1500) * np.linspace(0, 1, n) ** 2 * 0.22, t0)
        if b == 12 or b == 2:
            fx.put(impact(), t0, 0.8)
    n = int(total * SR)
    nz = hp(np.random.default_rng(12).standard_normal(n), 3000) * 0.012
    crackle = (np.random.default_rng(13).random(n) > 0.9997) * np.random.default_rng(14).standard_normal(n) * 0.25
    bed = np.stack([nz + crackle, nz[::-1] + crackle[::-1]], axis=1)
    ir = reverb_ir(2.0, 0.7, seed=8, lp_hz=5000)
    rev = apply_reverb(pad.buf * 0.8 + mel.buf * 0.8 + vox.buf + drums.buf * 0.1, ir)
    sc = sidechain(drums.n, kick_times, depth=0.5, release=0.16)
    mix = drums.buf + bass.buf * 0.8 + (mel.buf + pad.buf + vox.buf) * 0.85 * sc + fx.buf + rev * 0.5 + bed[: drums.n]
    mix = lp(mix, 12000)
    return master2(mix, wobble=1.0, low_gain=0.75)


def synthwave2(seed=3, bpm=108, bars=12):
    r = np.random.default_rng(seed)
    beat = 60.0 / bpm
    step = beat / 4
    bar_s = beat * 4
    total = bars * bar_s + 3.5
    drums, bass, arp, pad, lead, fx = Bus(total), Bus(total), Bus(total), Bus(total), Bus(total), Bus(total)
    chords = [(33, [57, 60, 64]), (29, [53, 57, 60]), (36, [60, 64, 67]), (31, [55, 59, 62])]
    phrases = {
        0: [(0, 81, 3), (3, 84, 3), (6, 83, 2), (8, 81, 6)],
        1: [(0, 81, 3), (3, 84, 3), (6, 86, 2), (8, 84, 6)],
        2: [(0, 84, 3), (3, 88, 3), (6, 86, 2), (8, 84, 6)],
        3: [(0, 83, 3), (3, 86, 3), (6, 88, 2), (8, 86, 4), (12, 83, 4)],
    }
    kick_s = S.kick(f0=125, f1=52, body=0.2, drive=1.8)
    sn = gated_snare()
    kick_times = []
    for b in range(bars):
        t0 = b * bar_s
        root, tri = chords[b % 4]
        intro = b < 2
        for k in range(4):
            drums.put(kick_s, t0 + k * beat, 0.95)
            kick_times.append(t0 + k * beat)
        if not intro:
            for s_ in (4, 12):
                drums.put(sn, t0 + s_ * step, 0.85)
        for s_ in range(16):
            if s_ % 4 == 2:
                drums.put(hat_h(r, open_=True), t0 + s_ * step, 0.26)
            elif not intro:
                drums.put(hat_h(r), t0 + s_ * step, 0.12 + 0.08 * r.random())
        if b % 4 == 3 and not intro:
            for k, f in enumerate((230, 185, 150, 118)):
                n = int(0.28 * SR)
                tt = np.arange(n) / SR
                tom = np.sin(2 * np.pi * f * tt * (1 + 0.2 * np.exp(-tt / 0.04))) * np.exp(-tt / 0.1)
                drums.put(fade_out(tom), t0 + (12 + k) * step, 0.55, pan=-0.45 + 0.3 * k)
        for s_ in range(16):
            nt = root + (12 if s_ % 8 in (3, 6) else 0)
            bass.put(bass2(float(midi(nt)), step * 0.95), t0 + s_ * step, 0.6)
        for tn in tri:
            pad.put(S.pad_voice(float(midi(tn + 12)), bar_s, detune=0.35, voices=3, lp_hz=1500 + 90 * b, attack=0.5,
                                release=0.9, seed=int(tn)), t0, 0.3)
        if b >= 2:
            up = [tri[0], tri[1], tri[2], tri[0] + 12, tri[2], tri[1], tri[0] + 12, tri[1] + 12]
            cut = 1800 + (b - 2) * 380  # filter opens over the track
            for s_ in range(16):
                nt = up[s_ % 8] + 12
                arp.put(S.arp_voice(float(midi(nt)), lp_hz=cut), t0 + s_ * step, 0.4 if s_ % 2 == 0 else 0.3,
                        pan=-0.25 if s_ % 2 else 0.25)
        if b >= 4:
            for s_, nt, ln in phrases[b % 4]:
                nt2 = nt + (12 if b >= 8 else 0)
                lead.put(S.lead_voice(float(midi(nt2)), ln * step * 0.95), t0 + s_ * step, 0.8)
        if b == 4 or b == 8:
            n = int(bar_s * SR)
            fx.put(hp(np.random.default_rng(b).standard_normal(n), 2500) * np.linspace(0, 1, n) ** 2 * 0.18, t0 - bar_s if b else 0)
    arp.buf = pingpong(arp.buf, step * 3, fb=0.4)
    lead.buf = pingpong(lead.buf, step * 3, fb=0.35, taps=4)
    ir = reverb_ir(2.2, 0.8, seed=21, lp_hz=6000)
    rev = apply_reverb(pad.buf * 0.5 + lead.buf * 0.6 + arp.buf * 0.3 + drums.buf * 0.18, ir)
    sc = sidechain(drums.n, kick_times, depth=0.6, release=0.2)
    mix = drums.buf + bass.buf * sc * 0.9 + (pad.buf + arp.buf + lead.buf) * sc + fx.buf + rev * 0.55
    return master2(mix, low_gain=0.85)


TRACKS2 = {"drift": drift_phonk2, "dark": dark_phonk2, "synthwave": synthwave2}
