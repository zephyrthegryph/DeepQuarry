"""Bounded paired runtime oracle; no game boot or general parity claim."""
import argparse
import ctypes
from contextlib import contextmanager
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time
import uuid
from collections import Counter

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[2] / "bench"
sys.path.insert(0, str(BENCH))
from iteration_memory import OwnedMemory


@contextmanager
def hidden_error_mode(set_mode=None):
    """Child inherits noninteractive critical-error/crash handling; restore parent."""
    if set_mode is None:
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        set_mode = kernel.SetErrorMode
        set_mode.argtypes = [ctypes.c_uint]
        set_mode.restype = ctypes.c_uint
    previous = set_mode(3)  # SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX
    try:
        yield
    finally:
        set_mode(previous)


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def record_pin(receipt, name, file, sha256):
    receipt.setdefault("pinned_inputs", {})[name] = {"path": str(file), "sha256": sha256}


def observations(file):
    if file.stat().st_size > 1024 * 1024:
        raise ValueError("tiny runtime log exceeds 1MiB")
    raw = file.read_bytes()
    text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
    markers = []
    errors = Counter()
    for line in text.splitlines():
        if "DQ_RETIRE " in line:
            markers.append(line[line.index("DQ_RETIRE "):])
        match = re.search(r"Runtime in (.+?\.dm),(\d+): (.*)", line)
        if match:
            source, number, message = match.groups()
            errors[(source.replace("\\", "/").rsplit("/", 1)[-1], int(number), message)] += 1
        else:
            direct = re.search(r"runtime error:\s*(.*)", line, re.IGNORECASE)
            if direct:
                # Standalone DreamDaemon reports do not use the game's Runtime
                # in ... wrapper. Preserve message/count; source is explicitly
                # unavailable here rather than inferred from the next stack.
                errors[("<standalone source unavailable>", 0, direct.group(1))] += 1
    if not markers or markers[-1] != "DQ_RETIRE finished":
        raise ValueError("runtime did not complete the fixture")
    return {"markers": markers, "runtimes": [
        {"source": source, "line": number, "message": message, "count": count}
        for (source, number, message), count in sorted(errors.items())]}


def fixture_files(asset_files):
    """Explicit relative assets only; no traversal, aliases or implicit discovery."""
    names = ["probe.dm", "probe.dme"]
    for name in asset_files:
        if (not isinstance(name, str) or not name or "\\" in name or ":" in name
                or name.startswith("/") or any(part in ("", ".", "..") for part in name.split("/"))):
            raise ValueError("unsafe fixture asset path")
        if name in names:
            raise ValueError("duplicate fixture asset path")
        names.append(name)
    return tuple(names)


def fixture_file(root, name):
    file = root / name
    for part in (file, *file.parents):
        if part == root.parent:
            break
        if part.is_symlink() or (part.exists() and getattr(part.stat(), "st_file_attributes", 0) & 0x400):
            raise ValueError("fixture asset has a reparse path")
    if not file.is_file():
        raise ValueError("fixture asset is not a regular file")
    return file


def copy_fixture_files(source, destination, names, hashes, sha):
    for name in names:
        file = fixture_file(source, name)
        if sha(file) != hashes[name]:
            raise ValueError("fixture input changed before copy")
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with file.open("rb") as reader, target.open("xb") as writer:
            shutil.copyfileobj(reader, writer)
        if sha(file) != hashes[name] or sha(target) != hashes[name]:
            raise ValueError("fixture input changed during copy")


