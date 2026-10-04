"""Keep public repository copies of the workspace handoff and plan in sync."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
for name in ["HANDOFF.md", "plan.md"]:
    source = ROOT.parent / name
    if source.is_file():
        data = source.read_bytes().replace(b"\r\n", b"\n")
        (ROOT / name).write_bytes(data)
        print("Synchronized", name)
