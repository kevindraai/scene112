#!/usr/bin/env python3
"""Print bounded resource-seal diagnostics for our generated private Mac bundle."""
import hashlib
import json
from pathlib import Path
import plistlib
import sys
import unicodedata

app = Path(sys.argv[1])
contents = app / "Contents"
seal = plistlib.loads((contents / "_CodeSignature/CodeResources").read_bytes())
for name, entry in seal.get("files2", {}).items():
    if not isinstance(entry, dict):
        continue
    path = contents / name
    normalized = contents / unicodedata.normalize("NFD", name)
    report = {"resource": name, "exists": path.exists(), "nfd_exists": normalized.exists()}
    if path.is_file():
        for key, algorithm in (("hash", "sha1"), ("hash2", "sha256")):
            if key in entry:
                digest = hashlib.new(algorithm, path.read_bytes()).digest()
                report[key + "_matches"] = digest == entry[key]
    print(json.dumps(report, ensure_ascii=True))
print("Bundle filenames:", json.dumps([str(p.relative_to(contents)) for p in contents.rglob("*") if p.is_file()], ensure_ascii=True))
