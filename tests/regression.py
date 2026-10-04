"""Feature-based spike corpus derived from a pinned real Excel fixture."""
from copy import deepcopy
import hashlib
import io
import json
from pathlib import Path
import struct
import subprocess
import sys
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "tools/partsieve.py"
GENERATED = ROOT / "tests/generated"
GENERATED.mkdir(exist_ok=True)
with zipfile.ZipFile(ROOT / "tests/fixtures/upstream/macro01.xlsm") as z:
    BASE = {n: z.read(n) for n in z.namelist()}
RELS = "xl/_rels/workbook.xml.rels"
CT = "[Content_Types].xml"
WORKBOOK = "xl/workbook.xml"
SHEET = "xl/worksheets/sheet1.xml"
VBA = "xl/vbaProject.bin"
OFFICE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
records = []


def package(parts, extra=()):
    out = io.BytesIO()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
            for name, payload in list(parts.items()) + list(extra):
                z.writestr(name, payload)
    return out.getvalue()


def change(part, old, new):
    data = deepcopy(BASE)
    assert old in data[part], (part, old)
    data[part] = data[part].replace(old, new)
    return data


def call(*args):
    process = subprocess.run([sys.executable, str(CLI), *map(str, args)], cwd=ROOT,
                             capture_output=True, text=True, timeout=90)
    try:
        result = json.loads(process.stdout)
    except ValueError as exc:
        raise AssertionError((process.returncode, process.stdout, process.stderr)) from exc
    return process.returncode, result


def fixture(name, payload, accept=False):
    path = GENERATED / (name + ".xlsm")
    path.write_bytes(payload)
    code, result = call("audit", path)
    assert (code == 0) == accept, (name, code, result)
    incomplete_cases = {
        "malformed-zip", "zip-truncated", "invalid-utf8", "malformed-xml",
        "xml-depth-plus-one", "per-element-attributes-over-limit", "markup-token-over-limit",
        "high-compression-xml-over-limit", "zip-entry-over-limit", "sdk-host-input-over-limit",
        "declared-uncompressed-size-understates-actual", "local-central-size-disagreement"
    }
    if name in incomplete_cases:
        assert result.get("status") == "Incomplete", (name, result)
    records.append({"name": name, "sha256": hashlib.sha256(payload).hexdigest(),
                    "source": "derived from pinned upstream macro01.xlsm",
                    "license": "BSD-2-Clause (upstream fixture)",
                    "expected": "AcceptedWithinProfile" if accept else "Refuse",
                    "actual_exit": code, "status": result.get("status", "Pass"), "reason": result.get("error")})
    return path


fixture("real-vba-control", package(BASE), True)
clean = ROOT / "tests/fixtures/upstream/simple01.xlsx"
code, clean_audit = call("audit", clean)
assert code == 0 and not clean_audit["findings"], clean_audit
records.append({"name": "clean-real-xlsx", "expected": "AcceptedWithinProfile", "actual_exit": code})
fixture("duplicate-name", package(BASE, [(SHEET, BASE[SHEET])]))
fixture("case-alias", package(BASE, [("XL/styles.xml", BASE["xl/styles.xml"])]))
fixture("malformed-zip", b"not a zip")
fixture("zip-truncated", package(BASE)[:-15])
bad = bytearray(package(BASE))
bad[30] ^= 1
fixture("local-central-name-disagreement", bytes(bad))
# Contradictory headers and matching false sizes are different attack paths.
bad = bytearray(package(BASE))
first_size = struct.unpack_from("<I", bad, 22)[0]
struct.pack_into("<I", bad, 22, first_size - 1)
fixture("local-central-size-disagreement", bytes(bad))
central_start = struct.unpack_from("<I", bad, len(bad) - 6)[0]
assert bad[central_start:central_start + 4] == b"PK\x01\x02"
struct.pack_into("<I", bad, central_start + 24, first_size - 1)
fixture("declared-uncompressed-size-understates-actual", bytes(bad))
store = io.BytesIO()
with zipfile.ZipFile(store, "w", zipfile.ZIP_STORED) as z:
    for n, p in BASE.items():
        z.writestr(n, p)
