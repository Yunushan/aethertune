#!/usr/bin/env python3
"""Reject missing/silent/malformed native audio acceptance evidence."""

import array
import math
from pathlib import Path
import sys
import tempfile
import unittest

from verify_native_audio import inspect_pcm


class NativeAudioEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'audio.raw'

    def write(self, values):
        samples = array.array('h', values)
        if sys.byteorder != 'little':
            samples.byteswap()
        self.path.write_bytes(samples.tobytes())

    def test_sustained_rendered_tone_is_accepted(self):
        self.write(round(2000 * math.sin(2 * math.pi * 440 * i / 22050)) for i in range(22050))
        report = inspect_pcm(self.path)
        self.assertEqual('passed', report['status'])
        self.assertEqual(22050, report['samples'])
        self.assertGreater(report['active_samples'], 18000)
        self.assertAlmostEqual(1414.214, report['rms'], delta=1)

    def test_silence_fails(self):
        self.write([0] * 22050)
        with self.assertRaisesRegex(ValueError, 'non-silent'):
            inspect_pcm(self.path)

    def test_single_peak_does_not_count_as_playback(self):
        self.write([3000] + [0] * 22049)
        with self.assertRaisesRegex(ValueError, 'non-silent'):
            inspect_pcm(self.path)

    def test_low_noise_fails(self):
        self.write([80, -80] * 11025)
        with self.assertRaisesRegex(ValueError, 'non-silent'):
            inspect_pcm(self.path)

    def test_partial_sample_fails(self):
        self.path.write_bytes(b'\0' * 44101)
        with self.assertRaisesRegex(ValueError, 'bounded'):
            inspect_pcm(self.path)

    def test_empty_and_short_capture_fail(self):
        for size in (0, 2, 44098):
            with self.subTest(size=size):
                self.path.write_bytes(b'\0' * size)
                with self.assertRaisesRegex(ValueError, 'bounded'):
                    inspect_pcm(self.path)

    def test_oversized_capture_fails_before_reading(self):
        with self.path.open('wb') as stream:
            stream.truncate(256 * 1024 * 1024 + 2)
        with self.assertRaisesRegex(ValueError, 'bounded'):
            inspect_pcm(self.path)

    def test_missing_capture_fails(self):
        with self.assertRaises(FileNotFoundError):
            inspect_pcm(self.path)


if __name__ == '__main__':
    unittest.main()
