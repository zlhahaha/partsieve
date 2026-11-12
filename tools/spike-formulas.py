"""Run the formula decision spike without executing external or unknown formulas."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile

from importlib import import_module
inventory = import_module("measure-corpus").inventory
SHEET = import_module("measure-corpus").SHEET


def classify_formula(formula):
    text = formula["text"] or ""
    if any(token in text.upper() for token in ("[", "|", "WEBSERVICE(", "RTD(", "HYPERLINK(")):
        return "ExternalData"
    if formula["attributes"]:
        return "Unknown"
    if re.fullmatch(r"(?:[A-Z]{1,3}[1-9][0-9]*|SUM\([A-Z]{1,3}[1-9][0-9]*:[A-Z]{1,3}[1-9][0-9]*\))", text):
        return "Formula"
    return "Unknown"


def mutate(source, target, formula):
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(target, "x") as variant:
        for member in original.infolist():
            data = original.read(member)
            if member.filename == "xl/worksheets/sheet1.xml":
                root = ET.fromstring(data)
                cell = next(c for c in root.iter(SHEET + "c") if c.find(SHEET + "v") is not None)
                cell.attrib.pop("t", None)
                cell.insert(0, ET.Element(SHEET + "f"))
                cell[0].text = formula
                cell.find(SHEET + "v").text = "0"
                data = ET.tostring(root, encoding="utf-8")
            variant.writestr(member, data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path, required=True)
    parser.add_argument("--ordinary-base", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("source", type=Path, nargs="+")
    args = parser.parse_args()
    args.output.mkdir()
    samples = list(args.source)
    for name, formula in {
        "local-reference": "A1",
        "network": 'WEBSERVICE("https://example.invalid/test")',
        "dde": "example|topic!A1",
        "dynamic": 'INDIRECT("A1")',
    }.items():
        sample = args.output / (name + ".xlsx")
        mutate(args.ordinary_base, sample, formula)
        samples.append(sample)
    rows = []
    for sample in samples:
        _, signals, formulas, _ = inventory(sample)
        target = args.output / (sample.stem + ".clean.xlsx")
        receipt = target.with_suffix(".json")
        result = subprocess.run([str(args.cli.resolve()), "rebuild", str(sample), "-o", str(target),
                                 "--receipt", str(receipt), "--receipt-format", "v2"],
                                capture_output=True, encoding="utf-8", check=False)
        if sample.name != "link-external-workbook-a.xlsx":
            assert result.returncode == 3 and not target.exists() and not receipt.exists(), sample
        rows.append({"sample": sample.name, "sha256": hashlib.sha256(sample.read_bytes()).hexdigest(),
                     "generated": sample.parent == args.output, "signals": signals,
                     "formulas": [{**formula, "class": classify_formula(formula)} for formula in formulas],
                     "decision": result.returncode, "diagnostic": json.loads(result.stdout or result.stderr),
                     "output": target.exists(), "receipt": receipt.exists()})
    print(json.dumps({"schema": "partsieve.formula-spike.v1",
                      "decision": "KILL for this release",
                      "classification_scope": "Selected fixture strings and OPC signals; diagnostic only",
                      "cases": rows}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
