"""Validate original GLB provenance and final-layout editable source before exports."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct


def validate(root: Path) -> int:
    root = root.resolve()
    declared = set()
    for manifest in sorted((root / "assets/models").rglob("*manifest.json")):
        records = json.loads(manifest.read_text(encoding="utf-8"))
        for record in records if isinstance(records, list) else [records]:

            def source_path(key: str, alternative: str) -> Path:
                path = (root / record.get(key, record.get(alternative, ""))).resolve()
                if not path.is_relative_to(root) or not path.is_file():
                    raise ValueError(
                        f"Missing/outside source in {manifest.name}: {key}"
                    )
                return path

            model = source_path("runtime_glb", "runtime")
            source_path("source_builder", "source")
            source_path("source_blend", "editable")
            if not record.get("author") or not record.get("license"):
                raise ValueError(f"Missing maker/license: {manifest.name}")
            if not (
                record.get("packed_images") or record.get("packed_editable_images")
            ):
                raise ValueError(
                    f"Editable source lacks packed-image provenance: {model.name}"
                )
            data = model.read_bytes()
            if hashlib.sha256(data).hexdigest() != record.get("glb_sha256"):
                raise ValueError(f"Accepted runtime hash mismatch: {model.name}")
            magic, version, length = struct.unpack_from("<4sII", data)
            if magic != b"glTF" or version != 2 or length != len(data):
                raise ValueError(f"Invalid GLB header: {model.name}")
            json_length, kind = struct.unpack_from("<I4s", data, 12)
            if kind != b"JSON":
                raise ValueError(f"Missing GLB scene JSON: {model.name}")
            scene = json.loads(data[20 : 20 + json_length])
            if any("uri" in image for image in scene.get("images", [])):
                raise ValueError(f"Runtime GLB images must be embedded: {model.name}")
            if model in declared:
                raise ValueError(f"Duplicate model provenance: {model.name}")
            declared.add(model)
    if declared != set((root / "assets/models").rglob("*.glb")):
        raise ValueError("Every runtime GLB needs exactly one original asset manifest")
    return len(declared)


if __name__ == "__main__":
    count = validate(Path(__file__).resolve().parents[2])
    print(
        f"SCENE112_ART_MANIFESTS_OK models={count} SHA/source/editable/license/embedded images"
    )
