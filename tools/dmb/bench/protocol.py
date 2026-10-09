"""Revision-6 cohort orchestration; no compiler/runtime building occurs here."""
import hashlib
import importlib.util
import json
import os
import ntpath
from pathlib import Path
import shutil
import stat
import time

_config_spec = importlib.util.spec_from_file_location("dmb_bench_configuration", Path(__file__).with_name("semantic_configuration.py"))
if _config_spec is None or _config_spec.loader is None:
    raise ImportError("cannot load semantic configuration gate")
configuration_gate = importlib.util.module_from_spec(_config_spec)
_config_spec.loader.exec_module(configuration_gate)

_evidence_spec = importlib.util.spec_from_file_location("dmb_structural_evidence", Path(__file__).with_name("structural_evidence.py"))
if _evidence_spec is None or _evidence_spec.loader is None:
    raise ImportError("cannot load structural evidence")
structural_evidence = importlib.util.module_from_spec(_evidence_spec)
_evidence_spec.loader.exec_module(structural_evidence)


_cached_spec = importlib.util.spec_from_file_location("dmb_cached_scenarios", Path(__file__).with_name("cached_scenarios.py"))
if _cached_spec is None or _cached_spec.loader is None:
    raise ImportError("cannot load cached scenario protocol")
cached_scenarios = importlib.util.module_from_spec(_cached_spec)
_cached_spec.loader.exec_module(cached_scenarios)

MARKER = ".dmb-benchmark-owned.json"
MIN_FREE = 25 * 1024**3
STRUCTURAL_CATEGORIES = frozenset(("type_set", "type_headers", "variable_defaults", "procedure_table", "procedure_flags", "globals", "strings_by_use", "bytecode", "other"))


def write(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False), encoding="utf-8")


