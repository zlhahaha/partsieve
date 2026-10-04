"""Independent checks for the pinned Word VBA fixture, without Office execution."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys
import zipfile
import xml.etree.ElementTree as ET

before, after = map(Path, sys.argv[1:3])
removed = {"word/vbaProject.bin", "word/vbaData.xml", "word/_rels/vbaProject.bin.rels"}
metadata = {"[Content_Types].xml", "word/_rels/document.xml.rels"}
records = []
with zipfile.ZipFile(before) as a, zipfile.ZipFile(after) as b:
    assert a.testzip() is None and b.testzip() is None
    assert len(a.namelist()) == len(set(a.namelist()))
    assert len(b.namelist()) == len(set(b.namelist()))
    assert set(b.namelist()) == set(a.namelist()) - removed
    for name in a.namelist():
        old = hashlib.sha256(a.read(name)).hexdigest()
        new = hashlib.sha256(b.read(name)).hexdigest() if name in b.namelist() else None
        classification = "RemovedByPolicy" if name in removed else "RegeneratedMetadata" if name in metadata else "BytePreserved"
        if classification == "BytePreserved":
            assert old == new, name
        records.append({"part": name, "before": old, "after": new, "classification": classification})
    for name in b.namelist():
        if name.endswith((".xml", ".rels")):
            root = ET.fromstring(b.read(name))
            if name.endswith(".rels"):
                assert all(not r.attrib["Type"].endswith(("/vbaProject", "/wordVbaData")) for r in root)
    ct = ET.fromstring(b.read("[Content_Types].xml"))
    mappings = {r.attrib.get("PartName"): r.attrib["ContentType"] for r in ct}
    assert mappings["/word/document.xml"] == "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"
    assert all("vba" not in r.attrib["ContentType"].lower() and "macroEnabled" not in r.attrib["ContentType"] for r in ct)
    ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    body = ET.fromstring(b.read("word/document.xml"))
    text = "".join(n.text or "" for n in body.findall(".//w:t", ns))
    assert text == "This is a macro word processing document"
    assert body.find(".//w:pgSz", ns).attrib == {"{" + ns["w"] + "}w": "12240", "{" + ns["w"] + "}h": "15840"}
report = {"tool": "CPython zipfile + ElementTree", "version": sys.version.split()[0], "status": "Pass",
          "input_sha256": hashlib.sha256(before.read_bytes()).hexdigest(),
          "output_sha256": hashlib.sha256(after.read_bytes()).hexdigest(), "text": text,
          "counts": dict(Counter(r["classification"] for r in records)), "parts": records}
print(json.dumps(report, indent=2))