bad = bytearray(store.getvalue())
pos = bad.index(b"standalone")
bad[pos] ^= 1
fixture("payload-crc-mismatch", bytes(bad))
fixture("invalid-utf8", package({**BASE, SHEET: b"\xff"}))
fixture("malformed-xml", package({**BASE, SHEET: b"<worksheet>"}))
fixture("metadata-unknown-root-attribute", package(change(CT, b"<Types ", b"<Types custom='x' ")))
fixture("metadata-non-whitespace-text", package(change(RELS, b"</Relationships>", b"unexpected</Relationships>")))
fixture("dtd-entity", package(change(SHEET, b"<worksheet", b"<!DOCTYPE worksheet [<!ENTITY x '123'>]><worksheet")))
fixture("duplicate-local-id", package(change(RELS, b'Id="rId4"', b'Id="rId1"')))
fixture("missing-target", package(change(RELS, b'Target="styles.xml"', b'Target="missing.xml"')))
fixture("traversal-target", package(change(RELS, b'Target="styles.xml"', b'Target="../../evil.xml"')))
fixture("percent-encoding-target", package(change(RELS, b'Target="styles.xml"', b'Target="%73tyles.xml"')))
fixture("external-workbook", package(change(RELS, b"relationships/theme", b"relationships/externalLink")))
fixture("external-target", package(change(RELS, b'Target="styles.xml"', b'Target="https://example.invalid/x" TargetMode="External"')))
fixture("activex", package(change(RELS, b"relationships/theme", b"relationships/control")))
fixture("ole", package(change(RELS, b"relationships/theme", b"relationships/oleObject")))
fixture("unknown-relation", package(change(RELS, b"relationships/theme", b"relationships/unknown")))
fixture("dangling-source-id", package(change(WORKBOOK, b'r:id="rId1"', b'r:id="missing"')))
fixture("wrong-source-binding", package(change(WORKBOOK, b'r:id="rId1"', b'r:id="rId3"')))
fixture("missing-source-id", package(change(WORKBOOK, b' r:id="rId1"', b"")))
fixture("wrong-source-element-placement", package({**BASE, SHEET: BASE[SHEET].replace(b"<v>123</v>", b"<v><row/></v>")}))
fixture("formula", package(change(SHEET, b"<v>123</v>", b'<f>WEBSERVICE("https://example.invalid")</f><v>123</v>')))
fixture("alternate-content", package(change(SHEET, b"<sheetData>", b"<sheetData><mc:AlternateContent xmlns:mc='http://schemas.openxmlformats.org/markup-compatibility/2006'/>")))
fixture("unknown-extension", package(change(SHEET, b"<sheetData>", b"<sheetData><extLst/>")))
fixture("undefined-prefix", package(change(WORKBOOK, b"<sheet ", b"<q:sheet ")))
fixture("renamed-vba", package({**{n: p for n, p in BASE.items() if n != VBA},
    "xl/renamed.bin": BASE[VBA], RELS: BASE[RELS].replace(b"vbaProject.bin", b"renamed.bin")}), True)
fixture("orphan-vba", package(change(RELS, b'<Relationship Id="rId4" Type="http://schemas.microsoft.com/office/2006/relationships/vbaProject" Target="vbaProject.bin"/>', b"")))
shared = BASE[RELS].replace(b"</Relationships>",
    b'<Relationship Id="shared" Type="http://schemas.microsoft.com/office/2006/relationships/vbaProject" Target="vbaProject.bin"/></Relationships>')
fixture("shared-vba", package({**BASE, RELS: shared}))
fixture("unknown-orphan", package({**BASE, "orphan.bin": b"unknown"}))
fixture("type-evidence-conflict", package(change(CT, b"application/vnd.ms-office.vbaProject", b"application/xml")))
fixture("non-cfb-vba", package({**BASE, VBA: b"fake VBA"}))
fixture("macro-in-xlsx-type", package(change(CT, b"application/vnd.ms-excel.sheet.macroEnabled.main+xml",
    b"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml")))
without = {n: p for n, p in BASE.items() if n != VBA}
without[RELS] = without[RELS].replace(b'<Relationship Id="rId4" Type="http://schemas.microsoft.com/office/2006/relationships/vbaProject" Target="vbaProject.bin"/>', b"")
no_vba = fixture("macro-enabled-without-vba", package(without), True)
prefix = change(WORKBOOK, b'xmlns:r=', b'xmlns:other=')
prefix[WORKBOOK] = prefix[WORKBOOK].replace(b'r:id=', b'other:id=')
prefix_path = fixture("namespace-prefix-variation", package(prefix), True)
absolute = change(RELS, b'Target="styles.xml"', b'Target="/xl/styles.xml"')
fixture("absolute-target", package(absolute), True)
fixture("xml-depth-plus-one", package({**BASE, SHEET: b"<a>" * 129 + b"</a>" * 129}))
fixture("per-element-attributes-over-limit", package({**BASE, SHEET: ("<a " + " ".join(f"a{i}='x'" for i in range(257)) + "/>").encode()}))
fixture("markup-token-over-limit", package({**BASE, SHEET: b"<a x='" + b"x" * 65536 + b"'/>"}))
fixture("high-compression-xml-over-limit", package({**BASE, SHEET: b"<a>" + b"x" * (8 * 1024 * 1024) + b"</a>"}))
fixture("zip-entry-over-limit", package({**BASE, VBA: b"x" * (32 * 1024 * 1024 + 1)}))
fixture("sdk-host-input-over-limit", b"x" * (32 * 1024 * 1024 + 1))

