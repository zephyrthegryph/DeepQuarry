"""Bounded real-source retained iterations with an independent fresh byte oracle.

No runtime/BYOND parity or r6 CPU/memory acceptance is claimed by this runner.
Source isolation uses hardlinks; edits atomically replace a private link, never
truncate shared source. Existing daemons are refused rather than retired.
"""
import argparse
import concurrent.futures
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
from pathlib import Path
import stat
import shutil
import subprocess
import time
import uuid

from watchdog import terminate_owned
from iteration_structural import Comparison, source_matches, authenticate_source_snapshot
import semantic_configuration
from iteration_history import EditHistory
import host_context
import worktree_authority
import build_receipt


DEFAULT = Path("E:/dmb-native-v2-phase0/review-power-focus")


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def regular(path):
    value = path.lstat()
    if not stat.S_ISREG(value.st_mode) or getattr(value, "st_file_attributes", 0) & 0x400:
        raise ValueError(f"not a regular non-reparse file: {path}")


def safe_e(path):
    path = Path(os.path.abspath(path))
    if path.drive.lower() != "e:":
        raise ValueError(f"requires E: path: {path}")
    for ancestor in (path, *path.parents):
        if ancestor.exists() and getattr(ancestor.lstat(), "st_file_attributes", 0) & 0x400:
            raise ValueError(f"reparse ancestor rejected: {ancestor}")
    return path


def disk_preflight(destination, minimum_free_bytes):
    """Observed headroom only: concurrent writers can consume it after this check."""
    existing = destination
    while not existing.exists():
        existing = existing.parent
    usage = shutil.disk_usage(existing)
    return {"status": "passed" if usage.free >= minimum_free_bytes else "failed",
            "checked_path": str(existing), "free_bytes": usage.free,
            "total_bytes": usage.total, "required_free_bytes": minimum_free_bytes,
            "policy": "configurable headroom floor; no reservation or completion guarantee"}


def isolate(source, destination, detached=()):
    """Every traversed directory is checked before descent; source stays immutable."""
    source = safe_e(source)
    destination.mkdir()
    count = 0
    for current, directories, files in os.walk(source, followlinks=False):
        current = safe_e(current)
        relative = current.relative_to(source)
        target = destination / relative
        target.mkdir(exist_ok=True)
        directories[:] = [name for name in directories if name not in (".git", ".dmbc", "target", "node_modules")]
        for name in directories:
            safe_e(current / name)
        for name in files:
            if name == ".git":
                continue
            original = current / name
            regular(original)
            # Generated outputs must not be retained through writable hardlinks.
            if original.suffix.lower() in (".dmb", ".rsc"):
                continue
            if (relative / name) in detached:
                # Edited files begin as private writable copies; a readonly
                # frozen inode must never have its attributes modified.
                with original.open("rb") as input_file, (target / name).open("xb") as output_file:
                    for block in iter(lambda: input_file.read(1024 * 1024), b""):
                        output_file.write(block)
            else:
                os.link(original, target / name)
            count += 1
    return count


def replace_edit(project, edit):
    labels = {}
    for label in ("kind", "structural_kind"):
        if label in edit:
            value = edit[label]
            if not isinstance(value, str) or not value or len(value) > 64:
                raise ValueError(f"invalid edit label: {label}")
            labels[label] = value
    relative = Path(edit["path"])
    if relative.is_absolute() or relative.drive or ".." in relative.parts:
        raise ValueError("edit path must be a contained relative source path")
    target = safe_e(project / relative)
    if not target.is_relative_to(project):
        raise ValueError("edit escaped project")
    regular(target)
    before = edit["before"].encode("utf-8")
    after = edit["after"].encode("utf-8")
    if not before or before == after:
        raise ValueError("edit must change exactly one nonempty byte sequence")
    data = target.read_bytes()
    if data.count(before) != 1:
        raise ValueError(f"edit does not identify exactly one site: {relative}")
    result = data.replace(before, after, 1)
    temporary = target.with_name(target.name + ".iteration-" + uuid.uuid4().hex)
    try:
        with temporary.open("xb") as output:
            output.write(result)
        # Never chmod a hardlinked source inode. Readonly targets fail closed.
        os.replace(temporary, target)
    finally:
        if temporary.exists():
            temporary.unlink()
    receipt = {"path": str(relative), "before_sha256": hashlib.sha256(data).hexdigest(),
               "after_sha256": hashlib.sha256(result).hexdigest(),
               "replacement_before_sha256": hashlib.sha256(before).hexdigest(),
               "replacement_after_sha256": hashlib.sha256(after).hexdigest()}
    # Preserve scenario labels in every session and edit-history receipt. These
    # describe the requested mutation; output admission still uses byte hashes.
    receipt.update(labels)
    return receipt


