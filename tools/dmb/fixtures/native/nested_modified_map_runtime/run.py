"""One-cell nested modified map contract using the existing paired launcher."""
import importlib.util
from pathlib import Path
import re
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("nested_map_launcher", HERE.parent / "power_retirement_runtime/run.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)
LABELS = ("parent_present", "child_type", "nested_amount", "leaf_scalar", "body_marker")
VALUES = [1, 1, 7, 11, 13]
EXPECTED = [f"DQ_NESTED {label} {value}" for label, value in zip(LABELS, VALUES)] + ["DQ_NESTED finished"]
def observations(file):
    if file.stat().st_size > 1024 * 1024:
        raise ValueError("tiny map runtime log exceeds 1MiB")
    raw = file.read_bytes()
    text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
    markers = [line[line.index("DQ_NESTED "):] for line in text.splitlines() if "DQ_NESTED " in line]
    if markers != EXPECTED:
        raise ValueError("nested map values differ from independent oracle: " + repr(markers))
    if re.search(r"Runtime in .+?\.dm,\d+:|runtime error:", text, re.IGNORECASE):
        raise ValueError("nested map fixture recorded a runtime error")
    return {"markers": markers, "runtimes": []}
if __name__ == "__main__":
    raise SystemExit(launcher.main(fixture_directory=HERE, observation_reader=observations,
        asset_files=("probe.dmm", "contract-resource.txt"),
        scope="one-cell nested modified type initializer and scalar map attribute"))
