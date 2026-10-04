"""Small-fixture smoke benchmark. Not calibration for default limits."""
import json
from pathlib import Path
import platform
import subprocess
import tempfile
import time
import psutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
WORKER = ROOT / "_build/native/debug/build/cmd/main/main.exe"
records = []
for command, input_path, extra in [
    ("audit", ROOT / "tests/fixtures/upstream/macro01.xlsm", None),
    ("rebuild", ROOT / "tests/fixtures/upstream/macro01.xlsm", ROOT / "tests/generated/bench.xlsx"),
    ("verify", ROOT / "docs/evidence/verified.xlsx", ROOT / "tests/fixtures/upstream/macro01.xlsm"),
    ("audit", ROOT / "tests/generated/high-compression-xml-over-limit.xlsm", None),
]:
    elapsed = []
    peaks = []
    codes = []
    for _ in range(3):
        args = [str(WORKER), command, str(input_path)] + ([str(extra)] if extra else [])
        with tempfile.TemporaryFile() as log:
            start = time.perf_counter()
            process = subprocess.Popen(args, stdout=log)
            observer = psutil.Process(process.pid)
            peak = 0
            while process.poll() is None:
                try:
                    memory = observer.memory_info()
                    peak = max(peak, getattr(memory, "peak_wset", memory.rss))
                except psutil.NoSuchProcess:
                    pass
                time.sleep(0.002)
            elapsed.append(round((time.perf_counter() - start) * 1000, 3))
            peaks.append(peak)
            codes.append(process.returncode)
    with zipfile.ZipFile(input_path) as package:
        entries = package.infolist()
        declared_expanded = sum(entry.file_size for entry in entries)
        compressed_payload = sum(entry.compress_size for entry in entries)
    expected = 3 if "high-compression" in input_path.name else 0
    assert all(code == expected for code in codes), (input_path, codes)
    records.append({"command": command, "input": input_path.relative_to(ROOT).as_posix(),
                    "input_bytes": input_path.stat().st_size, "milliseconds": elapsed,
                    "declared_expanded_bytes": declared_expanded,
                    "compressed_payload_bytes": compressed_payload, "part_count": len(entries),
                    "sampled_peak_working_set_bytes": peaks, "exit_codes": codes})
report = {"tool": "psutil subprocess sampling", "psutil": psutil.__version__,
          "machine": platform.platform(), "processor": platform.processor(),
          "build": "Native debug", "runs_per_case": 3,
          "toolchain": subprocess.run(["moon", "version", "--all"], capture_output=True, text=True, check=True).stdout.strip(),
          "limits_calibrated": False,
          "limitations": "Tiny-fixture smoke benchmark; samples may miss short-lived peaks. No 1/10/30 MiB calibration.",
          "cases": records}
(ROOT / "docs/evidence/benchmark.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report, indent=2))
