"""Validate graph facts through the public bounded host and pinned real fixture."""
from copy import deepcopy
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "tools/partsieve.py"
DEST = ROOT / "tests/generated/graph"
DEST.mkdir(parents=True, exist_ok=True)
FIXTURE = ROOT / "tests/fixtures/upstream/macro01.xlsm"
with zipfile.ZipFile(FIXTURE) as archive:
    BASE = {name: archive.read(name) for name in archive.namelist()}
OFFICE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
checks = []


def call(command, path, *args, accepted=True):
    run = subprocess.run([sys.executable, str(CLI), command, str(path), *map(str, args)],
                         cwd=ROOT, capture_output=True, text=True, timeout=90)
    assert (run.returncode == 0) == accepted, (command, run.returncode, run.stdout, run.stderr)
    return json.loads(run.stdout)


def fixture(name, parts):
    path = DEST / (name + ".xlsm")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for part, data in parts.items():
            archive.writestr(part, data)
    return path


def check(name):
    checks.append({"name": name, "status": "Pass"})


graph = call("graph", FIXTURE)
assert graph == call("graph", FIXTURE)
check("same input produces stable public graph")
audit = call("audit", FIXTURE)
assert graph["parts"] == audit["parts"] and graph["relationships"] == audit["relationships"]
assert graph["root"] == "/" and not graph["coverage_gaps"]
check("audit and graph expose identical part and relationship facts")
nodes = {n["part"]: n for n in graph["nodes"]}
assert len(nodes) == len(graph["parts"]) + 1 and nodes["/"]["reachable"]
for index, edge in enumerate(graph["relationships"]):
    assert index in nodes[edge["source"]]["outbound"]
    if not edge["external"]:
        assert index in nodes[edge["resolved"]]["inbound"]
for index, ref in enumerate(graph["xml_references"]):
    edge = graph["relationships"][ref["relationship_index"]]
    assert edge["source"] == ref["source"] and edge["id"] == ref["relationship_id"]
    assert index in nodes[ref["source"]]["xml_references"]
assert len(graph["xml_references"]) == 1
check("real workbook source-local sheet reference and inbound/outbound indices")
assert sorted(p for group in graph["content_types"] for p in group["parts"]) == sorted(nodes.keys() - {"/"})
check("complete content-type index and package-root node")
vba = [i for i,r in enumerate(graph["relationships"]) if r["kind"].endswith("/vbaProject")]
assert len(vba) == 1 and vba[0] in [r["relationship_index"] for r in graph["implicit_references"]]
assert "xl/vbaProject.bin" in graph["reachable"]
check("VBA implicit workbook relationship is reachable and indexed")

absolute = deepcopy(BASE)
absolute["xl/_rels/workbook.xml.rels"] = absolute["xl/_rels/workbook.xml.rels"].replace(
    b'Target="worksheets/sheet1.xml"', b'Target="/xl/worksheets/sheet1.xml"')
path = fixture("absolute-target", absolute)
g = call("graph", path)
assert [r["resolved"] for r in g["relationships"]] == [r["resolved"] for r in graph["relationships"]]
assert call("audit", path)["format"] == "XLSM"
check("package-absolute and source-relative targets resolve identically")

external = deepcopy(BASE)
external["xl/_rels/workbook.xml.rels"] = external["xl/_rels/workbook.xml.rels"].replace(
    b'</Relationships>', ('<Relationship Id="outside" Type="'+ OFFICE +
    'hyperlink" Target="https://example.invalid/xl/styles.xml" TargetMode="External"/></Relationships>').encode())
path = fixture("external-target", external)
g = call("graph", path)
edge_index = next(i for i,r in enumerate(g["relationships"]) if r["id"] == "outside")
edge = g["relationships"][edge_index]
assert edge["external"] and edge["resolved"] == ""
assert all(edge_index not in n["inbound"] for n in g["nodes"])
call("audit", path, accepted=False)
check("external URL never creates an internal edge; rebuilding profile refuses")

orphan = deepcopy(BASE)
orphan["xl/unusedstyles.xml"] = BASE["xl/styles.xml"]
orphan["[Content_Types].xml"] = orphan["[Content_Types].xml"].replace(b'</Types>',
    b'<Override PartName="/xl/unusedstyles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>')
path = fixture("known-orphan", orphan)
g = call("graph", path)
assert "xl/unusedstyles.xml" in g["orphan_candidates"]
output, receipt = DEST / "retained.xlsx", DEST / "retained.receipt.json"
for p in (output, receipt):
    if p.is_file(): p.unlink()
call("rebuild", path, "-o", output, "--receipt", receipt)
call("verify", output, "--original", path, "--receipt", receipt)
with zipfile.ZipFile(output) as archive:
    assert archive.read("xl/unusedstyles.xml") == orphan["xl/unusedstyles.xml"]
assert "xl/unusedstyles.xml" in call("graph", output)["orphan_candidates"]
check("orphan candidate retained byte-for-byte through rebuild and verify")

for name, xml in {
    "alternate-content": '<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"/>',
    "vml": '<v:shape xmlns:v="urn:schemas-microsoft-com:vml"/>',
    "unknown-extension": '<extLst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"/>',
}.items():
    parts = deepcopy(BASE)
    parts["xl/worksheets/sheet1.xml"] = parts["xl/worksheets/sheet1.xml"].replace(b'</worksheet>', xml.encode() + b'</worksheet>')
    path = fixture(name, parts)
    g = call("graph", path)
    assert g["coverage_gaps"] and any("xl/worksheets/sheet1.xml" in gap for gap in g["coverage_gaps"])
    call("audit", path, accepted=False)
    check(name + " is an explicit coverage gap and refuses profile audit")

summary = {"schema": "partsieve.graph-regression.v1", "status": "Pass", "checks": checks,
           "source": "pinned public macro01.xlsm and artificial mutations; not extra client compatibility evidence",
           "fixture_sha256": hashlib.sha256(FIXTURE.read_bytes()).hexdigest()}
(ROOT / "docs/evidence/graph-regression.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8", newline="\n")
print(json.dumps({"graph_assertions": len(checks), "status": "Pass"}))
