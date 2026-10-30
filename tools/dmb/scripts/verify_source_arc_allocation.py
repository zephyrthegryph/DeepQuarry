"""Headless allocator proof against one successful Cargo-issued profile."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def invoke(argv, env, seconds):
    flags = 0
    if os.name == "nt":
        flags = subprocess.BELOW_NORMAL_PRIORITY_CLASS | subprocess.CREATE_NO_WINDOW
    result = subprocess.run(argv, env=env, capture_output=True, text=True,
                            encoding="utf8", timeout=seconds, creationflags=flags)
    if result.returncode:
        raise RuntimeError(f"{argv[0]} failed ({result.returncode})\n"
                           f"{result.stdout}\n{result.stderr}")
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--build-json", type=Path, required=True)
    p.add_argument("--receipt", type=Path, required=True)
    a = p.parse_args()
    root = Path.cwd().resolve()
    crate = root / "tools/dmb/crates/dmbc"
    rows = [json.loads(line) for line in a.build_json.read_text().splitlines() if line.strip()]
    if not any(r.get("reason") == "build-finished" and r.get("success") for r in rows):
        raise RuntimeError("The selected Cargo build did not succeed")
    scripts = [r for r in rows if r.get("reason") == "compiler-artifact"
               and "custom-build" in r.get("target", {}).get("kind", [])
               and Path(r["target"]["src_path"]).resolve() == (crate / "build.rs").resolve()]
    if len(scripts) != 1:
        raise RuntimeError("Expected exactly this checkout's dmbc build script")
    package = scripts[0]["package_id"]
    outputs = [r for r in rows if r.get("reason") == "build-script-executed"
               and r.get("package_id") == package]
    if len(outputs) != 1:
        raise RuntimeError("Expected one exact Cargo OUT_DIR")
    out_dir = Path(outputs[0]["out_dir"]).resolve()
    profile_file = out_dir / "native_arc_profile.rs"
    fields = {}
    for name, raw in re.findall(r"^pub const (\w+):(?:bool|&str)=(.*);$",
                                profile_file.read_text(), re.M):
        fields[name] = json.loads(raw)
    if fields.get("CANDIDATE_MATCHED") is not True:
        raise RuntimeError("Cargo's actual compiler has no audited candidate contract")
    rustc = Path(fields["CARGO_RUSTC_PATH"])
    if not rustc.is_absolute() or not rustc.is_file():
        raise RuntimeError("Cargo did not seal an existing absolute compiler")
    target = fields["CARGO_TARGET"]
    env = dict(os.environ, OUT_DIR=str(out_dir))
    verbose = invoke([str(rustc), "-vV"], env, 15).stdout
    version = dict(line.split(": ", 1) for line in verbose.splitlines() if ": " in line)
    sysroot = Path(invoke([str(rustc), "--print", "sysroot"], env, 15).stdout.strip()).resolve()
    libdir = Path(invoke([str(rustc), "--print", "target-libdir", "--target", target], env, 15).stdout.strip()).resolve()
    if sysroot != Path(fields["SYSROOT"]).resolve() or libdir != Path(fields["TARGET_LIBDIR"]).resolve():
        raise RuntimeError("Probe compiler differs from Cargo's sealed sysroot/target")
    allocs = list(libdir.glob("liballoc-*.rlib"))
    if len(allocs) != 1 or allocs[0].resolve() != Path(fields["LIBALLOC_ARTIFACT"]).resolve():
        raise RuntimeError("Target liballoc roster differs from Cargo's sealed artifact")
    sync = sysroot / "lib/rustlib/src/rust/library/alloc/src/sync.rs"
    actual = "|".join([version["commit-hash"], version["release"], target, "64",
                       digest(sync), digest(allocs[0])])
    if actual != fields["DESCRIPTION"]:
        raise RuntimeError("Actual compiler/source/artifact tuple differs from Cargo's receipt")
    probe_source = root / "tools/dmb/tests/source_arc_allocation_probe.rs"
    files = [rustc, sync, allocs[0], profile_file, probe_source,
             crate / "build.rs", crate / "source_arc_profile_policy.rs",
             crate / "src/query_db/native_arc_allocation.rs",
             crate / "src/query_db/no_weak_arc_owner.rs"]
    before = {str(f.resolve()): digest(f) for f in files}
    wrapper = shutil.which(env.get("RUSTC_WRAPPER", "sccache"))
    if not wrapper:
        raise RuntimeError("The existing compiler cache wrapper is unavailable")
    binary = out_dir.parents[2] / "deps/source_arc_allocation_probe.exe"
    if not binary.parent.is_dir():
        raise RuntimeError("The selected Cargo target has no existing artifact directory")
    command = [wrapper, str(rustc), "--edition=2021", "--cfg", "dmb_arc_probe",
               "--check-cfg", "cfg(dmb_arc_probe)", "--target", target,
               "-C", "opt-level=0", "-C", "debuginfo=0", str(probe_source), "-o", str(binary)]
    compile_result = invoke(command, env, 45)
    probe = invoke([str(binary)], env, 20)
    result = json.loads(probe.stdout)
    if result.get("matched") is not True or len(result.get("cases", [])) != 9:
        raise RuntimeError("The complete nine-case allocator proof did not pass")
    after = {str(f.resolve()): digest(f) for f in files}
    if before != after:
        raise RuntimeError("Compiler/profile/probe inputs changed during the proof")
    receipt = dict(scope="actual-headless-standalone-allocator-proof", matched=True,
                   production_permission_issued=False, cargo_package=package,
                   cargo_build_json_sha256=digest(a.build_json), cargo_out_dir=str(out_dir),
                   cargo_profile=fields, rustc_verbose=verbose, input_hashes=before,
                   command=command, binary=str(binary), binary_sha256=digest(binary),
                   compile_stdout=compile_result.stdout, compile_stderr=compile_result.stderr,
                   probe_stdout=probe.stdout, probe_stderr=probe.stderr, result=result)
    a.receipt.write_text(json.dumps(receipt, indent=2), encoding="utf8")
    print(json.dumps(dict(matched=True, cases=len(result["cases"]),
                          receipt=str(a.receipt), production_permission_issued=False)))


if __name__ == "__main__":
    main()