def main(*, fixture_directory=None, observation_reader=None,
         prepare_runtime=None, asset_files=(),
         scope="four deterministic retirement decoder cases only"):
    fixture_directory = HERE if fixture_directory is None else Path(fixture_directory)
    observation_reader = observations if observation_reader is None else observation_reader
    names = fixture_files(asset_files)
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("native", "template", "dm", "dd"):
        parser.add_argument("--" + name, type=Path, required=True)
        parser.add_argument("--" + name + "-sha256", required=True)
    parser.add_argument("--output-root", type=Path, default=Path("E:/dq-cache/dmb-power-retirement"))
    args = parser.parse_args()
    if os.name != "nt":
        raise ValueError("this pinned Windows BYOND fixture requires Windows")
    h = load("retirement_iteration", BENCH / "native-iteration.py")
    fresh = load("retirement_fresh", BENCH / "native-fresh.py")
    h.safe_e(args.output_root)
    args.output_root.mkdir(parents=True, exist_ok=True)
    root = args.output_root / uuid.uuid4().hex
    root.mkdir()
    receipt = {"schema": 2, "scope": scope,
               "complete": False, "root": str(root), "executions": {}}
    receipt["fixture_sources"] = {name: h.sha(fixture_file(fixture_directory, name)) for name in names}
    memory = None
    previous_memory = h._owned_memory
    status = 1
    try:
        for name in ("native", "template", "dm", "dd"):
            file = getattr(args, name).resolve(strict=True)
            h.regular(file)
            expected = getattr(args, name + "_sha256")
            if not re.fullmatch("[0-9a-f]{64}", expected) or h.sha(file) != expected:
                raise ValueError("pinned input SHA mismatch: " + name)
            setattr(args, name, file)
            record_pin(receipt, name, file, expected)
        memory = OwnedMemory(4_000_000_000)
        h._owned_memory = memory
        memory.start()
        def run(label, executable, arguments, seconds):
            def launch():
                return h.run_child(executable, arguments, root / label, time.monotonic() + seconds,
                                   cache_directory=root / "cache")
            if label.endswith("-runtime"):
                with hidden_error_mode():
                    result = launch()
            else:
                result = launch()
            receipt["executions"][label] = result
            if result["exit"] != 0:
                raise ValueError(label + " failed; owned child evidence preserved")
        for backend in ("byond", "native"):
            directory = root / (backend + "-source")
            directory.mkdir()
            copy_fixture_files(fixture_directory, directory, names, receipt["fixture_sources"], h.sha)
            project = directory / "probe.dme"
            if backend == "byond":
                run("byond-compile", args.dm, [str(project)], 30)
                banner = (root / "byond-compile/stdout.log").read_text(encoding="utf-8-sig")
                if not re.search(r"\b516\.1687\b", banner):
                    raise ValueError("successful DreamMaker compile did not report pinned 516.1687")
                dmb = project.with_suffix(".dmb")
            else:
                result_file = root / "compile-result.json"
                artifacts = root / "artifacts"
                store = root / "store"
                run("native-compile", args.native, ["compile", str(project), "--workers", "2",
                    "--engine-template", str(args.template), "--bootstrap-catalog", "--no-daemon",
                    "--no-cache", "--exact-inputs", "--artifact-directory", str(artifacts),
                    "--output-store", str(store), "--compile-result-file", str(result_file)], 300)
                result = fresh.read_json(result_file, 65536)
                acquired_file = root / "acquired.json"
                slots = root / "slots"
                run("acquire", args.native, ["acquire", "--output-store", str(store),
                    "--pair-id", result["pair_id"], "--slots", str(slots),
                    "--result-file", str(acquired_file)], 30)
                acquired = fresh.read_json(acquired_file, 65536)
                fresh.admit_pair(result, acquired, artifacts / "probe.dme", store, slots, h.regular, h.sha)
                dmb = Path(acquired["dmb"])
            runtime_arguments = [] if prepare_runtime is None else prepare_runtime(dmb, backend, receipt)
            run(backend + "-runtime", args.dd, [str(dmb), "-close", "-trusted", "-invisible", "-logself", *runtime_arguments], 30)
            receipt[backend] = observation_reader(dmb.with_suffix(".log"))
            for name in names:
                if h.sha(fixture_file(directory, name)) != receipt["fixture_sources"][name] or h.sha(fixture_file(fixture_directory, name)) != receipt["fixture_sources"][name]:
                    raise ValueError("fixture source changed during run")
        for name in ("native", "template", "dm", "dd"):
            if h.sha(getattr(args, name)) != getattr(args, name + "_sha256"):
                raise ValueError("pinned input changed during run: " + name)
        receipt.update(complete=True, matches=receipt["byond"] == receipt["native"])
        status = 0 if receipt["matches"] else 1
    except Exception as error:
        receipt["error"] = str(error)
    finally:
        if memory is not None:
            receipt["memory"] = memory.finish()
            receipt["memory"]["scope"] = "registered owned compile/acquisition/runtime children, 200ms samples; not strict peak or unregistered-descendant proof"
            if receipt["memory"]["status"] == "failed":
                receipt.update(complete=False, matches=False)
                status = 1
        h._owned_memory = previous_memory
        # Evidence and acquired files stay owned under this fresh E: directory.
        # run_child reaps only its own process tree on deadline/interruption.
        (root / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
        print(root / "receipt.json")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
