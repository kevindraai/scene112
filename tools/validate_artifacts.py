#!/usr/bin/env python3
"""Validate native distribution structure and CPU architectures without launching."""

from __future__ import annotations

import argparse
from pathlib import Path
import plistlib
import stat
import struct
import sys
import zipfile


def check(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def macos(bundle: zipfile.ZipFile) -> None:
    names = bundle.namelist()
    plists = [name for name in names if name.endswith(".app/Contents/Info.plist")]
    check(len(plists) == 1, "Expected exactly one macOS .app bundle")
    plist_path = plists[0]
    metadata = plistlib.loads(bundle.read(plist_path))
    check(metadata.get("CFBundleIdentifier") == "nl.tunedpixel.scene112", "Incorrect bundle identifier")
    executable = plist_path.removesuffix("Info.plist") + "MacOS/" + metadata["CFBundleExecutable"]
    binary = bundle.read(executable)
    check(bool((bundle.getinfo(executable).external_attr >> 16) & stat.S_IXUSR), "macOS executable permission missing")
    check(len(binary) >= 8, "Invalid Mach-O binary")
    magic, count = struct.unpack_from(">II", binary)
    check(magic in (0xCAFEBABE, 0xCAFEBABF), "macOS executable is not a Universal binary")
    entry_size = 20 if magic == 0xCAFEBABE else 32
    check(len(binary) >= 8 + entry_size * count, "Truncated Universal binary header")
    architectures = {struct.unpack_from(">I", binary, 8 + entry_size * index)[0] for index in range(count)}
    check({0x01000007, 0x0100000C}.issubset(architectures), "Universal binary must contain x86_64 and arm64")
    resources = plist_path.removesuffix("Info.plist") + "Resources/"
    packs = [name for name in names if name.startswith(resources) and name.endswith(".pck")]
    check(len(packs) == 1, "Expected one macOS project resource pack")
    check(bundle.read(packs[0])[:4] == b"GDPC", "Invalid macOS project resource pack")
    print("macOS: Universal2 x86_64 + arm64, valid bundle, executable mode, project pack")


def windows(bundle: zipfile.ZipFile) -> None:
    names = bundle.namelist()
    check("Scene112.exe" in names, "Windows distribution lacks Scene112.exe")
    check("Scene112.pck" in names, "Windows distribution lacks Scene112.pck")
    binary = bundle.read("Scene112.exe")
    check(len(binary) > 0x40 and binary[:2] == b"MZ", "Invalid Windows executable")
    offset = struct.unpack_from("<I", binary, 0x3C)[0]
    check(len(binary) >= offset + 6, "Truncated Windows PE header")
    check(binary[offset:offset + 4] == b"PE\x00\x00", "Invalid Windows PE signature")
    check(struct.unpack_from("<H", binary, offset + 4)[0] == 0x8664, "Windows executable is not x86_64")
    check(bundle.read("Scene112.pck")[:4] == b"GDPC", "Invalid Windows project resource pack")
    print("Windows: valid standalone x86_64 PE executable and external project pack")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("macos", "windows"))
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    with zipfile.ZipFile(args.archive) as bundle:
        check(bundle.testzip() is None, "ZIP integrity failure")
        for member in bundle.namelist():
            check(not member.startswith(("/", "\\")) and ".." not in member.split("/"), "Unsafe archive path")
        {"macos": macos, "windows": windows}[args.platform](bundle)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, struct.error) as error:
        print(f"Artifact validation failed: {error}", file=sys.stderr)
        sys.exit(1)
