"""Reissue a byte-copied source roster after reversing exactly two issued edits.

No compiler runs; no original is written. This creates new provenance, never
claims equivalence to a missing historical snapshot or BYOND pin.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import time


def sha(path, deadline=None):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            if deadline is not None and time.monotonic() >= deadline:
                raise TimeoutError("source recovery deadline")
            digest.update(block)
    return digest.hexdigest()


def absolute_nonreparse(path):
    path = Path(os.path.abspath(path))
    for ancestor in (path, *path.parents):
        if ancestor.exists() and getattr(ancestor.lstat(), "st_file_attributes", 0) & 0x400:
            raise ValueError(f"reparse ancestor rejected: {ancestor}")
    return path


def regular(path):
    value = path.lstat()
    if getattr(value, "st_file_attributes", 0) & 0x400 or not stat.S_ISREG(value.st_mode):
        raise ValueError(f"nonregular/reparse source: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--cohort-receipt", type=Path, required=True)
    parser.add_argument("--edits", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--deadline-seconds", type=int, default=180)
    args = parser.parse_args()
    source, output = absolute_nonreparse(args.source), absolute_nonreparse(args.output)
    if source.drive.lower() != "e:" or not output.is_relative_to(Path("E:/dq-cache")):
        raise ValueError("source must be E: and output beneath E:/dq-cache")
    if output.exists() or output.is_relative_to(source) or source.is_relative_to(output):
        raise ValueError("requires a fresh disjoint output root")
    if not 1 <= args.deadline_seconds <= 300:
        raise ValueError("deadline must be 1..300 seconds")
    deadline = time.monotonic() + args.deadline_seconds
    recipe_sha, receipt_sha = sha(args.edits), sha(args.cohort_receipt)
    edits = json.loads(args.edits.read_text(encoding="utf-8"))[:2]
    if len(edits) != 2 or [edit["kind"] for edit in edits] != ["body", "structural"]:
        raise ValueError("requires first body and new-procedure edits")
    for edit in edits:
        relative = Path(edit["path"])
        if relative.is_absolute() or relative.drive or ".." in relative.parts:
            raise ValueError("escaped edit path")
        regular(source / relative)
        data = (source / relative).read_bytes()
        if data.count(edit["after"].encode()) != 1:
            raise ValueError(f"issued after text must occur exactly once: {relative}")
    output.mkdir(parents=True)
    target = output / "source"
    target.mkdir()
    original, files = {}, {}
    for current, directories, names in os.walk(source, followlinks=False):
        directory = Path(current)
        if getattr(directory.lstat(), "st_file_attributes", 0) & 0x400:
            raise ValueError("source reparse directory")
        directories[:] = [name for name in directories if name != ".dmbc"]
        relative = directory.relative_to(source)
        (target / relative).mkdir(exist_ok=True)
        for child in directories:
            if getattr((directory / child).lstat(), "st_file_attributes", 0) & 0x400:
                raise ValueError("source reparse child")
        for name in names:
            if time.monotonic() >= deadline:
                raise TimeoutError("source recovery deadline")
            path = directory / name
            regular(path)
            if path.suffix.lower() in (".dmb", ".rsc"):
                continue
            key = (relative / name).as_posix()
            destination = target / relative / name
            digest = hashlib.sha256()
            with path.open("rb") as incoming, destination.open("xb") as outgoing:
                for block in iter(lambda: incoming.read(1024 * 1024), b""):
                    if time.monotonic() >= deadline:
                        raise TimeoutError("source recovery deadline")
                    digest.update(block)
                    outgoing.write(block)
            original[key] = digest.hexdigest()
            if sha(path, deadline) != original[key] or sha(destination, deadline) != original[key]:
                raise ValueError("source changed during byte copy")
            files[key] = original[key]
    reversed_edits = []
    for edit in reversed(edits):
        path = target / edit["path"]
        data = path.read_bytes()
        after, before = edit["after"].encode(), edit["before"].encode()
        if data.count(after) != 1:
            raise ValueError("reverse edit lost exact occurrence")
        rewritten = data.replace(after, before, 1)
        path.write_bytes(rewritten)  # This is a fresh private copy, never a source hardlink.
        files[edit["path"]] = hashlib.sha256(rewritten).hexdigest()
        reversed_edits.append({"path": edit["path"], "before_sha256": hashlib.sha256(data).hexdigest(),
                               "after_sha256": files[edit["path"]]})
    if sha(args.edits) != recipe_sha or sha(args.cohort_receipt) != receipt_sha:
        raise ValueError("recovery authority changed")
    closure = [{"tree": "source", "path": key, "bytes": (target / key).stat().st_size,
                "sha256": files[key]} for key in sorted(files)]
    for name, value in (("input-closure.json", closure), ("source-snapshot.json", {"files": files}),
                        ("recovery.json", {"schema": 1, "status": "prepared", "source": str(source),
                         "cohort_receipt": str(args.cohort_receipt), "cohort_receipt_sha256": receipt_sha,
                         "edits": str(args.edits), "edits_sha256": recipe_sha, "original_files": original,
                         "reversed_edits": reversed_edits, "historical_snapshot_equivalence": "not asserted",
                         "excluded_producer_output_domains": [".dmbc/"], "BYOND_baseline": "not yet recaptured"})):
        (output / name).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
