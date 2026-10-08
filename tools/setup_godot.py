#!/usr/bin/env python3
"""Install the verified, pinned Godot toolchain into an isolated task cache."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shutil
import stat
import sys
import urllib.request
import zipfile


VERSION = "4.7.2"
TAG = f"{VERSION}-stable"
TEMPLATE_VERSION = f"{VERSION}.stable"
RELEASE_API = f"https://api.github.com/repos/godotengine/godot/releases/tags/{TAG}"
# Official release asset digests; never silently accept a replaced release asset.
DIGESTS = {
    f"Godot_v{TAG}_linux.x86_64.zip":
        "cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4",
    f"Godot_v{TAG}_macos.universal.zip":
        "c58a24e31d720be9d62f60cb5627c4e695fb72f21b0cfe1bc9ccaa9a3b3ba63e",
    f"Godot_v{TAG}_win64.exe.zip":
        "731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953",
    f"Godot_v{TAG}_export_templates.tpz":
        "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_release() -> dict:
	# GitHub-hosted runners share public API quotas. Use their read-only workflow
	# token for metadata on api.github.com only; never forward it to asset hosts.
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "scene112-build"}
    if token := os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        RELEASE_API,
        headers=headers,
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        release = json.load(response)
    if release["tag_name"] != TAG or release.get("draft") or release.get("prerelease"):
        raise RuntimeError("Official release is not the pinned stable release")
    return {asset["name"]: asset for asset in release["assets"]}


def download(name: str, cache: Path, assets: dict) -> Path:
    asset = assets[name]
    expected = DIGESTS[name]
    if asset.get("digest") != f"sha256:{expected}":
        raise RuntimeError(f"Official asset digest changed or missing: {name}")
    url = asset["browser_download_url"]
    if not url.startswith(f"https://github.com/godotengine/godot/releases/download/{TAG}/"):
        raise RuntimeError("Unexpected release download origin")
    target = cache / "downloads" / name
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and sha256(target) == expected:
        print(f"Verified cached {name}", flush=True)
        return target
    temporary = target.with_suffix(target.suffix + ".part")
    print(f"Downloading {name} ({asset['size']:,} bytes)", flush=True)
    request = urllib.request.Request(url, headers={"User-Agent": "scene112-build"})
    with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as stream:
        shutil.copyfileobj(response, stream, length=1024 * 1024)
    if temporary.stat().st_size != asset["size"] or sha256(temporary) != expected:
        temporary.unlink()
        raise RuntimeError(f"Downloaded asset failed SHA256/size verification: {name}")
    temporary.replace(target)
    print(f"Verified SHA256 {name}: {expected}", flush=True)
    return target


def extract(archive: Path, destination: Path, prefix: str = "") -> None:
    with zipfile.ZipFile(archive) as bundle:
        for member in bundle.infolist():
            name = member.filename
            if prefix:
                if not name.startswith(prefix):
                    continue
                name = name[len(prefix):]
            relative = PurePosixPath(name)
            if not name or name.endswith("/"):
                continue
            if relative.is_absolute() or ".." in relative.parts or "\\" in name:
                raise RuntimeError("Unsafe path in toolchain archive")
            mode = member.external_attr >> 16
            if stat.S_ISLNK(mode):
                raise RuntimeError("Unexpected symlink in toolchain archive")
            target = destination.joinpath(*relative.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            with bundle.open(member) as source, target.open("wb") as output:
                shutil.copyfileobj(source, output)
            target.chmod((mode & 0o777) or 0o644)


def export_environment(values: dict[str, str]) -> None:
    output_path = os.environ.get("GITHUB_ENV")
    if output_path:
        with Path(output_path).open("a", encoding="utf-8") as stream:
            for key, value in values.items():
                if "\n" in value or "\r" in value:
                    raise RuntimeError("Invalid environment path")
                stream.write(f"{key}={value}\n")
    print(json.dumps(values, indent=2), flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=Path, default=Path(".godot-tools"))
    parser.add_argument("--templates", action="store_true", help="Install matching export templates")
    parser.add_argument("--templates-only", action="store_true", help="Linux: install templates for an existing editor")
    args = parser.parse_args()
    cache = args.cache_dir.resolve()
    editor = cache / "editor"
    system = platform.system()
    if args.templates_only and system != "Linux":
        parser.error("--templates-only supports Linux with XDG_DATA_HOME")
    if system == "Linux" and platform.machine() not in ("x86_64", "AMD64"):
        parser.error("Pinned Linux editor requires x86_64")
    suffix = {"Linux": "linux.x86_64", "Darwin": "macos.universal", "Windows": "win64.exe"}.get(system)
    if suffix is None:
        parser.error(f"Unsupported build host: {system}")
    assets = read_release()
    if not args.templates_only:
        archive = download(f"Godot_v{TAG}_{suffix}.zip", cache, assets)
        stamp = editor / ".verified-asset"
        if not stamp.exists() or stamp.read_text() != DIGESTS[archive.name]:
            extract(archive, editor)
            stamp.write_text(DIGESTS[archive.name])
    if system == "Darwin":
        binary = editor / "Godot.app" / "Contents" / "MacOS" / "Godot"
    elif system == "Windows":
        binary = editor / f"Godot_v{TAG}_win64_console.exe"
    else:
        binary = editor / f"Godot_v{TAG}_linux.x86_64"
    environment = {"GODOT_BIN": str(binary)}
    if system == "Linux":
        data = Path(os.environ.get("XDG_DATA_HOME", str(cache / "data"))).resolve()
        environment.update({
            "XDG_DATA_HOME": str(data),
            "XDG_CONFIG_HOME": str(cache / "config"),
            "XDG_CACHE_HOME": str(cache / "cache"),
        })
        templates = data / "godot" / "export_templates" / TEMPLATE_VERSION
    else:
        # Self-contained mode avoids writes to user/system editor directories.
        # macOS resolves this root outside Godot.app (EditorPaths, pinned source).
        portable_root = editor if system == "Darwin" else binary.parent
        (portable_root / "_sc_").touch()
        templates = portable_root / "editor_data" / "export_templates" / TEMPLATE_VERSION
    if args.templates or args.templates_only:
        name = f"Godot_v{TAG}_export_templates.tpz"
        stamp = templates / ".verified-asset"
        if not stamp.exists() or stamp.read_text() != DIGESTS[name]:
            archive = download(name, cache, assets)
            extract(archive, templates, prefix="templates/")
            if not (templates / "version.txt").exists():
                raise RuntimeError("Template archive has an unexpected layout")
            if (templates / "version.txt").read_text().strip() != TEMPLATE_VERSION:
                raise RuntimeError("Export template version does not match the engine")
            stamp.write_text(DIGESTS[name])
        environment["GODOT_TEMPLATES"] = str(templates)
    if not args.templates_only:
        if not binary.is_file():
            raise RuntimeError(f"Editor binary missing: {binary}")
        binary.chmod(binary.stat().st_mode | 0o111)
    export_environment(environment)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, KeyError, zipfile.BadZipFile) as error:
        print(f"Godot setup failed: {error}", file=sys.stderr)
        sys.exit(1)
