"""Paired real external binding with an authenticated library input."""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import re
import shutil
import sys

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ffi_launcher", HERE.parent / "power_retirement_runtime/run.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)
EXPECTED = ["DQ_FFI direct 1", "DQ_FFI direct_abi 57759af855de3189",
            "DQ_FFI static 1", "DQ_FFI static_abi 57759af855de3189", "DQ_FFI finished"]

def observations(file):
    if file.stat().st_size > 1024 * 1024:
        raise ValueError("external binding log exceeds 1MiB")
    raw = file.read_bytes()
    text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
    markers = [line[line.index("DQ_FFI "):] for line in text.splitlines() if "DQ_FFI " in line]
    if markers != EXPECTED or re.search(r"runtime error:|Runtime in .+?\.dm,\d+:", text, re.IGNORECASE):
        raise ValueError("external bindings failed independent expected values: " + repr(markers))
    return {"markers": markers, "runtimes": []}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--library-sha256", required=True)
    parser.add_argument("--library-name", help="explicit runtime spelling; defaults to authenticated absolute path")
    parser.add_argument("--stage-library", action="store_true", help="stage the pinned library beside each isolated DMB")
    library, remaining = parser.parse_known_args()
    path = library.library.resolve(strict=True)
    if not path.is_file() or not re.fullmatch("[0-9a-f]{64}", library.library_sha256):
        raise ValueError("library pin is invalid")
    def verify():
        if hashlib.sha256(path.read_bytes()).hexdigest() != library.library_sha256:
            raise ValueError("library changed from authenticated pin")
    verify()
    def prepare_runtime(dmb, backend, receipt):
        verify()
        spelling = library.library_name or path.as_posix()
        hosted = None
        if library.stage_library:
            hosted = dmb.parent / path.name
            with hosted.open("xb") as target, path.open("rb") as source:
                shutil.copyfileobj(source, target)
            if hashlib.sha256(hosted.read_bytes()).hexdigest() != library.library_sha256:
                raise ValueError("staged runtime library differs from pin")
            verify()
        receipt.setdefault("pinned_inputs", {})["library"] = {
            "path": str(path), "sha256": library.library_sha256,
            "runtime_spelling": spelling,
            "scope": "same authenticated library bytes and requested spelling for both runtimes"}
        receipt.setdefault("hosted_libraries", {})[backend] = None if hosted is None else str(hosted)
        return ["-params", "library=" + spelling]
    sys.argv = [sys.argv[0], *remaining]
    code = launcher.main(fixture_directory=HERE, observation_reader=observations,
        prepare_runtime=prepare_runtime,
        scope="real load_ext/call_ext direct and procedure-static binding with operand-preserving OR; not game parity")
    verify()
    raise SystemExit(code)
