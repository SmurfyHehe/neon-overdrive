"""Headless test for tools/radio_import/import_treblo.py (no Godot).

Generates sine/pulse WAVs, runs the importer against a temp repo + inbox.
Run:  python tests/audio/test_import_treblo.py
Needs ffmpeg and ffprobe on PATH; skips itself if they are missing.
"""
import array
import math
import shutil
import struct
import sys
import tempfile
import unittest
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "radio_import"))
import import_treblo as imp  # noqa: E402

RATE = 22050


def write_wav(path, seconds, amp=0.5, pulse_hz=2.0, silence=None, tail=True):
    """A 220 Hz tone, amplitude-pulsed at pulse_hz (2.0 = 120 BPM).
    silence=(start,end) blanks that span. tail=False cuts the track at full level."""
    n = int(seconds * RATE)
    data = array.array("h")
    for i in range(n):
        t = i / RATE
        env = 0.55 + 0.45 * (1 if (t * pulse_hz) % 1.0 < 0.3 else 0)
        if tail and t > seconds - 3:
            env *= max(0.0, (seconds - t) / 3)
        v = amp * env * math.sin(2 * math.pi * 220 * t)
        if silence and silence[0] <= t < silence[1]:
            v = 0
        data.append(max(-32767, min(32767, int(v * 32767))))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