# Full rebuild, verification, forgery refusal, clean idempotence, host publish.
out = GENERATED / "verified.xlsx"
receipt = GENERATED / "verified.receipt.json"
out.unlink(missing_ok=True)
receipt.unlink(missing_ok=True)
assert call("rebuild", ROOT / "tests/fixtures/upstream/macro01.xlsm", "-o", out, "--receipt", receipt)[0] == 0
assert call("verify", out, "--original", ROOT / "tests/fixtures/upstream/macro01.xlsm", "--receipt", receipt)[0] == 0
saved = json.loads(receipt.read_bytes())
saved["receipt"]["plan"]["operations"] = []
forged = GENERATED / "forged.receipt.json"
forged.write_text(json.dumps(saved))
assert call("verify", out, "--original", ROOT / "tests/fixtures/upstream/macro01.xlsm", "--receipt", forged)[0] == 2
assert call("verify", out)[0] == 3
assert call("rebuild", clean, "--dry-run")[0] == 0
clean_out = GENERATED / "clean-preserved.xlsx"
clean_receipt = GENERATED / "clean-preserved.json"
clean_out.unlink(missing_ok=True)
clean_receipt.unlink(missing_ok=True)
assert call("rebuild", clean, "-o", clean_out, "--receipt", clean_receipt)[0] == 0
with zipfile.ZipFile(clean) as a, zipfile.ZipFile(clean_out) as b:
    assert {n: a.read(n) for n in a.namelist()} == {n: b.read(n) for n in b.namelist()}
assert call("rebuild", clean, "-o", out, "--receipt", receipt)[0] == 4
with zipfile.ZipFile(out) as z:
    output_parts = {n: z.read(n) for n in z.namelist()}
tampered = GENERATED / "tampered.xlsx"
tampered.write_bytes(package({**output_parts, SHEET: output_parts[SHEET].replace(b"123", b"124")}))
assert call("verify", tampered, "--original", ROOT / "tests/fixtures/upstream/macro01.xlsm", "--receipt", receipt)[0] != 0
changed_original = GENERATED / "changed-original.xlsm"
changed_original.write_bytes(package(change(SHEET, b"123", b"124")))
assert call("verify", out, "--original", changed_original, "--receipt", receipt)[0] != 0
second = GENERATED / "second.xlsx"
second_receipt = GENERATED / "second.receipt.json"
second.unlink(missing_ok=True)
second_receipt.unlink(missing_ok=True)
assert call("rebuild", out, "-o", second, "--receipt", second_receipt)[0] == 0
with zipfile.ZipFile(second) as z:
    assert {n: z.read(n) for n in z.namelist()} == output_parts
reject_out = GENERATED / "must-not-exist.xlsx"
reject_receipt = GENERATED / "must-not-exist.json"
reject_out.unlink(missing_ok=True)
reject_receipt.unlink(missing_ok=True)
assert call("rebuild", GENERATED / "formula.xlsm", "-o", reject_out, "--receipt", reject_receipt)[0] != 0
assert not reject_out.exists() and not reject_receipt.exists()
for path in [no_vba, prefix_path, GENERATED / "renamed-vba.xlsm"]:
    dest = GENERATED / (path.stem + ".xlsx")
    rec = GENERATED / (path.stem + ".json")
    dest.unlink(missing_ok=True)
    rec.unlink(missing_ok=True)
    assert call("rebuild", path, "-o", dest, "--receipt", rec)[0] == 0
integration_checks = [
    "genuine-vba-rebuild", "original-and-receipt-verify", "forged-receipt-refused",
    "no-original-incomplete", "dry-run", "clean-xlsx-rebuild", "clean-payloads-preserved",
    "existing-output-not-overwritten", "tampered-output-refused", "changed-original-refused",
    "second-rebuild", "second-rebuild-payload-idempotence", "unsupported-rebuild-refused",
    "refusal-publishes-no-files", "macro-enabled-without-vba-rebuild",
    "namespace-prefix-variation-rebuild", "renamed-vba-rebuild"
]
manifest = {"schema": "partsieve.corpus.spike-v1", "fixtures": records,
            "fixture_count": len(records), "integration_assertions": len(integration_checks),
            "integration_checks": integration_checks, "status": "Pass"}
(ROOT / "docs/evidence/regression.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
print(json.dumps({"fixture_count": len(records), "integration_assertions": len(integration_checks), "status": "Pass"}))
