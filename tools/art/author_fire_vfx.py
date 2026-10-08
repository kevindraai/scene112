"""Original deterministic SCÈNE 112 particle fields; no photographs or libraries.

Run with NumPy available: python3 tools/art/author_fire_vfx.py [--root DIRECTORY]
PNG encoding uses Python's standard library, so this tool does not need Pillow.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import zlib
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SEED = 1122026


def png(path, rgba):
    data = np.uint8(np.clip(rgba, 0, 1) * 255 + .5)
    height, width, _ = data.shape
    def chunk(kind, payload):
        return struct.pack('!I', len(payload)) + kind + payload + struct.pack('!I', zlib.crc32(kind + payload) & 0xffffffff)
    raw = b''.join(b'\0' + row.tobytes() for row in data)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', width, height, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def field(size, seed):
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:size, 0:size] / (size - 1)
    noise = np.zeros((size, size))
    for frequency, weight in [(2, .55), (5, .28), (11, .12), (23, .05)]:
        for _ in range(3):
            angle = rng.uniform(0, 2 * np.pi)
            noise += weight / 3 * np.sin((x * np.cos(angle) + y * np.sin(angle)) * frequency * 2 * np.pi + rng.uniform(0, 2 * np.pi))
    return x, y, np.clip(.5 + noise * .5, 0, 1)


def generate(root):
    directory = root / 'assets/vfx/textures'
    directory.mkdir(parents=True, exist_ok=True)
    entries = []
    for name, size, index in [('flame_wisp', 256, 0), ('smoke_curl', 256, 1), ('steam_veil', 256, 2), ('water_drop', 128, 3)]:
        x, y, noise = field(size, SEED + index)
        if name == 'flame_wisp':
            # Bottom-wide rising tongues; the field is intentionally asymmetric.
            height = 1 - y
            bend = .065 * np.sin(height * 11) + .045 * np.sin(height * 25)
            width = .245 * (1 - height) ** .75 + .025
            distance = np.abs(x - .5 - bend) / width
            alpha = np.clip(1 - distance, 0, 1) ** 1.7
            alpha *= np.clip(height * 12, 0, 1) * np.clip((1 - height) * 7, 0, 1)
            alpha *= .45 + .55 * noise
            rgb = np.stack([noise, height, np.clip(1 - distance, 0, 1)], axis=-1)
        elif name == 'water_drop':
            radius = ((x - .5) / .23) ** 2 + ((y - .5) / .43) ** 2
            alpha = np.clip(1 - radius, 0, 1) ** 2.1
            rgb = np.stack([.55 + .35 * noise, .75 + .22 * noise, .86 + .14 * noise], axis=-1)
        else:
            radial = np.sqrt(((x - .5) / .47) ** 2 + ((y - .5) / .47) ** 2)
            alpha = np.clip(1 - radial, 0, 1) ** 1.5
            alpha *= np.clip((noise - .1) * 1.4, 0, 1)
            intensity = .48 + .42 * noise if name == 'smoke_curl' else .79 + .2 * noise
            rgb = np.stack([intensity, intensity, intensity], axis=-1)
        # Border pixels are truly zero-alpha, avoiding bright rectangular edges.
        alpha[[0, -1], :] = 0
        alpha[:, [0, -1]] = 0
        path = directory / (name + '.png')
        png(path, np.dstack([rgb, alpha]))
        entries.append({'path': str(path.relative_to(root)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'width': size, 'height': size, 'channels': 4, 'bytes': path.stat().st_size, 'seed': SEED + index, 'alpha_nonzero_pixels': int(np.count_nonzero(alpha > 1 / 255))})
    manifest = {'author': 'Tuned.pixel / SCÈNE 112', 'license': 'Private/proprietary project asset; no third-party asset content', 'source': 'tools/art/author_fire_vfx.py', 'technique': 'Original analytic envelopes with deterministic multi-frequency scalar fields; no sampled photographs', 'textures': entries, 'rgba8_uncompressed_bytes': sum(e['width'] * e['height'] * 4 for e in entries)}
    (root / 'assets/vfx/manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf8')
    print('SCENE112_FIRE_TEXTURES_OK', len(entries), manifest['rgba8_uncompressed_bytes'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=ROOT)
    generate(parser.parse_args().root.resolve())
