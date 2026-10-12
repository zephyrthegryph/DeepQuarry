"""Bounded compile-only native replay of one pinned reference control; never starts DD."""
import argparse
import importlib.util
import json
import os
import sys
import time
import uuid
from pathlib import Path
BENCH = Path(__file__).resolve().parents[3] / "bench"
sys.path.insert(0, str(BENCH))
from upgrade_owned_job import OwnedJob
from machine_slot_command import slot_command
spec = importlib.util.spec_from_file_location("control_iteration", BENCH / "native-iteration.py")
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference-receipt", type=Path, required=True)
    parser.add_argument("--reference-sha256", required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--native-sha256", required=True)
    parser.add_argument("--template", type=Path, required=True)
    parser.add_argument("--template-sha256", required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--variant", choices=("forward", "reverse"), default="forward")
    args = parser.parse_args()
    for file, digest in ((args.reference_receipt, args.reference_sha256), (args.native, args.native_sha256), (args.template, args.template_sha256)):
        h.regular(file)
        if h.sha(file) != digest:
            raise ValueError("input pin differs: " + str(file))
    reference = json.loads(args.reference_receipt.read_text(encoding="utf-8-sig"))
    if reference.get("error") or reference.get("cleanup", {}).get("reaped") is not True:
        raise ValueError("complete reaped reference required")
    case = reference["cases"][args.variant]
    if case["execution"]["exit"] != 0:
        raise ValueError("successful reference compile required")
    source = Path(case["outputs"][".dmb"]["path"]).parent
    for name, digest in reference["sourceHashes"].items():
        if name == "probe.dme" and args.variant == "reverse":
            digest = reference["reverseManifestSha256"]
        if h.sha(source / name) != digest:
            raise ValueError("reference source differs: " + name)
    h.safe_e(args.output_root)
    args.output_root.mkdir(parents=True, exist_ok=True)
    root = args.output_root / uuid.uuid4().hex
    root.mkdir()
    command = [str(args.native), "compile", str(source / "probe.dme"), "--workers", "1", "--engine-template", str(args.template), "--bootstrap-catalog", "--no-daemon", "--no-cache", "--exact-inputs", "--artifact-directory", str(root / "artifacts"), "--output-store", str(root / "store"), "--compile-result-file", str(root / "result.json")]
    plan = slot_command("dm_compile", command, Path(__file__).resolve().parents[5], os.environ, label="string chronology native compile-only")
    receipt = {"schema": 1, "scope": "tiny native compile-only; no runtime or parity acceptance", "referenceReceipt": str(args.reference_receipt), "referenceSha256": args.reference_sha256, "nativeSha256": args.native_sha256, "templateSha256": args.template_sha256, "variant": args.variant, "machineSlot": plan["evidence"]}
    job = OwnedJob(4_000_000_000)
    h._owned_job = job
    prior = dict(os.environ)
    try:
        os.environ.clear()
        os.environ.update(plan["environment"])
        receipt["execution"] = h.run_child(Path(plan["command"][0]), plan["command"][1:], root / "compile", time.monotonic() + 30)
        for file, digest in ((args.reference_receipt, args.reference_sha256), (args.native, args.native_sha256), (args.template, args.template_sha256)):
            if h.sha(file) != digest:
                raise ValueError("input pin changed during compile")
        for suffix in (".dmb", ".rsc"):
            file = root / "artifacts" / ("probe" + suffix)
            if file.exists():
                receipt.setdefault("outputs", {})[suffix] = {"path": str(file), "sha256": h.sha(file), "bytes": file.stat().st_size}
    except Exception as error:
        receipt["error"] = str(error)
    finally:
        os.environ.clear()
        os.environ.update(prior)
        receipt["cleanup"] = job.close()
        (root / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(root / "receipt.json")
    return 0 if not receipt.get("error") and receipt.get("execution", {}).get("exit") == 0 and receipt["cleanup"]["reaped"] else 1

if __name__ == "__main__":
    raise SystemExit(main())
