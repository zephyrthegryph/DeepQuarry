"""Compare captured BYOND runtime errors; exit 1 for translated-only errors.

This checks reported errors, not gameplay equivalence. Counts and source lines
are retained, but different counts/line mappings do not change error identity.
"""

import argparse
import json
import re
from pathlib import Path


def runtime_errors(path):
    data = Path(path).read_bytes()
    encoding = "utf-16" if data.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
    records = {}
    for text in data.decode(encoding, errors="replace").splitlines():
        match = re.search(r"Runtime in (.+?\.dm),(\d+): (.*)", text)
        if not match:
            continue
        source, line, message = match.groups()
        source = source.replace("\\", "/")
        if "/code/" in source:
            source = "code/" + source.rsplit("/code/", 1)[1]
        key = (source, message)
        record = records.setdefault(key, {"source": source, "message": message, "count": 0, "lines": set()})
        record["count"] += 1
        record["lines"].add(int(line))
    for record in records.values():
        record["lines"] = sorted(record["lines"])
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("native_log")
    parser.add_argument("translated_log")
    args = parser.parse_args()
    native = runtime_errors(args.native_log)
    translated = runtime_errors(args.translated_log)
    result = {
        "native_only": [native[key] for key in sorted(native.keys() - translated.keys())],
        "translated_only": [translated[key] for key in sorted(translated.keys() - native.keys())],
        "shared": [{"native": native[key], "translated": translated[key]} for key in sorted(native.keys() & translated.keys())],
    }
    print(json.dumps(result, indent=2))
    return bool(result["translated_only"])


if __name__ == "__main__":
    raise SystemExit(main())
