"""Strict startup ordering oracle against independently captured BYOND output."""
import importlib.util
from pathlib import Path
import re
import hashlib
import json
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("order_runtime_launcher", HERE.parent / "power_retirement_runtime" / "run.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)

REFERENCE = json.loads((HERE / "discovery_receipt.json").read_text(encoding="utf-8"))
EXPECTED = REFERENCE["byond"]["markers"]

def validate_fixture_sources():
    for name, expected in REFERENCE["fixture_sources"].items():
        if hashlib.sha256((HERE / name).read_bytes()).hexdigest() != expected:
            raise ValueError("fixture no longer matches captured BYOND source: " + name)

def observations(file):
    if file.stat().st_size > 1024 * 1024:
        raise ValueError("ordering fixture log exceeds 1MiB")
    raw = file.read_bytes()
    text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
    markers = [line[line.index("DQ_ORDER "):] for line in text.splitlines() if "DQ_ORDER " in line]
    if not markers or markers[-1] != "DQ_ORDER finished":
        raise ValueError("ordering fixture did not finish")
    if re.search(r"Runtime in .+?\.dm,\d+:|runtime error:", text, re.IGNORECASE):
        raise ValueError("ordering fixture recorded a runtime")
    if markers != EXPECTED:
        raise ValueError("startup order differs from independent pinned BYOND expectation: " + repr(markers))
    return {"markers": markers, "runtimes": []}

if __name__ == "__main__":
    validate_fixture_sources()
    raise SystemExit(launcher.main(fixture_directory=HERE, observation_reader=observations,
        scope="strict independently captured BYOND global/procedure-static startup sequence; not whole-program or dense-table parity"))
