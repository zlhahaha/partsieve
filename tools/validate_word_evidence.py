"""Recheck saved Word evidence; retain the known WPS roundtrip failure."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs/evidence"


def run_json(args, expected_exit=0):
    result = subprocess.run(args, cwd=ROOT, capture_output=True, timeout=60)
    assert result.returncode == expected_exit, (args, result.returncode, result.stdout, result.stderr)
    return json.loads(result.stdout.decode("utf-8-sig"))


recomputed = run_json([sys.executable, "tools/partsieve.py", "verify", "docs/evidence/word-verified.docx",
                       "--original", "tests/fixtures/poi/SimpleMacro.docm",
                       "--receipt", "docs/evidence/word-verified.receipt.json"])
saved = json.loads((EVIDENCE / "word-verified.receipt.json").read_text(encoding="utf8"))
assert saved["receipt"] == recomputed
schema = json.loads((ROOT / "docs/word-receipt.schema.json").read_text(encoding="utf8"))
Draft202012Validator.check_schema(schema)
Draft202012Validator(schema).validate(saved)
independent = run_json([sys.executable, "tests/independent_word.py", "tests/fixtures/poi/SimpleMacro.docm", "docs/evidence/word-verified.docx"])
assert independent["output_sha256"] == recomputed["output_hash"]
sdk = run_json(["dotnet", "run", "--no-restore", "--project", "tests/OpenXmlValidation", "--",
                "tests/fixtures/poi/SimpleMacro.docm", "docs/evidence/word-verified.docx",
                "docs/evidence/word-wps-saved.docx"], expected_exit=2)
assert [r["status"] for r in sdk["reports"]] == ["Pass", "Pass", "Fail"]
errors = sdk["reports"][2]["errors"]
assert len(errors) == 3 and all(e["Part"] == "/word/styles.xml" and "uiPriority" in e["Description"] for e in errors)
client = json.loads((EVIDENCE / "word-wps-client.json").read_text(encoding="utf8"))
for item in client["files"]:
    path = ROOT / item["path"]
    assert path.parent == EVIDENCE
    data = path.read_bytes()
    assert len(data) == item["bytes"] and hashlib.sha256(data).hexdigest() == item["sha256"]
for name in ["word-wps-open-com.json", "word-wps-reopen-com.json"]:
    observation = json.loads((EVIDENCE / name).read_text(encoding="utf-8-sig"))
    assert observation["text"].rstrip("\r") == independent["text"]
    assert observation["paragraphs"] == observation["sections"] == 1
report = {"schema": "partsieve.word-evidence-check.v1", "status": "Pass",
          "meaning": "PartSieve original/output/Receipt checks Pass; saved client evidence and its known independent failure accurately retained. No client UI rerun.",
          "partsieve_output": recomputed["output_hash"], "receipt_recomputed": "Pass", "receipt_shape": "Pass",
          "independent_zip": "Pass", "openxml_original_output": "Pass",
          "wps_saved_openxml": "Fail", "wps_saved_errors": len(errors), "client_evidence_hash_binding": "Pass"}
(EVIDENCE / "word-evidence-check.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf8", newline="\n")
print(json.dumps(report, indent=2))