def require_e(path):
    original = path.absolute()
    for component in (original, *original.parents):
        if component.exists() and (component.is_symlink()
                or getattr(component.lstat(), "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0)):
            raise ValueError("benchmark ownership refuses reparse-point ancestors: " + str(component))
    path = original.resolve()
    if path.drive.lower() != "e:" or path == Path("E:/") or path.is_symlink():
        raise ValueError("benchmark-owned artifacts must be contained on E: " + str(path))
    return path


def free_space(path, floor):
    probe = path.resolve()
    while not probe.exists():
        probe = probe.parent
    free = shutil.disk_usage(probe).free
    if free < max(MIN_FREE, floor):
        raise ValueError("benchmark preflight: less than 25 GiB/requested free space on " + str(probe))
    return free


def owned_directory(path, owner):
    path = require_e(path)
    path.mkdir(parents=True, exist_ok=False)
    write(path / MARKER, {"schema": 1, "owner": str(owner.resolve()), "path": str(path)})
    return path


def validate_owned(path, owner, protected):
    path = require_e(path)
    owner = owner.resolve()
    if not path.is_relative_to(owner) or path == owner:
        raise ValueError("cleanup escaped its owning directory: " + str(path))
    if any(path == pin or path in pin.parents or pin in path.parents for pin in protected):
        raise ValueError("cleanup intersects protected input/reference: " + str(path))
    marker = json.loads((path / MARKER).read_text(encoding="utf-8"))
    if marker != {"schema": 1, "owner": str(owner), "path": str(path)}:
        raise ValueError("cleanup ownership marker mismatch")
    return path


def prepare_output_cleanup(paths, owner, protected):
    roots = [validate_owned(path, owner, protected) for path in paths if path.exists()]
    spec = importlib.util.spec_from_file_location("dmb_bench_closed_links", Path(__file__).with_name("closed_links.py"))
    if spec is None or spec.loader is None:
        raise ImportError("cannot load closed owned link validation")
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    return helper.prepare_owned_readonly(roots, protected)


def remove_owned(path, owner, protected):
    path = require_e(path)
    owner = owner.resolve()
    if not path.is_relative_to(owner) or path == owner:
        raise ValueError("cleanup escaped its owning directory: " + str(path))
    if any(path == pin or path in pin.parents or pin in path.parents for pin in protected):
        raise ValueError("cleanup intersects pinned input/reference: " + str(path))
    marker = json.loads((path / MARKER).read_text(encoding="utf-8"))
    if marker != {"schema": 1, "owner": str(owner), "path": str(path)}:
        raise ValueError("cleanup ownership marker mismatch")
    # Never follow a reparse point introduced inside an owned artifact tree.
    for directory, folders, files in os.walk(path, followlinks=False):
        for name in folders + files:
            item = Path(directory) / name
            if (item.is_symlink() or (hasattr(item, "is_junction") and item.is_junction())
                    or getattr(item.lstat(), "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0)):
                raise ValueError("cleanup refuses an artifact reparse point: " + str(item))
            if not item.resolve().is_relative_to(path):
                raise ValueError("cleanup descendant escaped artifact tree")
    # Windows attributes belong to the inode and can be shared by hardlinks to
    # pinned/global resources. Refuse cleanup rather than chmod shared content.
    for directory, _, files in os.walk(path, followlinks=False):
        for name in files:
            item = Path(directory) / name
            if os.name == "nt" and not item.stat().st_mode & stat.S_IWRITE:
                return {"status": "preserved", "reason": "read-only link; shared attributes unchanged", "path": str(item)}
    try:
        shutil.rmtree(path)
    except OSError as error:
        return {"status": "incomplete", "reason": str(error), "path": str(path)}
    return {"status": "removed", "path": str(path)}



def authenticate_replay_closure(h, root, scenario, journal, byond_pin):
    """Admit only harness-enforced cold replay; payload verification stays in Rust."""
    if journal is None:
        return {"mode": "full_physical_source_sha256", "pinned": {}}
    if scenario["name"] not in {"cold", "cold-body-edit", *cached_scenarios.SEQUENCE} or scenario.get("edits"):
        raise ValueError("journal-only closure requires authenticated replay without live edits")
    journal = Path(journal).resolve()
    index_path, checksum_path = journal / "index.json", journal / "index.hash"
    digest = h.sha(index_path)
    if byond_pin.get("snapshot_id") != digest:
        raise ValueError("BYOND snapshot does not match captured journal before compilation")
    index = json.loads(index_path.read_text(encoding="utf-8"))
    manifest = h.source_path(root, scenario["project"])
    normal = h.normal_windows_path
    def lexical_identity(path):
        value = str(path)
        if value.startswith("\\\\?\\UNC\\"):
            value = "\\\\" + value[8:]
        elif value.startswith("\\\\?\\"):
            value = value[4:]
        return ntpath.normcase(ntpath.normpath(value))
    matching = [path for path in index["files"] if lexical_identity(path) == lexical_identity(manifest)]
    if len(matching) != 1 or normal(matching[0]) != normal(manifest):
        raise ValueError("captured journal must contain exact canonical project manifest")
    if normal(root) != normal(manifest.parent):
        # Nested project manifests are allowed only within this same canonical root.
        if not normal(manifest).is_relative_to(normal(root)):
            raise ValueError("captured project topology escaped logical root")
    return {"mode": "authenticated_captured_journal_no_live_fallback",
            "logical_root": str(root), "canonical_manifest": str(manifest),
            "captured_manifest": matching[0], "snapshot_id": digest,
            "pinned": {index_path: digest, checksum_path: h.sha(checksum_path)},
            "timing_scope": "unmeasured_validation_not_compiler_speedup"}


def check_source_closure(h, root, expected, scenarios):
    if any(scenario["_closure_validation"]["mode"] == "full_physical_source_sha256" for scenario in scenarios):
        h.check_snapshot(root, expected)
    for scenario in scenarios:
        closure = scenario["_closure_validation"]
        if closure["mode"] != "full_physical_source_sha256":
            if str(h.source_path(root, scenario["project"])) != closure["canonical_manifest"]:
                raise ValueError("captured canonical project topology changed")
            if any(h.sha(path) != digest for path, digest in closure["pinned"].items()):
                raise ValueError("captured journal identity changed")


def warm_inputs(h, root, expected, journal):
    start = time.monotonic()
    if journal:
        journal = journal.resolve()
        index = json.loads((journal / "index.json").read_text(encoding="utf-8"))
        hashes = sorted({value[1] for value in index["files"].values()})
        paths = [journal / "index.json", journal / "index.hash"] + [
            journal / "payloads" / format(value, "032x") for value in hashes]
    else:
        paths = [h.source_path(root, relative) for relative in expected]
    buffer = bytearray(1024 * 1024)
    total = 0
    for path in paths:
        with path.open("rb") as stream:
            while size := stream.readinto(buffer):
                total += size
    return {"kind": "unmeasured_full_input_warmup", "files": len(paths),
            "bytes_read": total, "wall_s": time.monotonic() - start,
            "input_mode": "captured_replay" if journal else "private_source_snapshot"}


def binary(h, path, metadata, mode):
    path = path.resolve()
    digest = h.sha(path)
    value = json.loads(metadata.read_text(encoding="utf-8"))
    if value.get("compiler_sha256") != digest or value.get("measurement_revision") != 6:
        raise ValueError("compiler metadata must pin exact binary and measurement revision6")
    required = {"profile": "release", "lto": "thin", "debug": "line-tables-only",
                "codegen_units": 16, "allocator": "mimalloc",
                "allocation_counting": mode == "counting"}
    for key, expected in required.items():
        if value.get(key) != expected:
            raise ValueError("unsupported compiler profile metadata " + key)
    for key in ("compiler_commit", "source_archive_sha256"):
        if not isinstance(value.get(key), str) or not value[key]:
            raise ValueError("missing compiler provenance " + key)
    return {"path": path, "sha256": digest, "metadata": value,
            "metadata_path": metadata.resolve(), "metadata_sha256": h.sha(metadata)}


def valid_case_signatures(signatures):
    if not isinstance(signatures, dict):
        return False
    return all(isinstance(category, str) and isinstance(cases, list)
               and all(isinstance(case, str) and len(case) == 32
                       and all(character in "0123456789abcdef" for character in case) for case in cases)
               and cases == sorted(set(cases))
               for category, cases in signatures.items())


def exact_structural_evidence(value):
    if (value.get("schema_version") != 1 or value.get("tool_complete") is not True or value.get("traversal_complete") is not True
            or value.get("signature_algorithm") != "md5-length-framed-v1"):
        return False
    for signatures, counts, field in (("category_signatures", "categories", "discrepancy_count"),
                                      ("uncovered_signatures", "uncovered", "occurrence_count")):
        cases, roster = value.get(signatures), value.get(counts)
        if not valid_case_signatures(cases) or not isinstance(roster, dict) or set(cases) != set(roster):
            return False
        if counts == "categories" and set(roster) != STRUCTURAL_CATEGORIES:
            return False
        if any(not isinstance(entry, dict) or type(entry.get(field)) is not int or entry[field] < 0
               or (entry[field] > 0 and not cases[kind]) for kind, entry in roster.items()):
            return False
    return True


def structural_no_regression(previous, current):
    if (previous.get("snapshot_id") != current.get("snapshot_id")
            or previous.get("semantic_configuration_sha256") != current.get("semantic_configuration_sha256")
            or not exact_structural_evidence(previous) or not exact_structural_evidence(current)):
        return "not_evaluable"
    for signatures, counts, field in (("category_signatures", "categories", "discrepancy_count"),
                                      ("uncovered_signatures", "uncovered", "occurrence_count")):
        for kind, cases in current[signatures].items():
            if (not set(cases).issubset(previous[signatures].get(kind, []))
                    or current[counts][kind][field] > previous[counts].get(kind, {}).get(field, 0)):
                return "failed"
    return "passed"


def structural(h, args, scenario, manifest, run_dir, snapshot_id, env):
    baseline = Path(scenario.get("byond_dmb", args.byond_dmb)).resolve()
    baseline_snapshot = Path(scenario.get("byond_snapshot", args.byond_snapshot)).resolve()
    report = run_dir / "structural-diff.json"
    pin = json.loads(baseline_snapshot.read_text(encoding="utf-8"))
    configuration = scenario.get("_semantic_configuration")
    if configuration is None or pin.get("semantic_configuration") != configuration:
        return {"complete": False, "tool_complete": False, "error": "BYOND semantic configuration is not admitted"}
    if pin.get("snapshot_id") != snapshot_id or pin.get("dmb_sha256") != h.sha(baseline):
        return {"complete": False, "error": "BYOND baseline does not pin this exact captured snapshot"}
    command = [str(args.inspector.resolve()), "structural-diff", str(baseline), str(manifest),
               str(report), snapshot_id]
    code, wall, timeout = h.run(command, run_dir, run_dir / "structural", args.watchdog, env)
    if code or timeout or not report.exists():
        return {"complete": False, "error": "structural-diff invocation failed", "exit_code": code,
                "watchdog": timeout, "wall_s": wall}
    value = json.loads(report.read_text(encoding="utf-8"))
    if value.get("schema_version") != 1 or not isinstance(value.get("categories"), dict):
        return {"complete": False, "error": "invalid structural report schema"}
    if value.get("snapshot_id") != snapshot_id or value.get("traversal_complete") is not True:
        value["tool_complete"] = False
        value["complete"] = False
        value["error"] = "structural diff snapshot/traversal contract failed"
    value["semantic_configuration_sha256"] = configuration_gate.digest(configuration)
    value["parity_acceptance"] = "passed" if value.get("complete") is True and value.get("unexplained_discrepancies") == 0 else "failed"
    value["structural_measurement_admission"] = "passed" if value.get("tool_complete") is True else "failed"
    value["native_pair_sha256"] = {extension: h.sha(manifest.with_suffix(extension))
                                   for extension in (".dmb", ".rsc") if manifest.with_suffix(extension).exists()}
    baseline_path = scenario.get("structural_baseline", args.structural_baseline)
    value["no_regression"] = "not_evaluable"
    previous = None
    if baseline_path:
        previous = structural_evidence.load(json.loads(Path(baseline_path).read_text(encoding="utf-8")), snapshot_id, value["semantic_configuration_sha256"])
    elif args.establish_structural_baseline:
        baselines = getattr(args, "established_baselines", None)
        if baselines is None:
            baselines = args.established_baselines = {}
        baseline_key = (snapshot_id, value["semantic_configuration_sha256"])
        descriptor = baselines.get(baseline_key)
        previous = structural_evidence.load(descriptor, *baseline_key) if descriptor else None
        if previous is None and exact_structural_evidence(value):
            descriptor = dict(value, report=str(report), report_sha256=h.sha(report))
            baselines[baseline_key] = structural_evidence.compact(descriptor)
            value["no_regression"] = "baseline_established"
    if previous is not None:
        value["no_regression"] = structural_no_regression(previous, value)
    native_pin = scenario.get("native_baseline", getattr(args, "native_baseline", None))
    if value["no_regression"] != "passed" and native_pin and value.get("tool_complete") is True:
        native = json.loads(Path(native_pin).read_text(encoding="utf-8"))
        if (native.get("snapshot_id") == snapshot_id
                and native.get("semantic_configuration_sha256") == value["semantic_configuration_sha256"]
                and native.get("pair_sha256") == value["native_pair_sha256"]
                and set(value["native_pair_sha256"]) == {".dmb", ".rsc"}):
            value["no_regression"] = "passed"
            value["no_regression_basis"] = "same_snapshot_pinned_native_pair_byte_identity"
    value["report"] = str(report)
    value["report_sha256"] = h.sha(report)
    admission = run_dir / "structural-admission.json"
    summary = structural_evidence.compact(value)
    write(admission, summary)
    summary["admission_report"] = str(admission)
    summary["admission_report_sha256"] = h.sha(admission)
    return summary


def retain_small_evidence(h, run_dir, row):
    # Preserve the complete oracle diagnostics and profile/folded reports before
    # deleting only disposable compiler outputs. Failed runs remain untouched.
    artifacts = run_dir / "artifacts"
    small = run_dir / "oracle-evidence"
    small.mkdir(exist_ok=True)
    if artifacts.exists():
        for path in artifacts.rglob("*"):
            if path.is_file() and (path.name.endswith((".log", ".report.json", ".folded"))
                                   or path.name in ("receipt.json", "result.json")):
                destination = small / path.relative_to(artifacts)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, destination)
    write(run_dir / "output-hashes.json", row["pair_sha256"])


def cleanup_verified_outputs(h, run, row, protected):
    """Native-fresh equality admits disposal; structural coverage is separate."""
    if row.get("oracle") != "passed" or row.get("structural_invocation_finished") is not True:
        return []
    bulky = [run / name for name in ("pair-store", "oracle-store", "artifacts", "oracle-artifacts")]
    for target in bulky:
        if target.exists():
            target = require_e(target)
            if any(target == pin or target in pin.parents or pin in target.parents for pin in protected):
                raise ValueError("cleanup intersects protected input/reference: " + str(target))
    retain_small_evidence(h, run, row)
    row["closed_link_cleanup"] = prepare_output_cleanup(bulky, run, protected)
    cleanup = [remove_owned(path, run, protected) for path in bulky if path.exists()]
    row["cleanup"] = cleanup
    row["output_retention"] = "small_evidence_only" if all(item["status"] == "removed" for item in cleanup) else "cleanup_incomplete"
    write(run / "receipt.json", row)
    return cleanup


def cleanup_completed_round(round_cache, cache, rows, expected_count, protected):
    """Only a complete native-fresh verified round admits its owned cache."""
    if (len(rows) != expected_count or expected_count <= 0
            or any(row.get("oracle") != "passed" or row.get("structural_invocation_finished") is not True for row in rows)):
        return None
    preparation = prepare_output_cleanup([round_cache], cache, protected)
    cleanup = remove_owned(round_cache, cache, protected)
    return {**cleanup, "closed_link_cleanup": preparation}


def trim_complete_evidence(h, output, protected):
    """Keep three complete oracle-valid trace runs, independent of semantic coverage."""
    output = require_e(output)
    candidates = []
    for cohort in output.parent.iterdir():
        marker_path = cohort / MARKER
        if not cohort.is_dir() or not marker_path.is_file():
            continue
        try:
            cohort = require_e(cohort)
            marker = json.loads(marker_path.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            continue
        if marker != {"schema": 1, "owner": str(output.parent.resolve()), "path": str(cohort)}:
            continue
        for run in cohort.iterdir():
            receipt = run / "receipt.json"
            trace = run / "cold.trace.json"
            if not receipt.is_file():
                continue
            try:
                run = require_e(run)
                row = json.loads(receipt.read_text(encoding="utf-8"))
                run_marker = json.loads((run / MARKER).read_text(encoding="utf-8"))
            except (ValueError, OSError):
                continue
            if run_marker != {"schema": 1, "owner": str(cohort), "path": str(run)}:
                continue
            if (row.get("measurement_revision") == 6 and row.get("oracle") == "passed"
                    and row.get("structural_invocation_finished") is True):
                candidates.append((trace.stat().st_mtime_ns if trace.is_file() else 0, run, trace, row))
    limitations = []
    traced = sorted((entry for entry in candidates if entry[2].is_file()), key=lambda entry: entry[0])
    retained = {entry[1] for entry in traced[-3:]}
    for _, run, trace, row in candidates:
        if run in retained:
            continue
        # Validate every deletion target BEFORE preserving/copying or deleting
        # anything. A pinned descendant protects its entire ancestor artifact.
        bulky = [run / name for name in ("pair-store", "oracle-store", "artifacts", "oracle-artifacts")]
        if not trace.exists() and not any(path.exists() for path in bulky):
            continue
        targets = [path for path in (trace, *bulky) if path.exists()]
        for target in targets:
            target = require_e(target)
            if any(target == pin or target in pin.parents or pin in target.parents for pin in protected):
                raise ValueError("retention intersects protected input/reference: " + str(target))
        retain_small_evidence(h, run, row)
        row["closed_link_cleanup"] = prepare_output_cleanup(bulky, run, protected)
        previous_cleanup = row.get("cleanup", [])
        if previous_cleanup:
            row.setdefault("cleanup_history", []).append(previous_cleanup)
        cleanup = [remove_owned(path, run, protected) for path in bulky if path.exists()]
        if not trace.exists():
            pass
        elif os.name == "nt" and not trace.stat().st_mode & stat.S_IWRITE:
            cleanup.append({"status": "preserved", "path": str(trace),
                            "reason": "read-only link; shared attributes unchanged"})
        else:
            try:
                trace.unlink()
                cleanup.append({"status": "removed", "path": str(trace)})
            except OSError as error:
                cleanup.append({"status": "incomplete", "path": str(trace), "reason": str(error)})
        row["cleanup"] = cleanup
        row["retention"] = "small_evidence_only" if all(item["status"] == "removed" for item in cleanup) else "cleanup_incomplete"
        if row["retention"] == "cleanup_incomplete":
            limitations.append({"directory": str(run), "cleanup": cleanup})
        write(run / "receipt.json", row)
    return {"complete_run_limit": 3, "cleanup_limitations": limitations}


def profile_measurement(report, child_wall):
    """Keep the measured child lifetime distinct from the profiler's cutoff."""
    value = {key: item for key, item in report.items() if key != "schema"}
    value.update(profile_wall_s=report.get("wall_s"),
                 profile_wall_scope=report.get("wall_scope"),
                 child_wall_s=child_wall, wall_s=child_wall,
                 wall_scope="harness_child_launch_to_reap")
    return value


def protocol_quality(h, row, stage_map):
    errors = []
    if not isinstance(stage_map, dict) or set(stage_map) != set(h.STAGE_BUDGETS):
        return ["all explicit CPU budget domains must be mapped"]
    names = []
    for entries in stage_map.values():
        if not isinstance(entries, list) or not entries or any(not isinstance(name, str) for name in entries):
            return ["nonempty explicit stage lists required"]
        names.extend(entries)
    if len(names) != len(set(names)) or set(names) != set(row.get("critical_path_stages", [])):
        errors.append("stage mapping must cover the critical chain once")
    if row.get("binary_mode") == "acceptance" and row.get("allocation_counting") is not False:
        errors.append("acceptance binary must disable allocation counting")
    return errors


def comparison_stage_map_paths(args):
    # Self comparison runs the current binary twice. A supplied historical map
    # must not attach the previous topology to that same current executable.
    previous = args.stage_map if args.self_comparison else (
        getattr(args, "previous_stage_map", None) or args.stage_map)
    return {"A": previous, "B": args.stage_map}


def execute(h, args):
    root = args.project_root.resolve()
    output = require_e(args.output)
    cache = require_e(args.cache)
    previous = args.compiler if args.self_comparison else args.previous_compiler
    previous_metadata = args.profile_metadata if args.self_comparison else args.previous_profile_metadata
    if previous is None or previous_metadata is None:
        raise ValueError("provide previous frozen compiler metadata or --self-comparison")
    tools = {"A": binary(h, previous, previous_metadata, args.binary_mode),
             "B": binary(h, args.compiler, args.profile_metadata, args.binary_mode)}
    snapshot = json.loads(args.snapshot.read_text(encoding="utf-8"))
    expected = dict(snapshot["files"])
    scenarios = json.loads(args.scenarios.read_text(encoding="utf-8"))
    if not scenarios or len({value["name"] for value in scenarios}) != len(scenarios):
        raise ValueError("scenario names must be unique and nonempty")
    if any(value["name"] not in set(h.TARGETS) | {"cold-body-edit", *cached_scenarios.SEQUENCE} for value in scenarios):
        raise ValueError("unknown benchmark scenario")
    forbidden = {"--workers", "--trace", "--verify", "--record-inputs", "--replay-inputs",
                 "--artifact-directory", "--no-cache", "--output-store"}
    for scenario in scenarios:
        if any(str(arg).split("=", 1)[0] in forbidden for arg in scenario["arguments"]):
            raise ValueError("scenario overrides a harness-owned argument")
        configuration, engine_path = configuration_gate.command_configuration(scenario["project"], scenario["arguments"], h.sha)
        byond_pin_path = Path(scenario.get("byond_snapshot", args.byond_snapshot)).resolve()
        byond_pin = json.loads(byond_pin_path.read_text(encoding="utf-8-sig"))
        evidence = configuration_gate.authenticate_pin(byond_pin, configuration, h.sha)
        scenario["_semantic_configuration"] = configuration
        scenario["_configuration_evidence"] = evidence
        scenario["_engine_path"] = engine_path
        if scenario["name"] in {"cold-body-edit", *cached_scenarios.EDITED}:
            edit_spec = importlib.util.spec_from_file_location("dmb_edited_snapshot", Path(__file__).with_name("edited_snapshot.py"))
            edit_module = importlib.util.module_from_spec(edit_spec)
            edit_spec.loader.exec_module(edit_module)
            scenario["_edited_snapshot"] = edit_module.authenticate(h, scenario, args.input_journal, byond_pin)
            if h.sha(Path(scenario.get("byond_dmb", args.byond_dmb))) != byond_pin.get("dmb_sha256"):
                raise ValueError("edited BYOND output hash mismatch")
        elif scenario["name"] not in {"cold", *cached_scenarios.PARENT}:
            raise ValueError("revision6 initial cohort supports cold only; authenticated resident/edit warm-up protocol is not yet implemented")
        journal = scenario.get("input_journal", args.input_journal)
        scenario["_closure_validation"] = authenticate_replay_closure(h, root, scenario, journal, byond_pin)
        if args.input_journal and scenario.get("edits"):
            raise ValueError("captured replay edits require a separately pinned scenario journal")
    cached_scenarios.validate(scenarios, args.input_journal, args.worker_counts)
    free = free_space(output, args.min_free_bytes)
    free_space(cache, args.min_free_bytes)
    output = owned_directory(output, output.parent)
    cache.mkdir(parents=True, exist_ok=True)
    policy_path = Path(h.__file__).resolve().parent.parent / "diagnostic-measurements.json"
    policy = json.loads(policy_path.read_text(encoding="utf-8"))
    policy_hash = h.sha(policy_path)
    check_source_closure(h, root, expected, scenarios)
    initial_journal = scenarios[0].get("input_journal", args.input_journal)
    warmup = warm_inputs(h, root, expected, Path(initial_journal) if initial_journal else None)
    methodology = {Path(__file__).with_name(name).resolve(): h.sha(Path(__file__).with_name(name))
                   for name in ("dmb-bench.py", "protocol.py", "semantic_configuration.py",
                                "edited_snapshot.py", "cached_scenarios.py", "closed_links.py", "structural_evidence.py", "watchdog.py")}
    cohort = {"schema": 2, "measurement_revision": 6, "schedule": "ABABAB",
              "comparison": "self_noise_floor" if args.self_comparison else "previous_vs_new",
              "benchmark_methodology_sha256": {str(path): digest for path, digest in methodology.items()},
              "binary_mode": args.binary_mode, "free_bytes_before": free, "warmup": warmup,
              "compilers": {name: {key: str(value) if isinstance(value, Path) else value
                                     for key, value in tool.items()} for name, tool in tools.items()},
              "source_commit": snapshot["commit"], "snapshot_manifest_sha256": h.sha(args.snapshot),
              "source_closure_validation": {scenario["name"]: {key: value for key, value in scenario["_closure_validation"].items() if key != "pinned"} for scenario in scenarios},
              "semantic_configurations": {scenario["name"]: {
                  "configuration": scenario["_semantic_configuration"],
                  "sha256": configuration_gate.digest(scenario["_semantic_configuration"])} for scenario in scenarios}}
    write(output / "receipt.json", cohort)
    protected = {root, args.snapshot.resolve(), args.scenarios.resolve(), args.byond_dmb.resolve(), args.inspector.resolve(),
                 args.byond_snapshot.resolve(), *[tool["path"] for tool in tools.values()]}
    if args.input_journal:
        protected.add(args.input_journal.resolve())
    map_paths = comparison_stage_map_paths(args)
    stage_maps = {}
    map_provenance = {}
    for label, path in map_paths.items():
        stage_maps[label] = json.loads(path.read_text(encoding="utf-8-sig")) if path else {}
        map_provenance[label] = {"compiler_sha256": tools[label]["sha256"],
                                 "path": str(path.resolve()) if path else None,
                                 "sha256": h.sha(path) if path else None,
                                 "domains": stage_maps[label],
                                 "coverage_policy": "exact_declared_critical_chain_once"}
        if path:
            protected.add(path.resolve())
    cohort["stage_maps"] = map_provenance
    write(output / "receipt.json", cohort)
    if args.structural_baseline:
        protected.add(args.structural_baseline.resolve())
    if args.native_baseline:
        protected.add(args.native_baseline.resolve())
    for scenario in scenarios:
        if scenario.get("_edited_snapshot"):
            protected.update(scenario["_edited_snapshot"]["pinned"])
        protected.update(scenario["_closure_validation"]["pinned"])
        protected.add(scenario["_engine_path"])
        protected.update(scenario["_configuration_evidence"])
        for field in ("input_journal", "byond_dmb", "byond_snapshot", "structural_baseline", "native_baseline"):
            if scenario.get(field):
                protected.add(Path(scenario[field]).resolve())
    protected.update(methodology)
    protected.update(tool["metadata_path"] for tool in tools.values())
    inspector_digest = h.sha(args.inspector)
    pinned_files = {path: h.sha(path) for path in protected if path.is_file()}
    pinned_files.update(methodology)
    for scenario in scenarios:
        pinned_files.update(scenario.get("_edited_snapshot", {}).get("pinned", {}))
        pinned_files.update(scenario["_closure_validation"]["pinned"])

    originals = {}
    for scenario in scenarios:
        for edit in scenario.get("edits", []):
            path = h.source_path(root, edit["path"])
            if path.is_symlink() or path.stat().st_nlink > 1 or edit["path"] not in expected:
                raise ValueError("edited source must be a captured private file")
            originals[path] = path.read_bytes()
    collected = {(label, workers, scenario["name"]): [] for label in tools
                 for workers in args.worker_counts for scenario in scenarios}
    failed = False
    try:
        for workers in args.worker_counts:
            for repeat in range(3):
                for label in ("A", "B"):
                    tool = tools[label]
                    round_cache = owned_directory(cache / (output.name + f"-{workers}-{repeat+1}-{label}"), cache)
                    env = dict(os.environ, DMBD_VERIFY="1", DMB_CACHE_DIR=str(round_cache))
                    for path, value in originals.items():
                        path.write_bytes(value)
                    current = dict(expected)
                    for scenario in scenarios:
                        free_space(output, args.min_free_bytes)
                        for edit in scenario.get("edits", []):
                            path = h.source_path(root, edit["path"])
                            before, after = edit["before"].encode(), edit["after"].encode()
                            data = path.read_bytes()
                            if data.count(before) != 1:
                                raise ValueError("edit must match exactly once")
                            path.write_bytes(data.replace(before, after))
                            current[edit["path"]] = h.sha(path)
                        journal = Path(scenario.get("input_journal", args.input_journal)).resolve() if scenario.get("input_journal", args.input_journal) else None
                        snapshot_id = h.sha(journal / "index.json") if journal else hashlib.sha256(
                            json.dumps(current, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
                        if journal:
                            run_warmup = warm_inputs(h, root, current, journal)
                        else:
                            h.check_snapshot(root, current)
                            run_warmup = warm_inputs(h, root, current, None)
                        directory = owned_directory(output / f"{workers}-{repeat+1}-{label}-{scenario['name']}", output)
                        store = owned_directory(directory / "pair-store", directory)
                        artifacts = owned_directory(directory / "artifacts", directory)
                        oracle_store = owned_directory(directory / "oracle-store", directory)
                        source_manifest = h.source_path(root, scenario["project"])
                        # --artifact-directory publishes its conventional output
                        # paths here, not beside the frozen source manifest.
                        manifest = artifacts / source_manifest.name
                        common = [str(tool["path"]), "compile", scenario["project"], *scenario["arguments"],
                                  "--workers", str(workers), "--artifact-directory", str(artifacts)]
                        if journal:
                            common += ["--replay-inputs", str(journal)]
                        measured = common + ["--trace", str(directory / "cold.trace.json"), "--output-store", str(store)]
                        if scenario["name"] in ("cold", "cold-body-edit") or scenario.get("no_cache"):
                            measured.append("--no-cache")
                        if h.sha(tool["path"]) != tool["sha256"] or h.sha(tool["metadata_path"]) != tool["metadata_sha256"]:
                            raise ValueError("frozen compiler/profile changed")
                        if any(h.sha(path) != digest for path, digest in pinned_files.items()):
                            raise ValueError("pinned benchmark input/reference metadata changed")
                        start_context = h.process_context()
                        code, wall, timeout = h.run(measured, root, directory / "cold", args.watchdog, env)
                        end_context = h.process_context()
                        report_path = directory / "cold.trace.report.json"
                        report = h.profile(report_path)
                        hashes = {ext: h.sha(manifest.with_suffix(ext)) for ext in (".dmb", ".rsc")} if code == 0 and not timeout else {}
                        verified = False
                        diagnostics = None
                        diff = {"complete": False, "error": "compile failed before comparison"}
                        if hashes:
                            oracle_artifacts = owned_directory(directory / "oracle-artifacts", directory)
                            oracle_common = common.copy()
                            oracle_common[oracle_common.index("--artifact-directory") + 1] = str(oracle_artifacts)
                            oracle = oracle_common + ["--no-cache", "--output-store", str(oracle_store)]
                            ocode, _, otimed = h.run(oracle, root, directory / "fresh", args.watchdog, env)
                            diagnostics = h.normalized_diagnostics(directory / "cold.stderr.log", policy)
                            fresh_diag = h.normalized_diagnostics(directory / "fresh.stderr.log", policy)
                            stdout = h.normalized_diagnostics(directory / "cold.stdout.log", policy)
                            fresh_stdout = h.normalized_diagnostics(directory / "fresh.stdout.log", policy)
                            verified = ocode == 0 and not otimed and diagnostics == fresh_diag and stdout == fresh_stdout and all(
                                h.sha((oracle_artifacts / source_manifest.name).with_suffix(ext)) == digest for ext, digest in hashes.items())
                            write(directory / "diagnostics.json", {"measured": diagnostics, "fresh": fresh_diag,
                                "measured_stdout": stdout, "fresh_stdout": fresh_stdout, "matched": verified})
                            if verified:
                                diff = structural(h, args, scenario, manifest.with_suffix(".dmb"), directory, snapshot_id, env)
                        if journal:
                            if h.sha(journal / "index.json") != snapshot_id:
                                raise ValueError("captured journal changed during benchmark")
                        else:
                            h.check_snapshot(root, current)
                        if h.sha(tool["path"]) != tool["sha256"] or h.sha(policy_path) != policy_hash or h.sha(args.inspector) != inspector_digest:
                            raise ValueError("frozen compiler/diagnostic policy changed")
                        if any(h.sha(path) != digest for path, digest in pinned_files.items()):
                            raise ValueError("pinned benchmark input/reference metadata changed during run")
                        row = {"schema": h.SCHEMA, "kind": "run", "measurement_revision": 6,
                               "commit": snapshot["commit"], "compiler_sha256": tool["sha256"],
                               "compiler_metadata": tool["metadata"], "comparison_label": label,
                               "scenario": scenario["name"], "cache_protocol": scenario.get("_cache_protocol"), "workers": workers, "repeat": repeat+1,
                               "wall_s": wall, "exit_code": code, "status": "watchdog" if timeout else "verified" if verified else "failed",
                               "oracle": "passed" if verified else "not_passed", "snapshot_id": snapshot_id,
                               "source_closure_validation": {key: value for key, value in scenario["_closure_validation"].items() if key != "pinned"},
                               "snapshot_identity_scope": "captured_file_identity_only",
                               "semantic_configuration": scenario["_semantic_configuration"],
                               "semantic_configuration_sha256": configuration_gate.digest(scenario["_semantic_configuration"]),
                               "structural_invocation_finished": verified,
                               "pair_sha256": hashes, "diagnostics": diagnostics, "structural_diff": diff,
                               "command": measured, "trace": str(directory / "cold.trace.json"),
                               "profile_report": str(report_path), "competing_processes_start": start_context,
                               "competing_processes_end": end_context, "binary_mode": args.binary_mode,
                               "watchdog_seconds": args.watchdog, "artifact_directory": str(directory),
                               "unmeasured_warmup": run_warmup,
                               "source_edit_provenance": scenario.get("_edited_snapshot", {}).get("provenance"),
                               **profile_measurement(report, wall)}
                        row["stage_map"] = map_provenance[label]
                        row["allocation_counting"] = report.get("allocation_counting", False)
                        if row["allocation_counting"] != (args.binary_mode == "counting"):
                            row["profile_error"] = "binary allocation mode disagrees with pinned profile metadata"
                        write(directory / "receipt.json", row)
                        collected[(label, workers, scenario["name"])].append(row)
                        row["measurement_errors"] = h.cpu_quality(row) + protocol_quality(h, row, stage_maps[label])
                        row["measurement_admission"] = "passed" if verified and not row["measurement_errors"] and diff.get("structural_measurement_admission") == "passed" else "failed"
                        passed = row["measurement_admission"] == "passed" and diff.get("no_regression") in ("passed", "baseline_established")
                        row["phase0_admission"] = "passed" if passed else "failed"
                        if scenario["name"] in cached_scenarios.SEQUENCE:
                            row["performance_admission"] = "not_admitted_diagnostic_disk_cache_trace"
                            row["cache_sequence_admission"] = "passed" if passed else "failed"

                        write(directory / "receipt.json", row)
                        h.append(args.results, row)
                        failed |= not passed
                        if verified:
                            cleanup_verified_outputs(h, directory, row, protected)
                            retention = trim_complete_evidence(h, output, protected)
                            write(output / "retention.json", retention)
                        if scenario["name"] in cached_scenarios.SEQUENCE and not passed:
                            # Later phases cannot claim a populated parent cache
                            # after a failed population/oracle/admission boundary.
                            cohort.setdefault("aborted_cache_sequences", []).append({
                                "compiler": label, "workers": workers, "repeat": repeat + 1,
                                "failed_phase": scenario["name"], "remaining_phases_not_run": True})
                            write(output / "receipt.json", cohort)
                            break
                    round_rows = [rows[-1] for (key_label, key_workers, _), rows in collected.items()
                                  if key_label == label and key_workers == workers and rows and rows[-1]["repeat"] == repeat + 1]
                    cleanup = cleanup_completed_round(round_cache, cache, round_rows, len(scenarios), protected)
                    if cleanup is not None:
                        cohort.setdefault("round_cache_cleanup", []).append(cleanup)
                        write(output / "receipt.json", cohort)
                    free_space(output, args.min_free_bytes)
        summaries = []
        for (label, workers, name), rows in collected.items():
            if name in cached_scenarios.SEQUENCE:
                acceptance, reasons = "diagnostic_only", ["fresh CLI disk-cache trace; performance targets not admitted"]
            elif name == "cold-body-edit":
                acceptance, reasons = "diagnostic_only", ["edited-source cold trace; no incremental latency target"]
            elif args.binary_mode == "acceptance" and workers == 8:
                acceptance, reasons = h.gate(name, rows, [], stage_maps[label])
            else:
                acceptance, reasons = "diagnostic_only", []
            io_acceptance, io_reasons = h.io_gate(name, rows)
            if name in cached_scenarios.SEQUENCE:
                io_acceptance, io_reasons = "diagnostic_only", ["disk-cache cohort has no admitted I/O target"]
            summary = {"schema": h.SCHEMA, "kind": "median", "measurement_revision": 6,
                       "compiler_sha256": tools[label]["sha256"], "comparison_label": label,
                       "comparison": cohort["comparison"], "commit": snapshot["commit"], "scenario": name,
                       "workers": workers, "runs": len(rows), "acceptance": acceptance, "reasons": reasons,
                       "measurement_admission": "passed" if len(rows) == 3 and all(row["measurement_admission"] == "passed" for row in rows) else "incomplete_or_failed",
                       "structural_no_regression": "passed" if len(rows) == 3 and all(row["structural_diff"].get("no_regression") in ("passed", "baseline_established") for row in rows) else "failed",
                       "io_acceptance": io_acceptance, "io_reasons": io_reasons, **h.medians(rows)}
            h.append(args.results, summary)
            summaries.append(summary)
        deltas = []
        for workers in args.worker_counts:
            for scenario in scenarios:
                a = next(value for value in summaries if value["comparison_label"] == "A" and value["workers"] == workers and value["scenario"] == scenario["name"])
                b = next(value for value in summaries if value["comparison_label"] == "B" and value["workers"] == workers and value["scenario"] == scenario["name"])
                fields = {}
                for field in ("critical_path_cpu_s", "critical_path_cpu_budget_upper_s", "total_cpu_s", "wall_s", "peak_private_bytes"):
                    if isinstance(a.get(field), (int, float)) and isinstance(b.get(field), (int, float)):
                        fields[field] = {"A": a[field], "B": b[field], "B_minus_A": b[field] - a[field],
                                         "B_over_A": b[field] / a[field] if a[field] else None}
                delta = {"schema": h.SCHEMA, "kind": "alternating_comparison", "measurement_revision": 6,
                         "comparison": cohort["comparison"], "schedule": "ABABAB", "workers": workers,
                         "scenario": scenario["name"], "A_sha256": tools["A"]["sha256"], "B_sha256": tools["B"]["sha256"], "metrics": fields}
                h.append(args.results, delta)
                deltas.append(delta)
        write(output / "comparison.json", {"schedule": "ABABAB", "comparison": cohort["comparison"], "medians": summaries, "comparisons": deltas})
    finally:
        for path, value in originals.items():
            path.write_bytes(value)
        check_source_closure(h, root, expected, scenarios)
    return 1 if failed else 0
