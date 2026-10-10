"""Headless test for tools/radio_import/treblo_batch.py (no Godot, no network, no key).

Runs the batch against a fake Treblo API on 127.0.0.1.
Run:  python tests/audio/test_treblo_batch.py
Needs ffmpeg and ffprobe on PATH; skips itself if they are missing.
"""
import csv
import json
import os
import shutil
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "radio_import"))
sys.path.insert(0, str(ROOT / "tests" / "audio"))
import treblo_batch as tb  # noqa: E402
import test_import_treblo as ti  # noqa: E402

FAKE_KEY = "test-key-NOT-REAL-12345"


class Fake(BaseHTTPRequestHandler):
    wav_bytes = b""
    posts = []
    fail_first = False
    count = 0

    def log_message(self, *a):
        pass

    def _send(self, obj, ctype="application/json"):
        data = obj if isinstance(obj, bytes) else json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        assert self.headers.get("Authorization") == "Bearer " + FAKE_KEY
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        Fake.posts.append((self.path, body))
        Fake.count += 1
        self._send({"task_id": "task-%d" % Fake.count})

    def do_GET(self):
        p = self.path
        if p.startswith("/v1/generations/status/"):
            tid = p.rsplit("/", 1)[1]
            bad = Fake.fail_first and tid == "task-1"
            self._send("FAILURE" if bad else "SUCCESS")
        elif p == "/v1/credits/balance":
            self._send({"num_credits": 3000, "num_credits_payg": 0})
        elif p.startswith("/v1/generations/"):
            tid = p.rsplit("/", 1)[1]
            self._send({"song_paths": ["http://127.0.0.1:%d/audio/%s.wav" % (self.server.server_port, tid)]})
        elif p.startswith("/audio/"):
            self._send(Fake.wav_bytes, "audio/wav")
        else:
            self.send_error(404)


class BatchTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (shutil.which("ffmpeg") and shutil.which("ffprobe")):
            raise unittest.SkipTest("ffmpeg/ffprobe not on PATH")
        cls.tmp = Path(tempfile.mkdtemp(prefix="treblo_batch_test_"))
        good = cls.tmp / "good.wav"
        ti.write_wav(good, 165)
        Fake.wav_bytes = good.read_bytes()
        cls.srv = ThreadingHTTPServer(("127.0.0.1", 0), Fake)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        tb.API = "http://127.0.0.1:%d/v1" % cls.srv.server_port
        tb.POLL_SECONDS = 0
        os.environ["TREBLO_API_KEY"] = FAKE_KEY
        cls.csv = cls.tmp / "prompts.csv"
        with open(cls.csv, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["id", "station", "title", "band", "prompt", "file"])
            w.writerow(["afterglow_01", "afterglow", "Harlow Drive", "dusk", "synthwave test, instrumental",
                        "afterglow_01_harlow-drive_dusk"])
            w.writerow(["undertow_01", "undertow", "Cold Asphalt", "dead", "dark phonk test, instrumental",
                        "undertow_01_cold-asphalt_dead"])

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()

    def run_batch(self, name, *extra):
        inbox = self.tmp / name
        Fake.posts, Fake.count, Fake.fail_first = [], 0, False
        rc = tb.main(["--csv", str(self.csv), "--inbox", str(inbox), "--pause", "0"] + list(extra))
        return rc, inbox

    def test_full_run_and_restart(self):
        rc, inbox = self.run_batch("full")
        self.assertEqual(rc, 0)
        names = sorted(p.name for p in inbox.glob("*.wav"))
        self.assertEqual(names, [
            "afterglow_01_harlow-drive_dusk.wav", "afterglow_01_harlow-drive_dusk_b.wav",
            "undertow_01_cold-asphalt_dead.wav", "undertow_01_cold-asphalt_dead_b.wav"])
        self.assertEqual(len(Fake.posts), 4)
        path, body = Fake.posts[0]
        self.assertEqual(path, "/v1/generations/v3")
        self.assertTrue(body["instrumental"])
        self.assertEqual(body["output_format"], "wav")
        log = (inbox / "batch-log.txt").read_text(encoding="utf-8")
        self.assertNotIn(FAKE_KEY, log)
        self.assertEqual(tb.Log(inbox / "batch-log.txt").credits_spent(), 400)
        meta = json.loads((inbox / "afterglow_01_harlow-drive_dusk.api.json").read_text(encoding="utf-8"))
        self.assertEqual(meta["source"], "Treblo API")
        # restart: nothing new is sent, count does not change
        Fake.posts.clear()
        rc = tb.main(["--csv", str(self.csv), "--inbox", str(inbox), "--pause", "0"])
        self.assertEqual(rc, 0)
        self.assertEqual(Fake.posts, [])
        self.assertEqual(tb.Log(inbox / "batch-log.txt").credits_spent(), 400)

    def test_cap_stops_before_overspending(self):
        rc, inbox = self.run_batch("cap", "--credit-cap", "200")
        self.assertEqual(rc, 1)
        self.assertEqual(len(Fake.posts), 2)
        self.assertEqual(tb.Log(inbox / "batch-log.txt").credits_spent(), 200)
        self.assertIn("credit cap 200 reached", (inbox / "batch-log.txt").read_text(encoding="utf-8"))

    def test_failure_is_not_counted(self):
        inbox = self.tmp / "fail"
        Fake.posts, Fake.count, Fake.fail_first = [], 0, True
        rc = tb.main(["--csv", str(self.csv), "--inbox", str(inbox), "--pause", "0", "--versions", "1"])
        self.assertEqual(rc, 0)
        self.assertEqual(len(list(inbox.glob("*.wav"))), 1)       # task-1 failed, task-2 made
        self.assertEqual(tb.Log(inbox / "batch-log.txt").credits_spent(), 100)

    def test_missing_key_refuses(self):
        old = os.environ.pop("TREBLO_API_KEY")
        try:
            rc = tb.main(["--csv", str(self.csv), "--inbox", str(self.tmp / "nokey")])
            self.assertEqual(rc, 2)
        finally:
            os.environ["TREBLO_API_KEY"] = old


if __name__ == "__main__":
    unittest.main(verbosity=2)