class Endpoint:
    def __init__(self):
        sid = subprocess.check_output(
            ["powershell", "-NoProfile", "-Command",
             "[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value"],
            text=True, timeout=10, creationflags=subprocess.CREATE_NO_WINDOW).strip()
        self.name = "\\\\.\\pipe\\dmbd-" + sid
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        self.kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD,
            wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p]
        self.kernel.CreateFileW.restype = wintypes.HANDLE
        self.kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        self.kernel.WaitNamedPipeW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD]
        self.kernel.WaitNamedPipeW.restype = wintypes.BOOL
        self.kernel.GetNamedPipeServerProcessId.argtypes = [wintypes.HANDLE,
                                                           ctypes.POINTER(wintypes.ULONG)]

    def probe(self, owner=None):
        deadline = time.monotonic() + 2
        while True:
            handle = self.kernel.CreateFileW(self.name, 0xc0000000, 0, None, 3, 0, None)
            if handle != ctypes.c_void_p(-1).value:
                break
            error = ctypes.get_last_error()
            if error == 231 and owner is not None and owner.poll() is None and time.monotonic() < deadline:
                # A previous probe may still be draining on the owned server.
                # Wait for an instance, then verify its actual PID before use.
                self.kernel.WaitNamedPipeW(self.name, 100)
                time.sleep(0.01)
                continue
            if error == 2:
                return False
            raise RuntimeError(f"daemon endpoint unavailable/occupied: Windows {error}")
        try:
            pid = wintypes.ULONG()
            if owner is None:
                raise RuntimeError("pre-existing daemon refused and left untouched")
            if not self.kernel.GetNamedPipeServerProcessId(handle, ctypes.byref(pid)) or pid.value != owner.pid:
                raise RuntimeError("daemon endpoint belongs to another process")
            return True
        finally:
            self.kernel.CloseHandle(handle)


