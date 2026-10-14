"""Observable procedure enumeration order against independently pinned BYOND."""
import importlib.util
import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("enumeration_launcher", HERE.parent / "power_retirement_runtime/run.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)
REFERENCE = json.loads((HERE / "discovery_receipt.json").read_text(encoding="utf-8"))
EXPECTED = REFERENCE["byond"]["markers"]

def validate_fixture_sources():
    for name, expected in REFERENCE["fixture_sources"].items():
        if hashlib.sha256((HERE / name).read_bytes()).hexdigest() != expected:
            raise ValueError("enumeration source differs from pinned BYOND fixture")

def observations(file):
    if file.stat().st_size > 1024 * 1024:
        raise ValueError("enumeration log exceeds 1MiB")
    raw = file.read_bytes()
    text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
    markers = [line[line.index("DQ_ENUM "):] for line in text.splitlines() if "DQ_ENUM " in line]
    if not markers or markers[-1] != "DQ_ENUM finished":
        raise ValueError("enumeration did not finish")
    if re.search(r"Runtime in .+?\.dm,\d+:|runtime error:", text, re.IGNORECASE):
        raise ValueError("enumeration recorded a runtime")
    if markers != EXPECTED:
        raise ValueError("procedure enumeration differs from pinned BYOND: " + repr(markers))
    return {"markers": markers, "runtimes": []}

if __name__ == "__main__":
    validate_fixture_sources()
    raise SystemExit(launcher.main(fixture_directory=HERE, observation_reader=observations,
        scope="strict independent BYOND procedure typesof ordering, including override and inheritance; not whole-program parity"))
