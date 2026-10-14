"""One independently captured registration variant through the existing runner."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
CAPTURE = json.loads((HERE / "registration_cases/capture.json").read_text())


def validate_sources(case):
    directory = HERE / "registration_cases" / case
    expected = CAPTURE["cases"][case]
    for name, field in (("probe.dm", "source_sha256"),
                        ("probe.dme", "manifest_sha256")):
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != expected[field]:
            raise ValueError("registration source differs from pinned capture: " + name)
    receipt = directory / "discovery_receipt.json"
    if hashlib.sha256(receipt.read_bytes()).hexdigest() != expected["reference_receipt_sha256"]:
        raise ValueError("registration discovery receipt changed")
    return directory


def read_observations(file, expected):
    if file.stat().st_size > 1024 * 1024:
        raise ValueError("registration fixture log exceeds 1MiB")
    raw = file.read_bytes()
    text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
    markers = [line[line.index("DQ_REGISTER "):]
               for line in text.splitlines() if "DQ_REGISTER " in line]
    if re.search(r"Runtime in .+?\.dm,\d+:|runtime error:", text, re.IGNORECASE):
        raise ValueError("registration fixture recorded a runtime")
    if markers != expected:
        raise ValueError("registration differs from independent BYOND expectation: " + repr(markers))
    return {"markers": markers, "runtimes": []}


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--case", choices=sorted(CAPTURE["cases"]), required=True)
    args, remaining = parser.parse_known_args()
    directory = validate_sources(args.case)
    spec = importlib.util.spec_from_file_location(
        "registration_launcher", HERE.parent / "power_retirement_runtime/run.py")
    launcher = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(launcher)
    # Keep the common launcher's exact pinning, memory, deadline and popup policy.
    sys.argv = [sys.argv[0], *remaining]
    expected = CAPTURE["cases"][args.case]["expected"]
    return launcher.main(fixture_directory=directory,
        observation_reader=lambda file: read_observations(file, expected),
        scope="strict pinned BYOND registration variant " + args.case
              + "; not whole-program or complete allocation parity")


if __name__ == "__main__":
    raise SystemExit(main())
