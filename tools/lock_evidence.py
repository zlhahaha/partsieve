"""Record and verify installed dependency source hashes (not a Moon resolver lock)."""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "docs/dependency-lock.json"
MODULES = [("moonbit-community/flate", "0.8.4",
            "ac48f8d4798f4780c2753455087422cfa71f849a8de9f2422b041d578b933376"),
           ("Milky2018/xml", "0.5.0",
            "c05c0386d61348b1948e5e6f05bd443894a4be3f4ec9d4238559c0beedec4bbf"),
           ("moonbitlang/x", "0.5.5",
            "eb7ddddea2c871ac823d210c4a9fdf5efc75d2c1fe9965292760669f15041dc4")]


def source_digest(directory):
    digest = hashlib.sha256()
    count = 0
    for path in sorted(directory.rglob("*")):
        if not path.is_file() or "_build" in path.parts:
            continue
        name = path.relative_to(directory).as_posix().encode()
        data = path.read_bytes()
        digest.update(len(name).to_bytes(8, "big"))
        digest.update(name)
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)
        count += 1
    return digest.hexdigest(), count


items = []
for module, version, checksum in MODULES:
    directory = ROOT / ".mooncakes" / module
    manifest = (directory / "moon.mod").read_text(encoding="utf-8")
    assert f'version = "{version}"' in manifest
    digest, count = source_digest(directory)
    items.append({"module": module, "version": version, "license": "Apache-2.0",
                  "registry_archive_checksum": checksum,
                  "installed_source_sha256": digest, "source_file_count": count})
record = {"schema": "partsieve.dependency-evidence-v1",
          "moon": "0.1.20260920 (914d7da 2026-09-20)",
          "moonc": "v0.10.14+7d59c7ec9 (2026-09-18)",
          "dependencies": items,
          "note": "Exact manifest versions plus installed source verification. This is project evidence, not a native Moon lockfile."}
if "--write" in sys.argv:
    LOCK.write_text(json.dumps(record, indent=2), encoding="utf-8")
else:
    assert json.loads(LOCK.read_text(encoding="utf-8")) == record, "installed dependency source/version drift"
print("Dependency source/version evidence verified.")
