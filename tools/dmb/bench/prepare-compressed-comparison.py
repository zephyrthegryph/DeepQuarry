#!/usr/bin/env python3
"""Prepare authenticated same-profiler source snapshots; never build or run them."""
import argparse
import hashlib
import json
import time
import tomllib
import zipfile
from pathlib import Path, PurePosixPath

PROFILE = "tools/dmb/crates/dm-profile/"
LOCK = "tools/dmb/Cargo.lock"


def snapshot_overlay(root):
    """Explicit crate inputs only, including every nested Rust module."""
    crate = root / PROFILE
    names = [PROFILE + "Cargo.toml", LOCK]
    names.extend(path.relative_to(root).as_posix()
                 for path in (crate / "src").rglob("*.rs"))
    if PROFILE + "src/lib.rs" not in names:
        raise ValueError("profiler overlay is missing src/lib.rs")
    folded = [name.casefold() for name in names]
    if len(set(folded)) != len(names):
        raise ValueError("profiler overlay path collision")
    result = {}
    for name in sorted(names):
        path = root / name
        if path.is_symlink() or any(parent.is_symlink() for parent in path.parents
                                    if parent != root and root in parent.parents):
            raise ValueError("profiler overlay must not contain symbolic links")
        result[name] = path.read_bytes()
    return result


def profiler_closure(lock_bytes, manifest_bytes):
    """Resolve Cargo's exact lock graph; reject ambiguous or absent edges."""
    lock = tomllib.loads(lock_bytes.decode("utf-8"))
    manifest = tomllib.loads(manifest_bytes.decode("utf-8"))
    packages = lock.get("package", [])
    roots = [p for p in packages if p["name"] == "dm-profile"]
    if len(roots) != 1 or roots[0]["version"] != manifest["package"]["version"]:
        raise ValueError("profiler lock root does not match overlay manifest")
    def resolve(edge):
        parts = edge.split(" ", 2)
        matches = [p for p in packages if p["name"] == parts[0]
                   and (len(parts) < 2 or p["version"] == parts[1])
                   and (len(parts) < 3 or p.get("source") == parts[2].strip("()"))]
        if len(matches) != 1:
            raise ValueError("ambiguous or missing profiler lock dependency: " + edge)
        return matches[0]
    declared = {}
    sections = [manifest]
    sections.extend(manifest.get("target", {}).values())
    for section in sections:
        for kind in ("dependencies", "build-dependencies", "dev-dependencies"):
            for name, spec in section.get(kind, {}).items():
                if isinstance(spec, dict) and spec.get("workspace"):
                    raise ValueError("workspace profiler dependencies require explicit resolution")
                declared[name] = spec.get("package", name) if isinstance(spec, dict) else name
    root_names = {resolve(edge)["name"] for edge in roots[0].get("dependencies", [])}
    if root_names != set(declared.values()):
        raise ValueError("profiler manifest dependencies differ from lock root")
    pending = [roots[0]]
    visited = {}
    while pending:
        package = pending.pop()
        key = (package["name"], package["version"], package.get("source", ""))
        if key in visited:
            continue
        dependencies = [resolve(edge) for edge in package.get("dependencies", [])]
        visited[key] = {"name": key[0], "version": key[1], "source": key[2],
                        "checksum": package.get("checksum"),
                        "dependencies": sorted((p["name"], p["version"], p.get("source", ""))
                                               for p in dependencies)}
        pending.extend(dependencies)
    return [visited[key] for key in sorted(visited)]


