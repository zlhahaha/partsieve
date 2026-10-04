"""Reproduce and save independent test evidence for the immutable Spike pair."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from importlib.metadata import version
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs/evidence"


def run_json(args, destination):
    result = subprocess.run(args, cwd=ROOT, capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}): {result.stdout.decode(errors='replace')} {result.stderr.decode(errors='replace')}")
    report = json.loads(result.stdout.decode("utf-8-sig"))
    (EVIDENCE / destination).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


independent = run_json([sys.executable, "tests/independent_zip.py", "tests/fixtures/upstream/macro01.xlsm",
                        "docs/evidence/verified.xlsx"], "independent-zip.json")
sdk = run_json(["dotnet", "run", "--no-restore", "--project", "tests/OpenXmlValidation", "--",
                "tests/fixtures/upstream/macro01.xlsm", "docs/evidence/verified.xlsx",
                "tests/fixtures/upstream/simple01.xlsx", "docs/evidence/wps-saved.xlsx"], "openxml-final.json")
recomputed = run_json([sys.executable, "tools/partsieve.py", "verify", "docs/evidence/verified.xlsx",
                       "--original", "tests/fixtures/upstream/macro01.xlsm",
                       "--receipt", "docs/evidence/verified.receipt.json"], "verify.json")
saved = json.loads((EVIDENCE / "verified.receipt.json").read_text(encoding="utf-8"))
schema = json.loads((ROOT / "docs/receipt.schema.json").read_text(encoding="utf-8"))
Draft202012Validator.check_schema(schema)
Draft202012Validator(schema).validate(saved)
assert saved["receipt"] == recomputed
assert independent["output_sha256"] == recomputed["output_hash"]
assert sdk["reports"][1]["sha256"] == recomputed["output_hash"]
assert all(r["status"] == "Pass" and not r["errors"] for r in sdk["reports"])
ui = json.loads((EVIDENCE / "wps-ui-observation.json").read_text(encoding="utf-8"))
assert ui["status"] == "Pass" and ui["inputSha256"] == recomputed["output_hash"]
report = {"schema": "partsieve.evidence-check.spike-v1", "date": "2026-10-04", "status": "Pass",
          "output_sha256": recomputed["output_hash"], "receipt_shape": "Pass",
          "receipt_recomputed": "Pass", "independent_zip": "Pass", "openxml_documents": len(sdk["reports"]),
          "wps_ui_evidence_hash": "Pass", "jsonschema_version": version("jsonschema"),
          "note": "Rechecks saved WPS evidence binding; does not rerun or automate the client UI."}
(EVIDENCE / "evidence-check.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, indent=2))
