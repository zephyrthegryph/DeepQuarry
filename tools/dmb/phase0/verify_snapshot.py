"""Authenticate a relocated compiler input snapshot against the frozen inventory."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import time


def selected(relative):
    path = Path(relative)
    return (path.parts[0] not in ("data", "code-live-reference")
            and not any(part in (".git", ".cache", "target", "node_modules") for part in path.parts)
            and path.suffix.lower() not in (".dmb", ".rsc"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Evidence output already exists")
    started = time.monotonic()
    cpu_started = time.process_time()
    manifest_bytes = args.manifest.read_bytes()
    manifest = json.loads(manifest_bytes)
    receipt = {"manifest": str(args.manifest.resolve()),
               "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
               "source": str(args.source.resolve()), "checked": 0, "bytes": 0,
               "mismatches": [], "status": "started", "workers": 2}
    def authenticate(row):
        if time.monotonic() - started >= 285:
            raise TimeoutError("Snapshot authentication deadline")
        path = args.source / row["path"]
        digest = hashlib.sha256()
        size = 0
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                if time.monotonic() - started >= 285:
                    raise TimeoutError("Snapshot authentication deadline")
                digest.update(block)
                size += len(block)
        return size, path.stat().st_size == row["bytes"] and digest.hexdigest() == row["sha256"]
    try:
        entries = iter(row for row in manifest["source"] if selected(row["path"]))
        # Exactly two in-flight reads: overlap file-open latency without queueing
        # the entire inventory or growing the memory footprint with file count.
        with ThreadPoolExecutor(max_workers=2) as executor:
            pending = []
            for _ in range(2):
                row = next(entries, None)
                if row is not None:
                    pending.append((row, executor.submit(authenticate, row)))
            while pending:
                row, future = pending.pop(0)
                size, matches = future.result(timeout=max(0.01, 285 - (time.monotonic() - started)))
                receipt["bytes"] += size
                if not matches:
                    receipt["mismatches"].append(row["path"])
                receipt["checked"] += 1
                row = next(entries, None)
                if row is not None:
                    pending.append((row, executor.submit(authenticate, row)))
        receipt["status"] = "equal" if not receipt["mismatches"] else "different"
    except Exception as error:
        receipt["status"] = "failed"
        receipt["error"] = str(error)
    finally:
        receipt["seconds"] = time.monotonic() - started
        receipt["cpu_seconds"] = time.process_time() - cpu_started
        args.output.write_text(json.dumps(receipt, indent=2) + "\n")
    if receipt["status"] != "equal":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
