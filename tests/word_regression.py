"""Word handler tests. Artificial variants do not extend client compatibility."""
from collections import Counter
from copy import deepcopy
import json
from pathlib import Path
import subprocess
import sys
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "tools/partsieve.py"
DEST = ROOT / "tests/generated/word"
DEST.mkdir(parents=True, exist_ok=True)
FIXTURE = ROOT / "tests/fixtures/poi/SimpleMacro.docm"
with zipfile.ZipFile(FIXTURE) as archive:
    BASE = {name: archive.read(name) for name in archive.namelist()}
with zipfile.ZipFile(ROOT / "docs/evidence/word-verified.docx") as archive:
    CLEAN = {name: archive.read(name) for name in archive.namelist()}
REL = "http://schemas.openxmlformats.org/package/2006/relationships"
OFFICE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
VBA = "http://schemas.microsoft.com/office/2006/relationships/vbaProject"
DATA = "http://schemas.microsoft.com/office/2006/relationships/wordVbaData"
W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
DOCM = b"application/vnd.ms-word.document.macroEnabled.main+xml"
DOCX = b"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"
checks = []


def call(command, path, *args):
    result = subprocess.run([sys.executable, str(CLI), command, str(path), *map(str, args)],
                            cwd=ROOT, capture_output=True, text=True, timeout=90)
    return result.returncode, json.loads(result.stdout)


def write(name, parts):
    path = DEST / (name + ".zip")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as archive:
        for part, payload in parts.items(): archive.writestr(part, payload)
    return path


def check(name):
    checks.append({"name": name, "status": "Pass"})


def relation(parts, file, kind, target, id="extra", external=False):
    root = ET.fromstring(parts[file])
    attributes = {"Id": id, "Type": kind, "Target": target}
    if external: attributes["TargetMode"] = "External"
    ET.SubElement(root, "{" + REL + "}Relationship", attributes)
    parts[file] = ET.tostring(root, encoding="utf-8")


def rebuilt(name, path):
    out, receipt = DEST / (name + ".docx"), DEST / (name + ".receipt.json")
    # Only this test's known generated destinations are replaced between runs.
    out.unlink(missing_ok=True); receipt.unlink(missing_ok=True)
    code, report = call("rebuild", path, "-o", out, "--receipt", receipt)
    assert code == 0, (name, report)
    assert report["output_format"] == "DOCX" and report["structure"] == report["preservation"] == "Pass"
    code, verified = call("verify", out, "--original", path, "--receipt", receipt)
    assert code == 0 and verified == report
    return out, report


def refused(name, parts):
    path = write(name, parts)
    code, report = call("assess", path)
    assert code == 3 and report["decision"]["result"] == "Unsupported", (name, report)
    out, receipt = DEST / (name + ".docx"), DEST / (name + ".receipt.json")
    code, diagnostic = call("rebuild", path, "-o", out, "--receipt", receipt)
    assert code == 3 and not out.exists() and not receipt.exists(), (name, diagnostic)
    check(name + " refuses and publishes neither document nor Receipt")


code, audit = call("audit", FIXTURE)
assert code == 0 and audit["format"] == "DOCM" and len(audit["findings"]) == 1
code, assessment = call("assess", FIXTURE)
assert code == 0 and assessment["decision"]["rebuild_allowed"]
assert all(f["capability"] == "VBA" for f in assessment["findings"])
check("real DOCM records main type, actual VBA relationship and companion evidence")
out, receipt = rebuilt("real", FIXTURE)
counts = Counter(d["classification"] for d in receipt["dispositions"])
assert counts == {"RemovedByPolicy": 3, "RegeneratedMetadata": 2, "BytePreserved": 9}
assert out.read_bytes() == (ROOT / "docs/evidence/word-verified.docx").read_bytes()
check("real DOCM converts deterministically; all fourteen input parts have checked dispositions")
code, assessment = call("assess", out)
assert code == 0 and not assessment["findings"] and all(r["presence"] == "Absent" for r in assessment["coverage"]["rules"])
out, receipt = rebuilt("derived-clean", out)
assert not receipt["plan"]["operations"] and all(d["classification"] == "BytePreserved" for d in receipt["dispositions"])
check("derived clean DOCX negative has no VBA and preserves all eleven payloads")
code, partial = call("verify", out)
assert code == 3 and partial["structure"] == "Pass" and partial["preservation"] == "NotChecked"
check("Word verify without original remains Incomplete even with valid output structure")

parts = deepcopy(CLEAN)
parts["[Content_Types].xml"] = parts["[Content_Types].xml"].replace(DOCX, DOCM)
out, receipt = rebuilt("macro-type-without-vba", write("macro-type-without-vba", parts))
assert not receipt["audit"]["findings"] and len(receipt["plan"]["operations"]) == 2
assert Counter(d["classification"] for d in receipt["dispositions"]) == {"RegeneratedMetadata": 1, "BytePreserved": 10}
check("macro-enabled main type without VBA converts without invented macro evidence")

parts = deepcopy(BASE)
for old, new in [("word/vbaProject.bin", "word/code.bin"), ("word/_rels/vbaProject.bin.rels", "word/_rels/code.bin.rels"), ("word/vbaData.xml", "word/metadata.xml")]:
    parts[new] = parts.pop(old)
for name in ["[Content_Types].xml", "word/_rels/document.xml.rels", "word/_rels/code.bin.rels"]:
    parts[name] = parts[name].replace(b"vbaProject.bin", b"code.bin").replace(b"vbaData.xml", b"metadata.xml")