def run_child(executable, arguments, directory, deadline, require_owned=False, cache_directory=None):
    directory.mkdir(parents=True)
    started = time.monotonic()
    remaining = min(300, deadline - started)
    if remaining <= 0:
        raise TimeoutError("overall iteration deadline exhausted")
    with (directory / "stdout.log").open("xb") as out, (directory / "stderr.log").open("xb") as err:
        environment = os.environ.copy()
        if cache_directory is not None:
            environment["DMB_CACHE_DIR"] = str(cache_directory)
        if require_owned:
            environment["DMB_DAEMON_AUTOSTART"] = "0"
        child = subprocess.Popen([str(executable), *arguments], stdout=out, stderr=err, env=environment,
                                 creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            code = child.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            cleanup = terminate_owned(child)
            (directory / "timeout.json").write_text(json.dumps({
                "cleanup": cleanup, "watchdog_s": remaining,
                "wall_s": time.monotonic() - started, "arguments": arguments,
                "executable_sha256": sha(executable), "status": "timed_out",
                "admitted_output": False,
            }, indent=2), encoding="utf-8")
            raise TimeoutError(f"compiler child exceeded {remaining:.1f}s")
    result = {"exit": code, "wall_s": time.monotonic() - started,
              "wall_scope": "client launch through reap; daemon work included for retained requests"}
    (directory / "child.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def compile_one(executable, project, manifest, workers, semantic, artifacts, logs,
                mode, deadline, require_owned, endpoint, daemon, cache_directory):
    if daemon.poll() is not None or not endpoint.probe(daemon):
        raise RuntimeError("owned daemon missing before request")
    arguments = ["compile", str(project / manifest), "--workers", str(workers),
                 "--progress",
                 "--artifact-directory", str(artifacts / "artifacts"),
                 "--output-store", str(artifacts / "store"), *semantic]
    if mode == "fresh":
        arguments.extend(["--no-daemon", "--no-cache"])
    result = run_child(executable, arguments, logs, deadline,
                       require_owned and mode == "retained", cache_directory)
    result["stage_progress_logging"] = True
    stats = (project / manifest).parent / ".dmbc" / (manifest.stem + ".stats.json")
    for name, path in (("compiler_stats", stats),
                       ("last_run", stats.with_name(manifest.stem + ".last-run.json"))):
        if path.exists():
            # The next request overwrites the project-side files. Preserve the
            # complete evidence here, while keeping the cohort receipt bounded.
            raw = path.read_bytes()
            evidence = logs / (name + ".json")
            with evidence.open("xb") as output:
                output.write(raw)
            result[name + "_evidence"] = {
                "path": str(evidence), "bytes": len(raw),
                "sha256": hashlib.sha256(raw).hexdigest(),
            }
            value = json.loads(raw)
            explanations = value.pop("explanations", None)
            if explanations is not None:
                outcomes = {}
                for explanation in explanations:
                    outcome = explanation.get("outcome", "unknown")
                    outcomes[outcome] = outcomes.get(outcome, 0) + 1
                value["explanations_summary"] = {
                    "count": len(explanations), "outcomes": outcomes,
                    "complete_evidence": result[name + "_evidence"],
                }
            result[name] = value
    if daemon.poll() is not None or not endpoint.probe(daemon):
        raise RuntimeError("owned daemon changed during request; replacement left untouched")
    if result["exit"] != 0:
        raise RuntimeError(f"{mode} compiler failed: {result['exit']}")
    return result


def check_outputs(retained, fresh, manifest):
    outputs = {}
    for extension in ("dmb", "rsc"):
        name = manifest.with_suffix("." + extension).name
        hashes = [sha(directory / "artifacts" / name) for directory in (retained, fresh)]
        outputs[extension] = dict(zip(("retained", "fresh"), hashes))
        if hashes[0] != hashes[1]:
            raise RuntimeError(f"fresh native {extension} oracle mismatch")
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--build-receipt", help="optional successful-build receipt pinned to exact executable SHA")
    parser.add_argument("--inspector", required=True, help="frozen dmb-inspect structural comparator")
    parser.add_argument("--byond-dmb", default=str(DEFAULT / "frozen/pairs/byond/world.dmb"))
    parser.add_argument("--byond-pin", default=str(DEFAULT / "byond-structural-pin.json"))
    parser.add_argument("--source-snapshot", default=str(DEFAULT / "r6-source-snapshot.json"))
    parser.add_argument("--input-closure", default=str(DEFAULT / "input-closure.json"))
    parser.add_argument("--source", default=str(DEFAULT / "frozen/source"))
    parser.add_argument("--scenarios", default=str(DEFAULT / "r6-cold-scenarios.json"))
    parser.add_argument("--project", help="relative manifest override")
    parser.add_argument("--template", help="explicit engine-template override")
    parser.add_argument("--edits", required=True,
                        help='JSON ordered list: {kind:"body"|"structural",path,before,after}')
    parser.add_argument("--workers", type=int, choices=(2, 8), default=2)
    parser.add_argument("--output-root", default="E:/dq-cache/dmb-native-iterations")
    parser.add_argument("--overall-seconds", type=int, default=1800)
    parser.add_argument("--minimum-free-gib", type=int, default=16,
                        help="E: headroom floor before isolation/children (default 16 GiB; no reservation)")
    parser.add_argument("--require-owned-daemon", action="store_true",
                        help="opt in only for binaries implementing DMB_DAEMON_AUTOSTART=0")
    parser.add_argument("--worktree-sources", help="JSON array of exactly six distinct real E: Git worktree roots")
    parser.add_argument("--one-shot-requests", action="store_true",
                        help="six concurrent cache-enabled one-shot builds; retained daemon state is not exercised")
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("owned daemon lifecycle requires Windows")
    if not 1 <= args.overall_seconds <= 3600:
        parser.error("overall deadline must be between 1 and 3600 seconds")
    if args.minimum_free_gib < 1:
        parser.error("minimum free space must be at least 1 GiB")
    output_parent = safe_e(args.output_root)
    if not output_parent.is_relative_to(Path("E:/dq-cache")):
        raise ValueError("output must be beneath E:/dq-cache")
    # Previous real cohorts exhausted E: at roughly 10 GB free. Keep a
    # configurable 16 GiB floor, outside all measured timers and before scans.
    headroom = disk_preflight(output_parent, args.minimum_free_gib * 1024 ** 3)
    if headroom["status"] != "passed":
        root = output_parent / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
        root.mkdir(parents=True)
        failure = {"schema_version": 1, "status": "failed", "root": str(root),
                   "failure_stage": "disk_preflight", "disk_preflight": headroom,
                   "error": "insufficient observed E: headroom; no compiler child or source isolation started",
                   "rows": []}
        (root / "receipt.json").write_text(json.dumps(failure, indent=2), encoding="utf-8")
        print(json.dumps({"receipt": str(root / "receipt.json"), "status": "failed"}))
        return 1
    executable = safe_e(args.compiler)
    regular(executable)
    build_proof = build_receipt.authenticate(safe_e(args.build_receipt), executable, sha) if args.build_receipt else None
    sources = [safe_e(args.source)]
    if args.worktree_sources:
        sources = [safe_e(path) for path in json.loads(Path(args.worktree_sources).read_text(encoding="utf-8"))]
        if len(sources) != 6 or len({str(path).casefold() for path in sources}) != 6:
            raise ValueError("requires six distinct worktree roots")
        for source in sources:
            if not (source / ".git").exists():
                raise ValueError(f"source lacks Git worktree marker: {source}")
    try:
        worktree_proof = worktree_authority.authenticate(sources) if args.worktree_sources else None
    except Exception as error:
        print(json.dumps({"schema": "dm-six-worktree-authority-v1", "status": "failed", "error": str(error)}))
        raise

    scenario_path = safe_e(args.scenarios)
    scenario = json.loads(scenario_path.read_text())[0]
    arguments = list(scenario["arguments"])
    # Only semantic configuration from the scenario, never output/routing controls.
    semantic = []
    template = None
    index = 0
    while index < len(arguments):
        item = arguments[index]
        if item == "--engine-template":
            template = arguments[index + 1]
            index += 2
        elif item == "--bootstrap-catalog" or item.startswith("-D"):
            semantic.append(item)
            index += 1
        elif item == "--no-daemon":
            index += 1
        else:
            raise ValueError(f"unsupported default scenario argument: {item}")
    template = safe_e(args.template or template)
    regular(template)
    semantic += ["--engine-template", str(template)]
    if args.one_shot_requests:
        semantic.append("--no-daemon")
    edits = json.loads(Path(args.edits).read_text(encoding="utf-8"))
    if not edits or len(edits) > 8 or any(edit["kind"] not in ("body", "structural") for edit in edits):
        raise ValueError("requires 1..8 explicit body/structural edits")
    detached = set()
    for edit in edits:
        path = Path(edit["path"])
        if path.is_absolute() or path.drive or ".." in path.parts:
            raise ValueError("edit path must be a contained relative source path")
        detached.add(path)
    manifest = Path(args.project or scenario["project"])
    if manifest.is_absolute() or manifest.drive or ".." in manifest.parts:
        raise ValueError("manifest must be relative")
    configuration, _ = semantic_configuration.command_configuration(str(manifest), semantic, sha)
    structural = Comparison(args.inspector, args.byond_dmb, args.byond_pin, configuration, sha, safe_e)
    source_snapshot_path = safe_e(args.source_snapshot)
    source_snapshot = json.loads(source_snapshot_path.read_text(encoding="utf-8"))
    closure_sha = authenticate_source_snapshot(source_snapshot, safe_e(args.input_closure), structural.pin, sha)
    root = output_parent / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
    root.mkdir(parents=True)
    receipt = {"schema_version": 1, "status": "running", "root": str(root),
               "disk_preflight": headroom,
               "compiler_sha256": sha(executable), "template_sha256": sha(template),
               "build_provenance": build_proof,
               "scenario_sha256": sha(scenario_path), "workers": args.workers,
               "require_owned_daemon": args.require_owned_daemon,
               "worktree_authority": worktree_proof,
               "source_roots": [str(source) for source in sources], "session_count": len(sources),
               "request_mode": "one-shot" if args.one_shot_requests else "daemon",
               "isolated_compiler_cache": str(root / "compiler-cache"),
               "source_snapshot_sha256": sha(source_snapshot_path),
               "input_closure_sha256": closure_sha,
               "byond_pin_sha256": structural.pin_sha, "byond_dmb_sha256": structural.expected_sha,
               "inspector_sha256": structural.inspector_sha,
               "scope": "real-source daemon iteration wall telemetry plus fresh native DMB/RSC byte oracle; not runtime or r6 acceptance",
               "rows": []}
    endpoint = Endpoint()
    daemon = None
    started = time.monotonic()
    deadline = started + args.overall_seconds
    try:
        endpoint.probe()
        projects = [root / ("project" if len(sources) == 1 else f"project-{index}") for index in range(len(sources))]
        receipt["isolated_source_files"] = []
        for source, project in zip(sources, projects):
            receipt["isolated_source_files"].append(isolate(source, project, detached))
            regular(project / manifest)
        baseline_sources = [source_matches(project, source_snapshot, sha) for project in projects]
        receipt["source_identical_to_captured_baseline"] = baseline_sources
        receipt["private_edit_paths"] = [str(path) for path in sorted(detached)]
        cache_directory = root / "compiler-cache"
        daemon_environment = os.environ.copy()
        daemon_environment["DMB_CACHE_DIR"] = str(cache_directory)
        with (root / "daemon.stdout").open("xb") as out, (root / "daemon.stderr").open("xb") as err:
            daemon = subprocess.Popen([str(executable), "--serve-daemon"], stdout=out, stderr=err, env=daemon_environment,
                                      creationflags=subprocess.CREATE_NO_WINDOW)
        receipt["owned_daemon_pid"] = daemon.pid
        ready_deadline = min(deadline, time.monotonic() + 20)
        while not endpoint.probe(daemon):
            if daemon.poll() is not None or time.monotonic() >= ready_deadline:
                raise RuntimeError("owned daemon did not become ready within 20 seconds")
            time.sleep(0.05)
        # Initial population, unchanged request, then each real ordered edit.
        edit_history = EditHistory(len(projects))
        steps = [("initial", None), ("unchanged", None)] + [(edit["kind"], edit) for edit in edits]
        for ordinal, (kind, edit) in enumerate(steps):
            if daemon.poll() is not None or not endpoint.probe(daemon):
                raise RuntimeError("owned daemon missing before request")
            row = {"ordinal": ordinal, "kind": kind, "sessions": []}
            for index, project in enumerate(projects):
                session = {"index": index, "project": str(project / manifest)}
                if edit is not None:
                    session["edit"] = replace_edit(project, edit)
                    edit_history.append(index, session["edit"])
                row["sessions"].append(session)
            row_started = time.monotonic()
            def destination(index, mode):
                # Same destination across revisions is required for unchanged
                # output/session shortcut measurement.
                return root / mode if len(projects) == 1 else root / f"session-{index}" / mode
            def logs(index, mode):
                return root / str(ordinal) / mode if len(projects) == 1 else root / str(ordinal) / f"session-{index}" / mode
            row["host_context_before_retained"] = host_context.sample()
            burst_started = time.monotonic()
            with concurrent.futures.ThreadPoolExecutor(max_workers=len(projects)) as executor:
                futures = [executor.submit(compile_one, executable, project, manifest,
                    args.workers, semantic, destination(index, "retained"), logs(index, "retained"),
                    "retained", deadline, args.require_owned_daemon, endpoint, daemon, cache_directory)
                    for index, project in enumerate(projects)]
                failures = []
                for session, future in zip(row["sessions"], futures):
                    try:
                        session["retained"] = future.result()
                    except Exception as error:
                        failures.append(str(error))
                if failures:
                    raise RuntimeError("; ".join(failures))
            row["retained_burst_wall_s"] = time.monotonic() - burst_started
            row["host_context_after_retained"] = host_context.sample()
            # Fresh oracle processes never compete with retained measured work.
            for index, (project, session) in enumerate(zip(projects, row["sessions"])):
                session["host_context_before_fresh"] = host_context.sample()
                session["fresh"] = compile_one(executable, project, manifest, args.workers,
                    semantic, destination(index, "fresh"), logs(index, "fresh"), "fresh",
                    deadline, False, endpoint, daemon, cache_directory)
                session["host_context_after_fresh"] = host_context.sample()
                session["output_hashes"] = check_outputs(destination(index, "retained"), destination(index, "fresh"), manifest)
                session["fresh_native_byte_oracle"] = True
                source_context = {"snapshot_manifest_sha256": receipt["source_snapshot_sha256"],
                    "manifest_sha256": sha(project / manifest),
                    "native_pair": session["output_hashes"],
                    "edits": edit_history.snapshot(index),
                    "configuration_sha256": structural.configuration_sha}
                session["BYOND_structural"] = structural.compare(
                    destination(index, "retained") / "artifacts" / manifest.with_suffix(".dmb").name,
                    root / str(ordinal) / f"session-{index}" / "structural",
                    source_context, baseline_sources[index] and ordinal < 2,
                    run_child, deadline)
            if len(projects) == 1:
                row.update({key: row["sessions"][0][key] for key in ("retained", "fresh", "output_hashes")})
                if "edit" in row["sessions"][0]:
                    row["edit"] = row["sessions"][0]["edit"]
            row["end_to_end_s"] = time.monotonic() - row_started
            row["fresh_native_byte_oracle"] = True
            receipt["rows"].append(row)
            (root / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
        receipt["status"] = "passed"
        receipt["BYOND_baseline_gate"] = "passed" if all(
            session["BYOND_structural"]["baseline_admission"] == "passed"
            for row in receipt["rows"][:2] for session in row["sessions"]) else "open"
    except Exception as error:
        receipt["status"] = "failed"
        receipt["error"] = str(error)
    finally:
        if daemon is not None:
            receipt["daemon_cleanup"] = terminate_owned(daemon)
        receipt["total_end_to_end_s"] = time.monotonic() - started
        (root / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
        print(json.dumps({"receipt": str(root / "receipt.json"), "status": receipt["status"]}))
    return 0 if receipt["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
