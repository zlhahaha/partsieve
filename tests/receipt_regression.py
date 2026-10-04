"""Typed Receipt checks through the public host; never trust reported Pass."""
from collections import Counter
from copy import deepcopy
import json
from pathlib import Path
import subprocess
import sys
import zipfile
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "tests/generated/receipt"
DEST.mkdir(parents=True, exist_ok=True)
CLI = ROOT / "tools/partsieve.py"
schema = json.loads((ROOT / "docs/receipt-v2.schema.json").read_text(encoding="utf8"))
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema)
checks = []


def call(command, path, *args):
    result = subprocess.run([sys.executable, str(CLI), command, str(path), "--receipt-format", "v2", *map(str, args)],
                            cwd=ROOT, capture_output=True, text=True, timeout=90)
    return result.returncode, json.loads(result.stdout)


def check(name):
    checks.append({"name": name, "status": "Pass"})


records = []
for name, source, suffix, expected in [
    ("sheet", ROOT / "tests/fixtures/upstream/macro01.xlsm", ".xlsx", {"RemovedByPolicy": 1, "RegeneratedMetadata": 2, "BytePreserved": 7}),
    ("word", ROOT / "tests/fixtures/poi/SimpleMacro.docm", ".docx", {"RemovedByPolicy": 3, "RegeneratedMetadata": 2, "BytePreserved": 9}),
    ("clean", ROOT / "tests/fixtures/upstream/simple01.xlsx", ".xlsx", {"BytePreserved": 10}),
]:
    out, saved = DEST / (name + suffix), DEST / (name + ".receipt.json")
    out.unlink(missing_ok=True); saved.unlink(missing_ok=True)
    code, receipt = call("rebuild", source, "-o", out, "--receipt", saved)
    assert code == 0 and receipt["schema"] == "partsieve.receipt.v2-dev" and receipt["result"] == "Pass", receipt
    published = json.loads(saved.read_text(encoding="utf8")); validator.validate(published)
    assert published == {"publication": "pair-complete", "receipt": receipt}
    assert Counter(d["classification"] for d in receipt["dispositions"]) == expected
    assert len(receipt["dispositions"]) == len(receipt["plan"]["preconditions"])
    assert not receipt["output_findings"] and not receipt["allowed_capabilities"]
    assert receipt["independent_validation"] == "NotChecked" and not receipt["independent_tools"]
    assert all(r["state"] == "Checked" and r["presence"] == "Absent" for r in receipt["output_coverage"]["rules"])
    assert all(c["result"] == "Pass" for c in receipt["checks"] if c["state"] == "Checked")
    assert all("result" not in c for c in receipt["checks"] if c["state"] == "NotChecked")
    decisions = {d["decision_id"] for d in receipt["decisions"]}
    for d in receipt["dispositions"]:
        if d["classification"] == "BytePreserved": assert d["before_hash"] == d["after_hash"]
        else: assert d["decision_id"] in decisions and d["rule_id"] in ("vba-v1", "format-v1")
        if d["classification"] == "RemovedByPolicy": assert "after_hash" not in d
    assert call("verify", out, "--original", source, "--receipt", saved) == (0, receipt)
    again, again_receipt = DEST / (name + "-again" + suffix), DEST / (name + "-again.receipt.json")
    again.unlink(missing_ok=True); again_receipt.unlink(missing_ok=True)
    code, idempotent = call("rebuild", out, "-o", again, "--receipt", again_receipt)
    assert code == 0 and not idempotent["findings"] and not idempotent["plan"]["operations"]
    assert all(d["classification"] == "BytePreserved" for d in idempotent["dispositions"])
    with zipfile.ZipFile(out) as first, zipfile.ZipFile(again) as second:
        assert first.namelist() == second.namelist()
        assert all(first.read(n) == second.read(n) for n in first.namelist())
    code, partial = call("verify", out)
    assert code == 3 and partial["schema"] == "partsieve.verify.v2-partial" and partial["preservation"] == "NotChecked" and partial["status"] == "Incomplete"
    records.append((source, out, published))
    check(name + " typed Receipt shape, traceability, actual recomputation, payload idempotence and missing-original boundary")

word_source = records[1][0]
prepared = subprocess.run([sys.executable, str(CLI), "prepare", str(word_source)], cwd=ROOT,
                          capture_output=True, text=True, timeout=90)
assert prepared.returncode == 0
plan_path = DEST / "word.plan.json"
plan_path.write_text(prepared.stdout, encoding="utf8")
planned_out, planned_receipt = DEST / "planned.docx", DEST / "planned.receipt.json"
planned_out.unlink(missing_ok=True); planned_receipt.unlink(missing_ok=True)
code, receipt = call("rebuild", word_source, "--plan", plan_path, "-o", planned_out, "--receipt", planned_receipt)
assert code == 0 and receipt == records[1][2]["receipt"]
assert planned_out.read_bytes() == records[1][1].read_bytes()
check("saved prepared plan and typed Receipt use the same verified Word bytes")
release_out, release_receipt = DEST / "release.docx", DEST / "release.receipt.json"
release_out.unlink(missing_ok=True); release_receipt.unlink(missing_ok=True)
code, receipt = call("rebuild", word_source, "--release", "-o", release_out, "--receipt", release_receipt)
assert code == 0 and receipt == records[1][2]["receipt"]
assert release_out.read_bytes() == records[1][1].read_bytes()
assert call("verify", release_out, "--release", "--original", word_source, "--receipt", release_receipt) == (0, receipt)
check("public Release host recomputes the identical typed contract and bytes")

