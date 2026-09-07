import hashlib
import json
import subprocess
import tempfile
import unittest
import wave
from pathlib import Path
from unittest.mock import patch

from PIL import Image

from generate_windows_media_fixture import generate


class MediaFixtureTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.encoder = self.root / "ffmpeg"
        self.encoder.write_bytes(b"synthetic executable identity, never executed")
        self.output = self.root / "media"
        self.raw = b""
        self.decode_mode = "valid"

    def run_encoder(self, command, **kwargs):
        if command[-1] == "-version":
            return subprocess.CompletedProcess(command, 0, stdout=b"fixture encoder\n")
        if "input" in kwargs:
            self.raw = kwargs["input"]
            Path(command[-1]).write_bytes(b"synthetic encoded output")
            return subprocess.CompletedProcess(command, 0, stdout=b"")
        decoded = self.raw
        if self.decode_mode == "truncated":
            decoded = decoded[:-1]
        elif self.decode_mode == "wrong-colors":
            decoded = b"\0" * len(decoded)
        return subprocess.CompletedProcess(command, 0, stdout=decoded)

    def test_generates_inputs_and_checks_every_decoded_color_frame(self):
        with patch("generate_windows_media_fixture.subprocess.run", side_effect=self.run_encoder) as run:
            generate(self.output, self.encoder)
        self.assertEqual(run.call_count, 5)
        self.assertEqual(set(path.name for path in self.output.iterdir()), {
            "Original.wav", "Imported.wav", "Colors.apng", "Colors.mp4",
            "Colors.webm", "Invalid.mp4", "manifest.json",
        })
        with wave.open(str(self.output / "Original.wav")) as audio:
            self.assertEqual(audio.getnframes(), 220500)
            self.assertEqual(audio.getframerate(), 22050)
        with Image.open(self.output / "Colors.apng") as image:
            self.assertEqual(image.n_frames, 8)
            self.assertEqual(image.size, (320, 180))
        manifest = json.loads((self.output / "manifest.json").read_text())
        self.assertEqual(manifest["encoder_sha256"], hashlib.sha256(self.encoder.read_bytes()).hexdigest())
        for name, digest in manifest["files"].items():
            self.assertEqual(digest, hashlib.sha256((self.output / name).read_bytes()).hexdigest())
        self.assertTrue(manifest["video_validation"]["Colors.mp4"]["decoded_colors_verified"])
        self.assertTrue(manifest["video_validation"]["Colors.webm"]["decoded_colors_verified"])

    def test_does_not_overwrite_existing_evidence(self):
        self.output.mkdir()
        sentinel = self.output / "keep"
        sentinel.write_bytes(b"preserved")
        with self.assertRaisesRegex(ValueError, "must be empty"):
            generate(self.output, self.encoder)
        self.assertEqual(sentinel.read_bytes(), b"preserved")

    def test_missing_encoder_fails_before_creating_output(self):
        with self.assertRaises(FileNotFoundError):
            generate(self.output, self.root / "missing")
        self.assertFalse(self.output.exists())

    def test_encoder_failure_cannot_create_success_manifest(self):
        with patch("generate_windows_media_fixture.subprocess.run", side_effect=subprocess.CalledProcessError(1, "ffmpeg")):
            with self.assertRaises(subprocess.CalledProcessError):
                generate(self.output, self.encoder)
        self.assertFalse((self.output / "manifest.json").exists())

    def test_truncated_decode_cannot_create_success_manifest(self):
        self.decode_mode = "truncated"
        with patch("generate_windows_media_fixture.subprocess.run", side_effect=self.run_encoder):
            with self.assertRaisesRegex(ValueError, "dimensions/frame count"):
                generate(self.output, self.encoder)
        self.assertFalse((self.output / "manifest.json").exists())

    def test_wrong_color_cannot_create_success_manifest(self):
        self.decode_mode = "wrong-colors"
        with patch("generate_windows_media_fixture.subprocess.run", side_effect=self.run_encoder):
            with self.assertRaisesRegex(ValueError, "decoded color differs"):
                generate(self.output, self.encoder)
        self.assertFalse((self.output / "manifest.json").exists())


if __name__ == "__main__":
    unittest.main()
