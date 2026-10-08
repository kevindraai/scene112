#!/usr/bin/env python3
"""Two original nonvocal free-duty textures; no samples, speech or music."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import random

from compose_audio import RATE, TAU, empty, write


def texture(kind: str, seconds: float, seed: int):
    audio = empty(seconds, stereo=False)
    rng = random.Random(seed)
    low = soft = previous = 0.0
    for index in range(len(audio[0])):
        t = index / RATE
        white = rng.uniform(-1, 1)
        low = low * 0.98 + white * 0.02
        soft = soft * 0.76 + white * 0.24
        edge = soft - previous
        previous = soft
        if kind == "street_murmur":
            # Cloth/foot-shuffle air and tiny nonpitched object movement.
            # Deliberately no vocal tract, syllables, words or person voice.
            pause = max(0.0, math.sin(TAU * t / 3.0)) ** 2
            shuffle = max(0.0, math.sin(TAU * 1.4 * t + 0.7)) ** 4
            soft_tap = math.exp(-((t % 1.3) / 0.018))
            value = pause * (low * 0.055 + soft * shuffle * 0.026)
            value += edge * soft_tap * 0.045
        else:
            # A small fictional petrol motor and tyre rolling on asphalt.
            # Spatial trajectory/pitch are provided by the real traffic actor.
            cycle = math.sin(TAU * 47.0 * t)
            exhaust = cycle + 0.22 * math.sin(TAU * 94.0 * t)
            exhaust += 0.08 * math.sin(TAU * 141.0 * t)
            engine_flutter = 0.92 + 0.08 * math.sin(TAU * 8.0 * t)
            value = exhaust * engine_flutter * 0.075 + soft * 0.04 + low * 0.055
        audio[0][index] = value
    return audio


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("assets/audio"))
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    files = []
    for index, kind in enumerate(("street_murmur", "civilian_passby")):
        item = write(
            args.output_dir / f"{kind}.wav", texture(kind, 6.0, 5112 + index), True
        )
        item["source"] = "tools/compose_free_audio.py"
        item["creator"] = "SCENE 112 original procedural free-duty environment audio"
        files.append(item)
    manifest = {
        "schema": 1,
        "milestone": "M5",
        "source_seed": 5112,
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "helper_sha256": hashlib.sha256(
            Path(__file__).with_name("compose_audio.py").read_bytes()
        ).hexdigest(),
        "no_speech_recording_or_synthesis": True,
        "no_music_added": True,
        "files": files,
    }
    (args.output_dir / "free_manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n"
    )
    print("Generated 2 original M5 environment WAVs with per-file provenance")


if __name__ == "__main__":
    main()
