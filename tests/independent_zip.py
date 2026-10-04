"""Independent ZIP/XML/part-preservation check; test dependency only."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile
import xml.etree.ElementTree as ET

before, after = map(Path, sys.argv[1:3])
records = []
with zipfile.ZipFile(before) as a, zipfile.ZipFile(after) as b:
    assert a.testzip() is None and b.testzip() is None
    assert len(a.namelist()) == len(set(a.namelist()))
    assert len(b.namelist()) == len(set(b.namelist()))
    assert "xl/vbaProject.bin" in a.namelist()
    assert "xl/vbaProject.bin" not in b.namelist()
    expected_changes = {"[Content_Types].xml", "xl/_rels/workbook.xml.rels", "xl/vbaProject.bin"}
    assert set(b.namelist()) == set(a.namelist()) - {"xl/vbaProject.bin"}
    for name in a.namelist():
        old = hashlib.sha256(a.read(name)).hexdigest()
        new = hashlib.sha256(b.read(name)).hexdigest() if name in b.namelist() else None
        if name not in expected_changes:
            assert old == new, name
        records.append({"part": name, "before": old, "after": new})
    for name in b.namelist():
        if name.endswith((".xml", ".rels")):
            root = ET.fromstring(b.read(name))
            if name.endswith(".rels"):
                assert all(not r.attrib["Type"].endswith("/vbaProject") for r in root)
    assert b"macroEnabled" not in b.read("[Content_Types].xml")
    root = ET.fromstring(b.read("xl/worksheets/sheet1.xml"))
    ns = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    assert root.find(".//s:c[@r='A1']/s:v", ns).text == "123"
report = {"tool": "CPython zipfile + ElementTree", "version": sys.version.split()[0],
          "status": "Pass", "input_sha256": hashlib.sha256(before.read_bytes()).hexdigest(),
          "output_sha256": hashlib.sha256(after.read_bytes()).hexdigest(),
          "a1": 123, "parts": records}
print(json.dumps(report, indent=2))