def compatible_parent_lock(parent, overlay_lock, manifest):
    expected = profiler_closure(overlay_lock, manifest)
    actual = profiler_closure(parent, manifest)
    if actual != expected:
        raise ValueError("parent lock profiler transitive resolution differs from overlay lock")
    encoded = json.dumps(actual, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def replaced_by_overlay(name):
    return name == LOCK or name.startswith(PROFILE)



def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        while block := stream.read(128 * 1024):
            digest.update(block)
    return digest.hexdigest()


def e_path(path):
    path = Path(path).resolve()
    if path.drive.lower() != "e:":
        raise ValueError("source snapshots and overlay must stay on E:")
    return path


def write(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")


def prepare(control, candidate, overlay_root, output, timeout, retain_parent_lock=False):
    started = time.monotonic()
    def deadline():
        if time.monotonic() - started > timeout:
            raise TimeoutError("source preparation deadline reached; partial evidence preserved")
    overlay_root = e_path(overlay_root)
    output = e_path(output)
    output.mkdir(parents=True, exist_ok=False)
    overlays = snapshot_overlay(overlay_root)
    overlay_rows = [{"path": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                    for name, data in overlays.items()]
    write(output / "overlay.manifest.json", overlay_rows)
    result = {"schema": 1, "purpose": "same-profiler-gzip-comparison-source-only",
              "required_environment": {"DMB_TRACE_COMPRESSION": "gzip"},
              "required_report_mode": "gzip-level1-v1", "overlay_scope": "complete-dm-profile-crate-rust-and-lock", "overlay": overlay_rows, "lock_policy": "authenticated-parent" if retain_parent_lock else "overlay", "snapshots": []}
    for label, record_path in (("control", control), ("candidate", candidate)):
        deadline()
        record_path = e_path(record_path)
        record = json.loads(record_path.read_text(encoding="utf-8"))
        archive = e_path(record["source_archive"])
        manifest = e_path(record["manifest"])
        if sha(archive) != record["source_archive_sha256"] or sha(manifest) != record["manifest_sha256"]:
            raise ValueError("parent source archive/manifest authentication failed")
        roster = json.loads(manifest.read_text(encoding="utf-8"))
        expected = {row["path"]: row for row in roster}
        if len(expected) != len(roster):
            raise ValueError("duplicate parent source manifest path")
        destination = output / label
        destination.mkdir()
        rows = []
        parent_lock = None
        parent_profile_manifest = None
        with zipfile.ZipFile(archive) as source:
            names = [entry.filename for entry in source.infolist() if not entry.is_dir()]
            if (len(names) != len(set(name.casefold() for name in names))
                    or set(names) != set(expected)):
                raise ValueError("archive file roster differs from authenticated manifest")
            for name in sorted(expected):
                deadline()
                relative = PurePosixPath(name)
                if relative.is_absolute() or ".." in relative.parts or "\\" in name or ":" in name:
                    raise ValueError("unsafe archive path")
                data = source.read(name)
                if len(data) != expected[name]["bytes"] or hashlib.sha256(data).hexdigest() != expected[name]["sha256"]:
                    raise ValueError("parent source file differs from manifest: " + name)
                if name == LOCK:
                    parent_lock = data
                if name == PROFILE + "Cargo.toml":
                    parent_profile_manifest = data
                if replaced_by_overlay(name):
                    continue
                path = destination / name
                path.parent.mkdir(parents=True, exist_ok=True)
                with path.open("xb") as stream:
                    stream.write(data)
                rows.append({"path": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        selected = dict(overlays)
        closure_hash = None
        if retain_parent_lock:
            if parent_lock is None:
                raise ValueError("authenticated parent archive is missing Cargo.lock")
            if parent_profile_manifest != overlays[PROFILE + "Cargo.toml"]:
                raise ValueError("parent profiler Cargo.toml differs from overlay manifest")
            closure_hash = compatible_parent_lock(parent_lock, overlays[LOCK],
                                                  overlays[PROFILE + "Cargo.toml"])
            selected[LOCK] = parent_lock
        for name, data in selected.items():
            path = destination / name
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("xb") as stream:
                stream.write(data)
            rows.append({"path": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        rows.sort(key=lambda row: row["path"])
        derived_manifest = output / (label + ".manifest.json")
        write(derived_manifest, rows)
        derived_archive = output / (label + ".zip")
        with zipfile.ZipFile(derived_archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=1) as target:
            for row in rows:
                deadline()
                target.write(destination / row["path"], row["path"])
        result["snapshots"].append({"label": label, "parent_build_record": str(record_path),
            "parent_build_record_sha256": sha(record_path), "parent_archive_sha256": record["source_archive_sha256"],
            "parent_manifest_sha256": record["manifest_sha256"], "parent_source_commit": record.get("source_commit"),
            "source_archive": str(derived_archive), "source_archive_sha256": sha(derived_archive),
            "manifest": str(derived_manifest), "manifest_sha256": sha(derived_manifest),
            "build_source": str(destination), "files": len(rows), "build_status": "not_built",
            "lock_policy": result["lock_policy"],
            "lock_sha256": hashlib.sha256(selected[LOCK]).hexdigest(),
            "profiler_closure_sha256": closure_hash,
            "profiler_closure_proof": "resolved-package-version-source-checksum-graph-only"
                if retain_parent_lock else None})
    if snapshot_overlay(overlay_root) != overlays:
        raise ValueError("overlay source changed during preparation; snapshots not admitted")
    write(output / "comparison-source.json", result)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--control-build-record", required=True)
    parser.add_argument("--candidate-build-record", required=True)
    parser.add_argument("--overlay-root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--retain-parent-lock", action="store_true",
                        help="retain authenticated parent locks only after exact profiler closure proof")
    args = parser.parse_args()
    if not 1 <= args.timeout <= 300:
        parser.error("timeout must be between 1 and 300 seconds")
    result = prepare(args.control_build_record, args.candidate_build_record,
                     args.overlay_root, args.output, args.timeout, args.retain_parent_lock)
    print(json.dumps({"output": args.output, "snapshots": result["snapshots"]}, indent=2))
