"""Bounded explicit runtime contract across actual retained and fresh compilers."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[2] / "bench"
sys.path.insert(0, str(BENCH))
from iteration_memory import OwnedMemory
from watchdog import record_daemon_cleanup, terminate_owned

LABELS = ("inherited", "parent_default", "parent_explicit", "argument_defaults",
          "global", "static_first", "static_second", "structural", "resource", "new_type_inherited", "new_type_own")


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_text(file):
    if file.stat().st_size > 1024 * 1024:
        raise ValueError("standalone evidence exceeds 1MiB")
    raw = file.read_bytes()
    return raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")


def expected_markers(values, labels=LABELS, prefix="DQ_CONTRACT"):
    if not isinstance(prefix, str) or not re.fullmatch(r"DQ_[A-Z_]+", prefix):
        raise ValueError("invalid declared marker prefix")
    if not isinstance(values, list) or len(values) != len(labels) or any(type(value) is not int for value in values):
        raise ValueError("scenario must declare all declared integer expectations")
    return [f"{prefix} {name} {value}" for name, value in zip(labels, values)] + [f"{prefix} finished"]


def observations(file, expected, prefix="DQ_CONTRACT"):
    text = read_text(file)
    markers = [line[line.index(prefix + " "):] for line in text.splitlines() if prefix + " " in line]
    errors = [line for line in text.splitlines()
              if re.search(r"runtime error:|Runtime in .+?\.dm,\d+:", line, re.IGNORECASE)]
    result = {"markers": markers, "runtime_errors": errors, "expected": expected,
              "matches_expected": markers == expected and not errors}
    # Missing/extra/reordered values fail even when both compilers agree.
    return result


def runtime_copies(acquired, hashes, directory, regular, sha):
    """DD may rewrite RSC archives. Preserve the authenticated compiled pair."""
    directory.mkdir()
    evidence = {}
    for extension in ("dmb", "rsc"):
        source = Path(acquired[extension])
        regular(source)
        if sha(source) != hashes[extension]["sha256"]:
            raise ValueError("authenticated acquisition changed before runtime copy: " + extension)
        destination = directory / ("deepquarry." + extension)
        # Exclusive creation prevents copying into an existing alias/inode.
        with source.open("rb") as reader, destination.open("xb") as writer:
            shutil.copyfileobj(reader, writer)
        regular(destination)
        if sha(destination) != hashes[extension]["sha256"] or sha(source) != hashes[extension]["sha256"]:
            raise ValueError("runtime copy failed authentication: " + extension)
        evidence[extension] = {"path": str(destination), "initial_sha256": sha(destination)}
    return directory / "deepquarry.dmb", evidence


def apply_step(source, step):
    if "before" not in step and "after" not in step:
        return source
    before, after = step.get("before"), step.get("after")
    if not isinstance(before, str) or not before or not isinstance(after, str) or source.count(before) != 1:
        raise ValueError("edit does not identify one exact source site")
    return source.replace(before, after, 1)


def admitted_asset_edits(steps, fixture_names):
    """Only explicit extra source assets may be edited; special hooks stay separate."""
    allowed = set(fixture_names) - {"probe.dm", "probe.dme", "contract-resource.txt", "scenarios.json"}
    paths = set()
    for step in steps:
        if "asset_edit" not in step:
            continue
        edit = step["asset_edit"]
        if (not isinstance(edit, dict) or set(edit) != {"path", "before", "after"}
                or not isinstance(edit["path"], str) or edit["path"] not in allowed
                or not isinstance(edit["before"], str) or not edit["before"]
                or not isinstance(edit["after"], str)):
            raise ValueError("asset edit requires one declared extra asset and exact before/after text")
        paths.add(edit["path"])
    return tuple(sorted(paths))


def current_asset_hashes(original, copies, names, original_hashes, current_bytes, regular, sha):
    """Original producer bytes stay immutable; each private copy matches issued revision."""
    hashes = {}
    for name in names:
        regular(original, name)
        if sha(original / name) != original_hashes[name]:
            raise ValueError("original asset changed during revision: " + name)
        expected = hashlib.sha256(current_bytes[name]).hexdigest() if name in current_bytes else original_hashes[name]
        for directory in copies:
            regular(directory, name)
            if sha(directory / name) != expected:
                raise ValueError("current asset copy differs from admitted revision: " + name)
        hashes[name] = expected
    return hashes


def read_steps(file, labels=LABELS, prefix="DQ_CONTRACT"):
    if file.stat().st_size > 64 * 1024:
        raise ValueError("scenario descriptor exceeds 64KiB")
    descriptor = json.loads(file.read_text(encoding="utf-8"))
    steps = descriptor.get("steps")
    if descriptor.get("schema") != 1 or not isinstance(steps, list) or not 1 <= len(steps) <= 16:
        raise ValueError("unsupported bounded scenario descriptor")
    names = set()
    for step in steps:
        name = step.get("name")
        if not isinstance(name, str) or not re.fullmatch(r"[a-z_]+", name) or name in names:
            raise ValueError("scenario names must be unique safe path components")
        names.add(name)
        expected_markers(step.get("expected"), labels, prefix)
    return steps


def compile_arguments(project, output, template, retained):
    arguments = ["compile", str(project), "--workers", "2", "--engine-template", str(template),
                 "--bootstrap-catalog", "--exact-inputs", "--artifact-directory", str(output / "artifacts"),
                 "--output-store", str(output / "store"), "--compile-result-file", str(output / "compile-result.json")]
    if not retained:
        arguments.extend(["--no-daemon", "--no-cache"])
    return arguments


def owned_daemon_route(h, cache, compiler, compiler_sha256, *, owned_job=None):
    """Configure the probe and client launcher for one private daemon endpoint."""
    namespace = "runtime-contract-" + uuid.uuid4().hex
    h._daemon_namespace = namespace
    environment = os.environ.copy()
    environment["DMB_CACHE_DIR"] = str(cache)
    environment["DMB_DAEMON_NAMESPACE"] = namespace
    return namespace, h.Endpoint(compiler, compiler_sha256, namespace, owned_job=owned_job), environment


def main(*, fixture_directory=HERE, labels=LABELS, prefix="DQ_CONTRACT", asset_files=("contract-resource.txt",), scope="eleven standalone observations including resource replacement and type addition/deletion"):
    fixture_directory = Path(fixture_directory).resolve(strict=True)
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("native", "template", "dm", "dd"):
        parser.add_argument("--" + name, type=Path, required=True)
        parser.add_argument("--" + name + "-sha256", required=True)
    parser.add_argument("--output-root", type=Path, default=Path("E:/dq-cache/dmb-incremental-runtime-contract"))
    args = parser.parse_args()
    if os.name != "nt":
        raise ValueError("the pinned daemon/runtime route requires Windows")
    h = load("contract_iteration", BENCH / "native-iteration.py")
    fresh = load("contract_fresh", BENCH / "native-fresh.py")
    retirement = load("contract_retirement", HERE.parent / "power_retirement_runtime/run.py")
    h.safe_e(args.output_root)
    args.output_root.mkdir(parents=True, exist_ok=True)
    root = args.output_root / uuid.uuid4().hex
    root.mkdir()
    receipt = {"schema": 1, "scope": scope,
               "acceptance_profile": False, "complete": False, "matches": False,
               "root": str(root), "steps": [], "executions": {}}
    fixture_names = retirement.fixture_files(asset_files)
    if "contract-resource.txt" not in fixture_names:
        raise ValueError("retained contract requires its explicit resource asset")
    immutable_assets = tuple(name for name in fixture_names if name not in ("probe.dm", "contract-resource.txt"))
    for name in (*fixture_names, "scenarios.json"):
        retirement.fixture_file(fixture_directory, name)
    receipt["fixture_sources"] = {name: h.sha(fixture_directory / name) for name in (*fixture_names, "scenarios.json")}
    daemon = None
    memory = None
    previous_memory = h._owned_memory
    previous_namespace = h._daemon_namespace
    status = 1
    deadline = time.monotonic() + 300  # Includes owned daemon lifetime, all compiles/acquires/runtimes.
    try:
        for name in ("native", "template", "dm", "dd"):
            file = getattr(args, name).resolve(strict=True)
            h.regular(file)
            expected = getattr(args, name + "_sha256")
            if not re.fullmatch("[0-9a-f]{64}", expected) or h.sha(file) != expected:
                raise ValueError("pinned input SHA mismatch: " + name)
            setattr(args, name, file)
            retirement.record_pin(receipt, name, file, expected)
        steps = read_steps(fixture_directory / "scenarios.json", labels, prefix)
        edited_assets = admitted_asset_edits(steps, fixture_names)
        extra_assets = tuple(name for name in fixture_names if name not in ("probe.dm", "probe.dme", "contract-resource.txt"))
        asset_text = {}
        for name in edited_assets:
            file = retirement.fixture_file(fixture_directory, name)
            if file.stat().st_size > 1024 * 1024:
                raise ValueError("editable fixture asset exceeds 1MiB")
            asset_text[name] = file.read_bytes().decode("utf-8")
        immutable_assets = tuple(name for name in immutable_assets if name not in edited_assets)
        source = (fixture_directory / "probe.dm").read_text(encoding="utf-8")
        resource = (fixture_directory / "contract-resource.txt").read_text(encoding="utf-8")
        native_source, byond_source = root / "native-source", root / "byond-source"
        for directory in (native_source, byond_source):
            directory.mkdir()
            retirement.copy_fixture_files(fixture_directory, directory, fixture_names, receipt["fixture_sources"], h.sha)
        cache = root / "cache"
        namespace, endpoint, environment = owned_daemon_route(h, cache, args.native, args.native_sha256)
        receipt["daemon_namespace"] = namespace
        receipt["daemon_endpoint_descriptor"] = endpoint.descriptor
        endpoint.probe()  # Refuse an occupied endpoint; never replace another process.
        memory = OwnedMemory(4_000_000_000)
        h._owned_memory = memory
        memory.start()

        def run(label, executable, arguments, seconds, retained=False, runtime=False):
            child_deadline = min(deadline, time.monotonic() + seconds)
            def launch():
                return h.run_child(executable, arguments, root / label, child_deadline,
                                   require_owned=retained, cache_directory=cache)
            # Apply to all owned launches, including compilation, not only DD.
            with retirement.hidden_error_mode():
                result = launch()
            receipt["executions"][label] = result
            if result["exit"] != 0:
                raise ValueError(label + " failed; owned child evidence preserved")

        with (root / "daemon.stdout").open("xb") as out, (root / "daemon.stderr").open("xb") as err:
            with retirement.hidden_error_mode():
                daemon = subprocess.Popen([str(args.native), "--serve-daemon"], stdout=out, stderr=err,
                                          env=environment, creationflags=subprocess.CREATE_NO_WINDOW)
        receipt["owned_daemon_pid"] = daemon.pid
        memory.register(daemon)
        ready_deadline = min(deadline, time.monotonic() + 20)
        while not endpoint.probe(daemon):
            memory.check()
            if daemon.poll() is not None or time.monotonic() >= ready_deadline:
                raise RuntimeError("owned daemon did not become ready within 20 seconds")
            time.sleep(0.05)

        for index, step in enumerate(steps):
            source = apply_step(source, step)
            if "resource_before" in step or "resource_after" in step:
                resource = apply_step(resource, {"before": step.get("resource_before"), "after": step.get("resource_after")})
            if "asset_edit" in step:
                edit = step["asset_edit"]
                asset_text[edit["path"]] = apply_step(asset_text[edit["path"]], edit)
                if len(asset_text[edit["path"]].encode("utf-8")) > 1024 * 1024:
                    raise ValueError("edited fixture asset exceeds 1MiB")
            current_asset_bytes = {name: text.encode("utf-8") for name, text in asset_text.items()}
            expected = expected_markers(step["expected"], labels, prefix)
            label = f"{index:02d}-{step['name']}"
            row = {"name": step["name"], "status": "pending", "expected": expected}
            receipt["steps"].append(row)
            for directory in (native_source, byond_source):
                target = directory / "probe.dm"
                temporary = directory / "probe.next"
                temporary.write_text(source, encoding="utf-8", newline="\n")
                os.replace(temporary, target)
                (directory / "contract-resource.txt").write_text(resource, encoding="utf-8", newline="\n")
                for name, data in current_asset_bytes.items():
                    target = directory / name
                    retirement.fixture_file(directory, name)
                    temporary = target.with_name(target.name + ".next")
                    with temporary.open("xb") as output:
                        output.write(data)
                    os.replace(temporary, target)
            for directory in (native_source, byond_source):
                for name in immutable_assets:
                    retirement.fixture_file(directory, name)
                    retirement.fixture_file(fixture_directory, name)
                    expected_hash = receipt["fixture_sources"][name]
                    if h.sha(directory / name) != expected_hash or h.sha(fixture_directory / name) != expected_hash:
                        raise ValueError("immutable fixture asset changed before revision: " + name)
            row["immutable_asset_sha256"] = {name: receipt["fixture_sources"][name] for name in immutable_assets}
            row["asset_sha256"] = current_asset_hashes(fixture_directory,
                (native_source, byond_source), extra_assets, receipt["fixture_sources"],
                current_asset_bytes, retirement.fixture_file, h.sha)
            row["source_sha256"] = h.sha(native_source / "probe.dm")
            row["resource_sha256"] = h.sha(native_source / "contract-resource.txt")
            if h.sha(byond_source / "probe.dm") != row["source_sha256"]:
                raise ValueError("compiler fixture source copies differ")
            if h.sha(byond_source / "contract-resource.txt") != row["resource_sha256"]:
                raise ValueError("compiler resource copies differ")

            run(label + "/byond-compile", args.dm, [str(byond_source / "probe.dme")], 30)
            if not re.search(r"\b516\.1687\b", read_text(root / label / "byond-compile/stdout.log")):
                raise ValueError("successful DreamMaker compile did not report pinned 516.1687")
            # Give each revision an independent runtime log/output namespace;
            # DD's -logself must not append an earlier revision's observations.
            byond_runtime = root / label / "byond-owned"
            byond_runtime.mkdir()
            row["byond_outputs"] = {}
            for extension in ("dmb", "rsc"):
                original = byond_source / ("probe." + extension)
                h.regular(original)
                shutil.copyfile(original, byond_runtime / original.name)
                row["byond_outputs"][extension] = {"present": True, "sha256": h.sha(original), "bytes": original.stat().st_size}
            run(label + "/byond-runtime", args.dd,
                [str(byond_runtime / "probe.dmb"), "-close", "-trusted", "-invisible", "-logself"], 30, runtime=True)
            row["byond"] = observations(byond_runtime / "probe.log", expected, prefix)
            if not row["byond"]["matches_expected"]:
                raise ValueError("BYOND does not match the declared runtime expectation: " + step["name"])

            for mode in ("retained", "fresh"):
                output = root / label / mode
                output.mkdir(parents=True)
                if daemon.poll() is not None or not endpoint.probe(daemon):
                    raise RuntimeError("owned daemon missing before compilation")
                run(label + "/" + mode + "-compile", args.native,
                    compile_arguments(native_source / "probe.dme", output, args.template, mode == "retained"),
                    300, retained=mode == "retained")
                if daemon.poll() is not None or not endpoint.probe(daemon):
                    raise RuntimeError("owned daemon changed during compilation; replacement left untouched")
                result = fresh.read_json(output / "compile-result.json", 65536)
                slots = output / "slots"
                acquired_file = output / "acquired.json"
                run(label + "/" + mode + "-acquire", args.native,
                    ["acquire", "--output-store", str(output / "store"), "--pair-id", result["pair_id"],
                     "--slots", str(slots), "--result-file", str(acquired_file)], 30)
                acquired = fresh.read_json(acquired_file, 65536)
                hashes = fresh.admit_pair(result, acquired, output / "artifacts/probe.dme",
                                         output / "store", slots, h.regular, h.sha)
                row[mode + "_pair"] = {"published": result, "acquired": acquired, "outputs": hashes}
                dmb, runtime_evidence = runtime_copies(acquired, hashes, output / "runtime-owned", h.regular, h.sha)
                row[mode + "_pair"]["runtime_copies"] = runtime_evidence
                run(label + "/" + mode + "-runtime", args.dd,
                    [str(dmb), "-close", "-trusted", "-invisible", "-logself"], 30, runtime=True)
                row[mode] = observations(dmb.with_suffix(".log"), expected, prefix)
                if not row[mode]["matches_expected"]:
                    raise ValueError(mode + " does not match declared expectations: " + step["name"])
                for extension in ("dmb", "rsc"):
                    if h.sha(Path(acquired[extension])) != hashes[extension]["sha256"]:
                        raise ValueError("acquired runtime input changed: " + mode + " " + extension)
                    stored = output / "store/pairs" / result["pair_id"] / ("deepquarry." + extension)
                    h.regular(stored)
                    if h.sha(stored) != hashes[extension]["sha256"]:
                        raise ValueError("immutable published input changed: " + mode + " " + extension)
                    runtime_evidence[extension]["after_runtime_sha256"] = h.sha(dmb.with_suffix("." + extension))
            # admit_pair returns location-bearing evidence. Compare the actual artifact bytes explicitly.
            row["fresh_byte_oracle"] = {extension: {
                mode: h.sha(root / label / mode / "artifacts" / ("probe." + extension))
                for mode in ("retained", "fresh")} for extension in ("dmb", "rsc")}
            if any(answer["retained"] != answer["fresh"] for answer in row["fresh_byte_oracle"].values()):
                raise ValueError("retained/fresh native output bytes differ: " + step["name"])
            for directory in (native_source, byond_source):
                if h.sha(directory / "probe.dm") != row["source_sha256"] or h.sha(directory / "probe.dme") != receipt["fixture_sources"]["probe.dme"]:
                    raise ValueError("current fixture input changed during a request")
                for name in immutable_assets:
                    retirement.fixture_file(directory, name)
                    retirement.fixture_file(fixture_directory, name)
                    if h.sha(directory / name) != receipt["fixture_sources"][name] or h.sha(fixture_directory / name) != receipt["fixture_sources"][name]:
                        raise ValueError("immutable fixture asset changed during request: " + name)
                if h.sha(directory / "contract-resource.txt") != row["resource_sha256"]:
                    raise ValueError("current resource input changed during a request")
            if current_asset_hashes(fixture_directory, (native_source, byond_source),
                    extra_assets, receipt["fixture_sources"], current_asset_bytes,
                    retirement.fixture_file, h.sha) != row["asset_sha256"]:
                raise ValueError("current asset evidence changed during request")
            row["status"] = "passed"
        for name in receipt["fixture_sources"]:
            if h.sha(fixture_directory / name) != receipt["fixture_sources"][name]:
                raise ValueError("committed fixture changed during the cohort")
        for name in ("native", "template", "dm", "dd"):
            if h.sha(getattr(args, name)) != getattr(args, name + "_sha256"):
                raise ValueError("pinned input changed during cohort: " + name)
        receipt.update(complete=True, matches=True)
        status = 0
    except Exception as error:
        receipt["error"] = str(error)
    finally:
        h._owned_memory = previous_memory
        h._daemon_namespace = previous_namespace
        if daemon is not None:
            record_daemon_cleanup(receipt, terminate_owned(daemon))
            if receipt.get("status") == "failed":
                receipt.update(complete=False, matches=False)
                status = 1
        if memory is not None:
            receipt["memory"] = memory.finish()
            receipt["memory"]["scope"] = "registered owned daemon/compile/acquire/runtime handles, 200ms samples; not strict peak or descendant proof"
            if receipt["memory"]["status"] == "failed":
                receipt.update(complete=False, matches=False)
                status = 1
        # All acquired outputs and logs remain under this new owned E: root for review.
        (root / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
        print(root / "receipt.json")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
