"""Bounded compile-only worker determinism through the real CLI and pair store.

Use a self-contained tiny frozen fixture directory. Runs are sequential, workers
are exactly 1 and 2, and every run publishes to a fresh store at the SAME source
path. This isolates worker count from source/debug path differences. No runtime
is launched. Failure or unsupported syntax is a failed comparison, never parity.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def outputs(project):
    return (project.with_suffix(".dmb"), project.with_suffix(".rsc"),
            project.with_suffix(".dmb-pair.json"))


def published(project, store):
    dmb, rsc, marker = outputs(project)
    pair = json.loads(marker.read_text(encoding="utf-8"))
    if pair.get("version") != 1:
        raise ValueError("unsupported output pair version")
    name = f"{pair['id']:032x}"
    directory = store / "pairs" / name
    stored_pair = json.loads((directory / "pair.json").read_text(encoding="utf-8"))
    if stored_pair != pair:
        raise ValueError("installed marker differs from published manifest")
    hashes = {}
    for kind, installed in (("dmb", dmb), ("rsc", rsc)):
        stored = directory / f"deepquarry.{kind}"
        if installed.stat().st_size != pair[f"{kind}_bytes"]:
            raise ValueError(f"installed {kind} length differs from manifest")
        if sha(installed) != sha(stored):
            raise ValueError(f"installed {kind} differs from immutable pair")
        hashes[kind] = sha(stored)
    return {"pair": pair, "sha256": hashes, "store_directory": str(directory)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--native-sha256", required=True,
                        help="expected frozen release SHA256, supplied by the build owner")
    parser.add_argument("--engine-template", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--project", default="probe.dme", help="relative fixture manifest")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--define", action="append", default=[])
    parser.add_argument("--repeat", type=int, default=2, choices=(1, 2))
    parser.add_argument("--timeout", type=float, default=60,
                        help="per-process watchdog, at most 285 seconds")
    parser.add_argument("--total-timeout", type=float, default=285,
                        help="entire comparison watchdog, at most 285 seconds")
    args = parser.parse_args()
    if not (0 < args.timeout <= 285 and 0 < args.total_timeout <= 285):
        parser.error("watchdogs must be positive and at most 285 seconds")
    for name in ("native", "engine_template", "fixture", "output"):
        setattr(args, name, getattr(args, name).resolve())
    relative = Path(args.project)
    if relative.is_absolute() or ".." in relative.parts or relative.suffix.lower() != ".dme":
        parser.error("--project must be a relative .dme path within the fixture")
    native_hash = sha(args.native)
    if native_hash != args.native_sha256.lower():
        raise ValueError("release executable differs from supplied frozen SHA256")
    original_project = args.fixture / relative
    original_outputs = set(outputs(original_project))
    files = []
    total_bytes = 0
    for path in sorted(args.fixture.rglob("*")):
        if path.is_symlink():
            raise ValueError("fixture must have captured regular files, not symlinks")
        if not path.is_file() or path in original_outputs:
            continue
        # Receipt logs and reference outputs are evidence, not compiler inputs.
        if path.name.endswith((".native.bin", ".native.rsc", ".log")):
            continue
        files.append(path)
        total_bytes += path.stat().st_size
    if len(files) > 1024 or total_bytes > 16 * 1024 * 1024:
        raise ValueError("this gate accepts tiny fixtures only (1024 files / 16 MiB)")
    if original_project not in files:
        raise ValueError("fixture manifest is missing")
    args.output.mkdir(parents=True, exist_ok=False)
    source_dir = args.output / "source"
    input_hashes = {}
    for original in files:
        key = original.relative_to(args.fixture).as_posix()
        destination = source_dir / key
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, destination)
        input_hashes[key] = sha(original)
        if sha(destination) != input_hashes[key]:
            raise ValueError(f"fixture copy changed bytes: {key}")
    project = source_dir / relative
    report = {"schema": 1, "native_sha256": native_hash,
              "engine_template_sha256": sha(args.engine_template),
              "fixture": str(args.fixture), "project": str(relative),
              "source_sha256": input_hashes, "defines": args.define,
              "same_source_path": str(project), "runs": [], "passed": False}
    started = time.perf_counter()
    baseline = None
    for repetition in range(args.repeat):
        for workers in (1, 2):
            remaining = args.total_timeout - (time.perf_counter() - started)
            run_dir = args.output / f"repeat-{repetition + 1}-workers-{workers}"
            run_dir.mkdir()
            store = run_dir / "store"
            command = [str(args.native), "compile", "--no-daemon", str(project),
                       "--workers", str(workers), "--engine-template", str(args.engine_template),
                       "--bootstrap-catalog", "--output-store", str(store),
                       *[f"-D{define}" for define in args.define]]
            result = {"workers": workers, "repetition": repetition + 1,
                      "command": command, "passed": False, "timed_out": False}
            before = time.perf_counter()
            try:
                if remaining <= 0:
                    raise TimeoutError("entire comparison watchdog expired")
                # Prevent a failed run from appearing to publish a preceding result.
                for output in outputs(project):
                    if output.exists():
                        output.unlink()
                with (run_dir / "compiler.log").open("wb") as log:
                    process = subprocess.run(command, cwd=source_dir, stdout=log,
                                             stderr=subprocess.STDOUT,
                                             timeout=min(args.timeout, remaining), check=False,
                                             creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
                result["exit_code"] = process.returncode
                if process.returncode != 0:
                    raise ValueError("compiler did not successfully publish the fixture")
                result["published"] = published(project, store)
                for key, digest in input_hashes.items():
                    if sha(source_dir / key) != digest or sha(args.fixture / key) != digest:
                        raise ValueError(f"source changed during comparison: {key}")
                if sha(args.native) != native_hash or sha(args.engine_template) != report["engine_template_sha256"]:
                    raise ValueError("compiler or engine template changed during comparison")
                current = (result["published"]["pair"], result["published"]["sha256"])
                if baseline is None:
                    baseline = current
                result["passed"] = current == baseline
                if not result["passed"]:
                    result["error"] = "published DMB/RSC bytes or pair identity differ from first run"
                for output in outputs(project):
                    shutil.copyfile(output, run_dir / output.name)
            except (subprocess.TimeoutExpired, TimeoutError) as error:
                result["timed_out"] = True
                result["error"] = str(error)
            except (OSError, ValueError, KeyError) as error:
                result["error"] = str(error)
            result["seconds"] = time.perf_counter() - before
            report["runs"].append(result)
            (args.output / "comparison.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
            print(f"workers={workers} repeat={repetition + 1}: {'PASS' if result['passed'] else 'FAIL'} ({result['seconds']:.3f}s)")
            if result["timed_out"]:
                break
        if report["runs"][-1]["timed_out"]:
            break
    report["seconds"] = time.perf_counter() - started
    report["passed"] = len(report["runs"]) == args.repeat * 2 and all(row["passed"] for row in report["runs"])
    (args.output / "comparison.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
