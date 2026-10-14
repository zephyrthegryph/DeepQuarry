"""Paired observations through the existing bounded runtime driver."""
import importlib.util
from pathlib import Path
import re
from collections import Counter
HERE = Path(__file__).resolve().parent
NAMES = ("objects", "filtered_count", "unfiltered_count", "filtered_dispatch",
         "obj_isobj", "screen_isobj", "movable_isobj", "obj_strict", "screen_strict",
         "movable_strict", "obj_type", "screen_type", "movable_type", "all_filtered_count", "mixed_caught")
def observations(file):
    if file.stat().st_size > 1024 * 1024:
        raise ValueError("tiny runtime log exceeds 1MiB")
    raw = file.read_bytes()
    text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
    markers, errors = [], Counter()
    for line in text.splitlines():
        if "DQ_ITER " in line:
            markers.append(line[line.index("DQ_ITER "):])
        match = re.search(r"Runtime in (.+?\.dm),(\d+): (.*)", line)
        if match:
            source, number, message = match.groups()
            errors[(source.replace("\\", "/").rsplit("/", 1)[-1], int(number), message)] += 1
        else:
            direct = re.search(r"runtime error:\s*(.*)", line, re.IGNORECASE)
            if direct: errors[("<standalone source unavailable>", 0, direct.group(1))] += 1
    if not markers or markers[-1] != "DQ_ITER finished" or [line.split()[1] for line in markers[:-1]] != list(NAMES):
        raise ValueError("runtime marker roster/order incomplete")
    return {"markers": markers, "expected_values_authenticated": False, "runtimes": [
        {"source": source, "line": number, "message": message, "count": count}
        for (source, number, message), count in sorted(errors.items())]}
def main():
    spec = importlib.util.spec_from_file_location("iterator_runtime_driver", HERE.parent / "bodyless_loop_runtime" / "run.py")
    driver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(driver)
    return driver.main(fixture_directory=HERE, observation_reader=observations,
                       scope="typed iterator/emote and intrinsic observations; BYOND reference values, no full game parity")
if __name__ == "__main__":
    raise SystemExit(main())
