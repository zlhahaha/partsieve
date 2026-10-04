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


def worker(command, input_path, extra=None):
    args = [str(WORKER), command, str(input_path)]
    if extra is not None:
        args.append(str(extra))
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["audit", "assess", "graph", "plan", "rebuild", "verify"])
    parser.add_argument("input", type=Path)
    parser.add_argument("--json", action="store_true", help="JSON is always used by the spike")
    parser.add_argument("--policy", default="passive-office-v1", choices=["passive-office-v1"])
    parser.add_argument("-o", "--output", type=Path)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--original", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.command in ("assess", "graph") and args.dry_run:
        raise Diagnostic("--dry-run does not apply to structural/coverage inspection", 4)
    if not WORKER.is_file():
        raise Diagnostic("build first: moon build --target native", 4)
    data = bounded_bytes(args.input)
    with tempfile.TemporaryDirectory(prefix="partsieve-") as private_dir:
        snapshot = Path(private_dir) / "input.zip"
        snapshot.write_bytes(data)
        if args.command in ("audit", "assess", "graph", "plan") or args.dry_run:
            result = worker("plan" if args.dry_run else args.command, snapshot)
        elif args.command == "verify":
            if args.original is None:
                audit = worker("audit", snapshot)
                result = {"schema": "partsieve.verify.spike-v1",
                          "structure": "Pass" if audit["format"] == "XLSX" and not audit["findings"] else "Fail",
                          "preservation": "NotChecked", "status": "Incomplete", "audit": audit}
                print(json.dumps(result, ensure_ascii=True))
                return 3
            original = Path(private_dir) / "original.zip"
            original.write_bytes(bounded_bytes(args.original))
            result = worker("verify", snapshot, original)
            if args.receipt:
                saved = json.loads(bounded_bytes(args.receipt, REPORT_CAP))
                expected = {"publication": "pair-complete", "receipt": result}
                if saved != expected:
                    raise Diagnostic("Receipt differs from independently recomputed verification", 2)
        else:
            if args.output is None or args.receipt is None:
                raise Diagnostic("rebuild requires -o and --receipt", 4)
            output = args.output.absolute()
            receipt_path = args.receipt.absolute()
            if output.suffix.lower() != ".xlsx":
                raise Diagnostic("restricted spreadsheet output must use .xlsx", 4)
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
                result = worker("rebuild", snapshot, temp_output)
                actual = bounded_bytes(temp_output, 64 * 1024 * 1024)
                if hashlib.sha256(actual).hexdigest() != result["output_hash"]:
                    raise Diagnostic("temporary output hash mismatch", 2)
                # Re-read actual file on disk through the SDK before publishing.
                recheck = worker("verify", temp_output, snapshot)
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
