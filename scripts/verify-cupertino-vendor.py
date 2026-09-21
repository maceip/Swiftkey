#!/usr/bin/env python3
"""Verify every pinned upstream file and every declared local Cupertino patch."""
from pathlib import Path
import hashlib
import json
import sys

root = Path(__file__).resolve().parents[1] / "vendor" / "compose-cupertino"
source = json.loads((root / "SWIFTKEY-SOURCE.json").read_text())
manifest = json.loads((root / "SWIFTKEY-FILES.json").read_text())
patches = json.loads((root / "SWIFTKEY-PATCHES.json").read_text())
if source["revision"] != manifest["revision"] or source["revision"] != patches["revision"]:
    raise SystemExit("Cupertino revision metadata disagrees")
expected = {entry["path"]: entry["sha256"] for entry in manifest["files"]}
if len(expected) != len(manifest["files"]):
    raise SystemExit("Duplicate upstream manifest path")
for patch in patches["files"]:
    if expected.get(patch["path"]) != patch["original_sha256"]:
        raise SystemExit(f"Patch base mismatch: {patch['path']}")
    expected[patch["path"]] = patch["sha256"]
errors = []
for name, digest in expected.items():
    path = root / name
    if not path.is_file():
        errors.append(f"missing: {name}")
    elif hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        errors.append(f"changed: {name}")
metadata = {"SWIFTKEY-SOURCE.json", "SWIFTKEY-FILES.json", "SWIFTKEY-PATCHES.json"}
actual = {str(path.relative_to(root)) for path in root.rglob("*") if path.is_file()}
errors += [f"unexpected: {name}" for name in sorted(actual - expected.keys() - metadata)]
print(json.dumps({"revision": source["revision"], "upstream_files": len(expected),
                  "patched_files": len(patches["files"]), "passed": not errors, "errors": errors}, indent=2))
sys.exit(bool(errors))
