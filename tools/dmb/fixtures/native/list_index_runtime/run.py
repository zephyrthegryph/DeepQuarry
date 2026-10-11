"""Paired list-index observations; no predefined fractional/error semantics."""
import importlib.util
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "list_index_launcher", HERE.parent / "power_retirement_runtime" / "run.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


def observations(file):
    result = launcher.observations(file)
    raw = file.read_bytes()
    text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
    origins = []
    for line in text.splitlines():
        match = re.search(r"DQ_INDEX_ORIGIN (.*?)\|(.*?)\|(.*)$", line)
        if match:
            source, number, message = match.groups()
            source = source.replace("\\", "/").rsplit("/", 1)[-1]
            if source != "probe.dm" or not number.isdecimal() or int(number) <= 0:
                raise ValueError("list-index runtime lacks an engine-issued current source origin")
            origins.append({"source": source, "line": int(number), "message": message})
    if not origins:
        raise ValueError("bounds controls produced no attributed runtime observations")
    result["engine_runtime_origins"] = origins
    return result

if __name__ == "__main__":
    raise SystemExit(launcher.main(
        fixture_directory=HERE,
        observation_reader=observations,
        scope="numeric/associative/nested list-index observations and uncaught errors; "
              "same pinned fixture inputs, not full-program source closure or parity"))
