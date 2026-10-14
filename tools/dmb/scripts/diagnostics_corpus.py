#!/usr/bin/env python3
"""Diagnostic parity corpus for the native compiler.

Each `fixtures/diagnostics/cases/NAME.dm` is compiled alone through a
generated `NAME.dme`. `record` stores DreamMaker's output as
`fixtures/diagnostics/expected/NAME.txt`; `check` runs `dmbc` on the same
input and compares normalized output (only diagnostic and summary lines kept,
summary timestamp removed). Exit status is 0 only when every case matches,
unless `--report` is given.

  python tools/dmb/scripts/diagnostics_corpus.py record --dm "D:/Program Files (x86)/BYOND516/bin/dm.exe"
  python tools/dmb/scripts/diagnostics_corpus.py check --dmbc tools/dmb/target/release/dmbc.exe [--report]
"""
import argparse
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
CORPUS = ROOT / "fixtures" / "diagnostics"
TEMPLATE = ROOT / "fixtures" / "native_template.bin"
# DreamMaker diagnostics, the native compiler's own classified lines and the
# summary; telemetry and progress lines are not part of the contract.
KEEP = re.compile(r"^([^\s:][^:]*(:\d+)?:(error|warning|native|internal)|\S+\.dmb - \d+ errors?, \d+ warnings?)")
STAMP = re.compile(r" \(\d+/\d+/\d+ \d+:\d+ [ap]m\)$")


def normalize(text: str) -> str:
    lines = []
    for line in text.replace("\r\n", "\n").split("\n"):
        line = line.rstrip()
        if not KEEP.match(line):
            continue
        lines.append(STAMP.sub("", line))
    return "\n".join(lines) + "\n"


def stage(case: pathlib.Path, directory: pathlib.Path) -> pathlib.Path:
    shutil.copy(case, directory / case.name)
    dme = directory / f"{case.stem}.dme"
    dme.write_text(f'#include "{case.name}"\n', encoding="utf-8")
    return dme


def run(command, cwd) -> str:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, errors="replace")
    return result.stdout + result.stderr


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["record", "check"])
    parser.add_argument("--dm")
    parser.add_argument("--dmbc")
    parser.add_argument("--report", action="store_true", help="always exit 0; print mismatches")
    parser.add_argument("cases", nargs="*")
    args = parser.parse_args()
    if args.dmbc:
        args.dmbc = str(pathlib.Path(args.dmbc).resolve())
    cases = sorted((CORPUS / "cases").glob("*.dm"))
    if args.cases:
        cases = [case for case in cases if case.stem in args.cases]
    expected_dir = CORPUS / "expected"
    expected_dir.mkdir(exist_ok=True)
    matched, mismatched = 0, []
    for case in cases:
        with tempfile.TemporaryDirectory() as temp:
            directory = pathlib.Path(temp)
            dme = stage(case, directory)
            if args.mode == "record":
                output = normalize(run([args.dm, dme.name], directory))
                (expected_dir / f"{case.stem}.txt").write_text(output, encoding="utf-8", newline="\n")
                continue
            output = normalize(run([args.dmbc, "compile", dme.name, "--engine-template", str(TEMPLATE), "--no-daemon"], directory))
        expected = (expected_dir / f"{case.stem}.txt").read_text(encoding="utf-8")
        if output == expected:
            matched += 1
        else:
            mismatched.append((case.stem, expected, output))
    if args.mode == "record":
        print(f"recorded {len(cases)} cases")
        return 0
    for name, expected, output in mismatched:
        print(f"--- {name}\n  expected:\n" + "".join(f"    {l}\n" for l in expected.splitlines())
              + "  native:\n" + "".join(f"    {l}\n" for l in output.splitlines()))
    print(f"diagnostic corpus: {matched}/{len(cases)} match")
    return 0 if args.report or not mismatched else 1


if __name__ == "__main__":
    sys.exit(main())