out, receipt = rebuilt("renamed-controlled", write("renamed-controlled", parts))
assert {d["part"] for d in receipt["dispositions"] if d["classification"] == "RemovedByPolicy"} == {"word/code.bin", "word/_rels/code.bin.rels", "word/metadata.xml"}
check("renamed VBA project, relationship part and data removed by semantic evidence")
parts = deepcopy(BASE)
parts["word/_rels/document.xml.rels"] = parts["word/_rels/document.xml.rels"].replace(b'Target="vbaProject.bin"', b'Target="/word/vbaProject.bin"')
parts["word/_rels/vbaProject.bin.rels"] = parts["word/_rels/vbaProject.bin.rels"].replace(b'Target="vbaData.xml"', b'Target="/word/vbaData.xml"')
rebuilt("absolute-controlled", write("absolute-controlled", parts))
check("package absolute controlled targets have the same removal semantics")
parts = deepcopy(BASE)
relation(parts, "word/_rels/document.xml.rels", VBA, "vbaProject.bin")
refused("shared-project", parts)
parts = deepcopy(BASE)
relation(parts, "word/_rels/vbaProject.bin.rels", DATA, "vbaData.xml")
refused("shared-data", parts)
parts = deepcopy(BASE)
parts["word/_rels/document.xml.rels"] = ET.tostring(ET.fromstring(parts["word/_rels/document.xml.rels"]), encoding="utf-8")
root = ET.fromstring(parts["word/_rels/document.xml.rels"])
for e in list(root):
    if e.attrib["Type"] == VBA: root.remove(e)
parts["word/_rels/document.xml.rels"] = ET.tostring(root, encoding="utf-8")
refused("orphan-project", parts)
parts = deepcopy(BASE)
parts.pop("word/_rels/vbaProject.bin.rels")
refused("orphan-data", parts)
parts = deepcopy(BASE)
parts["word/_rels/vbaData.xml.rels"] = ('<Relationships xmlns="' + REL + '"/>').encode()
refused("nested-data-dependencies", parts)
parts = deepcopy(BASE)
parts["[Content_Types].xml"] = parts["[Content_Types].xml"].replace(DOCM, DOCX)
refused("vba-in-non-macro-main", parts)
parts = deepcopy(BASE)
parts["word/vbaProject.bin"] = b"not a real CFB"
refused("invalid-cfb", parts)
parts = deepcopy(BASE)
parts["word/document.xml"] = parts["word/document.xml"].replace(b"<w:t>", b'<w:t r:id="rId1">')
refused("retained-reference-project", parts)
for name, kind in [("remote-template", "attachedTemplate"), ("http-link", "hyperlink"), ("external-image", "image"), ("ole", "oleObject"), ("activex", "control")]:
    parts = deepcopy(BASE)
    relation(parts, "word/_rels/document.xml.rels", OFFICE + kind, "https://example.invalid/resource", external=True)
    refused("mixed-vba-" + name, parts)
for name, part, old, new in [
    ("unknown-attribute", "word/document.xml", b"<w:body>", b'<w:body w:unknownFeature="1">'),
    ("field-semantics", "word/document.xml", b"<w:t>", b'<w:fldChar w:fldCharType="begin"/><w:t>'),
    ("template-property-uri", "docProps/app.xml", b"Normal.dotm", b"https://example.invalid/evil.dotm"),
    ("vml-shape", "word/settings.xml", b"<w:compat/>", b'<w:compat/><v:shape id="x"/>'),
    ("attached-template-without-rel", "word/settings.xml", b"<w:compat/>", b'<w:compat/><w:attachedTemplate/>'),
]:
    parts = deepcopy(BASE); assert old in parts[part]
    parts[part] = parts[part].replace(old, new)
    refused(name, parts)
parts = deepcopy(BASE)
parts["word/document.xml"] = parts["word/document.xml"].replace(b'This is a macro', b'Changed is a macro')
changed_original = write("changed-original", parts)
code, diagnostic = call("verify", ROOT / "docs/evidence/word-verified.docx", "--original", changed_original)
assert code == 2 and diagnostic["status"] == "Fail"
check("Word body payload mismatch fails independent recomputation")
for name, path, suffix in [("word-wrong-suffix", FIXTURE, ".xlsx"), ("sheet-wrong-suffix", ROOT / "tests/fixtures/upstream/macro01.xlsm", ".docx")]:
    output, receipt = DEST / (name + suffix), DEST / (name + ".receipt.json")
    code, diagnostic = call("rebuild", path, "-o", output, "--receipt", receipt)
    assert code == 4 and not output.exists() and not receipt.exists()
    check(name + " never publishes misleading format extension")
code, unsupported = call("assess", ROOT / "tests/fixtures/poi/SampleDoc.docx")
assert code == 3 and unsupported["decision"]["result"] == "Unsupported"
check("real clean DOCX with custom XML is refused; clean does not imply supported")
summary = {"schema": "partsieve.word-regression.v1", "status": "Pass", "checks": checks,
           "source": "one pinned real DOCM; its macro-free derived clean negative; one real clean DOCX outside profile. Artificial mutations are refusal/ownership tests, not extra client evidence."}
(ROOT / "docs/evidence/word-regression.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf8", newline="\n")
print(json.dumps({"word_assertions": len(checks), "status": "Pass"}))
