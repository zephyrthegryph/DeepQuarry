"""Independent static/instance lifetime oracle on the shared paired launcher."""
import importlib.util
from pathlib import Path
import re
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("lifetime_launcher", HERE.parent / "power_retirement_runtime/run.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)
LABELS = ('static_count', 'static_first', 'static_second', 'static_after_write', 'instance_count', 'instance_first', 'instance_second')
VALUES = [1, 7, 7, 19, 2, 11, 22]
EXPECTED = [f"DQ_LIFETIME {label} {value}" for label, value in zip(LABELS, VALUES)] + ["DQ_LIFETIME finished"]
def observations(file):
    if file.stat().st_size > 1024 * 1024:
        raise ValueError("tiny runtime log exceeds 1MiB")
    raw = file.read_bytes()
    text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
    markers = [line[line.index("DQ_LIFETIME "):] for line in text.splitlines() if "DQ_LIFETIME " in line]
    if markers != EXPECTED:
        raise ValueError("static/instance lifetime contract differs: " + repr(markers))
    if re.search(r"Runtime in .+?\.dm,\d+:|runtime error:", text, re.IGNORECASE):
        raise ValueError("lifetime fixture recorded a runtime error")
    return {"markers": markers, "runtimes": []}
if __name__ == "__main__":
    raise SystemExit(launcher.main(fixture_directory=HERE, observation_reader=observations,
        asset_files=("contract-resource.txt",), scope="independent static initialization once and instance construction twice"))
