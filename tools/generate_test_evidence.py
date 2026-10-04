"""Generate reproducible SDK pairs for regression/CI; never opens Office."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs/evidence"
EVIDENCE.mkdir(parents=True, exist_ok=True)
for source, name, expected in [
    ("tests/fixtures/upstream/macro01.xlsm", "verified.xlsx", "fcc9a0ca93810d894df21c71d5764db7252afd3b1232b5aef55c21f3efcc9e53"),
    ("tests/fixtures/poi/SimpleMacro.docm", "word-verified.docx", "4bb624cf9a6e465b1658c69f6d0bc607ccccf25e2ee1e3048b3e11376d8aa65e"),
]:
    output = EVIDENCE / name
    receipt = output.with_suffix(".receipt.json")
    if not output.exists() and not receipt.exists():
        result = subprocess.run([sys.executable, "tools/partsieve.py", "rebuild", source,
                                 "-o", str(output), "--receipt", str(receipt)], cwd=ROOT,
                                capture_output=True, timeout=90)
        assert result.returncode == 0, result.stdout.decode(errors="replace")
    # Existing pairs are rechecked; never overwrite a partial/mismatched pair.
    result = subprocess.run([sys.executable, "tools/partsieve.py", "verify", str(output),
                             "--original", source, "--receipt", str(receipt)], cwd=ROOT,
                            capture_output=True, timeout=90)
    assert result.returncode == 0, result.stdout.decode(errors="replace")
    report = json.loads(result.stdout)
    assert report["output_hash"] == hashlib.sha256(output.read_bytes()).hexdigest() == expected
    print(json.dumps({"output": name, "sha256": expected, "status": "Pass"}))