source, out, valid = records[0]
reordered = DEST / "reordered.receipt.json"
reordered.write_text(json.dumps(valid, sort_keys=True), encoding="utf8")
assert call("verify", out, "--original", source, "--receipt", reordered) == (0, valid["receipt"])
check("JSON object key order is irrelevant to a genuine typed Receipt")
raw = json.dumps(valid)
for name, payload, expected_code in [
    ("duplicate-key", '{"publication":"pair-complete",' + raw[1:], 2),
    ("invalid-utf8", b"\xff", 2),
    ("malformed", "{", 2),
    ("deep", "[" * 33 + "0" + "]" * 33, 3),
    ("long-token", '"' + "a" * 65537 + '"', 3),
]:
    p = DEST / (name + ".receipt.json")
    p.write_bytes(payload if isinstance(payload, bytes) else payload.encode("utf8"))
    code, error = call("verify", out, "--original", source, "--receipt", p)
    assert code == expected_code and error["status"] == ("Fail" if code == 2 else "Incomplete"), (name, error)
    check(name + " Receipt JSON is refused with a bounded diagnostic")
mutations = []
for name, field, value in [("input-hash", "input_hash", "0" * 64), ("output-hash", "output_hash", "0" * 64),
                           ("fake-client-pass", "independent_validation", "Checked"), ("fake-tools", "independent_tools", ["WPS Pass"]),
                           ("missing-decisions", "decisions", []), ("missing-parts", "dispositions", [])]:
    tampered = deepcopy(valid);tampered["receipt"][field] = value;mutations.append((name, tampered))
tampered = deepcopy(valid);tampered["receipt"]["output_coverage"]["rules"][0]["presence"] = "Unknown";mutations.append(("coverage-gap", tampered))
tampered = deepcopy(valid);tampered["receipt"]["plan"]["operations"][0]["before_hash"] = "0" * 64;mutations.append(("operation-precondition", tampered))
tampered = deepcopy(valid);next(d for d in tampered["receipt"]["dispositions"] if d["classification"] == "BytePreserved")["after_hash"] = "0" * 64;mutations.append(("preservation-claim", tampered))
tampered = deepcopy(valid);tampered["receipt"]["decisions"][0]["finding_index"] = False;mutations.append(("boolean-as-number", tampered))
for name, tampered in mutations:
    p = DEST / (name + ".receipt.json");p.write_text(json.dumps(tampered), encoding="utf8")
    code, error = call("verify", out, "--original", source, "--receipt", p)
    assert code == 2 and error["status"] == "Fail", (name, error)
    check(name + " cannot manufacture verification Pass")
with zipfile.ZipFile(out) as z: parts = {n: z.read(n) for n in z.namelist()}
parts["xl/worksheets/sheet1.xml"] = parts["xl/worksheets/sheet1.xml"].replace(b"123", b"124")
changed = DEST / "changed.xlsx"
with zipfile.ZipFile(changed, "w") as z:
    for name, payload in parts.items(): z.writestr(name, payload)
code, error = call("verify", changed, "--original", source)
assert code == 2 and error["status"] == "Fail"
check("typed verify reparses actual modified output rather than executor memory")
with zipfile.ZipFile(source) as z: original_parts = {n: z.read(n) for n in z.namelist()}
original_parts["xl/worksheets/sheet1.xml"] = original_parts["xl/worksheets/sheet1.xml"].replace(b"123", b"122")
changed_original = DEST / "changed-original.xlsm"
with zipfile.ZipFile(changed_original, "w") as z:
    for name, payload in original_parts.items(): z.writestr(name, payload)
code, error = call("verify", out, "--original", changed_original)
assert code == 2 and error["status"] == "Fail"
check("modified original cannot match preservation of earlier output")
for name, path in [("unsupported", ROOT / "tests/fixtures/poi/SampleDoc.docx"), ("incomplete", DEST / "truncated.docm")]:
    if name == "incomplete": path.write_bytes(b"PK\x03\x04")
    output, receipt = DEST / (name + ".docx"), DEST / (name + ".receipt.json")
    code, error = call("rebuild", path, "-o", output, "--receipt", receipt)
    assert code == 3 and not output.exists() and not receipt.exists()
    check(name + " returns no typed success pair")
summary = {"schema": "partsieve.receipt-regression.v1", "status": "Pass", "checks": checks,
           "scope": "Current accepted VBA profiles; semantic source rewrites and independent clients remain uncertified."}
(ROOT / "docs/evidence/receipt-regression.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf8", newline="\n")
print(json.dumps({"receipt_assertions": len(checks), "status": "Pass"}))
