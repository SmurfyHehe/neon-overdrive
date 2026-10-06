"""Full-length, parameterized radio tracks. Each (seed, tempo, key, progression, motifs, plan) gives a distinct track."""
import numpy as np
import synth as S
import synth2 as T
from synth import Bus, midi, hp, lp, fade_out, reverb_ir, apply_reverb, pingpong, sidechain

# natural-minor degrees: name -> (semitones above tonic, triad quality)
DEG = {"i": (0, "m"), "III": (3, "M"), "iv": (5, "m"), "v": (7, "m"), "V": (7, "M"), "VI": (8, "M"), "VII": (10, "M")}


def make_chords(bass_tonic, tone_tonic, prog):
    out = []
    for nm in prog:
        d, q = DEG[nm]
        down = 12 if d >= 5 else 0
        root = bass_tonic + d - down
        tr = tone_tonic + d - down
        out.append((root, [tr, tr + (3 if q == "m" else 4), tr + 7]))
    return out


COW_MOTIFS = [
    {0: 3, 3: 3, 6: 2, 8: 1, 10: 2, 12: 3, 14: 4},
    {0: 4, 2: 3, 4: 3, 7: 2, 10: 3, 12: 2, 13: 3, 15: 4},
    {0: 3, 2: 4, 3: 3, 6: 5, 8: 4, 10: 3, 12: 2, 14: 3},
    {0: 5, 3: 4, 6: 3, 8: 4, 11: 3, 14: 2},
    {0: 3, 4: 3, 6: 4, 8: 3, 10: 5, 12: 4, 15: 3},
]
KICKS = [[0, 6, 10], [0, 3, 6, 10], [0, 5, 10], [0, 6, 8, 11], [0, 4, 7, 10]]
LEAD_TEMPLATES = [
    [(0, 0, 3), (3, 2, 3), (6, 1, 2), (8, 0, 6)],
    [(0, 2, 3), (3, 3, 3), (6, 2, 2), (8, 1, 4), (12, 0, 4)],
    [(0, 1, 2), (2, 2, 2), (4, 3, 4), (8, 2, 4), (12, 1, 4)],
    [(0, 3, 6), (8, 2, 3), (11, 1, 3), (14, 0, 2)],
]


def end_fade(buf, seconds=4.0):
    n = int(seconds * S.SR)
    buf = buf.copy()
    buf[-n:] *= np.linspace(1, 0, n)[:, None]
    return buf


def riser_before(plan, b):
    """True if bar b is the last-break-bar run feeding a drop; returns bars to cover (1 or 2) else 0."""
    if plan[b] != "B":
        return 0
    if b + 1 < len(plan) and plan[b + 1] == "D":
        return 2 if b > 0 and plan[b - 1] == "B" else 1
    return 0


def first_of_run(plan, b, lab):
    return plan[b] == lab and (b == 0 or plan[b - 1] != lab)


