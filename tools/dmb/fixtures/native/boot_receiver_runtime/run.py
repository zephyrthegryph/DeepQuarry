"""Boot receiver contract using the shared bounded paired runtime launcher."""
import importlib.util
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "boot_runtime_launcher", HERE.parent / "power_retirement_runtime" / "run.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)

# Native early access exposes a non-null HiddenInitializer sentinel, not a
# constructed datum. Typed availability guards access; null text is empty.
EXPECTED = [
    "DQ_BOOT early_cache_null 0",
    "DQ_BOOT early_cache_typed 0",
    "DQ_BOOT null_safe ",
    "DQ_BOOT null_not 1",
    "DQ_BOOT configured_loaded 0",
    "DQ_BOOT configured_not 1",
    "DQ_BOOT or_null 1",
    "DQ_BOOT or_short 1",
    "DQ_BOOT callback 17",
    "DQ_BOOT callback_short 17",
    "DQ_BOOT cache_list 1",
    "DQ_BOOT cache_hash 0",
    "DQ_BOOT cache_safe 42",
    "DQ_BOOT cache_direct 42",
    "DQ_BOOT finished",
]


def observations(file):
    if file.stat().st_size > 1024 * 1024:
        raise ValueError("tiny runtime log exceeds 1MiB")
    raw = file.read_bytes()
    text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
    markers = [line[line.index("DQ_BOOT "):] for line in text.splitlines()
               if "DQ_BOOT " in line]
    if markers != EXPECTED:
        raise ValueError("boot receiver results differ from independent expected contract: "
                         + repr(markers))
    if re.search(r"Runtime in .+?\.dm,\d+:|runtime error:", text, re.IGNORECASE):
        raise ValueError("standalone boot fixture recorded a runtime error")
    return {"markers": markers, "runtimes": []}


if __name__ == "__main__":
    raise SystemExit(launcher.main(
        fixture_directory=HERE, observation_reader=observations,
        scope="standalone global initialization, safe receivers and Profile callback only"))