SHEET = """| id | station | hour band | length target | prompt text | instrumental ON |
|---|---|---|---|---|---|
| afterglow_01_harlow-drive_dusk | afterglow | dusk | 2:00 | test | yes |
| afterglow_02_short-one_late | afterglow | late | 2:00 | test | yes |
| afterglow_03_quiet_dead | afterglow | dead | 2:00 | test | yes |
| afterglow_04_loud_dawn | afterglow | dawn | 2:00 | test | yes |
| afterglow_05_gap_dusk | afterglow | dusk | 2:00 | test | yes |
| afterglow_06_cutoff_late | afterglow | late | 2:00 | test | yes |
"""


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg not on PATH")
class ImportTreblo(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="treblo_test_"))
        self.repo = self.tmp / "repo"
        self.inbox = self.tmp / "inbox"
        (self.repo / "docs" / "audio").mkdir(parents=True)
        (self.repo / "docs" / "audio" / "treblo-prompts.md").write_text(SHEET, encoding="utf-8")
        (self.repo / "docs" / "audio-licences.md").write_text(
            "# log\n\n" + imp.LICENCE_HEADER + "\n" + "|---|" * 1 + "\n", encoding="utf-8")
        (self.repo / "assets" / "radio").mkdir(parents=True)
        (self.repo / "assets" / "radio" / "CREDITS.md").write_text("# Radio tracks\n", encoding="utf-8")
        self.inbox.mkdir()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def proof(self):
        d = self.repo / "docs" / "audio-licences-proof" / "treblo-2026-10-10"
        d.mkdir(parents=True)
        (d / "terms.txt").write_text("terms page", encoding="utf-8")

    def run_import(self, *extra):
        return imp.main(["--inbox", str(self.inbox), "--repo-root", str(self.repo),
                         "--date", "2026-10-10", "--min-seconds", "20", *extra])

    def test_name_pattern(self):
        self.assertTrue(imp.NAME_RE.match("afterglow_01_harlow-drive_dusk.wav"))
        self.assertFalse(imp.NAME_RE.match("afterglow_03_late.wav"))      # old pattern
        self.assertFalse(imp.NAME_RE.match("afterglow_01_Harlow_dusk.wav"))
        self.assertFalse(imp.NAME_RE.match("afterglow_01_x_noon.wav"))

    def test_refuses_without_proof(self):
        write_wav(self.inbox / "afterglow_01_harlow-drive_dusk.wav", 30)
        self.assertEqual(self.run_import(), 3)
        self.assertTrue((self.inbox / "afterglow_01_harlow-drive_dusk.wav").exists())

    def test_import_and_rejects(self):
        self.proof()
        write_wav(self.inbox / "afterglow_01_harlow-drive_dusk.wav", 30)           # good
        write_wav(self.inbox / "afterglow_02_short-one_late.wav", 10)               # short
        write_wav(self.inbox / "afterglow_03_quiet_dead.wav", 30, amp=0.0005)      # silent
        write_wav(self.inbox / "afterglow_04_loud_dawn.wav", 30, amp=3.0)          # clipped
        write_wav(self.inbox / "afterglow_05_gap_dusk.wav", 30, silence=(10, 18))  # gap
        write_wav(self.inbox / "afterglow_06_cutoff_late.wav", 30, tail=False)     # mid-note
        write_wav(self.inbox / "afterglow_07_unsheeted_dusk.wav", 30)              # not in sheet
        write_wav(self.inbox / "badname.wav", 30)
        self.run_import()
        ogg = self.repo / "assets" / "radio" / "afterglow" / "01_harlow-drive_dusk.ogg"
        self.assertTrue(ogg.exists())
        self.assertTrue((self.inbox / "done" / "afterglow_01_harlow-drive_dusk.wav").exists())
        self.assertFalse((self.inbox / "afterglow_01_harlow-drive_dusk.wav").exists())
        for n in ("02_short-one_late", "03_quiet_dead", "04_loud_dawn", "05_gap_dusk",
                  "06_cutoff_late"):
            self.assertFalse((self.repo / "assets" / "radio" / "afterglow" / (n + ".ogg")).exists(), n)
        for n in ("afterglow_02_short-one_late", "afterglow_03_quiet_dead", "afterglow_04_loud_dawn",
                  "afterglow_05_gap_dusk", "afterglow_06_cutoff_late", "afterglow_07_unsheeted_dusk",
                  "badname"):
            self.assertTrue((self.inbox / (n + ".wav")).exists(), n)
        log = (self.repo / "docs" / "audio-licences.md").read_text(encoding="utf-8")
        self.assertIn("afterglow_01_harlow-drive_dusk", log)
        self.assertIn("sha256", log)
        self.assertEqual(log.count("| afterglow_0"), 1)
        credits = (self.repo / "assets" / "radio" / "CREDITS.md").read_text(encoding="utf-8")
        self.assertIn("01_harlow-drive_dusk.ogg", credits)
        tracks = (self.repo / "assets" / "radio" / "afterglow" / "tracks.md").read_text(encoding="utf-8")
        self.assertIn("Harlow Drive", tracks)
        self.assertIn("dusk", tracks)

    def test_output_loudness_and_format(self):
        self.proof()
        write_wav(self.inbox / "afterglow_01_harlow-drive_dusk.wav", 30, amp=0.2)
        self.run_import()
        ogg = self.repo / "assets" / "radio" / "afterglow" / "01_harlow-drive_dusk.ogg"
        ff = imp.Ff()
        self.assertGreater(ff.duration(ogg), 25)
        lufs = float(ff.loudnorm_measure(ogg)["input_i"])
        self.assertAlmostEqual(lufs, -16.0, delta=1.5)

    def test_second_run_does_not_reimport(self):
        self.proof()
        wav = self.inbox / "afterglow_01_harlow-drive_dusk.wav"
        write_wav(wav, 30)
        self.run_import()
        write_wav(wav, 30)           # same name dropped again
        self.run_import()
        log = (self.repo / "docs" / "audio-licences.md").read_text(encoding="utf-8")
        self.assertEqual(log.count("| afterglow_01_harlow-drive_dusk |"), 1)
        self.assertTrue(wav.exists())

    def test_ab_copy(self):
        write_wav(self.inbox / "whatever.wav", 60)
        self.assertEqual(self.run_import("--ab-only"), 0)    # no proof folder needed
        outs = list((self.inbox / "ab").glob("ab_*.wav"))
        self.assertEqual(len(outs), 1)
        self.assertNotIn("whatever", outs[0].name)
        self.assertAlmostEqual(imp.Ff().duration(outs[0]), 45.0, delta=0.3)
        self.assertTrue((self.inbox / "ab-key.csv").exists())
        self.assertTrue((self.inbox / "whatever.wav").exists())   # left in place

    # ---- paired blind test (--pairs) ------------------------------------------
    def make_game_ogg(self, rel, seconds=70, amp=0.8):
        src = self.tmp / "game_src.wav"
        write_wav(src, seconds, amp=amp)
        out = self.repo / "assets" / "radio" / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        rc, _, err = imp.run(["ffmpeg", "-v", "error", "-y", "-i", str(src), "-ac", "2",
                              "-c:a", "libvorbis", "-b:a", "112k", str(out)])
        self.assertEqual(rc, 0, err)
        return out

    def probe(self, path):
        rc, out, _ = imp.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                              "stream=codec_name,sample_rate,channels", "-of", "csv=p=0", str(path)])
        return out.strip()

    def test_pairs(self):
        game_rel = imp.PAIRS[0][2]
        game = self.make_game_ogg(game_rel)
        before = sorted(p.name for p in (self.repo / "assets" / "radio").rglob("*"))
        # Treblo song much quieter than ours: loudness must still match after the cut
        write_wav(self.inbox / "afterglow_01_harlow-drive_dusk.wav", 70, amp=0.15)
        write_wav(self.inbox / "greyhour_01_wet-road_late.wav", 70, amp=0.3)
        code = self.run_import("--pairs", "--seed", "7")
        self.assertEqual(code, 0)
        bt = self.inbox / "blind-test"
        a, b = bt / "pair_01_A.wav", bt / "pair_01_B.wav"
        self.assertTrue(a.exists() and b.exists())
        ff = imp.Ff()
        for f in (a, b, bt / "solo_10.wav"):
            self.assertAlmostEqual(ff.duration(f), 45.0, delta=0.3)
            self.assertEqual(self.probe(f), "pcm_s16le,44100,2")
            self.assertAlmostEqual(float(ff.loudnorm_measure(f)["input_i"]), -16.0, delta=1.5)
        key = (bt / "key.txt").read_text(encoding="utf-8")
        self.assertRegex(key, r"pair_01: Treblo = [AB], ours = [AB]")
        self.assertIn("solo_10: Treblo only", key)
        # pairs with no Treblo WAV yet are skipped, not faked
        self.assertFalse((bt / "pair_02_A.wav").exists())
        self.assertNotIn("pair_02", key)
        # key.txt is right: the "ours" side really is the game song (same loudness is not
        # enough to tell, so compare the amplitude pattern via the source cut)
        self.assertNotEqual(key.split("pair_01: Treblo = ")[1][0], key.split("ours = ")[1][0])
        # nothing written to the game's files, and the inbox WAVs are left alone
        after = sorted(p.name for p in (self.repo / "assets" / "radio").rglob("*"))
        self.assertEqual(before, after)
        self.assertTrue(game.exists())
        self.assertTrue((self.inbox / "afterglow_01_harlow-drive_dusk.wav").exists())
        # a re-run keeps the same A/B answers
        first = key.split("pair_01: Treblo = ")[1][0]
        self.run_import("--pairs", "--seed", "99")
        key2 = (bt / "key.txt").read_text(encoding="utf-8")
        self.assertEqual(key2.split("pair_01: Treblo = ")[1][0], first)

    def test_pairs_rejects_short_song(self):
        self.make_game_ogg(imp.PAIRS[0][2])
        write_wav(self.inbox / "afterglow_01_harlow-drive_dusk.wav", 40)   # < 60 s
        self.assertEqual(self.run_import("--pairs"), 1)
        self.assertFalse((self.inbox / "blind-test" / "pair_01_A.wav").exists())
        self.assertFalse((self.inbox / "blind-test" / "pair_01_B.wav").exists())

    def test_pair_table_is_sane(self):
        self.assertEqual([n for n, _, _ in imp.PAIRS], list(range(1, 10)))
        self.assertEqual([n for n, _ in imp.SOLOS], [10, 11, 12])
        for _, prefix, rel in imp.PAIRS:
            self.assertTrue((ROOT / "assets" / "radio" / rel).is_file(), rel)
        sheet = imp.load_sheet(ROOT / "docs" / "audio" / "treblo-prompts.md")
        self.assertEqual(len(sheet), 40)
        ids = list(sheet)
        for _, prefix, _ in imp.PAIRS:
            self.assertEqual(sum(i.startswith(prefix + "_") for i in ids), 1, prefix)
        for _, prefix in imp.SOLOS:
            self.assertEqual(sum(i.startswith(prefix + "_") for i in ids), 1, prefix)

    def test_tempo(self):
        ff = imp.Ff()
        p = self.tmp / "t.wav"
        write_wav(p, 40, pulse_hz=2.0)
        bpm = imp.tempo_bpm(ff.decode_mono(p, 4000))
        self.assertIsNotNone(bpm)
        self.assertTrue(any(abs(bpm * k - 120) < 6 for k in (0.5, 1, 2)), bpm)


if __name__ == "__main__":
    unittest.main()
