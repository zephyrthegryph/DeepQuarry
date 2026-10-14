#!/usr/bin/env python3
"""Extract complete gzip trace artifacts from explicit profiler metadata.

Gzip CRC and recorded lengths are checked. XXH3 certificates remain in the
report; this helper does not claim to independently verify that hash algorithm.
Raw artifacts retain their original paths and need no extraction.
"""
import argparse
import gzip
import json
from pathlib import Path


def extract(report_path, destination):
    report_path = Path(report_path).resolve()
    report = json.loads(report_path.read_text(encoding="utf-8"))
    output = report.get("trace_output", {"mode": "raw", "artifacts": []})
    if output["mode"] == "raw":
        return {"mode": "raw", "artifacts": [], "note": "Use original uncompressed trace paths."}
    if output["mode"] != "gzip-level1-v1":
        raise ValueError("unsupported trace compression mode")
    destination = Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    extracted = []
    for artifact in output["artifacts"]:
        source = Path(artifact["path"])
        if not source.is_absolute():
            source = report_path.parent / source.name
        if not source.name.endswith(".gz"):
            raise ValueError("compressed trace lacks gzip suffix")
        if source.stat().st_size != artifact["stored_bytes"]:
            raise ValueError("compressed trace length differs from report")
        target = destination / source.name[:-3]
        count = 0
        # Exclusive creation protects existing diagnostic evidence.
        with gzip.open(source, "rb") as reader, target.open("xb") as writer:
            while block := reader.read(128 * 1024):
                count += len(block)
                if count > artifact["uncompressed_bytes"]:
                    raise ValueError("trace exceeds recorded logical length")
                writer.write(block)
        if count != artifact["uncompressed_bytes"]:
            raise ValueError("trace logical length differs from report")
        extracted.append({"path": str(target), "logical_format": artifact["logical_format"],
                          "bytes": count, "gzip_crc_checked": True})
    return {"mode": output["mode"], "artifacts": extracted,
            "xxh3_verification": "not performed by this standard-library viewer helper"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report")
    parser.add_argument("--extract", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(extract(args.report, args.extract), indent=2))
