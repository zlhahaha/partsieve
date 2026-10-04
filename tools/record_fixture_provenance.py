"""Record pinned public test fixtures; never execute VBA or fetch new bytes."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMIT = "5d4606d89a955226d2d0825a0f44309043ae7251"
FILES = {
    "macro01.xlsm": ("xlsx_files/macro01.xlsm", "09c35d1580eb6d7e678ba8249cdd1cbc0bd245fbb0eed8794981728715944736"),
    "simple01.xlsx": ("xlsx_files/simple01.xlsx", "cc6caf6efe9b60d5e9b59cc9c490cd02d7998af42021830f2def3e87f79004ad"),
    "test_macro01.py": ("test_macro01.py", "bef4201b145c586d798a527cf31cae2ef94bdb830a2177aa681773fbf41686c0"),
    "test_simple01.py": ("test_simple01.py", "7f93f01852442f89f90b9a888b0728a03f32bc1bfa2377cc579a4bd4eb6eb7a8"),
    "LICENSE.txt": (None, "cf08b60a4ded986b58a617cb8304373bda5c4eff42fb4e30d7597b616e116e87"),
}
records = []
for name, (suffix, expected) in FILES.items():
    path = ROOT / "tests/fixtures/upstream" / name
    data = path.read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    assert sha == expected, f"Pinned fixture drift: {name}: {sha}"
    remote = "LICENSE.txt" if suffix is None else "xlsxwriter/test/comparison/" + suffix
    records.append({"path": path.relative_to(ROOT).as_posix(), "bytes": len(data),
                    "sha256": sha, "license": "BSD-2-Clause",
                    "source": f"https://github.com/jmcnamara/XlsxWriter/blob/{COMMIT}/{remote}"})
result = {
    "schema": "partsieve.fixture-provenance.spike-v1", "recorded": "2026-10-04",
    "upstream": "jmcnamara/XlsxWriter", "commit": COMMIT, "files": records,
    "expectations": {
        "macro01.xlsm": {"kind": "real Excel comparison fixture", "sheets": 1,
                         "cell": "Sheet1!A1", "value": 123, "vba_projects": 1,
                         "expected_rewrite": "remove VBA payload and relationship; convert main type to XLSX; preserve other payloads",
                         "static_macro_review": "docs/evidence/vba-source-review.json", "vba_executed": False},
        "simple01.xlsx": {"kind": "real clean XLSX comparison fixture",
                          "expected_rewrite": "preserve every part payload; do not invent VBA findings"}
    },
    "derived_cases": {"generator": "tests/regression.py", "manifest": "docs/evidence/regression.json",
                      "purpose": "bounded-reader, URI, XML, capability and refusal variants; not additional real-client compatibility evidence",
                      "license": "BSD-2-Clause for upstream-derived fixture payloads"},
    "limitations": ["One-cell genuine VBA fixture; no image or visual-fidelity evidence.",
                    "Only verified macro-free output opened in WPS."]
}
(ROOT / "tests/fixtures/provenance.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"pinned_fixture_files": len(records), "status": "Pass"}))

# POI provenance is reviewed and pinned alongside the downloaded bytes. Do not
# regenerate expected hashes from local bytes, which would conceal drift.
poi = json.loads((ROOT / "tests/fixtures/poi/provenance.json").read_text(encoding="utf8"))
assert poi["commit"] == "12c3688d130035f3dc2ca2a0f50d929456435a93"
assert len(poi["files"]) == 5
for record in poi["files"]:
    path = ROOT / record["path"]
    assert path.parent == ROOT / "tests/fixtures/poi"
    payload = path.read_bytes()
    assert len(payload) == record["bytes"]
    assert hashlib.sha256(payload).hexdigest() == record["sha256"], f"POI fixture drift: {path.name}"
    assert poi["commit"] in record["source"] and record["license"].startswith("Apache-2.0")
print(json.dumps({"pinned_poi_fixture_files": len(poi["files"]), "status": "Pass"}))