def drift3(seed=1, bpm=140, t=0, prog=("i", "VI", "VII", "i"), motifs=(0, 1), kicks=(0, 1),
           plan="IIVVVVVVVVBBDDDDDDDDVVVVBBDDDDDDDDDDDDOO"):
    r = np.random.default_rng(seed)
    beat = 60.0 / bpm
    step = beat / 4
    bar_s = beat * 4
    bars = len(plan)
    total = bars * bar_s + 3.0
    drums, bass, mel, pad, vox, fx = (Bus(total) for _ in range(6))
    bt = 30 + t - (12 if 30 + t > 36 else 0)
    chords = make_chords(bt, 66 + t, prog)
    kick_s = S.kick(f0=165, f1=46, body=0.15)
    cl = S.clap()
    sn = S.snare(noise_decay=0.09, tone=210)
    kick_times = []
    prev_root = None
    kp = [KICKS[kicks[0]], KICKS[kicks[1]]]
    for b in range(bars):
        t0 = b * bar_s
        lab = plan[b]
        root, tri = chords[b % len(chords)]
        tones = tri + [x + 12 for x in tri]
        for tn in tri:
            pad.put(S.pad_voice(float(midi(tn - 12)), bar_s, lp_hz=1100 + (500 if lab == "D" else 0), attack=0.4,
                                release=0.8, voices=3, seed=int(tn)), t0, 0.26 * (0.6 if lab == "O" else 1.0))
        if lab in "VD":
            pat = kp[b % 2]
            if lab == "D" and b % 4 == 3:
                pat = sorted(set(pat + [13]))
            for s_ in pat:
                tt = t0 + s_ * step
                drums.put(kick_s, tt, 1.0)
                kick_times.append(tt)
            for s_ in (4, 12):
                drums.put(cl, t0 + s_ * step, 0.8, pan=0.05)
                if lab == "D":
                    drums.put(sn, t0 + s_ * step, 0.45)
            dens = 2 if lab == "V" and (b % 4 < 2) else 2
            for s_ in range(0, 16, dens):
                drums.put(T.hat_h(r, bright=7800), t0 + s_ * step, 0.35 + 0.2 * r.random() + 0.1 * (s_ % 4 == 0),
                          pan=r.uniform(-0.35, 0.35))
            if b % 2 == 1:
                for k in range(4):
                    drums.put(T.hat_h(r), t0 + (12 + k) * step, 0.3 + 0.07 * k)
            if b % 4 == 3:
                for k in range(8):
                    drums.put(T.hat_h(r), t0 + (12 + k * 0.5) * step, 0.25 + 0.06 * k)
            drums.put(T.hat_h(r, open_=True), t0 + 14 * step, 0.35)
            for s_ in pat:
                d = step * (3 if s_ in (0, 10) else 2)
                gf = None
                if s_ == 0 and prev_root is not None and prev_root != root:
                    gf = float(midi(prev_root))
                elif s_ == 0:
                    gf = float(midi(root)) * 1.5
                bass.put(T.s808h(float(midi(root)), d * 1.1, glide_from=gf), t0 + s_ * step, 0.95)
            if b % 4 == 3:
                bass.put(T.s808h(float(midi(root + 7)), step * 2.5, glide_from=float(midi(root + 12))), t0 + 13 * step, 0.8)
            prev_root = root
        if lab == "B":
            m = {0: 3, 8: 1}
        elif lab == "O":
            m = {0: 3, 8: 1}
        else:
            m = COW_MOTIFS[motifs[1 if lab == "D" and (b // 2) % 2 else 0]]
        for s_, idx in m.items():
            mel.put(T.cowbell2(tones[idx] + 12), t0 + s_ * step, (0.4 if lab == "O" else 0.5) + 0.12 * (s_ % 4 == 0), pan=0.15)
        run_pos = 0
        k = b
        while k > 0 and plan[k - 1] == lab:
            k -= 1
            run_pos += 1
        if lab == "D" or (lab == "V" and run_pos >= 4):
            for s_, idx in ((0, 1), (6, 2), (11, 1)):
                vox.put(T.stab(float(midi(tones[idx])), 0.22), t0 + s_ * step, 0.38, pan=-0.25)
        if lab == "B":
            for s_, idx in ((0, 2), (4, 1), (8, 0), (12, 1)):
                vox.put(T.stab(float(midi(tones[idx])), 0.5, vowel="oh"), t0 + s_ * step, 0.35)
        rb = riser_before(plan, b)
        if rb:
            n = int(bar_s * rb * S.SR)
            ris = hp(np.random.default_rng(b).standard_normal(n), 1800) * np.linspace(0, 1, n) ** 2 * 0.3
            fx.put(ris, t0 - (bar_s if rb == 2 else 0))
        if first_of_run(plan, b, "D"):
            fx.put(T.impact(), t0, 0.7)
    ir = reverb_ir(1.3, 0.35, seed=4)
    rev = apply_reverb(mel.buf * 0.6 + vox.buf + drums.buf * 0.15, ir)
    sc = sidechain(drums.n, kick_times, depth=0.5, release=0.14)
    mix = drums.buf + bass.buf * 0.9 + (mel.buf * 0.9 + pad.buf * 0.8 + vox.buf) * sc + fx.buf + rev * 0.5
    return T.master2(end_fade(mix))


def dark3(seed=2, bpm=130, t=0, prog=("i", "i", "VI", "V"), kicks=(0, 1),
          plan="IIVVVVVVVVBBDDDDDDDDVVVVBBDDDDDDDDDDDDOO"):
    r = np.random.default_rng(seed)
    beat = 60.0 / bpm
    step = beat / 4
    bar_s = beat * 4
    bars = len(plan)
    total = bars * bar_s + 3.5
    drums, bass, mel, pad, vox, fx = (Bus(total) for _ in range(6))
    bt = 33 + t - (12 if 33 + t > 38 else 0)
    chords = make_chords(bt, 57 + t, prog)
    kick_s = S.kick(f0=135, f1=42, body=0.22, drive=2.8)
    sn = S.snare(noise_decay=0.15, tone=170)
    cl = S.clap()
    kick_times = []
    kp = [[0, 7, 10], [0, 7, 9, 14], [0, 6, 10], [0, 3, 7, 10], [0, 7, 11]]
    kp = [kp[kicks[0]], kp[kicks[1]]]
    vow = ("oo", "ah", "oh", "oo")
    for b in range(bars):
        t0 = b * bar_s
        lab = plan[b]
        root, tri = chords[b % len(chords)]
        for i, tn in enumerate(tri):
            pad.put(S.formant_choir(float(midi(tn + 12)), bar_s * 0.98, vowel=vow[(b + seed) % 4], seed=int(tn)), t0,
                    0.5 * (0.6 if lab == "O" else 1.0), pan=(-0.35, 0.0, 0.35)[i])
        pad.put(S.pad_voice(float(midi(tri[0] - 12)), bar_s, lp_hz=500, attack=0.6, release=1.0, voices=2, seed=1), t0, 0.35)
        if lab in "VD":
            pat = kp[b % 2]
            for s_ in pat:
                tt = t0 + s_ * step
                drums.put(kick_s, tt, 1.0)
                kick_times.append(tt)
            for s_ in (4, 12):
                drums.put(sn, t0 + s_ * step, 0.75)
                drums.put(cl, t0 + s_ * step, 0.35)
            for k in range(8):
                drums.put(T.hat_h(r, bright=6500), t0 + k * 2 * step, 0.28 + 0.15 * r.random())
            for k in range(3):
                drums.put(T.hat_h(r, bright=6500), t0 + 3 * beat + k * beat / 3, 0.4)
            if b % 4 == 3:
                for k in range(6):
                    drums.put(T.hat_h(r, bright=6500), t0 + 2.5 * beat + k * beat / 6, 0.32 + 0.05 * k)
            for s_ in pat:
                d = step * (4 if s_ == 0 else 3)
                gf = float(midi(root)) * 1.35 if s_ in (0, 7) else None
                bass.put(T.s808h(float(midi(root)), d, glide_from=gf, drive=5.5, decay_frac=0.9, harm=0.45),
                         t0 + s_ * step, 1.0)
        cpat = {0: 0, 6: 2, 10: 1} if lab in "VD" else {0: 0}
        for s_, idx in cpat.items():
            mel.put(T.cowbell2(tri[idx] + 12, dur=0.42, drive=3.0), t0 + s_ * step, 0.55 * (0.7 if lab == "O" else 1), pan=-0.2)
        if lab == "D" or (lab == "V" and b >= 6):
            for s_, idx in ((3, 1), (13, 2)):
                vox.put(T.stab(float(midi(tri[idx] + 12)), 0.3, vowel="oh"), t0 + s_ * step, 0.3, pan=0.3)
        if riser_before(plan, b) == 1 or riser_before(plan, b) == 2:
            n = int(bar_s * S.SR)
            fx.put(hp(np.random.default_rng(b + 15).standard_normal(n), 1500) * np.linspace(0, 1, n) ** 2 * 0.22, t0)
        if first_of_run(plan, b, "D"):
            fx.put(T.impact(), t0, 0.8)
    n = int(total * S.SR)
    nz = hp(np.random.default_rng(12).standard_normal(n), 3000) * 0.012
    crackle = (np.random.default_rng(13).random(n) > 0.9997) * np.random.default_rng(14).standard_normal(n) * 0.25
    bed = np.stack([nz + crackle, nz[::-1] + crackle[::-1]], axis=1)
    ir = reverb_ir(2.0, 0.7, seed=8, lp_hz=5000)
    rev = apply_reverb(pad.buf * 0.8 + mel.buf * 0.8 + vox.buf + drums.buf * 0.1, ir)
    sc = sidechain(drums.n, kick_times, depth=0.5, release=0.16)
    mix = drums.buf + bass.buf * 0.8 + (mel.buf + pad.buf + vox.buf) * 0.85 * sc + fx.buf + rev * 0.5 + bed[: drums.n]
    mix = lp(mix, 12000)
    return T.master2(end_fade(mix), wobble=1.0, low_gain=0.75)


def synth3(seed=3, bpm=108, t=0, prog=("i", "VI", "III", "VII"), lead_t=(0, 1),
           plan="IIVVVVVVBBDDDDDDDDVVVVBBDDDDDDDDOO"):
    r = np.random.default_rng(seed)
    beat = 60.0 / bpm
    step = beat / 4
    bar_s = beat * 4
    bars = len(plan)
    total = bars * bar_s + 3.5
    drums, bass, arp, pad, lead, fx = (Bus(total) for _ in range(6))
    bt = 33 + t - (12 if 33 + t > 38 else 0)
    chords = make_chords(bt, 57 + t, prog)
    kick_s = S.kick(f0=125, f1=52, body=0.2, drive=1.8)
    sn = T.gated_snare()
    kick_times = []
    arp_i = 0
    for b in range(bars):
        t0 = b * bar_s
        lab = plan[b]
        root, tri = chords[b % len(chords)]
        play_drums = lab in "VD" or lab == "I" or lab == "O"
        for k in range(4):
            if lab != "B":
                drums.put(kick_s, t0 + k * beat, 0.95 * (0.6 if lab == "O" else 1.0))
                kick_times.append(t0 + k * beat)
        if lab in "VD":
            for s_ in (4, 12):
                drums.put(sn, t0 + s_ * step, 0.85)
        for s_ in range(16):
            if lab == "B":
                continue
            if s_ % 4 == 2:
                drums.put(T.hat_h(r, open_=True), t0 + s_ * step, 0.26)
            elif lab in "VD":
                drums.put(T.hat_h(r), t0 + s_ * step, 0.12 + 0.08 * r.random())
        if lab == "D" and b % 4 == 3:
            for k, f in enumerate((230, 185, 150, 118)):
                n = int(0.28 * S.SR)
                tt = np.arange(n) / S.SR
                tom = np.sin(2 * np.pi * f * tt * (1 + 0.2 * np.exp(-tt / 0.04))) * np.exp(-tt / 0.1)
                drums.put(fade_out(tom), t0 + (12 + k) * step, 0.55, pan=-0.45 + 0.3 * k)
        if lab != "B":
            for s_ in range(16):
                nt = root + (12 if s_ % 8 in (3, 6) else 0)
                bass.put(T.bass2(float(midi(nt)), step * 0.95), t0 + s_ * step, 0.6)
        for tn in tri:
            pad.put(S.pad_voice(float(midi(tn + 12)), bar_s, detune=0.35, voices=3, lp_hz=1500 + 60 * min(b, 24),
                                attack=0.5, release=0.9, seed=int(tn)), t0, 0.3)
        if lab in "VBD":
            up = [tri[0], tri[1], tri[2], tri[0] + 12, tri[2], tri[1], tri[0] + 12, tri[1] + 12]
            cut = 1800 + min(b, 24) * 150
            for s_ in range(16):
                nt = up[s_ % 8] + 12
                arp.put(S.arp_voice(float(midi(nt)), lp_hz=cut), t0 + s_ * step, 0.4 if s_ % 2 == 0 else 0.3,
                        pan=-0.25 if s_ % 2 else 0.25)
        if lab == "D":
            pool = [x + 12 * o for o in (5, 6) for x in sorted(tri)]
            pool = sorted(p for p in pool if 74 <= p + 0 <= 96) or [tri[0] + 72 - 12]
            tmpl = LEAD_TEMPLATES[(seed + b // 4) % len(LEAD_TEMPLATES)]
            for s_, idx, ln in tmpl:
                nt = pool[min(idx + lead_t[(b // 8) % 2], len(pool) - 1)]
                lead.put(S.lead_voice(float(midi(nt)), ln * step * 0.95), t0 + s_ * step, 0.8)
        if riser_before(plan, b):
            n = int(bar_s * S.SR)
            fx.put(hp(np.random.default_rng(b).standard_normal(n), 2500) * np.linspace(0, 1, n) ** 2 * 0.18, t0)
    arp.buf = pingpong(arp.buf, step * 3, fb=0.4)
    lead.buf = pingpong(lead.buf, step * 3, fb=0.35, taps=4)
    ir = reverb_ir(2.2, 0.8, seed=21, lp_hz=6000)
    rev = apply_reverb(pad.buf * 0.5 + lead.buf * 0.6 + arp.buf * 0.3 + drums.buf * 0.18, ir)
    sc = sidechain(drums.n, kick_times, depth=0.6, release=0.2)
    mix = drums.buf + bass.buf * sc * 0.9 + (pad.buf + arp.buf + lead.buf) * sc + fx.buf + rev * 0.55
    return T.master2(end_fade(mix), low_gain=0.85)
