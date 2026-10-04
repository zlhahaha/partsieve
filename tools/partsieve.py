#!/usr/bin/env python3
"""Bounded host CLI for the MoonBit spike SDK. No OOXML logic lives here."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CAP = 32 * 1024 * 1024
REPORT_CAP = 16 * 1024 * 1024
WORKER = ROOT / "_build/native/debug/build/cmd/main/main"
if os.name == "nt":
    WORKER = WORKER.with_suffix(".exe")


class Diagnostic(Exception):
    def __init__(self, message, code=3, status=None):
        super().__init__(message)
        self.code = code
        self.status = status


def bounded_bytes(path, cap=CAP):
    with open(path, "rb") as stream:
        if os.fstat(stream.fileno()).st_size > cap:
            raise Diagnostic("input/report exceeds byte limit", status="Incomplete")
        data = stream.read(cap + 1)
        if len(data) > cap:
            raise Diagnostic("input grew beyond byte limit during read", status="Incomplete")
        return data


def bounded_json(path, label):
    raw = bounded_bytes(path, REPORT_CAP)
    try:
        text = raw.decode("utf-8")
    except UnicodeError as exc:
        raise Diagnostic(f"{label} is not UTF-8 JSON", 2) from exc
    depth = token = tokens = 0
    quoted = escaped = False
    for char in text:
        token += 1
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
                token = 0
        elif char == '"':
            quoted = True
            tokens += 1
            token = 1
        elif char in "[{":
            depth += 1
            tokens += 1
            token = 0
        elif char in "]}":
            depth -= 1
            token = 0
        elif char in ",:" or char.isspace():
            token = 0
        if depth > 32 or token > 65536 or tokens > 200000:
            raise Diagnostic(f"{label} JSON resource limit", status="Incomplete")

    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key")
            result[key] = value
        return result

    try:
        json.loads(text, object_pairs_hook=unique_object,
                   parse_constant=lambda value: (_ for _ in ()).throw(ValueError("non-finite JSON value")))
    except (ValueError, RecursionError) as exc:
        raise Diagnostic(f"malformed or ambiguous {label} JSON", 2) from exc
    return raw


def worker(command, input_path, extra=None):
    args = [str(WORKER), command, str(input_path)]
    if extra is not None:
        args.extend(map(str, extra)) if isinstance(extra, list) else args.append(str(extra))
    # Worker is trusted local code, never a user-supplied executable. A file
    # avoids an unbounded Python stdout capture. SDK report is also bounded.
    with tempfile.TemporaryFile() as log:
        result = subprocess.run(args, stdout=log, stderr=subprocess.DEVNULL, timeout=60)
        log.seek(0)
        raw = log.read(REPORT_CAP + 1)
    if len(raw) > REPORT_CAP:
        raise Diagnostic("report limit exceeded", status="Incomplete")
    try:
        report = json.loads(raw)
    except (ValueError, UnicodeError) as exc:
        raise Diagnostic("invalid worker response", 4) from exc
    if command == "assess" and report.get("schema") == "partsieve.assessment.v1":
        expected = {"Pass": 0, "Fail": 2, "Incomplete": 3, "Unsupported": 3}.get(report.get("decision", {}).get("result"))
        if expected != result.returncode:
            raise Diagnostic("assessment decision/worker exit mismatch", 4)
        return report
    if result.returncode:
        raise Diagnostic(report.get("error", "worker refused"), result.returncode, report.get("status"))
    return report


def main():
    global WORKER
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["audit", "assess", "graph", "plan", "prepare", "rebuild", "verify"])
    parser.add_argument("input", type=Path)
    parser.add_argument("--json", action="store_true", help="JSON is always used by the spike")
    parser.add_argument("--policy", default="passive-office-v1", choices=["passive-office-v1"])
    parser.add_argument("-o", "--output", type=Path)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--original", type=Path)
    parser.add_argument("--plan", type=Path, help="rebuild using an independently recomputed prepared plan")
    parser.add_argument("--receipt-format", choices=["legacy", "v2"], default="legacy")
    parser.add_argument("--release", action="store_true", help="use the locally compiled Native release worker")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.release:
        WORKER = ROOT / "_build/native/release/build/cmd/main/main"
        if os.name == "nt":
            WORKER = WORKER.with_suffix(".exe")
    if args.command in ("assess", "graph", "prepare") and args.dry_run:
        raise Diagnostic("--dry-run does not apply to structural/coverage inspection", 4)
    if args.plan and (args.command != "rebuild" or args.dry_run):
        raise Diagnostic("--plan applies only to rebuild without --dry-run", 4)
    if args.receipt_format != "legacy" and (args.command not in ("rebuild", "verify") or args.dry_run):
        raise Diagnostic("--receipt-format applies only to rebuild/verify without --dry-run", 4)
    verify_command = "verify-v2" if args.receipt_format == "v2" else "verify"
    if not WORKER.is_file():
        raise Diagnostic("build first: moon build " + ("--release " if args.release else "") + "--target native", 4)
    data = bounded_bytes(args.input)
    with tempfile.TemporaryDirectory(prefix="partsieve-") as private_dir:
        snapshot = Path(private_dir) / "input.zip"
        snapshot.write_bytes(data)
        if args.command in ("audit", "assess", "graph", "plan", "prepare") or args.dry_run:
            result = worker("plan" if args.dry_run else args.command, snapshot)
        elif args.command == "verify":
            if args.original is None:
                audit = worker("audit", snapshot)
                result = {"schema": "partsieve.verify.v2-partial" if args.receipt_format == "v2" else "partsieve.verify.spike-v1",
                          "structure": "Pass" if audit["format"] in ("XLSX", "DOCX") and not audit["findings"] else "Fail",
                          "preservation": "NotChecked", "status": "Incomplete", "audit": audit}
                print(json.dumps(result, ensure_ascii=True))
                return 3
            original = Path(private_dir) / "original.zip"
            original.write_bytes(bounded_bytes(args.original))
            result = worker(verify_command, snapshot, original)
            if args.receipt:
                saved = json.loads(bounded_json(args.receipt, "Receipt"))
                expected = {"publication": "pair-complete", "receipt": result}
                # Python equates False with 0 and True with 1. Receipt field
                # types are part of the contract; ignore only object key order.
                if json.dumps(saved, sort_keys=True, separators=(",", ":")) != json.dumps(expected, sort_keys=True, separators=(",", ":")):
                    raise Diagnostic("Receipt differs from independently recomputed verification", 2)
        else:
            if args.output is None or args.receipt is None:
                raise Diagnostic("rebuild requires -o and --receipt", 4)
            output = args.output.absolute()
            receipt_path = args.receipt.absolute()
            if output.suffix.lower() not in (".xlsx", ".docx"):
                raise Diagnostic("output must use .xlsx or .docx", 4)
            if output == receipt_path or output == args.input.absolute() or receipt_path == args.input.absolute():
                raise Diagnostic("input/document/Receipt paths must differ", 4)
            if output.exists() or receipt_path.exists():
                raise Diagnostic("output or Receipt already exists; overwrite refused", 4)
            temporary_paths = []
            published = []
            try:
                # Both temporaries live on their destination filesystems.
                fd, temp_name = tempfile.mkstemp(prefix=".partsieve-", dir=output.parent)
                os.close(fd)
                temp_output = Path(temp_name)
                temporary_paths.append(temp_output)
                if args.plan:
                    plan_snapshot = Path(private_dir) / "plan.json"
                    plan_snapshot.write_bytes(bounded_json(args.plan, "supplied plan"))
                    command = "rebuild-plan-v2" if args.receipt_format == "v2" else "rebuild-plan"
                    result = worker(command, snapshot, [temp_output, plan_snapshot])
                else:
                    result = worker("rebuild-v2" if args.receipt_format == "v2" else "rebuild", snapshot, temp_output)
                expected_suffix = {"XLSX": ".xlsx", "DOCX": ".docx"}.get(result["output_format"])
                if output.suffix.lower() != expected_suffix:
                    raise Diagnostic("output extension differs from verified main document type", 4)
                actual = bounded_bytes(temp_output, 64 * 1024 * 1024)
                if hashlib.sha256(actual).hexdigest() != result["output_hash"]:
                    raise Diagnostic("temporary output hash mismatch", 2)
                # Re-read actual file on disk through the SDK before publishing.
                recheck = worker(verify_command, temp_output, snapshot)
                if recheck != result:
                    raise Diagnostic("temporary output verification mismatch", 2)
                payload = json.dumps({"publication": "pair-complete", "receipt": result},
                                     ensure_ascii=True, indent=2).encode()
                if len(payload) > REPORT_CAP:
                    raise Diagnostic("Receipt limit", status="Incomplete")
                fd, temp_name = tempfile.mkstemp(prefix=".partsieve-", dir=receipt_path.parent)
                temp_receipt = Path(temp_name)
                temporary_paths.append(temp_receipt)
                with os.fdopen(fd, "wb") as stream:
                    stream.write(payload)
                    stream.flush()
                    os.fsync(stream.fileno())
                # Exclusive links cannot replace an existing destination.
                os.link(temp_output, output)
                published.append(output)
                os.link(temp_receipt, receipt_path)
                published.append(receipt_path)
                if hashlib.sha256(bounded_bytes(output, 64 * 1024 * 1024)).hexdigest() != result["output_hash"]:
                    raise Diagnostic("published output hash mismatch", 2)
                if bounded_bytes(receipt_path, REPORT_CAP) != payload:
                    raise Diagnostic("published Receipt mismatch", 2)
            except Exception:
                cleanup = []
                for path in reversed(published):
                    try:
                        path.unlink()
                        cleanup.append(str(path))
                    except OSError as exc:
                        cleanup.append(f"{path}: {exc}")
                print(json.dumps({"cleanup": cleanup}), file=sys.stderr)
                raise
            finally:
                for path in temporary_paths:
                    path.unlink(missing_ok=True)
        print(json.dumps(result, ensure_ascii=True))
        if args.command == "assess":
            return {"Pass": 0, "Fail": 2, "Incomplete": 3, "Unsupported": 3}[result["decision"]["result"]]
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Diagnostic as exc:
        print(json.dumps({"schema": "partsieve.error.spike-v1", "status": exc.status or ("Unsupported" if exc.code == 3 else "Fail"), "error": str(exc)}))
        sys.exit(exc.code)
    except subprocess.TimeoutExpired:
        print(json.dumps({"status": "Incomplete", "error": "worker exceeded host 60-second timeout"}))
        sys.exit(3)
    except (OSError, ValueError) as exc:
        print(json.dumps({"error": str(exc)}))
        sys.exit(4)
