"""Hash current project sources/docs, including mirrored handoff/plan."""
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "docs/evidence/artifact-manifest.json"
SKIP = {".git", ".mooncakes", "_build", "target", "test-deps", "generated", "bin", "obj", "__pycache__", ".moonagent"}
records = []
for current, directories, filenames in os.walk(ROOT):
    directories[:] = sorted(d for d in directories if d not in SKIP)
    for name in sorted(filenames):
        if name.startswith(("~$", ".~lock.")):
            continue  # Office's live lock files are not document artifacts.
        path = Path(current) / name
        if path == DEST:
            continue
        data = path.read_bytes()
        records.append({"path": path.relative_to(ROOT).as_posix(), "bytes": len(data),
                        "sha256": hashlib.sha256(data).hexdigest()})
records.sort(key=lambda item: item["path"])
report = {"schema": "partsieve.artifact-manifest.spike-v1", "date": "2026-10-04", "files": records,
          "excluded": sorted(SKIP), "excluded_file_prefixes": ["~$", ".~lock."],
          "note": "Local review snapshot, not an authenticity signature. Regenerate after edits."}
DEST.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
print(json.dumps({"hashed_files": len(records), "manifest": DEST.relative_to(ROOT).as_posix()}))
