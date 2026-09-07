#!/usr/bin/env python3
"""Generate and independently decode synthetic native media test inputs."""

import argparse
import hashlib
import json
import math
import struct
import subprocess
import wave
from pathlib import Path

from PIL import Image


def generate(output: Path, ffmpeg: Path) -> None:
    ffmpeg = ffmpeg.resolve(strict=True)
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise ValueError("The media fixture output directory must be empty")
    for name, frequency in (("Original.wav", 440), ("Imported.wav", 660)):
        samples = b"".join(
            struct.pack("<h", round(5000 * math.sin(2 * math.pi * frequency * n / 22050)))
            for n in range(22050 * 10)
        )
        with wave.open(str(output / name), "wb") as stream:
            stream.setparams((1, 2, 22050, 0, "NONE", "not compressed"))
            stream.writeframes(samples)
    frames = [
        Image.new("RGB", (320, 180), color)
        for color in [(224, 32, 48), (24, 184, 104)] * 4
    ]
    try:
        frames[0].save(
            output / "Colors.apng", format="PNG", save_all=True,
            append_images=frames[1:], duration=800, loop=0, disposal=0, blend=0,
        )
        raw_frames = b"".join(frame.tobytes() * 20 for frame in frames)
        formats = {
            "Colors.mp4": ["-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-movflags", "+faststart"],
            "Colors.webm": ["-c:v", "libvpx-vp9", "-deadline", "realtime", "-cpu-used", "4", "-crf", "24", "-b:v", "0"],
        }
        validations = {}
        for name, codec in formats.items():
            path = output / name
            subprocess.run(
                [str(ffmpeg), "-v", "error", "-nostdin", "-n", "-f", "rawvideo",
                 "-pixel_format", "rgb24", "-video_size", "320x180", "-framerate", "25",
                 "-i", "pipe:0", "-an", *codec, "-pix_fmt", "yuv420p", "-threads", "1", str(path)],
                input=raw_frames, capture_output=True, timeout=60, check=True,
            )
            decoded = subprocess.run(
                [str(ffmpeg), "-v", "error", "-nostdin", "-i", str(path),
                 "-f", "rawvideo", "-pix_fmt", "rgb24", "-threads", "1", "pipe:1"],
                capture_output=True, timeout=60, check=True,
            ).stdout
            frame_bytes = 320 * 180 * 3
            if len(decoded) != len(raw_frames):
                raise ValueError(f"{name}: unexpected decoded dimensions/frame count")
            for index in range(160):
                offset = index * frame_bytes + (90 * 320 + 160) * 3
                expected = frames[index // 20].getpixel((160, 90))
                actual = decoded[offset:offset + 3]
                if any(abs(left - right) > 8 for left, right in zip(actual, expected)):
                    raise ValueError(f"{name}: decoded color differs at frame {index}")
            validations[name] = {"frames": 160, "width": 320, "height": 180, "fps": 25,
                                 "decoded_colors_verified": True}
        (output / "Invalid.mp4").write_bytes(b"Synthetic invalid video, not a media container.\n")
        manifest = {
            "scope": "synthetic media only; host FFmpeg validation is not app-backend acceptance",
            "encoder_sha256": hashlib.sha256(ffmpeg.read_bytes()).hexdigest(),
            "encoder_version": subprocess.run(
                [str(ffmpeg), "-version"], capture_output=True, timeout=10, check=True,
            ).stdout.decode("utf-8").splitlines()[0],
            "video_validation": validations,
            "files": {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                      for path in sorted(output.iterdir()) if path.is_file()},
        }
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    finally:
        for frame in frames:
            frame.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    args = parser.parse_args()
    generate(args.output, args.ffmpeg)
