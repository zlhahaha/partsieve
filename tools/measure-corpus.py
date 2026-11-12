"""Join a pinned corpus run, independent schema results and an OPC inventory."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import zipfile

SHEET = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
WORD = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
REL = "{http://schemas.openxmlformats.org/package/2006/relationships}Relationship"
FORMULA_NAMES = {"f", "formula", "formula1", "formula2", "definedName", "calcChain"}
EXTERNAL_NAMES = {"externalReferences", "externalLink", "externalBook", "ddeLink", "oleLink", "connections", "connection"}
WORD_FEATURES = {"p", "tbl", "drawing", "footnoteReference", "endnoteReference", "numPr", "noProof", "srcRect"}
SHEET_FEATURES = {"c", "mergeCell", "numFmt", "phoneticPr", "headerFooter"}
ACTIVE_RELATIONS = {"vbaProject", "oleObject", "control", "attachedTemplate", "externalLink", "externalLinkPath", "connections"}


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inventory(path):
    features = collections.Counter()
    signals = []
    formulas = []
    payloads = {}
    with zipfile.ZipFile(path) as archive:
        for item in archive.infolist():
            if item.is_dir():
                continue
            if item.filename in payloads:
                raise ValueError(f"duplicate ZIP member in {path.name}: {item.filename}")
            data = archive.read(item)
            payloads[item.filename] = digest(data)
            if not item.filename.endswith((".xml", ".rels")):
                continue
            part = item.filename
            try:
                root = ET.fromstring(data)
            except ET.ParseError as error:
                signals.append({"class": "Format", "part": part, "detail": str(error)})
                continue
            for node in root.iter():
                local = node.tag.rsplit("}", 1)[-1]
                if local in WORD_FEATURES | SHEET_FEATURES:
                    features[local] += 1
                if node.tag == REL:
                    kind = node.get("Type", "").rsplit("/", 1)[-1]
                    mode = node.get("TargetMode", "Internal")
                    if kind == "calcChain":
                        category = "Formula"
                    elif kind in ACTIVE_RELATIONS:
                        category = "ExternalData" if kind.startswith("externalLink") or kind == "connections" else "ActiveCapability"
                    elif mode == "External":
                        category = "ClickLink" if kind == "hyperlink" else "ExternalData"
                    else:
                        continue
                    signals.append({"class": category, "part": part, "kind": kind,
                                    "id": node.get("Id"), "target": node.get("Target"), "mode": mode})
                if node.tag.startswith(SHEET) and local in EXTERNAL_NAMES:
                    signals.append({"class": "ExternalData", "part": part, "kind": local})
            for cell in root.iter(SHEET + "c"):
                for formula in cell.findall(SHEET + "f"):
                    cached = cell.find(SHEET + "v")
                    formulas.append({"part": part, "cell": cell.get("r"),
                                     "text": formula.text, "attributes": formula.attrib,
                                     "cached": None if cached is None else cached.text,
                                     "cell_type": cell.get("t")})
            if root.tag == SHEET + "calcChain":
                signals.append({"class": "Formula", "part": part, "kind": "calcChain",
                                "entries": [child.attrib for child in root]})
            for local in FORMULA_NAMES - {"f", "calcChain"}:
                for node in root.iter(SHEET + local):
                    signals.append({"class": "Formula", "part": part, "kind": local,
                                    "text": node.text, "attributes": node.attrib})
    return dict(sorted(features.items())), signals, formulas, payloads


def policy_class(reason):
    if not reason:
        return None
    if "resource" in reason or "budget" in reason or "limit exceeded" in reason:
        return "Resource"
    if "ambiguous" in reason or "conflict" in reason or "invalid" in reason:
        return "FormatOrAmbiguity"
    if "opaque" in reason:
        return "Unknown"
    return "ProfileGap"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--cli", type=Path, required=True)
    parser.add_argument("--schema", type=Path, action="append", required=True)
    args = parser.parse_args()
    manifest = read_json(args.manifest)
    batch = read_json(args.run / "result.json")
    assert digest(args.manifest.read_bytes()) == batch["manifest_sha256"]
    assert digest(args.cli.read_bytes()) == batch["cli_sha256"]
    schemas = [read_json(path) for path in args.schema]
    outcomes = {row["input"]: row for row in batch["cases"]}
    cases = []
    for fixture in manifest["cases"]:
        name = fixture["name"]
        path = args.cache / name
        row = outcomes[name]
        assert digest(path.read_bytes()) == fixture["sha256"]
        features, signals, formulas, before = inventory(path)
        validation = {}
        for schema in schemas:
            matches = [r for r in schema["reports"] if Path(r["path"]).name == name]
            assert len(matches) == 1
            result = matches[0]
            assert result.get("sha256", fixture["sha256"]) == fixture["sha256"]
            validation[schema["target"]] = {k: v for k, v in result.items() if k not in {"path", "sha256"}}
        graph = subprocess.run([str(args.cli.resolve()), "graph", str(path)],
                               capture_output=True, encoding="utf-8", check=False)
        graph_data = json.loads(graph.stdout)
        gaps = graph_data.get("coverage_gaps")
        output = None
        if row["status"] == "Success":
            delivered = args.run / "delivery" / row["output"]
            _, _, _, after = inventory(delivered)
            output = {"sha256": digest(delivered.read_bytes()),
                      "same_archive": fixture["sha256"] == row["output_hash"],
                      "same_payloads": before == after,
                      "changed_parts": sorted(p for p in before.keys() | after.keys()
                                              if before.get(p) != after.get(p))}
            assert output["sha256"] == row["output_hash"]
        reason = row.get("reason")
        classification = policy_class(reason)
        if reason and "relationship semantics" in reason and any(
                s["class"] == "Formula" and s.get("id")
                and reason.endswith("#" + s["id"]) for s in signals):
            classification = "Formula"
        cases.append({"name": name, "format": path.suffix[1:], "sha256": fixture["sha256"],
                      "original_schema": validation, "ordinary_features": features,
                      "policy": row["status"], "first_blocker": reason, "first_class": classification,
                      "graph_blockers": gaps, "graph_error": graph_data.get("error"),
                      "independent_signals": signals, "formulas": formulas, "output": output})
    print(json.dumps({
        "schema": "partsieve.corpus-matrix.v1",
        "source_revision": manifest["revision"],
        "license": manifest["license"],
        "manifest_sha256": batch["manifest_sha256"],
        "scope": "Production first refusal, all reported graph gaps and independent OPC signals. Later profile validators can still contain masked blockers.",
        "policy_counts": dict(collections.Counter(case["policy"] for case in cases)),
        "first_class_counts": dict(collections.Counter(case["first_class"] for case in cases if case["first_class"])),
        "cases": cases,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
