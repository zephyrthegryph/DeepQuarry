"""Bounded paired compiler-only include-return/EOF diagnostics; never starts DreamDaemon."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[2] / "bench"
CASES = ('terminal', 'define_after', 'conditional_after', 'nested_define', 'repeated', 'nonterminal', 'continued_include', 'no_final_newline')
DM_SHA = "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"

def diagnostics(text):
    return [{"file": match[1], "line": int(match[2]), "severity": match[3], "message": match[4]}
            for line in text.splitlines()
            if (match := re.match(r"^(.*\.dme?):(\d+):(error|warning|note):\s*(.*)$", line))]

def relative_diagnostics(rows, directory):
    """Return independent normalized rows; preserve original evidence."""
    prefix = str(directory).replace("\\", "/") + "/"
    result = []
    for original in rows:
        row = dict(original)
        file = row["file"].replace("\\", "/")
        row["file"] = file[len(prefix):] if file.startswith(prefix) else file
        result.append(row)
    return result


def bounded_log(directory):
    text = []
    for name in ("stdout.log", "stderr.log"):
        path = directory / name
        if path.stat().st_size > 1024 * 1024:
            raise ValueError("tiny compiler log exceeds 1MiB")
        text.append(path.read_text(encoding="utf-8-sig", errors="replace"))
    return "\n".join(text)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", nargs="+", choices=CASES, default=CASES)
    parser.add_argument("--backend", choices=("both", "byond-only"), default="both")
    for name in ("native", "template", "dm"):
        parser.add_argument("--" + name, required=name == "dm", type=Path)
        parser.add_argument("--" + name + "-sha256", required=name == "dm")
    parser.add_argument("--output-root", type=Path,
                        default=Path("E:/dq-cache/dmb-include-return-diagnostics"))
    args = parser.parse_args()
    cases = tuple(args.cases)
    backends = ("byond", "native") if args.backend == "both" else ("byond",)
    pins = ("native", "template", "dm") if args.backend == "both" else ("dm",)
    if any(getattr(args, name) is None or getattr(args, name + "_sha256") is None for name in pins):
        parser.error("selected backends require explicit executable/template pins")
    if os.name != "nt":
        raise ValueError("pinned Windows compiler fixture requires Windows")
    sys.path.insert(0, str(BENCH))
    spec = importlib.util.spec_from_file_location("include_return_iteration", BENCH / "native-iteration.py")
    h = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(h)
    from upgrade_owned_job import OwnedJob
    h.safe_e(args.output_root)
    args.output_root.mkdir(parents=True, exist_ok=True)
    root = args.output_root / uuid.uuid4().hex
    root.mkdir()
    receipt = {"schema": 1, "scope": "compiler-only include-return/EOF discovery",
               "complete": False, "runtime": "not run", "root": str(root),
               "overall_watchdog_seconds": 300, "child_watchdog_seconds": 30,
               "job_memory_bytes": 4 * 1024 ** 3, "pins": {}, "cases": {}}
    deadline = time.monotonic() + 300
    job = None
    previous_job = h._owned_job
    try:
        for name in pins:
            file = getattr(args, name).resolve(strict=True)
            h.regular(file)
            expected = getattr(args, name + "_sha256")
            if not re.fullmatch(r"[0-9a-f]{64}", expected) or h.sha(file) != expected:
                raise ValueError("pinned SHA mismatch: " + name)
            if name == "dm" and expected != DM_SHA:
                raise ValueError("DreamMaker must be pinned 516.1687 capture compiler")
            setattr(args, name, file)
            receipt["pins"][name] = {"path": str(file), "sha256": expected}
        source_hashes = {str(path.relative_to(HERE)).replace("\\", "/"): h.sha(path)
                         for case in cases for path in sorted((HERE / case).iterdir())
                         if path.suffix in (".dm", ".dme")}
        receipt["source_sha256"] = source_hashes
        job = OwnedJob(4 * 1024 ** 3)
        h._owned_job = job
        for case in cases:
            outcomes = {}
            receipt["cases"][case] = outcomes
            for backend in backends:
                directory = root / case / backend
                directory.mkdir(parents=True)
                for path in sorted((HERE / case).iterdir()):
                    if path.suffix in (".dm", ".dme"):
                        shutil.copyfile(path, directory / path.name)
                project = directory / "probe.dme"
                arguments = [str(project)] if backend == "byond" else [
                    "compile", str(project), "--workers", "1", "--no-daemon", "--no-cache",
                    "--exact-inputs", "--engine-template", str(args.template), "--bootstrap-catalog",
                    "--artifact-directory", str(directory / "artifacts"),
                    "--output-store", str(directory / "store"),
                    "--compile-result-file", str(directory / "result.json")]
                evidence = h.run_child(args.dm if backend == "byond" else args.native,
                    arguments, directory / "child", min(deadline, time.monotonic() + 30),
                    cache_directory=root / "cache")
                outcomes[backend] = {"child": evidence}
                text = bounded_log(directory / "child")
                outcomes[backend]["diagnostics"] = diagnostics(text)
                outcomes[backend]["raw_diagnostics"] = diagnostics(text)
                if evidence.get("timeout") or evidence.get("timed_out") or evidence.get("status") == "timeout":
                    raise TimeoutError("compiler child watchdog expired")
                if backend == "byond" and not re.search(r"\b516\.1687\b", text):
                    raise ValueError("DreamMaker did not report pinned version")
                for path in sorted((HERE / case).iterdir()):
                    if path.suffix not in (".dm", ".dme"):
                        continue
                    key = str(path.relative_to(HERE)).replace("\\", "/")
                    if h.sha(directory / path.name) != source_hashes[key] or h.sha(path) != source_hashes[key]:
                        raise ValueError("source changed during probe")
                outcomes[backend]["diagnostics"] = relative_diagnostics(
                    outcomes[backend]["raw_diagnostics"], directory)
                if backend == "byond" and (evidence["exit"] == 0 or not any(
                    row["severity"] == "error" for row in outcomes[backend]["diagnostics"]
                )):
                    raise ValueError("malformed discovery case did not produce reference source errors: " + case)
            # Discovery deliberately has no guessed reference location or message.
            if args.backend == "byond-only":
                continue
            outcomes["acceptance_agrees"] = ((outcomes["byond"]["child"]["exit"] == 0)
                                               == (outcomes["native"]["child"]["exit"] == 0))
            byond_errors = [d for d in outcomes["byond"]["diagnostics"] if d["severity"] == "error"]
            native_errors = [d for d in outcomes["native"]["diagnostics"] if d["severity"] == "error"]
            byond_rejected = outcomes["byond"]["child"]["exit"] != 0
            outcomes["rejection_class_agrees"] = (
                outcomes["acceptance_agrees"] and
                (not byond_rejected or
                 (bool(byond_errors) and outcomes["native"]["child"]["exit"] == 2 and bool(native_errors))))
            # Preserve exact files, line numbers, severity and wording.
            outcomes["diagnostics_agree"] = (
                outcomes["byond"]["diagnostics"] == outcomes["native"]["diagnostics"])
            outcomes["primary_error_messages"] = {
                "byond": byond_errors[0]["message"] if byond_errors else None,
                "native": native_errors[0]["message"] if native_errors else None,
            }
        for name in pins:
            if h.sha(getattr(args, name)) != receipt["pins"][name]["sha256"]:
                raise ValueError("pinned input changed during probe: " + name)
        receipt["complete"] = True
        if args.backend == "byond-only":
            receipt["backend"] = "byond-only"
            receipt["paired_parity"] = "not measured"
        else:
            receipt["backend"] = "both"
        receipt["acceptance_agrees"] = all(receipt["cases"][case].get("acceptance_agrees", False) for case in cases)
        receipt["rejection_class_agrees"] = all(receipt["cases"][case].get("rejection_class_agrees", False) for case in cases)
        receipt["diagnostics_agree"] = all(receipt["cases"][case].get("diagnostics_agree", False) for case in cases)
    except Exception as error:
        receipt["error"] = str(error)
    finally:
        receipt["pin_after_checks"] = {}
        for name, pin in receipt["pins"].items():
            try:
                actual = h.sha(Path(pin["path"]))
                receipt["pin_after_checks"][name] = {"sha256": actual, "unchanged": actual == pin["sha256"]}
                if actual != pin["sha256"]:
                    receipt["complete"] = False
                    receipt["error"] = "pinned input changed: " + name
            except Exception as error:
                receipt["complete"] = False
                receipt["pin_after_checks"][name] = {"error": str(error)}
        if job is not None:
            receipt["owned_job_cleanup"] = job.close()
            if not receipt["owned_job_cleanup"].get("reaped"):
                receipt["complete"] = False
                receipt["error"] = "owned compiler job was not fully reaped"
        h._owned_job = previous_job
        (root / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
        print(root / "receipt.json")
    return 0 if receipt["complete"] and (args.backend == "byond-only" or (receipt.get("acceptance_agrees") and receipt.get("rejection_class_agrees") and receipt.get("diagnostics_agree"))) else 1

if __name__ == "__main__":
    raise SystemExit(main())
