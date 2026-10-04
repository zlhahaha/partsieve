"""Detailed coverage/decision evidence through the public host; no remote I/O."""
from copy import deepcopy
import json
from pathlib import Path
import struct
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "tools/partsieve.py"
DEST = ROOT / "tests/generated/coverage"
DEST.mkdir(parents=True, exist_ok=True)
FIXTURE = ROOT / "tests/fixtures/upstream/macro01.xlsm"
with zipfile.ZipFile(FIXTURE) as archive:
    BASE = {name: archive.read(name) for name in archive.namelist()}
OFFICE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
checks = []


def call(command, path, *args):
    result = subprocess.run([sys.executable, str(CLI), command, str(path), *map(str, args)],
                            cwd=ROOT, capture_output=True, text=True, timeout=90)
    return result.returncode, json.loads(result.stdout)


def write(name, parts):
    path = DEST / (name + ".xlsm")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as archive:
        for name, payload in parts.items(): archive.writestr(name, payload)
    return path


def check(name):
    checks.append({"name": name, "status": "Pass"})


code, report = call("assess", FIXTURE)
assert code == 0 and report["decision"]["result"] == "Pass" and report["decision"]["rebuild_allowed"]
assert report["coverage"]["parse_complete"] and not report["coverage"]["unchecked_features"]
rules = {r["capability"]: r for r in report["coverage"]["rules"]}
assert len(rules) == 9 and rules["VBA"]["presence"] == "Present"
assert all(r["state"] == "Checked" for r in rules.values())
assert report["findings"][0]["certainty"] == "Declared"
check("real XLSM Pass is scoped; VBA Present and supported removal rather than safe-input claim")
code, clean = call("assess", ROOT / "tests/fixtures/upstream/simple01.xlsx")
assert code == 0 and not clean["findings"] and all(r["presence"] == "Absent" for r in clean["coverage"]["rules"])
check("clean supported real XLSX records checked absence")

for name, kind, capability in [
    ("http-click", OFFICE + "hyperlink", "HTTPHyperlink"),
    ("automatic-image", OFFICE + "image", "ExternalResource"),
    ("remote-template", OFFICE + "attachedTemplate", "RemoteTemplate"),
    ("external-data", OFFICE + "externalLinkPath", "ExternalData"),
    ("ole", OFFICE + "oleObject", "OLE"),
    ("activex", OFFICE + "control", "ActiveX"),
    ("unknown-external", "urn:unknown", "UnknownExternalRelationship"),
]:
    parts = deepcopy(BASE)
    parts["xl/_rels/workbook.xml.rels"] = parts["xl/_rels/workbook.xml.rels"].replace(b'</Relationships>',
        ('<Relationship Id="outside" Type="' + kind + '" Target="https://example.invalid/resource" TargetMode="External"/></Relationships>').encode())
    path = write(name, parts)
    code, report = call("assess", path)
    assert code == 3 and report["decision"]["result"] == "Unsupported" and not report["decision"]["rebuild_allowed"]
    assert any(f["capability"] == capability and f["rebuild_support"] == "Unsupported" for f in report["findings"])
    assert report["coverage"]["parse_complete"] and report["coverage"]["unchecked_features"]
    assert all(r["presence"] == "Unknown" for r in report["coverage"]["rules"] if r["state"] == "NotChecked")
    code_audit, _ = call("audit", path)
    assert code_audit != 0
    out, receipt = DEST / (name + ".xlsx"), DEST / (name + ".receipt.json")
    assert not out.exists() and not receipt.exists()
    rebuild_exit, _ = call("rebuild", path, "-o", out, "--receipt", receipt)
    assert rebuild_exit != 0 and not out.exists() and not receipt.exists()
    check(capability + " declared evidence; Unsupported decisions never publish and untested rules stay Unknown")

opaque = deepcopy(BASE)
opaque["xl/worksheets/sheet1.xml"] = opaque["xl/worksheets/sheet1.xml"].replace(b'</worksheet>',
    b'<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"/></worksheet>')
code, report = call("assess", write("opaque", opaque))
assert code == 3 and any(f["capability"] == "UnknownPotentiallyActiveExtension" for f in report["findings"])
assert any(r["state"] == "Opaque" and r["presence"] == "Unknown" for r in report["coverage"]["rules"])
check("opaque XML marks Unknown presence rather than assumed absence")

