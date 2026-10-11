"""Callable semantics contract using the shared bounded paired runtime launcher."""
import importlib.util
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "callable_runtime_launcher", HERE.parent / "power_retirement_runtime" / "run.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)

EXPECTED = [
    "DQ_CALL copy_length 2", "DQ_CALL copy_value 99", "DQ_CALL original_value 7",
    "DQ_CALL safe_known 11", "DQ_CALL safe_null 1", "DQ_CALL colon_verb 23",
    "DQ_CALL typed_verb 23", "DQ_CALL self_verb 23", "DQ_CALL catch_number 42",
    "DQ_CALL catch_exception 1", "DQ_CALL finished",
]


def observations(file):
    if file.stat().st_size > 1024 * 1024:
        raise ValueError("tiny runtime log exceeds 1MiB")
    raw = file.read_bytes()
    text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
    markers = [line[line.index("DQ_CALL "):] for line in text.splitlines()
               if "DQ_CALL " in line]
    if markers != EXPECTED:
        raise ValueError("callable results differ from independent expected contract: "
                         + repr(markers))
    if re.search(r"Runtime in .+?\.dm,\d+:|runtime error:", text, re.IGNORECASE):
        raise ValueError("standalone callable fixture recorded a runtime error")
    return {"markers": markers, "runtimes": []}


if __name__ == "__main__":
    raise SystemExit(launcher.main(
        fixture_directory=HERE, observation_reader=observations,
        scope="standalone callable value, safe-null, verb and catch semantics only"))
