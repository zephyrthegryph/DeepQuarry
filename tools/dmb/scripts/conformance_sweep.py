"""Compile OpenDream's isolated DM tests with both compilers and audit lowering.

This never starts DreamDaemon. Native rejection is recorded separately from a
translator failure; compiler fixtures are evidence, not execution parity proof.
"""
import argparse
import concurrent.futures
import json
import hashlib
import re
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--native", required=True, type=Path)
    parser.add_argument("--compiler", required=True, type=Path)
    parser.add_argument("--inspector", required=True, type=Path)
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--reuse", action="store_true")
    parser.add_argument("--parity-tool", type=Path)
    parser.add_argument("--strip-pragmas", action="store_true",
                        help="Compile identical temporary sources without OpenDream-only diagnostic pragmas")
    args = parser.parse_args()
    compiler_assembly = args.compiler.with_suffix(".dll")
    compiler_digest = hashlib.sha256((compiler_assembly if compiler_assembly.exists() else args.compiler).read_bytes()).hexdigest()
    project = args.source / "Content.Tests/DMProject"
    tests = sorted((project / "Tests").rglob("*.dm"))
    if args.limit:
        tests = tests[:args.limit]
    args.output.mkdir(parents=True, exist_ok=True)

    def run(command, directory, log):
        result = subprocess.run([str(part) for part in command], cwd=directory,
                                capture_output=True, text=True, errors="replace",
                                timeout=120)
        log.write_text(result.stdout + result.stderr, encoding="utf-8")
        return result.returncode

    def case(test):
        relative = test.relative_to(project / "Tests")
        directory = args.output / relative.with_suffix("")
        directory.mkdir(parents=True, exist_ok=True)
        manifest = directory / "probe.dme"
        included = test
        source = test.read_text(encoding="utf-8-sig", errors="surrogateescape") if args.strip_pragmas else ""
        if args.strip_pragmas and re.search(r"(?m)^\s*#pragma\b", source):
            included = directory / "corpus_source.dm"
            source = re.sub(r"(?m)^[ \t]*#pragma[^\r\n]*",
                            "// Diagnostic pragma omitted for paired compiler comparison", source)
            source = re.sub(r'(?m)^(\s*#include\s+)"([^"\r\n]+)"',
                            lambda match: match[1] + '"' + (test.parent / match[2]).resolve().as_posix() + '"', source)
            included.write_text(source, encoding="utf-8", errors="surrogateescape")
        contents = (f'#define FILE_DIR "{project.as_posix()}"\n'
                    f'#define FILE_DIR "{test.parent.as_posix()}"\n'
                    '#undef OPENDREAM\n'
                    '/var/list/conformance_force_516 = alist()\n'
                    f'#include "{included.as_posix()}"\n')
        unchanged = manifest.exists() and manifest.read_text(encoding="utf-8") == contents
        manifest.write_text(contents, encoding="utf-8")
        row = {"test": relative.as_posix(), "directory": str(directory)}
        row["diagnostic_pragmas_removed"] = included != test
        compiler_stamp = directory / "compiler.sha256"
        same_compiler = compiler_stamp.exists() and compiler_stamp.read_text(encoding="utf-8") == compiler_digest
        try:
            if not args.reuse or not unchanged or not (directory / "probe.dmb").exists():
                status = run([args.native, manifest], directory, directory / "native.log")
                if status or not (directory / "probe.dmb").exists():
                    row["status"] = "native_rejected"
                    return row
            if not args.reuse or not unchanged or not same_compiler or not (directory / "probe.json").exists():
                status = run([args.compiler, "--version=516.1687", manifest], directory,
                             directory / "opendream.log")
                if status or not (directory / "probe.json").exists():
                    row["status"] = "opendream_rejected"
                    return row
                compiler_stamp.write_text(compiler_digest, encoding="utf-8")
            status = run([args.inspector, "od-lowering-audit", directory / "probe.json",
                          args.package / "fixtures/native_template_savefile_5161687.json",
                          args.package / "fixtures/native_template.dmb", project,
                          "--debug-lines", "--examples=20"], directory,
                         directory / "lowering.log")
            row["status"] = "lowering_failed" if status else "lowering_passed"
            row["audit"] = (directory / "lowering.log").read_text(encoding="utf-8")
            if status == 0 and args.parity_tool:
                emitted = run([args.inspector, "od-to-dmb", directory / "probe.json",
                               args.package / "fixtures/native_template_savefile_5161687.json",
                               args.package / "fixtures/native_template.dmb", project,
                               directory / "translated.dmb", directory / "translated.rsc"],
                              directory, directory / "emission.log")
                if emitted:
                    row["status"] = "emission_failed"
                    row["emission"] = (directory / "emission.log").read_text(encoding="utf-8")
                else:
                    audited = run([args.inspector, "opcode-audit", directory / "translated.dmb"],
                                  directory, directory / "instruction.log")
                    if audited:
                        row["status"] = "instruction_failed"
                        row["instruction"] = (directory / "instruction.log").read_text(encoding="utf-8")
                    compared = run([args.parity_tool, directory / "probe.dmb",
                                    directory / "translated.dmb", directory / "parity.ndjson",
                                    "--classify", f"--corpus={directory / 'probe.json'}"], directory, directory / "parity.log")
                    row["parity_status"] = compared
                    row["parity"] = (directory / "parity.log").read_text(encoding="utf-8")
        except (OSError, subprocess.SubprocessError) as error:
            row["status"] = "harness_error"
            row["error"] = str(error)
        return row

    counts = {}
    parity_failures = 0
    with (args.output / "sweep.ndjson").open("w", encoding="utf-8") as report:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            for row in pool.map(case, tests):
                if row.get("parity_status", 0):
                    parity_failures += 1
                report.write(json.dumps(row) + "\n")
                report.flush()
                counts[row["status"]] = counts.get(row["status"], 0) + 1
                if sum(counts.values()) % 25 == 0:
                    print(json.dumps(counts), flush=True)
    print(json.dumps(counts), flush=True)
    failures = sum(count for status, count in counts.items()
                   if status not in {"lowering_passed", "native_rejected", "opendream_rejected"})
    if failures or parity_failures:
        print(json.dumps({"translation_failures": failures,
                          "parity_tool_failures": parity_failures}), flush=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