unknown_part = deepcopy(BASE)
unknown_part["unknown.bin"] = b"artificial opaque metadata fixture"
unknown_part["[Content_Types].xml"] = unknown_part["[Content_Types].xml"].replace(b'</Types>',
    b'<Override PartName="/unknown.bin" ContentType="application/unknown-capability"/></Types>')
unknown_relation = deepcopy(BASE)
unknown_relation["xl/_rels/workbook.xml.rels"] = unknown_relation["xl/_rels/workbook.xml.rels"].replace(b'</Relationships>',
    b'<Relationship Id="unknown-internal" Type="urn:unknown" Target="styles.xml"/></Relationships>')
for name, parts in (("unknown-binary", unknown_part), ("unknown-internal", unknown_relation)):
    code, report = call("assess", write(name, parts))
    assert code == 3 and not report["decision"]["rebuild_allowed"]
    assert any(f["capability"] == "VBA" for f in report["findings"])
    assert any(f["capability"] == "UnknownPotentiallyActiveExtension" and f["certainty"] == "Unknown" for f in report["findings"])
    check(name + " is reported even when known VBA findings also exist")

for name, data in [("truncated-zip", b"PK\x03\x04"), ("invalid-utf8", None)]:
    if data is None:
        parts = deepcopy(BASE); parts["xl/worksheets/sheet1.xml"] = b"\xff"
        path = write(name, parts)
    else:
        path = DEST / (name + ".xlsm"); path.write_bytes(data)
    code, report = call("assess", path)
    assert code == 3 and report["decision"]["result"] == "Incomplete"
    assert not report["coverage"]["parse_complete"] and not report["decision"]["rebuild_allowed"]
    assert not report["findings"] and not report["coverage"]["checked_rules"]
    assert all(r["state"] == "Incomplete" and r["presence"] == "Unknown" for r in report["coverage"]["rules"])
    out, receipt = DEST / (name + ".xlsx"), DEST / (name + ".receipt.json")
    code, _ = call("rebuild", path, "-o", out, "--receipt", receipt)
    assert code != 0 and not out.exists() and not receipt.exists()
    check(name + " produces Incomplete coverage and never files")

missing = deepcopy(BASE); del missing["xl/worksheets/sheet1.xml"]
# Remove its CT override so this case reaches internal-target verification.
missing["[Content_Types].xml"] = missing["[Content_Types].xml"].replace(
    b'<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>', b'')
code, report = call("assess", write("missing-target", missing))
assert code == 2 and report["decision"]["result"] == "Fail" and not report["decision"]["rebuild_allowed"]
check("definite missing internal target is Fail rather than Unsupported or Incomplete")

corrupt = bytearray(write("bad-crc", BASE).read_bytes())
first_name_length = struct.unpack_from("<H", corrupt, 26)[0]
first_extra_length = struct.unpack_from("<H", corrupt, 28)[0]
corrupt[30 + first_name_length + first_extra_length] ^= 1
path = DEST / "bad-crc.xlsm"; path.write_bytes(corrupt)
code, report = call("assess", path)
assert code == 2 and report["decision"]["result"] == "Fail"
check("actual CRC integrity mismatch is Fail")

with zipfile.ZipFile(ROOT / "docs/evidence/verified.xlsx") as archive:
    tampered = {name: archive.read(name) for name in archive.namelist()}
tampered["xl/worksheets/sheet1.xml"] = tampered["xl/worksheets/sheet1.xml"].replace(b"123", b"124")
code, report = call("verify", write("changed-output", tampered), "--original", FIXTURE,
                    "--receipt", ROOT / "docs/evidence/verified.receipt.json")
assert code == 2 and report["status"] == "Fail"
check("actual output preservation mismatch is Fail rather than Unsupported")

summary = {"schema": "partsieve.coverage-regression.v1", "status": "Pass", "checks": checks,
           "source": "two pinned real fixtures; unsupported capability cases are artificial metadata variants, not compatibility proof"}
(ROOT / "docs/evidence/coverage-regression.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8", newline="\n")
print(json.dumps({"coverage_assertions": len(checks), "status": "Pass"}))
