"""Explicit six-root preparation only; never compiles, runs, or invents a BYOND pin."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from iteration_structural import authenticate_source_snapshot
from worktree_authority import authenticate

EXCLUDED = {".git", ".dmbc", "target", "node_modules"}
MAX_FILES = 40_000
MAX_BYTES = 4 * 1024 ** 3
_deadline = None


def relative_path(value):
    if not isinstance(value, str) or "\\" in value or ":" in value:
        raise ValueError("closure path must be a canonical relative POSIX path")
    path = PurePosixPath(value)
    if path.is_absolute() or not path.parts or any(part in ("", ".", "..") for part in value.split("/")):
        raise ValueError("closure path escapes its owner")
    if any(part in EXCLUDED for part in path.parts) or path.suffix.lower() in (".dmb", ".rsc"):
        raise ValueError("closure contains excluded producer outputs")
    return Path(*path.parts)


def normalized_path(value):
    return Path(os.path.abspath(os.fspath(value)))


def owned_output(value):
    path = existing_e(value)
    parent = normalized_path("E:/dq-cache")
    if path == parent or not path.is_relative_to(parent) or path.exists():
        raise ValueError("new owned E:/dq-cache output directory required")
    return path


def existing_e(value):
    path = normalized_path(value)
    if path.drive.casefold() != "e:":
        raise ValueError("all preparation paths must be on E:")
    for item in (path, *path.parents):
        if item.exists() and (item.is_symlink() or item.stat().st_file_attributes & 0x400):
            raise ValueError("reparse paths are unsupported")
    return path


def target_roots(values):
    roots = [existing_e(value) for value in values]
    parent = normalized_path("E:/projects/dq-wt")
    if len(roots) != 6 or len({str(path).casefold() for path in roots}) != 6:
        raise ValueError("exactly six distinct roots required")
    if any(not path.is_relative_to(parent) or path == parent or path.exists() for path in roots):
        raise ValueError("all roots must be new owned paths under E:/projects/dq-wt")
    return roots


def seed_action(tracked, exists, matches):
    if exists:
        if not matches:
            raise ValueError("existing content differs; preparation never overwrites tracked or untracked files")
        return "verified"
    if tracked:
        raise ValueError("tracked input missing from newly created worktree")
    return "seed"


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            if _deadline is not None and time.monotonic() > _deadline:
                raise TimeoutError("overall preparation deadline")
            digest.update(block)
    return digest.hexdigest()


def git_blob_sha1(path):
    size = path.stat().st_size
    if not path.is_file() or size > MAX_BYTES:
        raise ValueError("tracked seed is nonregular or exceeds source byte bound")
    digest = hashlib.sha1(("blob " + str(size) + "\0").encode("ascii"))
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            if _deadline is not None and time.monotonic() > _deadline:
                raise TimeoutError("overall preparation deadline")
            digest.update(block)
    if path.stat().st_size != size: raise ValueError("tracked seed changed during check")
    return digest.hexdigest()


def read_json(path, limit):
    if path.stat().st_size > limit:
        raise ValueError("bounded preparation JSON exceeded")
    raw = path.read_bytes()
    if len(raw) > limit:
        raise ValueError("preparation JSON grew beyond limit")
    return json.loads(raw)


def git(repository, arguments):
    environment = {key: value for key, value in os.environ.items() if not key.upper().startswith("GIT_")}
    result = subprocess.run(["git", "-C", str(repository), *arguments], capture_output=True,
        timeout=min(180, max(0.01, _deadline - time.monotonic())) if _deadline else 180, check=True, env=environment,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    if len(result.stdout) > 8 * 1024 ** 2 or len(result.stderr) > 1024 ** 2:
        raise ValueError("Git output exceeded preparation bound")
    return result.stdout


def capture(root, deadline):
    entries, total = [], 0
    for current, directories, files in os.walk(root, followlinks=False):
        if time.monotonic() > deadline:
            raise TimeoutError("overall preparation deadline")
        current = existing_e(current)
        directories[:] = sorted(name for name in directories if name not in EXCLUDED)
        for name in sorted(files):
            if name == ".git" or Path(name).suffix.lower() in (".dmb", ".rsc"):
                continue
            path = existing_e(current / name)
            if not path.is_file():
                raise ValueError("nonregular source input")
            size = path.stat().st_size
            total += size
            if len(entries) >= MAX_FILES or total > MAX_BYTES:
                raise ValueError("current source exceeds 40,000 files or 4 GiB")
            digest = sha(path)
            if path.stat().st_size != size:
                raise ValueError("source changed during capture")
            entries.append({"tree": "source", "path": path.relative_to(root).as_posix(), "bytes": size, "sha256": digest})
    return sorted(entries, key=lambda row: row["path"])


def main():
    global _deadline
    _deadline = time.monotonic() + 300
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("repository", "payload", "snapshot", "closure", "pin", "output"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--overall-seconds", type=int, default=300, choices=range(1, 301), metavar="1..300")
    parser.add_argument("--revision", required=True, help="explicit full committed Git SHA")
    parser.add_argument("--root", action="append", required=True)
    args = parser.parse_args()
    _deadline = time.monotonic() + args.overall_seconds
    if os.name != "nt" or not re.fullmatch(r"[0-9a-f]{40}", args.revision):
        raise ValueError("Windows and explicit full committed revision required")
    roots = target_roots(args.root)
    repository, payload = existing_e(args.repository), existing_e(args.payload)
    output = owned_output(args.output)
    snapshot_file, closure_file, pin_file = map(existing_e, (args.snapshot, args.closure, args.pin))
    snapshot = read_json(snapshot_file, 4 * 1024 ** 2)
    entries = read_json(closure_file, 8 * 1024 ** 2)
    pin = read_json(pin_file, 1024 ** 2)
    authenticate_source_snapshot(snapshot, closure_file, pin, sha)
    if len(entries) > MAX_FILES or sum(row["bytes"] for row in entries) > MAX_BYTES:
        raise ValueError("seed closure exceeds bounded materialization")
    for row in entries:
        relative = relative_path(row["path"])
        if row["tree"] != "source" or not re.fullmatch(r"[0-9a-f]{64}", row["sha256"]):
            raise ValueError("unsupported seed closure entry")
        source = existing_e(payload / relative)
        if not source.is_file() or source.stat().st_size != row["bytes"] or sha(source) != row["sha256"]:
            raise ValueError("seed payload differs from authenticated closure")
    if git(repository, ["rev-parse", args.revision + "^{commit}"]).decode().strip() != args.revision:
        raise ValueError("revision is not exact committed authority")
    if git(repository, ["rev-parse", "--show-object-format"]).decode().strip() != "sha1":
        raise ValueError("non-SHA1 Git object format is unsupported by this bounded seed check")
    tracked = {}
    for raw in git(repository, ["ls-tree", "-r", "-z", args.revision]).split(b"\0"):
        if not raw: continue
        descriptor, name = raw.decode("utf-8").split("\t", 1)
        mode, kind, object_id = descriptor.split()
        tracked[name] = (mode, kind, object_id)
    # Reject before creating any root. Raw object bytes are deliberate authority:
    # payloads requiring historical smudge/filter reconstruction decline safely.
    for row in entries:
        if row["path"] in tracked:
            mode, kind, expected = tracked[row["path"]]
            if mode not in ("100644", "100755") or kind != "blob":
                raise ValueError("tracked symlink/submodule seed is unsupported")
            if git_blob_sha1(existing_e(payload / relative_path(row["path"]))) != expected:
                raise ValueError("tracked seed differs from committed bytes; no roots created")
    output.mkdir(parents=True, exist_ok=False)
    receipt = {"status": "preparing", "revision": args.revision, "roots": [],
               "seed_closure_sha256": sha(closure_file), "overall_seconds": args.overall_seconds, "current_byond_pin": "not issued",
               "scope": "current registered source closure; historical seed pin does not authenticate current compilation"}
    deadline = _deadline
    try:
        for root in roots:
            if time.monotonic() > deadline: raise TimeoutError("overall preparation deadline")
            git(repository, ["worktree", "add", "--detach", str(root), args.revision])
            receipt["roots"].append(str(root))
            for row in entries:
                target = existing_e(root / relative_path(row["path"]))
                action = seed_action(row["path"] in tracked, target.exists(), target.is_file() and sha(target) == row["sha256"])
                if action == "seed":
                    target.parent.mkdir(parents=True, exist_ok=True)
                    # Private copies: later tools cannot mutate a shared historical inode.
                    with existing_e(payload / relative_path(row["path"])).open("rb") as reader, target.open("xb") as writer:
                        for block in iter(lambda: reader.read(1024 * 1024), b""):
                            if time.monotonic() > deadline: raise TimeoutError("overall preparation deadline")
                            writer.write(block)
                    if sha(target) != row["sha256"]: raise ValueError("seed changed during copy")
            current = capture(root, deadline)
            if root == roots[0]:
                baseline = current
                (output / "input-closure.json").write_text(json.dumps(current, indent=2), encoding="utf-8")
                (output / "source-snapshot.json").write_text(json.dumps({"files": {row["path"]: row["sha256"] for row in current}}, indent=2), encoding="utf-8")
            elif current != baseline:
                raise ValueError("six current source closures differ")
        receipt["worktree_authority"] = authenticate(roots)
        receipt["status"] = "prepared_not_compiled"
        receipt["source_files"] = len(baseline)
        receipt["source_bytes_per_root"] = sum(row["bytes"] for row in baseline)
        (output / "worktrees.json").write_text(json.dumps([str(root) for root in roots]), encoding="utf-8")
    except Exception as error:
        receipt.update(status="failed", error=str(error))
        raise
    finally:
        # Preserve new owned roots for inspection. No automatic recursive deletion or lock manipulation.
        (output / "preparation.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
    print(json.dumps({"status": receipt["status"], "receipt": str(output / "preparation.json")}))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
