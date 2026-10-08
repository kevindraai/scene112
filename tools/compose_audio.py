#!/usr/bin/env python3
"""Compose original SCENE 112 PCM audio with only the Python standard library."""
from __future__ import annotations

import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import wave

RATE = 22050
TAU = math.tau
LICENSE = "Original SCENE 112 project asset; private/proprietary project license. No third-party samples."
MOTIF = (60, 67, 70, 65, 63)


def frequency(note: float) -> float:
    return 440.0 * 2 ** ((note - 69) / 12)


def empty(seconds: float, stereo: bool = True) -> list[array]:
    return [array("f", [0.0]) * int(seconds * RATE) for _ in range(2 if stereo else 1)]


def note(audio: list[array], at: float, seconds: float, midi: float,
         gain: float = 0.1, pan: float = 0.0, soft: bool = False) -> None:
    start = int(at * RATE)
    count = min(int(seconds * RATE), len(audio[0]) - start)
    if count <= 0:
        return
    freq = frequency(midi)
    attack = 0.35 if soft else 0.025
    release = 0.8 if soft else 0.22
    left = math.sqrt((1 - pan) / 2)
    right = math.sqrt((1 + pan) / 2)
    for index in range(count):
        t = index / RATE
        envelope = min(1.0, t / attack, (seconds - t) / release)
        if not soft:
            envelope *= math.exp(-t * 1.25)
        sound = gain * envelope * (
            math.sin(TAU * freq * t)
            + 0.18 * math.sin(TAU * freq * 2 * t)
            + (0.05 if soft else 0.12) * math.sin(TAU * freq * 3 * t)
        )
        audio[0][start + index] += sound * left
        if len(audio) > 1:
            audio[1][start + index] += sound * right


