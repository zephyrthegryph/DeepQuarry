"""Bounded paired compiler-only parameter diagnostics; never starts DreamDaemon."""
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
CASES = ("duplicate_parameter", "local_shadows_parameter", "distinct_parameters",
         "duplicate_typed_first", "duplicate_typed_last",
         "nested_parameter_shadow", "for_parameter_shadow")
EXPECTED_BYOND = {'duplicate_parameter': {'accepted': True, 'errors': []}, 'local_shadows_parameter': {'accepted': False, 'errors': [(2, 'value: duplicate definition'), (1, 'value: previous definition')]}, 'distinct_parameters': {'accepted': True, 'errors': []}, 'duplicate_typed_first': {'accepted': False, 'errors': [(2, 'value.formerly_missing: undefined proc')]}, 'duplicate_typed_last': {'accepted': False, 'errors': [(2, 'value.formerly_missing: undefined proc')]}, 'nested_parameter_shadow': {'accepted': False, 'errors': [(3, 'value: duplicate definition'), (1, 'value: previous definition')]}, 'for_parameter_shadow': {'accepted': False, 'errors': [(2, 'value: duplicate definition'), (1, 'value: previous definition')]}}
DM_SHA = "8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0"

def diagnostics(text):
    return [{"file": match[1], "line": int(match[2]), "severity": match[3], "message": match[4]}
            for line in text.splitlines()
            if (match := re.match(r"^(.*\.dm):(\d+):(error|warning|note):\s*(.*)$", line))]

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
    for name in ("native", "template", "dm"):
        parser.add_argument("--" + name, required=True, type=Path)
        parser.add_argument("--" + name + "-sha256", required=True)
    parser.add_argument("--output-root", type=Path,
                        default=Path("E:/dq-cache/dmb-parameter-diagnostics"))
    args = parser.parse_args()
    if os.name != "nt":
        raise ValueError("pinned Windows compiler fixture requires Windows")
    sys.path.insert(0, str(BENCH))
    spec = importlib.util.spec_from_file_location("parameter_iteration", BENCH / "native-iteration.py")
    h = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(h)
    from upgrade_owned_job import OwnedJob
    h.safe_e(args.output_root)
    args.output_root.mkdir(parents=True, exist_ok=True)
    root = args.output_root / uuid.uuid4().hex
    root.mkdir()
    receipt = {"schema": 1, "scope": "seven paired compiler-only diagnostic controls",
               "complete": False, "runtime": "not run", "root": str(root),
               "overall_watchdog_seconds": 90, "child_watchdog_seconds": 30,
               "job_memory_bytes": 4 * 1024 ** 3, "pins": {}, "cases": {}}
    deadline = time.monotonic() + 90
    job = None
    previous_job = h._owned_job
    try:
        for name in ("native", "template", "dm"):
            file = getattr(args, name).resolve(strict=True)
            h.regular(file)
            expected = getattr(args, name + "_sha256")
            if not re.fullmatch(r"[0-9a-f]{64}", expected) or h.sha(file) != expected:
                raise ValueError("pinned SHA mismatch: " + name)
            if name == "dm" and expected != DM_SHA:
                raise ValueError("DreamMaker must be pinned 516.1687 capture compiler")
            setattr(args, name, file)
            receipt["pins"][name] = {"path": str(file), "sha256": expected}
        source_hashes = {path.name: h.sha(path) for case in CASES
                         for path in (HERE / (case + ".dm"), HERE / (case + ".dme"))}
        receipt["source_sha256"] = source_hashes
        job = OwnedJob(4 * 1024 ** 3)
        h._owned_job = job
        for case in CASES:
            outcomes = {}
            receipt["cases"][case] = outcomes
            for backend in ("byond", "native"):
                directory = root / case / backend
                directory.mkdir(parents=True)
                for suffix in (".dm", ".dme"):
                    shutil.copyfile(HERE / (case + suffix), directory / (case + suffix))
                project = directory / (case + ".dme")
                arguments = [str(project)] if backend == "byond" else [
                    "compile", str(project), "--workers", "1", "--no-daemon", "--no-cache",
                    "--exact-inputs", "--engine-template", str(args.template), "--bootstrap-catalog",
                    "--artifact-directory", str(directory / "artifacts"),
                    "--output-store", str(directory / "store"),
                    "--compile-result-file", str(directory / "result.json")]
                evidence = h.run_child(args.dm if backend == "byond" else args.native,
                    arguments, directory / "child", min(deadline, time.monotonic() + 30),
                    cache_directory=root / "cache")
                text = bounded_log(directory / "child")
                outcomes[backend] = {"child": evidence, "diagnostics": diagnostics(text)}
                if evidence.get("timeout") or evidence.get("timed_out") or evidence.get("status") == "timeout":
                    raise TimeoutError("compiler child watchdog expired")
                if backend == "byond" and not re.search(r"\b516\.1687\b", text):
                    raise ValueError("DreamMaker did not report pinned version")
                for suffix in (".dm", ".dme"):
                    name = case + suffix
                    if h.sha(directory / name) != source_hashes[name] or h.sha(HERE / name) != source_hashes[name]:
                        raise ValueError("source changed during probe")
            outcomes["acceptance_agrees"] = ((outcomes["byond"]["child"]["exit"] == 0)
                                               == (outcomes["native"]["child"]["exit"] == 0))
            byond_errors = [d for d in outcomes["byond"]["diagnostics"] if d["severity"] == "error"]
            outcomes["byond_contract_agrees"] = (
                (outcomes["byond"]["child"]["exit"] == 0) == EXPECTED_BYOND[case]["accepted"]
                and [(d["line"], d["message"]) for d in byond_errors] == EXPECTED_BYOND[case]["errors"])
            if not outcomes["byond_contract_agrees"]:
                raise ValueError("captured BYOND diagnostic contract changed: " + case)

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
            # Do not pre-bless duplicate/shadow rules. Captured BYOND results are
            # the evidence; valid distinct parameters are the positive control.
            if case == "distinct_parameters" and any(outcomes[b]["child"]["exit"] != 0
                                                      for b in ("byond", "native")):
                raise ValueError("valid distinct-parameter control failed")
        receipt["complete"] = True
        receipt["acceptance_agrees"] = all(receipt["cases"][case]["acceptance_agrees"] for case in CASES)
        receipt["rejection_class_agrees"] = all(receipt["cases"][case]["rejection_class_agrees"] for case in CASES)
        receipt["diagnostics_agree"] = all(receipt["cases"][case]["diagnostics_agree"] for case in CASES)
    except Exception as error:
        receipt["error"] = str(error)
    finally:
        if job is not None:
            receipt["owned_job_cleanup"] = job.close()
            if not receipt["owned_job_cleanup"].get("reaped"):
                receipt["complete"] = False
                receipt["error"] = "owned compiler job was not fully reaped"
        h._owned_job = previous_job
        (root / "receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
        print(root / "receipt.json")
    return 0 if receipt["complete"] and receipt.get("acceptance_agrees") else 1

if __name__ == "__main__":
    raise SystemExit(main())
