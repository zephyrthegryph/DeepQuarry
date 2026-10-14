#!/usr/bin/env python3
"""Import legacy small receipts; never substitute wall time for CPU or I/O."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("results.jsonl"))
    args = parser.parse_args()
    rows = []
    receipts = args.output.parent / "receipts"
    receipts.mkdir(parents=True, exist_ok=True)
    for folder in sorted(args.source.glob("phase2-20261007-*")):
        path = folder / "receipt.json"
        if not path.exists():
            continue
        raw = path.read_bytes()
        value = json.loads(raw)
        target = receipts / (folder.name + ".json")
        shutil.copyfile(path, target)
        stats_path = folder / "compiler-stats.json"
        stats = {}
        stats_hash = None
        if stats_path.exists():
            stats_raw = stats_path.read_bytes()
            stats_hash = hashlib.sha256(stats_raw).hexdigest()
            stats = json.loads(stats_raw)
        rows.append({"schema": 1, "kind": "historical_receipt", "cohort": folder.name,
                     "scenario": folder.name.split("-", 3)[-1], "commit": value.get("commit"),
                     "compiler_sha256": value.get("compiler_sha256"), "workers": value.get("workers"),
                     "wall_s": value.get("process_seconds"), "total_cpu_s": value.get("sampled_cpu_seconds"),
                     "critical_path_cpu_s": None, "read_bytes": None, "write_bytes": None, "io_blocked_s": None,
                     "peak_private_bytes": value.get("sampled_max_private_bytes"),
                     "competing_processes_start": value.get("competing_cargo_rustc_count_at_start"),
                     "competing_processes_end": value.get("competing_cargo_rustc_count_at_end"),
                     "status": value.get("status"), "exit_code": value.get("exit_code"),
                     "oracle": "not_recorded_in_receipt", "acceptance": "not_evaluable",
                     "receipt": "receipts/" + target.name, "receipt_origin": str(path).replace("\\", "/"),
                     "receipt_sha256": hashlib.sha256(raw).hexdigest(),
                     "stats_origin": str(stats_path).replace("\\", "/") if stats_hash else None,
                     "stats_sha256": stats_hash,
                     "stages_wall_s": {k: v for k, v in stats.items() if k.endswith("_seconds")},
                     "dmb_sha256": value.get("dmb_sha256"), "rsc_sha256": value.get("rsc_sha256")})
    old = [json.loads(line) for line in args.output.read_text().splitlines()] if args.output.exists() else []
    retained = [row for row in old if row.get("kind") != "historical_receipt"]
    with args.output.open("w", encoding="utf-8") as out:
        for row in rows + retained:
            out.write(json.dumps(row, separators=(",", ":")) + "\n")
    print("Imported", len(rows), "receipts; retained", len(retained), "new benchmark rows")


if __name__ == "__main__":
    main()
