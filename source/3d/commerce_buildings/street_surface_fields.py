"""Original tileable street PBR maps, authored from physical surface patterns.

No downloaded samples. Blender's NumPy or python3-numpy is the only dependency.
Outputs are source assets for Blender/glTF and Godot, not screen-space effects.
"""

from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib
import numpy as np

SIZE = 512


def png(path: Path, pixels: np.ndarray) -> None:
    pixels = np.uint8(np.clip(pixels, 0, 255))
    height, width = pixels.shape[:2]
    if pixels.ndim == 2:
        pixels = np.repeat(pixels[:, :, None], 3, axis=2)
    raw = b"".join(b"\0" + row.tobytes() for row in pixels)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data))
        )

    content = b"\x89PNG\r\n\x1a\n" + chunk(
        b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    )
    content += chunk(b"IDAT", zlib.compress(raw, 7)) + chunk(b"IEND", b"")
    path.write_bytes(content)


def smooth_noise(rng: np.random.Generator, scale: int) -> np.ndarray:
    # Periodic low-frequency interpolation retains seamless tile boundaries.
    small = rng.random((scale, scale))
    coords = np.arange(SIZE) * scale / SIZE
    low = coords.astype(int)
    fract = coords - low
    fract = fract * fract * (3 - 2 * fract)
    horizontal = small[:, low] * (1 - fract) + small[:, (low + 1) % scale] * fract
    return (
        horizontal[low, :] * (1 - fract[:, None])
        + horizontal[(low + 1) % scale, :] * fract[:, None]
    )


def maps(kind: str, seed: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[:SIZE, :SIZE] / SIZE
    grain = rng.random((SIZE, SIZE))
    broad = smooth_noise(rng, 12)
    fine = smooth_noise(rng, 64)
    rough = np.full((SIZE, SIZE), 0.83)
    if kind == "brick":
        row = np.floor(y * 30).astype(int)
        u = (x * 10 + (row % 2) * 0.5) % 1
        v = y * 30 % 1
        mortar = (u < 0.027) | (v < 0.07)
        edge = np.minimum(np.minimum(u, 1 - u) * 7, np.minimum(v, 1 - v) * 3)
        bevel = np.clip(edge / 0.09, 0, 1)
        brick_id = ((np.floor(x * 10 + (row % 2) * 0.5).astype(int) % 10) + row * 10) % 300
        variation = rng.uniform(-0.12, 0.12, 300)[brick_id]
        tone = 0.78 + broad * 0.16 + fine * 0.12 + grain * 0.05 + variation
        colour = tone[:, :, None] * np.array([164, 88, 65])
        colour[mortar] = (
            178 + broad[mortar, None] * 22 + grain[mortar, None] * 6
        ) * np.array([1.0, 0.98, 0.89])
        height = 0.007 * bevel + broad * 0.0008 + (grain - 0.5) * 0.0004
        height[mortar] = -0.0008 + grain[mortar] * 0.00015
        rough = 0.77 + fine * 0.17
        rough[mortar] = 0.97
    elif kind == "paving":
        u, v = x * 8 % 1, y * 8 % 1
        joint = (u < 0.033) | (v < 0.033)
        edge = np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v))
        tone = 0.8 + broad * 0.18 + grain * 0.13
        colour = tone[:, :, None] * np.array([184, 179, 165])
        colour[joint] = 74 + grain[joint, None] * 23
        height = 0.004 * np.clip(edge / 0.055, 0, 1) + grain * 0.0004
        height[joint] = -0.001
        rough = 0.80 + fine * 0.18
    elif kind == "asphalt":
        aggregate = np.maximum(0, (grain - 0.89) * 10)
        tone = 0.55 + fine * 0.17 + broad * 0.19 + grain * 0.13
        colour = tone[:, :, None] * np.array([69, 73, 76]) + aggregate[:, :, None] * 20
        height = grain * 0.00055 + fine * 0.0004
        rough = 0.80 + broad * 0.18
    elif kind == "roof":
        row = np.floor(y * 8).astype(int)
        u = (x * 10 + (row % 2) * 0.5) % 1
        v = y * 8 % 1
        curved = 0.5 + 0.5 * np.cos(u * np.pi * 2)
        height = curved * 0.018 + v * 0.003 + fine * 0.0006
        joint = (v < 0.035) | (u < 0.025)
        height[joint] -= 0.004
        tone = 0.76 + broad * 0.22 + fine * 0.10 + grain * 0.04
        colour = tone[:, :, None] * np.array([129, 68, 48])
        colour[joint] *= 0.65
        rough = 0.75 + fine * 0.17
    elif kind == "wood":
        fibre = 0.5 + 0.5 * np.sin(
            x * np.pi * 340 + broad * 7 + np.sin(y * np.pi * 2) * 1.8
        )
        tone = 0.64 + fibre * 0.09 + fine * 0.17 + broad * 0.13
        colour = tone[:, :, None] * np.array([146, 109, 70])
        height = fibre * 0.0003 + fine * 0.0004
        rough = 0.66 + fine * 0.20
    elif kind == "grass":
        fibres = 0.5 + 0.5 * np.sin(x * np.pi * 580 + fine * 9 + y * np.pi * 42)
        blades = smooth_noise(rng, 180)
        tone = 0.56 + broad * 0.32 + grain * 0.18 + fibres * 0.10
        colour = tone[:, :, None] * np.array([69, 91, 45])
        earth = blades < 0.18
        colour[earth] = (0.5 + grain[earth, None] * 0.4) * np.array([79, 63, 44])
        height = fibres * 0.0008 + blades * 0.0012
        rough = 0.89 + fine * 0.09
    else:
        raise ValueError(kind)
    # OpenGL tangent normals;2.1m repeat, central wrapped derivative.
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * SIZE / 4.2
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * SIZE / 4.2
    normal = np.stack((-dx, -dy, np.ones_like(height)), axis=2)
    normal /= np.linalg.norm(normal, axis=2)[:, :, None]
    return colour, (normal * 0.5 + 0.5) * 255, rough * 255


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[3] / "assets/textures/commerce_buildings",
    )
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    records = []
    for index, kind in enumerate(
        ["brick"]
    ):
        for suffix, pixels in zip(
            ["albedo", "normal", "roughness"], maps(kind, 112 + index)
        ):
            path = args.output / f"commerce_masonry_{suffix}.png"
            png(path, pixels)
            records.append(
                {
                    "file": path.name,
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "resolution": [SIZE, SIZE],
                    "author": "SCÈNE 112 original project asset",
                    "source": "source/3d/commerce_buildings/street_surface_fields.py",
                    "license": "Private/proprietary SCÈNE 112 project license; no third-party samples",
                }
            )
    (args.output / "manifest.json").write_text(json.dumps(records, indent=2) + "\n")
    print("SCENE112_DUTY_MASONRY_AUTHORED maps=3 resolution=512 original_seed=112")


if __name__ == "__main__":
    main()