def score(kind: str, seconds: float) -> list[array]:
    audio = empty(seconds)
    roots = (48, 46, 44, 43)
    blocks = int(seconds // 8)
    for block in range(blocks):
        # Surveillance deliberately has whole passages with no score.
        if kind.startswith("surveillance") and block % 4 == 3:
            continue
        root = roots[(block + (1 if kind == "surveillance_b" else 0)) % 4]
        if kind == "academy":
            root += 5
        gain = 0.045 if kind == "investigation" else 0.075
        for degree in (0, 7, 15):
            note(audio, block * 8 + 0.15, 7.4, root + degree, gain,
                 pan=(-0.35 if degree == 0 else 0.35), soft=True)
    offsets = [1, 17, 33] if kind == "menu" else [5, 37, 61]
    if kind == "academy":
        offsets = [3, 19]
    if kind == "investigation":
        offsets = [11, 29]
    for offset in offsets:
        for index, midi in enumerate(MOTIF):
            if offset + index * 0.7 + 2 > seconds:
                break
            shift = -12 if kind == "investigation" else (5 if kind == "academy" else 0)
            note(audio, offset + index * 0.7, 2.0, midi + shift,
                 gain=0.075 if kind == "menu" else 0.04, pan=math.sin(index) * 0.3)
    return audio


def texture(kind: str, seconds: float, seed: int) -> list[array]:
    audio = empty(seconds, stereo=False)
    rng = random.Random(seed)
    low = 0.0
    previous = 0.0
    for index in range(len(audio[0])):
        t = index / RATE
        white = rng.uniform(-1, 1)
        low = low * 0.96 + white * 0.04
        high = white - previous
        previous = white
        if kind == "engine":
            sound = 0.24 * math.sin(TAU * 88 * t) + 0.09 * math.sin(TAU * 176 * t) + 0.035 * low
        elif kind == "wind":
            sound = low * (0.24 + 0.08 * math.sin(TAU * t / 8))
        elif kind == "room":
            sound = low * 0.07 + math.sin(TAU * 110 * t) * 0.018
        elif kind == "rain":
            sound = high * 0.055 + low * 0.13
        elif kind == "traffic":
            passing = math.sin(math.pi * ((t % 5) / 5)) ** 6
            sound = low * 0.12 + passing * (low * 0.22 + math.sin(TAU * (70 + t * 2) * t) * 0.09)
        elif kind == "harbour":
            sound = low * 0.13 + math.sin(TAU * 62 * t) * (0.035 + 0.018 * math.sin(TAU * t / 12))
        elif kind == "crackle":
            sound = high * 0.2 * (0.2 if index % 2000 < 900 else 1)
        elif kind.startswith("step"):
            pulse = math.exp(-t * 27)
            sound = (low * 0.8 + white * (0.06 if kind == "step_wood" else 0.2)) * pulse
            if kind == "step_wood":
                sound += math.sin(TAU * 190 * t) * math.exp(-t * 25) * 0.12
        else:
            sound = 0.0
        audio[0][index] = sound
    return audio


def birds() -> list[array]:
    audio = empty(12, stereo=False)
    for at, base in [(1.0, 80), (1.4, 85), (5.5, 82), (9.0, 87), (9.5, 83)]:
        note(audio, at, 0.22, base, 0.08)
    return audio


def siren() -> list[array]:
    audio = empty(4, stereo=False)
    phase = 0.0
    for index in range(len(audio[0])):
        t = index / RATE
        # A fictive, original two-tone signal, not a recorded service brand.
        freq = 610 if int(t * 2) % 2 == 0 else 790
        phase += TAU * freq / RATE
        audio[0][index] = (math.sin(phase) + 0.1 * math.sin(phase * 2)) * 0.22
    return audio


def cue(kind: str) -> list[array]:
    durations = {"sonic_logo": 3.6, "urgency": 6.0, "radio_tone": 0.8,
                 "ui": 0.12, "interaction": 0.24, "success": 2.6, "partial": 2.2, "error": 1.8}
    seconds = durations[kind]
    audio = empty(seconds, stereo=kind in ("sonic_logo", "urgency", "success", "partial", "error"))
    notes = {
        "sonic_logo": MOTIF, "urgency": (60, 60, 67, 70, 67, 60, 62, 67),
        "radio_tone": (81, 86), "ui": (84,), "interaction": (72, 79),
        "success": (60, 67, 72), "partial": (60, 65, 63), "error": (60, 58),
    }[kind]
    gap = min(0.48, (seconds - 0.08) / len(notes))
    for index, midi in enumerate(notes):
        note(audio, 0.015 + index * gap, min(0.65, seconds - index * gap - 0.02),
             midi, 0.12 if kind == "urgency" else 0.18, pan=0.12 * (index % 2 * 2 - 1))
    return audio


def write(path: Path, audio: list[array], loop: bool) -> dict:
    # Preserve deliberately quiet texture levels; do not normalize every cue to
    # maximum loudness. Gentle endpoint fades prevent loop/cue discontinuities.
    peak = max(abs(value) for channel in audio for value in channel)
    gain = min(1.0, 0.72 / max(peak, 0.0001))
    frames = len(audio[0])
    fade = min(int(RATE * (0.06 if loop else 0.015)), frames // 4)
    pcm = bytearray()
    square = 0.0
    final_peak = 0.0
    for index in range(frames):
        envelope = min(1.0, index / max(1, fade), (frames - 1 - index) / max(1, fade))
        for channel in audio:
            value = float(channel[index]) * gain * envelope
            if not math.isfinite(value):
                raise ValueError("Nonfinite audio sample")
            final_peak = max(final_peak, abs(value))
            square += value * value
            pcm.extend(struct.pack("<h", round(value * 32767)))
    with wave.open(str(path), "wb") as output:
        output.setnchannels(len(audio))
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm)
    return {
        "file": path.name, "source": "tools/compose_audio.py", "creator": "SCENE 112 original procedural composition",
        "license": LICENSE, "third_party_samples": False, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "sample_rate": RATE, "channels": len(audio), "seconds": frames / RATE, "loop": loop,
        "peak": round(final_peak, 5), "rms": round(math.sqrt(square / (frames * len(audio))), 5),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("assets/audio"))
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    files = []
    for kind, seconds in [("menu", 40), ("surveillance_a", 72), ("surveillance_b", 72),
                          ("academy", 32), ("investigation", 40)]:
        name = f"music_{kind}.wav"
        print(f"Composing {name}", flush=True)
        files.append(write(args.output_dir / name, score(kind, seconds), kind in ("menu", "academy")))
    for kind in ("sonic_logo", "urgency", "radio_tone", "ui", "interaction", "success", "partial", "error"):
        files.append(write(args.output_dir / f"{kind}.wav", cue(kind), False))
    for index, (kind, seconds) in enumerate([
        ("wind", 8), ("room", 8), ("rain", 8), ("traffic", 15), ("harbour", 12),
        ("engine", 3), ("crackle", 0.65), ("step_asphalt", 0.25), ("step_wood", 0.25),
    ]):
        files.append(write(args.output_dir / f"{kind}.wav", texture(kind, seconds, 112 + index),
                           seconds >= 3))
    files.append(write(args.output_dir / "birds.wav", birds(), True))
    files.append(write(args.output_dir / "siren.wav", siren(), True))
    manifest = {"schema": 1, "identity": "Original five-note SCENE 112 motif: C-G-Bb-F-Eb",
                "source_seed": 112, "files": files}
    (args.output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Generated {len(files)} original WAV assets and per-file provenance", flush=True)


if __name__ == "__main__":
    main()
