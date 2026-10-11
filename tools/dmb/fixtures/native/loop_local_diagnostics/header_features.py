"""Optional decoded feature gate on the existing owned paired compiler job."""
import importlib.util
from pathlib import Path
import re
import time


def load(file):
    spec = importlib.util.spec_from_file_location("feature_native_fresh", file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def header_flags(text):
    # dmb-detail emits the actual typed Header Debug record on its first line.
    line = next((line for line in text.splitlines() if line.startswith("header=")), "")
    matches = re.findall(r"(?<![\w])flags: (0x[0-9a-fA-F]+|[0-9]+)(?=,| })", line.split(" world=", 1)[0])
    if len(matches) != 1:
        raise ValueError("inspector did not issue one typed header flags field")
    return int(matches[0], 16 if matches[0].startswith("0x") else 10)


def compare(case, directory, sources, capture_files, args, h, bench, deadline, bounded_log):
    fresh = load(bench / "native-fresh.py")
    native = directory / "native"
    byond = directory / "byond" / (case + ".dmb")
    h.regular(byond)
    byond_hash = h.sha(byond)
    result = fresh.read_json(native / "result.json", 65536)
    slots = native / "slots"
    acquired_file = native / "acquired.json"
    evidence = {"scope": "CPU bit 0x1 and graphics bit 0x40 only; no runtime or full input closure",
                "byond": {"path": str(byond), "sha256": byond_hash},
                "published": result, "captured_reference": None}

    def run(executable, arguments, output):
        child = h.run_child(executable, arguments, output,
                            min(deadline, time.monotonic() + 30), cache_directory=directory / "cache")
        if child.get("exit") != 0 or child.get("timeout") or child.get("timed_out"):
            raise ValueError("feature gate child did not complete successfully: " + str(output))
        return child

    evidence["acquire_child"] = run(args.native, ["acquire", "--output-store", str(native / "store"),
        "--pair-id", result["pair_id"], "--slots", str(slots), "--result-file", str(acquired_file)], native / "acquire-child")
    acquired = fresh.read_json(acquired_file, 65536)
    hashes = fresh.admit_pair(result, acquired, native / "artifacts" / (case + ".dme"),
                              native / "store", slots, h.regular, h.sha)
    evidence.update(acquired=acquired, outputs=hashes)
    files = {"native": Path(acquired["dmb"]), "byond": byond}
    # Existing stored receipts bind reference output bytes to their exact sources.
    # New observation controls use this run's separately pinned BYOND compilation.
    captured = sources / (case + ".byond.bin")
    captured_receipt = None
    if captured.exists():
        h.regular(captured)
        for name in capture_files:
            receipt_file = sources / name
            if not receipt_file.exists():
                continue
            receipt = fresh.read_json(receipt_file)
            expected = receipt.get("captured_outputs", {}).get(case) or receipt.get("captured_outputs", {}).get(case + ".byond.bin")
            if expected is None:
                continue
            if (not receipt.get("complete") or receipt.get("pins", {}).get("dm", {}).get("sha256") != args.dm_sha256
                    or receipt.get("cases", {}).get(case, {}).get("byond", {}).get("child", {}).get("exit") != 0):
                raise ValueError("stored BYOND feature capture is not authenticated")
            for suffix in (".dm", ".dme"):
                if receipt["source_sha256"].get(case + suffix) != h.sha(sources / (case + suffix)):
                    raise ValueError("stored BYOND feature source differs")
            if captured.stat().st_size != expected["bytes"] or h.sha(captured) != expected["sha256"]:
                raise ValueError("stored BYOND feature bytes differ")
            captured_receipt = {"path": str(receipt_file), "receipt_sha256": h.sha(receipt_file),
                                "output_path": str(captured), **expected}
            break
        if captured_receipt is None:
            raise ValueError("stored feature output lacks an admitted capture receipt")
        evidence["captured_reference"] = captured_receipt
        files["captured"] = captured
    flags = {}
    for backend, file in files.items():
        output = directory / ("header-" + backend)
        evidence[backend + "_decode_child"] = run(args.feature_inspector, ["dmb-detail", str(file)], output)
        flags[backend] = header_flags(bounded_log(output))
    evidence["flags"] = flags
    evidence["masks"] = {"world_cpu": 1, "graphics_wire_flag": 0x40}
    evidence["matches"] = all((value & 0x41) == (flags["byond"] & 0x41) for value in flags.values())
    if h.sha(byond) != byond_hash:
        raise ValueError("BYOND compiled output changed during feature gate")
    after = fresh.admit_pair(result, acquired, native / "artifacts" / (case + ".dme"),
                            native / "store", slots, h.regular, h.sha)
    if after != hashes:
        raise ValueError("authenticated native pair changed during feature decoding")
    if captured_receipt and (h.sha(captured) != captured_receipt["sha256"] or
                            h.sha(Path(captured_receipt["path"])) != captured_receipt["receipt_sha256"]):
        raise ValueError("stored feature capture changed during decoding")
    return evidence
