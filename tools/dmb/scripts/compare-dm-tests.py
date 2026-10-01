"""Summarize completed DM suites and identify native/translated status changes."""

import argparse
import json
from collections import Counter
from pathlib import Path


def read_results(path):
    data = Path(path).read_bytes()
    encoding = "utf-16" if data.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
    results = json.loads(data.decode(encoding))
    if not isinstance(results, dict) or not results:
        raise ValueError(f"No completed test results in {path}")
    for name, result in results.items():
        if result.get("status") not in (0, 1, 2):
            raise ValueError(f"Unknown status for {name}: {result.get('status')}")
    return results


def summary(results):
    counts = Counter(result["status"] for result in results.values())
    return {
        "total": len(results),
        "passed": counts[0],
        "failed": counts[1],
        "skipped": counts[2],
        "reported_test_runtimes": sum(result.get("runtimes", 0) for result in results.values()),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("native_results")
    parser.add_argument("translated_results")
    args = parser.parse_args()
    native = read_results(args.native_results)
    translated = read_results(args.translated_results)
    shared = native.keys() & translated.keys()
    output = {
        "native": summary(native),
        "translated": summary(translated),
        "missing_translated": sorted(native.keys() - translated.keys()),
        "extra_translated": sorted(translated.keys() - native.keys()),
        "status_changes": [
            {"name": name, "native": native[name], "translated": translated[name]}
            for name in sorted(shared)
            if native[name]["status"] != translated[name]["status"]
        ],
        "translated_failures": [
            {"name": name, "shared_native_failure": native.get(name, {}).get("status") == 1, "result": translated[name]}
            for name in sorted(translated)
            if translated[name]["status"] == 1
        ],
    }
    print(json.dumps(output, indent=2))
    return bool(output["missing_translated"] or output["extra_translated"] or output["translated"]["failed"])


if __name__ == "__main__":
    raise SystemExit(main())
