"""Standalone damage arithmetic oracle using the bounded paired runtime launcher."""
import importlib.util
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "damage_runtime_launcher", HERE.parent / "power_retirement_runtime" / "run.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)

# Expectations are independent of the DM implementation and must pass for BOTH
# backends; agreement on a wrong result never admits this fixture.
EXPECTED = [
    ("full", 0), ("light", 1), ("moderate", 2), ("heavy", 3),
    ("repair_light", 1), ("repair_full", 0), ("heavy_again", 3),
    ("boundary_light", 0), ("boundary_moderate", 1), ("boundary_heavy", 2),
]


def observations(file):
    if file.stat().st_size > 1024 * 1024:
        raise ValueError("tiny runtime log exceeds 1MiB")
    raw = file.read_bytes()
    text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
    markers = [line[line.index("DQ_DAMAGE "):] for line in text.splitlines()
               if "DQ_DAMAGE " in line]
    expected = [f"DQ_DAMAGE {label} {band} {band} {band} 1" for label, band in EXPECTED]
    expected.append("DQ_DAMAGE finished")
    if markers != expected:
        raise ValueError("damage threshold results differ from independent expected contract")
    if re.search(r"Runtime in .+?\.dm,\d+:|runtime error:", text, re.IGNORECASE):
        raise ValueError("standalone threshold fixture recorded a runtime error")
    return {"markers": markers, "runtimes": []}


if __name__ == "__main__":
    raise SystemExit(launcher.main(
        fixture_directory=HERE, observation_reader=observations,
        scope="standalone damage threshold arithmetic only; no game rule lifecycle"))
