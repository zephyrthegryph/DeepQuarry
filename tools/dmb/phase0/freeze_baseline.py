"""Freeze Phase 0 provenance and recover compiled asset payloads from the RSC."""
import argparse
import hashlib
import json
import shutil
import struct
from pathlib import Path


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def archive_assets(archive, destination):
    rows = []
    destination = destination.resolve()
    with archive.open("rb") as stream:
        while header := stream.read(5):
            if len(header) != 5:
                raise ValueError("Truncated RSC entry header")
            length, validity = struct.unpack("<IB", header)
            if length > 512 * 1024 * 1024:
                raise ValueError("Implausible RSC entry size")
            payload = stream.read(length)
            if len(payload) != length:
                raise ValueError("Truncated RSC entry")
            if validity != 1:
                continue
            if length < 18:
                raise ValueError("Truncated named resource")
            kind, resource_id, timestamp, source_timestamp, size = struct.unpack_from("<BIIII", payload)
            end = payload.find(b"\0", 17)
            if end < 0 or end + 1 + size > length:
                raise ValueError("Invalid resource filename or declared size")
            name = payload[17:end].decode("utf-8", errors="strict")
            relative = name.replace("\\", "/")
            if ":" in relative:
                raise ValueError("Absolute archive name: " + name)
            target = (destination / relative).resolve()
            if not target.is_relative_to(destination):
                raise ValueError("Archive path escapes frozen inputs: " + name)
            asset = payload[end + 1:end + 1 + size]
            target.parent.mkdir(parents=True, exist_ok=True)
            previous = digest(target) if target.is_file() else None
            target.write_bytes(asset)
            rows.append({"path": relative, "kind": kind, "resource_id": resource_id,
                         "bytes": size, "sha256": hashlib.sha256(asset).hexdigest(),
                         "previous_sha256": previous, "source_timestamp": source_timestamp})
    return rows


def restore_external_runtime_inputs(frozen):
    """Only explicit non-imported fixture data, not a wholesale source overlay."""
    relative = 'code/modules/unit_tests/data/dq_constraint_parity.json'
    source = frozen / 'source' / relative
    target = frozen / 'runtime' / relative
    if not source.is_file():
        raise ValueError('Missing preserved constraint fixture: ' + str(source))
    expected = digest(source)
    if target.exists() and digest(target) != expected:
        raise ValueError('Runtime fixture differs; refuse replacement: ' + str(target))
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        shutil.copy2(source, target)
    return [{'path': relative, 'source': str(source), 'sha256': expected,
             'bytes': source.stat().st_size, 'reason': 'runtime file2text dependency, not imported into RSC'}]


def inventory(root):
    rows = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        if path.relative_to(root).parts[0] == "data" or any(part in {"target", "node_modules", ".git"} for part in path.relative_to(root).parts):
            continue
        stat = path.stat()
        rows.append({"path": relative, "bytes": stat.st_size, "mtime_ns": stat.st_mtime_ns,
                     "sha256": digest(path)})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--comparison", type=Path, required=True)
    parser.add_argument("--artifact-root", type=Path, required=True)
    parser.add_argument("--repository", type=Path, required=True)
    args = parser.parse_args()
    root = args.artifact_root.resolve()
    frozen = root / "frozen"
    pairs = frozen / "pairs"
    pairs.mkdir(parents=True, exist_ok=True)
    originals = {
        "byond": (args.comparison / "source-final/comparison.dmb", args.comparison / "source-final/comparison.rsc"),
        "native": tuple(args.comparison / "rust-output-final/generations/2be3e35918c9bd4cc7f90b0ad9c71e55655e61f604584e60085d446fbdbc9fbc" / ("world." + extension) for extension in ("dmb", "rsc")),
    }
    pair_rows = {}
    for name, files in originals.items():
        directory = pairs / name
        directory.mkdir(exist_ok=True)
        pair_rows[name] = []
        for source in files:
            target = directory / ("world" + source.suffix)
            shutil.copy2(source, target)
            before = digest(source)
            after = digest(target)
            if before != after:
                raise ValueError("Pair changed during copying: " + str(source))
            pair_rows[name].append({"original": str(source), "frozen": str(target), "sha256": after, "bytes": target.stat().st_size})
    restored = archive_assets(pairs / "byond/world.rsc", frozen / "source")
    raw_root = frozen / "preserved"
    shutil.copy2(args.comparison / "expected-runnable-tests.txt", frozen / "expected-runnable-tests.txt")
    for name, run_id in {"byond": "6475a3d057ca4f5eabab43addc3dae04", "native": "8a6054fad0144a82b6456d651415ba16"}.items():
        destination = raw_root / name
        destination.mkdir(parents=True, exist_ok=True)
        result_root = args.repository / "tools/dmb/target/runtime-tests" / ("native-compiler-" + run_id)
        runtime_root = args.comparison / ("byond-runtime-final" if name == "byond" else "rust-runtime-final") / "data/logs" / ("native-compiler-" + run_id)
        for basename in ("unit_tests.json", "stdout.log", "stderr.log"):
            shutil.copy2(result_root / basename, destination / basename)
        for basename in ("runtime-errors.log", "runtime.log.json", "tests.log"):
            source = runtime_root / basename
            if source.exists():
                shutil.copy2(source, destination / basename)
    compiler = args.repository / "tools/dmb/target/compiler-integration-fiftieth.exe"
    shutil.copy2(compiler, frozen / compiler.name)
    external_inputs = restore_external_runtime_inputs(frozen)
    report = {"external_runtime_inputs": external_inputs, "schema": 1, "reference_commit": "ac1af55d1a9a8e023e46bd058be59ed82c503f52",
              "comparison_id": "dcd1b1f39fe14bd6a3ad65fd8d2bc1da", "hash_algorithm": "sha256 provenance audit (preserved compiler unchanged)",
              "pairs": pair_rows, "preserved_native_binary": {"path": str(frozen / compiler.name), "sha256": digest(compiler)},
              "test_selection": {"path": str(frozen / "expected-runnable-tests.txt"), "sha256": digest(frozen / "expected-runnable-tests.txt")},
              "restored_original_imported_assets": restored, "source": inventory(frozen / "source"),
              "runtime": inventory(frozen / "runtime"), "preserved_records": inventory(raw_root),
              "limitations": ["Recovered assets are compiled RSC payloads; formats transformed by DreamMaker need not reproduce their original source encoding or timestamps.",
                               "Non-imported external resources copied from retained runtime directories; the original DMB/RSC bytes remain independently pinned.",
                               "Runtime seed controls must be recorded from the preserved world; no seed override is invented."]}
    target = root / "frozen-manifest.json"
    target.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"manifest": str(target), "source_files": len(report["source"]), "runtime_files": len(report["runtime"]), "restored_resources": len(restored)}))


if __name__ == "__main__":
    main()
