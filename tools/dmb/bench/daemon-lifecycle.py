"""Windows owned-daemon lifecycle functionality probe; no runtime/performance claim.

Direct protocol retirement exercises draining but does not certify automatic
client upgrade between distinct compiler binaries. All outputs get a fresh oracle.
"""
import argparse
import ctypes
import importlib.util
import json
import msvcrt
import os
from pathlib import Path
import struct
import subprocess
import time
import uuid
from watchdog import terminate_owned

_spec = importlib.util.spec_from_file_location("native_iteration", Path(__file__).with_name("native-iteration.py"))
iteration = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(iteration)


class Pipe:
    def __init__(self, endpoint, owner):
        self.endpoint = endpoint
        self.deadline = time.monotonic() + 300
        while True:
            if owner.poll() is not None:
                raise RuntimeError("owned daemon exited before connection")
            handle = endpoint.kernel.CreateFileW(endpoint.name, 0xc0000000, 0, None, 3, 0, None)
            if handle != ctypes.c_void_p(-1).value:
                break
            if ctypes.get_last_error() not in (2, 231) or time.monotonic() >= self.deadline:
                raise RuntimeError("owned endpoint failed to become available")
            time.sleep(.02)
        pid = ctypes.wintypes.ULONG()
        if not endpoint.kernel.GetNamedPipeServerProcessId(handle, ctypes.byref(pid)) or pid.value != owner.pid:
            endpoint.kernel.CloseHandle(handle)
            raise RuntimeError("replacement or foreign daemon refused")
        self.handle = handle
        self.file = os.fdopen(msvcrt.open_osfhandle(handle, os.O_BINARY), "r+b", buffering=0)
        endpoint.kernel.PeekNamedPipe.argtypes = [ctypes.wintypes.HANDLE, ctypes.c_void_p,
            ctypes.wintypes.DWORD, ctypes.c_void_p, ctypes.POINTER(ctypes.wintypes.DWORD), ctypes.c_void_p]
        self.send({"Hello": {"version": 2, "compiler": 0}})
        hello = self.receive()["Hello"]
        if hello["version"] != 2 or hello["retiring"]:
            self.close()
            raise RuntimeError("unexpected daemon generation state")
        self.compiler = hello["compiler"]
        # The first mismatched Hello cannot Build. Reconnect with exact identity.
        self.close()
        self.reconnect(endpoint, owner)

    def reconnect(self, endpoint, owner):
        deadline = self.deadline
        while True:
            handle = endpoint.kernel.CreateFileW(endpoint.name, 0xc0000000, 0, None, 3, 0, None)
            if handle != ctypes.c_void_p(-1).value:
                break
            if owner.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError("owned daemon reconnection deadline")
            time.sleep(.02)
        pid = ctypes.wintypes.ULONG()
        if not endpoint.kernel.GetNamedPipeServerProcessId(handle, ctypes.byref(pid)) or pid.value != owner.pid:
            endpoint.kernel.CloseHandle(handle)
            raise RuntimeError("foreign daemon refused")
        self.handle = handle
        self.file = os.fdopen(msvcrt.open_osfhandle(handle, os.O_BINARY), "r+b", buffering=0)
        self.send({"Hello": {"version": 2, "compiler": self.compiler}})
        if self.receive()["Hello"] != {"version": 2, "compiler": self.compiler, "retiring": False}:
            raise RuntimeError("generation changed during handshake")

    def close(self):
        self.file.close()

    def send(self, value):
        data = json.dumps(value).encode()
        if len(data) > 4 * 1024 * 1024:
            raise ValueError("oversized protocol frame")
        self.file.write(struct.pack("<I", len(data)) + data)

    def read(self, length):
        result = bytearray()
        while len(result) < length:
            available = ctypes.wintypes.DWORD()
            if not self.endpoint.kernel.PeekNamedPipe(self.handle, None, 0, None, ctypes.byref(available), None):
                raise OSError(ctypes.get_last_error(), "owned pipe disconnected")
            if available.value:
                result.extend(self.file.read(min(available.value, length - len(result))))
            elif time.monotonic() >= self.deadline:
                raise TimeoutError("owned protocol child exceeded 300 seconds")
            else:
                time.sleep(.01)
        return result

    def receive(self):
        length = struct.unpack("<I", self.read(4))[0]
        if length > 4 * 1024 * 1024:
            raise ValueError("oversized daemon frame")
        return json.loads(self.read(length))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--template", required=True)
    parser.add_argument("--output-root", default="E:/dq-cache/dmb-lifecycle")
    args = parser.parse_args()
    root = iteration.safe_e(args.output_root) / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
    if not root.is_relative_to(Path("E:/dq-cache")):
        raise ValueError("owned outputs must be beneath E:/dq-cache")
    compiler, template = iteration.safe_e(args.compiler), iteration.safe_e(args.template)
    iteration.regular(compiler); iteration.regular(template)
    endpoint = iteration.Endpoint()
    endpoint.probe()  # Refuse any pre-existing daemon without retiring it.
    root.mkdir(parents=True)
    source = root / "source"; source.mkdir()
    project = source / "world.dme"
    project.write_text('/world\n    name = "lifecycle"\n/proc/lifecycle_value()\n    return 42\n', encoding="utf-8")
    environment = os.environ.copy(); environment["DMB_CACHE_DIR"] = str(root / "cache")
    owned = []
    report = {"schema_version": 1, "status": "running", "scope": "direct protocol retirement, owned crash restart and fresh byte oracle; not version-upgrade autostart, runtime or performance acceptance", "compiler_sha256": iteration.sha(compiler), "template_sha256": iteration.sha(template)}
    def start(name):
        with (root / (name + ".stdout")).open("xb") as out, (root / (name + ".stderr")).open("xb") as err:
            child = subprocess.Popen([str(compiler), "--serve-daemon"], stdout=out, stderr=err, env=environment, creationflags=subprocess.CREATE_NO_WINDOW)
        owned.append(child)
        return child
    def build(owner, name, retire=False):
        artifacts = root / name / "artifacts"
        request = dict(command="Compile", project=str(project), defines={}, workers=2,
            engine_template=str(template), bootstrap_catalog=True, progress_enabled=True,
            output_store=str(root / name / "store"), exact_inputs=True, no_cache=False,
            cache_root=str(root / "cache"), record_inputs=None, replay_inputs=None,
            artifact_directory=str(artifacts), no_daemon=False, trace_path=None)
        pipe = Pipe(endpoint, owner)
        try:
            pipe.send({"Build": request})
            retired = False
            while True:
                reply = pipe.receive()
                if isinstance(reply, dict) and "Diagnostic" in reply and retire and not retired:
                    control = Pipe(endpoint, owner)
                    try:
                        control.send("Retire")
                        if control.receive() != "Retiring":
                            raise RuntimeError("retirement was not acknowledged")
                        retired = True
                    finally:
                        control.close()
                if isinstance(reply, dict) and "Rejected" in reply:
                    raise RuntimeError(str(reply))
                if isinstance(reply, dict) and "Completed" in reply:
                    if retire and not retired:
                        raise RuntimeError("tiny build missed active retirement window; no drain claim")
                    result = reply["Completed"]
                    if "Published" not in result:
                        raise RuntimeError("compile did not issue published pair")
                    report[name] = {"published": result["Published"], "retirement_acknowledged_before_completion_received": retired}
                    return artifacts
        finally:
            pipe.close()
    try:
        first = start("initial-daemon")
        build(first, "drained", True)
        if first.wait(timeout=300) != 0:
            raise RuntimeError("retiring daemon did not exit successfully")
        second = start("replacement-daemon")
        build(second, "replacement")
        report["owned_crash"] = terminate_owned(second)
        if not report["owned_crash"]["reaped"]:
            raise RuntimeError("owned crash process could not be reaped")
        third = start("recovered-daemon")
        build(third, "recovered")
        fresh = root / "fresh"
        child = iteration.run_child(compiler, ["compile", str(project), "--engine-template", str(template), "--bootstrap-catalog", "--workers", "2", "--no-daemon", "--no-cache", "--exact-inputs", "--artifact-directory", str(fresh / "artifacts"), "--output-store", str(fresh / "store")], root / "fresh-logs", time.monotonic() + 300, cache_directory=root / "cache")
        if child["exit"] != 0:
            raise RuntimeError("independent fresh oracle failed")
        for name in ("drained", "replacement", "recovered"):
            report[name]["hashes"] = iteration.check_outputs(root / name, fresh, Path("world.dme"))
        report["status"] = "passed"
    except Exception as error:
        report["status"] = "failed"; report["error"] = str(error)
    finally:
        report["cleanup"] = [terminate_owned(child) for child in owned if child.poll() is None]
        (root / "receipt.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(json.dumps({"receipt": str(root / "receipt.json"), "status": report["status"]}))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
