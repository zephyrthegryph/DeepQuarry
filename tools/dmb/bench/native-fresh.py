"""One bounded fresh native compile; no daemon, iteration or acceptance claim."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import hashlib
import time
import uuid

from iteration_memory import OwnedMemory
from iteration_structural import authenticate_source_snapshot, source_matches
import build_receipt
import semantic_configuration


def helpers():
    spec = importlib.util.spec_from_file_location("native_iteration_helpers", Path(__file__).with_name("native-iteration.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_json(path, limit=1024 * 1024):
    if path.stat().st_size > limit:
        raise ValueError(f"receipt exceeds {limit} bytes: {path}")
    return json.loads(path.read_text(encoding="utf-8-sig"))


def semantic_arguments(scenario, template):
    arguments = scenario["arguments"]
    result = []
    index = 0
    while index < len(arguments):
        item = arguments[index]
        if item == "--engine-template":
            index += 2
        elif item == "--no-daemon":
            index += 1
        elif item == "--bootstrap-catalog" or item.startswith("-D"):
            result.append(item)
            index += 1
        else:
            raise ValueError(f"unsupported semantic scenario argument: {item}")
    return [*result, "--engine-template", str(template)]


def resolved_path(value):
    """Compare Windows extended and ordinary names for the same resolved path."""
    resolved = str(Path(value).resolve())
    if os.name == "nt":
        if resolved.startswith("\\\\?\\UNC\\"):
            resolved = "\\\\" + resolved[8:]
        elif resolved.startswith("\\\\?\\") and re.match(r"[A-Za-z]:\\", resolved[4:]):
            resolved = resolved[4:]
    return Path(resolved)


def admit_pair(result, acquired, project, store, slots, regular, sha):
    if result.get("schema_version") != 1 or result.get("kind") != "native_pair":
        raise ValueError("unsupported compile result")
    if acquired.get("schema_version") != 1 or acquired.get("kind") != "acquired_pair":
        raise ValueError("unsupported acquisition result")
    if resolved_path(result["output_project"]) != resolved_path(project):
        raise ValueError("compile result names another project")
    for value in (result, acquired):
        if resolved_path(value["store"]) != resolved_path(store):
            raise ValueError("result names another output store")
        for field in ("pair_id", "dmb_hash", "rsc_hash"):
            if not isinstance(value.get(field), str) or not re.fullmatch("[0-9a-f]{32}", value[field]):
                raise ValueError("invalid pair identity")
        for field in ("dmb_bytes", "rsc_bytes"):
            if type(value.get(field)) is not int or value[field] < 0:
                raise ValueError("invalid pair size")
    for field in ("pair_id", "dmb_hash", "rsc_hash", "dmb_bytes", "rsc_bytes"):
        if acquired[field] != result[field]:
            raise ValueError("acquisition differs from published generation")
    slot = resolved_path(acquired["slot"])
    if slot.parent != resolved_path(slots):
        raise ValueError("acquisition escaped owned slots")
    marker = slot / "slot-complete"
    regular(marker)
    if marker.read_text() != result["pair_id"]:
        raise ValueError("acquired slot incomplete")
    outputs = {}
    for extension in ("dmb", "rsc"):
        actual = resolved_path(acquired[extension])
        if actual != slot / ("deepquarry." + extension):
            raise ValueError("unexpected acquired artifact path")
        conventional = project.with_suffix("." + extension)
        for file in (actual, conventional):
            regular(file)
            if file.stat().st_size != result[extension + "_bytes"]:
                raise ValueError("artifact length mismatch")
        if actual.stat().st_nlink != 1:
            raise ValueError("acquired artifact is not independent")
        digest = sha(actual)
        if sha(conventional) != digest:
            raise ValueError("artifact copy differs from acquired pair")
        outputs[extension] = {"sha256": digest, "bytes": actual.stat().st_size,
                              "path": str(conventional), "acquired_path": str(actual)}
    return outputs


def preserve_telemetry(project, evidence, regular, sha):
    """Move only exact new compiler telemetry; unexpected namespace stays rejected."""
    folder = project.parent / ".dmbc"
    if not folder.exists():
        return []
    if folder.is_symlink() or getattr(folder.lstat(), "st_file_attributes", 0) & 0x400:
        raise ValueError("telemetry directory is a reparse point")
    rows = []
    evidence.mkdir()
    for suffix in ("stats", "last-run"):
        file = folder / (project.stem + "." + suffix + ".json")
        if not file.exists():
            continue
        regular(file)
        row = {"name": file.name, "sha256": sha(file), "bytes": file.stat().st_size}
        target = evidence / file.name
        os.rename(file, target)
        if sha(target) != row["sha256"]:
            raise ValueError("telemetry changed during preservation")
        rows.append({**row, "path": str(target)})
    # Only an empty owned generated directory may be removed. Unknown files
    # survive and cause the full namespace comparison to reject success.
    if not any(folder.iterdir()):
        folder.rmdir()
    return rows


def require_absent_lock(project_root, manifest, snapshot):
    relative = manifest.parent / ".dmbc" / "build.lock"
    if relative.as_posix() in snapshot["files"]:
        raise ValueError("captured source contains compiler lock")
    lock = project_root / relative
    if lock.exists() or lock.is_symlink():
        raise ValueError("compiler lock existed before run")
    return lock


def confirm_source(project, snapshot, sha, generated_lock=None):
    proof = None
    admitted = snapshot
    if generated_lock is not None:
        lock = generated_lock
        relative = lock.relative_to(project).as_posix()
        if relative in snapshot["files"]:
            raise ValueError("captured source contains compiler lock")
        for item in (lock.parent, lock):
            value = item.lstat()
            if stat.S_ISLNK(value.st_mode) or getattr(value, "st_file_attributes", 0) & 0x400:
                raise ValueError("generated lock is a reparse point")
        value = lock.lstat()
        if not stat.S_ISREG(value.st_mode) or value.st_size != 0 or value.st_nlink != 1:
            raise ValueError("generated lock must be an independent empty regular file")
        with lock.open("rb") as handle:
            before = os.fstat(handle.fileno())
            if handle.read(1) or os.fstat(handle.fileno()).st_size != 0 or before.st_size != 0:
                raise ValueError("generated lock contents changed")
        digest = sha(lock)
        if digest != hashlib.sha256(b"").hexdigest():
            raise ValueError("generated lock contents changed")
        proof = {"path": str(lock), "relative": relative, "bytes": 0, "sha256": digest,
                 "scope": "new exact compile_driver build.lock leaf; retained in place, not a source input"}
        # Existing full-roster validator still checks every other name and byte.
        # This one generated leaf is added only after producer-shape validation;
        # the captured semantic source manifest is never mutated.
        admitted = {**snapshot, "files": {**snapshot["files"], relative: digest}}
    if not source_matches(project, admitted, sha):
        raise ValueError("isolated source differs from captured closure after compilation")
    return proof


def main():
    h = helpers()
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("compiler", "build-receipt", "template", "source", "source-snapshot", "input-closure", "byond-pin", "scenarios"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--project")
    parser.add_argument("--output-root", default="E:/dq-cache/dmb-native-fresh")
    parser.add_argument("--minimum-free-gib", type=int, default=16)
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("owned private memory sampling requires Windows")
    if args.minimum_free_gib < 1:
        parser.error("minimum headroom must be positive")
    parent = h.safe_e(args.output_root)
    if not parent.is_relative_to(Path("E:/dq-cache")):
        raise ValueError("output root must be under E:/dq-cache")
    root = parent / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
    root.mkdir(parents=True)
    receipt = {"schema": "dm-native-fresh-v1", "status": "starting", "workers": 2,
               "watchdog_seconds": 300, "owned_private_budget_bytes": 4_000_000_000,
               "acceptance_admitted": False, "scope": "one fresh compile with progress logging and sampled owned private memory; no incremental, BYOND, runtime or r6 acceptance"}
    memory = None
    try:
        receipt["disk_preflight"] = h.disk_preflight(root, args.minimum_free_gib * 1024 ** 3)
        if receipt["disk_preflight"]["status"] != "passed":
            raise ValueError("insufficient E: headroom")
        executable = h.safe_e(args.compiler)
        template = h.safe_e(args.template)
        for file in (executable, template):
            h.regular(file)
        receipt["build"] = build_receipt.authenticate(h.safe_e(args.build_receipt), executable, h.sha)
        executable_sha = h.sha(executable)
        template_sha = h.sha(template)
        receipt.update(compiler_sha256=executable_sha, template_sha256=template_sha)
        snapshot_path = h.safe_e(args.source_snapshot)
        snapshot = read_json(snapshot_path, 32 * 1024 * 1024)
        closure = h.safe_e(args.input_closure)
        pin = read_json(h.safe_e(args.byond_pin))
        receipt["input_closure_sha256"] = authenticate_source_snapshot(snapshot, closure, pin, h.sha)
        receipt["source_snapshot_sha256"] = h.sha(snapshot_path)
        scenario_path = h.safe_e(args.scenarios)
        scenario = read_json(scenario_path)[0]
        receipt["scenario_sha256"] = h.sha(scenario_path)
        manifest = Path(args.project or scenario["project"])
        if manifest.is_absolute() or manifest.drive or ".." in manifest.parts:
            raise ValueError("manifest must be a contained relative path")
        semantic = semantic_arguments(scenario, template)
        configuration, _ = semantic_configuration.command_configuration(str(manifest), semantic, h.sha)
        receipt["configuration_evidence"] = [str(path) for path in semantic_configuration.authenticate_pin(pin, configuration, h.sha)]
        receipt["semantic_configuration_sha256"] = semantic_configuration.digest(configuration)
        project_root = root / "project"
        receipt["isolated_files"] = h.isolate(h.safe_e(args.source), project_root)
        confirm_source(project_root, snapshot, h.sha)
        generated_lock = require_absent_lock(project_root, manifest, snapshot)
        receipt["build_lock_absent_before_run"] = True
        project = root / "artifacts" / manifest.name
        store = root / "store"
        result_path = root / "compile-result.json"
        arguments = ["compile", str(project_root / manifest), "--workers", "2", "--progress",
                     "--no-daemon", "--no-cache", "--exact-inputs", "--artifact-directory", str(project.parent),
                     "--output-store", str(store), "--compile-result-file", str(result_path),
                     *semantic]
        receipt["arguments"] = arguments
        h.write_receipt(root, receipt)
        memory = OwnedMemory(4_000_000_000)
        h._owned_memory = memory
        memory.start()
        compile_result = h.run_child(executable, arguments, root / "compile", time.monotonic() + 300,
                                     cache_directory=root / "compiler-cache")
        receipt["compile_execution"] = compile_result
        if compile_result["exit"] != 0:
            raise ValueError(f"fresh compile failed with status {compile_result['exit']}")
        result = read_json(result_path, 64 * 1024)
        # Core acquisition validates immutable pair content. This second child is
        # outside compile timing and shares the same bounded owned-memory watcher.
        slots = root / "slots"
        acquired_path = root / "acquired.json"
        acquisition = h.run_child(executable, ["acquire", "--output-store", str(store), "--pair-id", result["pair_id"],
            "--slots", str(slots), "--result-file", str(acquired_path)], root / "acquire", time.monotonic() + 30)
        receipt["acquisition_execution"] = acquisition
        if acquisition["exit"] != 0:
            raise ValueError("published pair acquisition failed")
        h.safe_e(project)
        outputs = admit_pair(result, read_json(acquired_path, 64 * 1024), project, store, slots, h.regular, h.sha)
        if h.sha(executable) != executable_sha or h.sha(template) != template_sha:
            raise ValueError("compiler or template changed during run")
        # Hardlinks share input inodes: recheck captured bytes after all compiler
        # and acquisition work, before admitting output or successful timing.
        receipt["telemetry"] = preserve_telemetry(project_root / manifest, root / "telemetry", h.regular, h.sha)
        receipt["generated_build_lock"] = confirm_source(project_root, snapshot, h.sha, generated_lock)
        receipt["source_unchanged_after_compile"] = True
        memory.check()
        receipt.update(status="passed", admitted_output=True, outputs=outputs,
                       compile_timing={"wall_seconds": compile_result["wall_s"], "scope": "fresh compiler launch through reap; source isolation and output acquisition excluded"})
    except Exception as error:
        receipt.update(status="failed", admitted_output=False, error=str(error))
    finally:
        if memory is not None:
            receipt["memory"] = memory.finish()
            receipt["memory"]["scope"] = "registered owned fresh compiler and acquisition children only; 200ms samples, unregistered descendants/unrelated processes excluded; not strict peak proof"
            if receipt["memory"]["status"] == "failed":
                receipt.update(status="failed", admitted_output=False)
                receipt.pop("compile_timing", None)
            h._owned_memory = None
        receipt["child_evidence"] = {phase: str(root / phase / "child.json") for phase in ("compile", "acquire") if (root / phase / "child.json").exists()}
        h.write_receipt(root, receipt)
    print(json.dumps({"receipt": str(root / "receipt.json"), "status": receipt["status"]}))
    return 0 if receipt["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
