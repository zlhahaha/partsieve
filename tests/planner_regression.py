"""Public host plan execution and rejection; reports remain local/CI artifacts."""
from copy import deepcopy
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "tests/generated/planner"
DEST.mkdir(parents=True, exist_ok=True)
CLI = ROOT / "tools/partsieve.py"
checks = []


def call(command, path, *args):
    r = subprocess.run([sys.executable, str(CLI), command, str(path), *map(str, args)], cwd=ROOT,
                       capture_output=True, text=True, timeout=90)
    return r.returncode, json.loads(r.stdout)


def save(name, plan):
    p = DEST / (name + ".plan.json")
    p.write_text(json.dumps(plan, indent=2), encoding="utf8")
    return p


def check(name):
    checks.append({"name": name, "status": "Pass"})


controls = [
    ("sheet", ROOT / "tests/fixtures/upstream/macro01.xlsm", ".xlsx", 10, 5),
    ("word", ROOT / "tests/fixtures/poi/SimpleMacro.docm", ".docx", 14, 7),
    ("clean", ROOT / "tests/fixtures/upstream/simple01.xlsx", ".xlsx", 10, 0),
]
plans = {}
for name, source, suffix, count, operations in controls:
    code, plan = call("prepare", source)
    assert code == 0 and plan["schema"] == "partsieve.prepared-plan.v1"
    assert plan["gate"]["result"] == "Pass" and len(plan["preconditions"]) == count
    assert len(plan["operations"]) == operations
    assert call("prepare", source) == (code, plan)
    decisions = {d["decision_id"]: d for d in plan["decisions"]}
    previous = set()
    for op in plan["operations"]:
        assert op["decision_id"] in decisions and op["rule_id"] == decisions[op["decision_id"]]["rule_id"]
        assert all(d in previous for d in op["depends_on"])
        assert len(op["before_hash"]) == 64
        previous.add(op["operation_id"])
    for d in plan["decisions"]:
        if d.get("finding_index") is not None:
            assert plan["findings"][d["finding_index"]]["part"] == d["part"]
    saved = save(name, plan)
    out, receipt = DEST / (name + suffix), DEST / (name + ".receipt.json")
    out.unlink(missing_ok=True); receipt.unlink(missing_ok=True)
    code, result = call("rebuild", source, "--plan", saved, "-o", out, "--receipt", receipt)
    assert code == 0 and result["preservation"] == "Pass", (name, result)
    assert call("verify", out, "--original", source, "--receipt", receipt) == (0, result)
    plans[name] = plan
    check(name + " prepared plan has stable complete preconditions and traceable decisions; saved execution verifies")

source = controls[0][1]
mutations = []
for field, value in [("input_hash", "0" * 64), ("policy", "allow-all"), ("rules", "future-rules"), ("output_format", "DOCX")]:
    p = deepcopy(plans["sheet"]); p[field] = value; mutations.append((field, p))
p = deepcopy(plans["sheet"]); p["preconditions"][0]["sha256"] = "0" * 64; mutations.append(("part-hash", p))
p = deepcopy(plans["sheet"]); p["limits"]["input_bytes"] -= 1; mutations.append(("limits", p))
p = deepcopy(plans["sheet"]); p["operations"][0]["part"] = "xl/worksheets/sheet1.xml"; mutations.append(("protected-payload", p))
p = deepcopy(plans["sheet"]); p["operations"].append(p["operations"][0]); mutations.append(("duplicate-operation", p))
p = deepcopy(plans["sheet"]); p["operations"][0]["depends_on"] = [p["operations"][0]["operation_id"]]; mutations.append(("cyclic-dependency", p))
p = deepcopy(plans["sheet"]); p["operations"][0]["decision_id"] = "format"; mutations.append(("decision-link", p))
p = deepcopy(plans["sheet"]); p["operations"][0]["kind"] = "RewriteSourceXml"; mutations.append(("unaccepted-source-handler", p))
p = deepcopy(plans["sheet"]); p["operations"][2]["expected_after_hash"] = "0" * 64; mutations.append(("postcondition", p))
for name, plan in mutations:
    out, receipt = DEST / (name + ".xlsx"), DEST / (name + ".receipt.json")
    code, error = call("rebuild", source, "--plan", save(name, plan), "-o", out, "--receipt", receipt)
    assert code == 2 and error["status"] == "Fail" and not out.exists() and not receipt.exists(), (name, error)
    check(name + " tampering fails before pair publication")
for name, raw, expected in [
    ("duplicate-json-key", '{"schema":"bad","schema":"partsieve.prepared-plan.v1"}', 2),
    ("truncated-json", '{"schema":', 2),
    ("invalid-utf8", b'\xff', 2),
    ("json-depth-limit", '[' * 33 + '0' + ']' * 33, 3),
    ("json-string-limit", '{"schema":"' + 'x' * 65537 + '"}', 3),
]:
    path = DEST / (name + ".plan.json")
    path.write_bytes(raw if isinstance(raw, bytes) else raw.encode())
    out, receipt = DEST / (name + ".xlsx"), DEST / (name + ".receipt.json")
    code, error = call("rebuild", source, "--plan", path, "-o", out, "--receipt", receipt)
    assert code == expected and not out.exists() and not receipt.exists(), (name, error)
    check(name + " rejects without a partial pair")
code, unsupported = call("prepare", ROOT / "tests/fixtures/poi/SampleDoc.docx")
assert code == 3 and unsupported["status"] == "Unsupported"
check("prepare cannot authorize an unsupported real document")
summary = {"schema": "partsieve.planner-regression.v1", "status": "Pass", "checks": checks,
           "scope": "Accepted VBA handlers only; source XML rewrite remains unavailable. Plan is recomputed, not treated as authority."}
(ROOT / "docs/evidence/planner-regression.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf8", newline="\n")
print(json.dumps({"planner_assertions": len(checks), "status": "Pass"}))
