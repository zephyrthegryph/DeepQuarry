"""Sample only caller-owned Windows process handles; never a strict peak proof."""
import ctypes
from ctypes import wintypes
import threading


def request_concurrency(projects, workers, one_shot):
    if not 1 <= workers <= 8 or not 1 <= projects <= 6:
        raise ValueError("bounded request dimensions required")
    return min(projects, 8 // workers) if one_shot else projects


def iteration_concurrency(kind, projects, workers, one_shot, total_workers):
    if not workers <= total_workers <= 8:
        raise ValueError("active worker budget must cover a request and stay bounded")
    clients = request_concurrency(projects, workers, one_shot)
    # Cold population is deliberately bounded. Once populated, real concurrent
    # daemon clients queue independently of the server's physical worker limit.
    return min(clients, total_workers // workers) if one_shot or kind == 'initial' else clients


class Counters(ctypes.Structure):
    _fields_ = [("cb", wintypes.DWORD), ("faults", wintypes.DWORD)] + [
        (name, ctypes.c_size_t) for name in ("peak_working", "working", "peak_paged",
        "paged", "peak_nonpaged", "nonpaged", "pagefile", "peak_pagefile", "private")]


def private_bytes(child):
    # Popen retains the exact Windows process handle. No PID reopening can
    # accidentally observe a replacement process after the owned child exits.
    handle = getattr(child, "_handle", None)
    if handle is None:
        raise RuntimeError("owned Windows process handle unavailable")
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetProcessId.argtypes = [wintypes.HANDLE]
    kernel.GetProcessId.restype = wintypes.DWORD
    if kernel.GetProcessId(int(handle)) != child.pid:
        raise RuntimeError("owned process handle identity differs")
    library = ctypes.WinDLL("psapi", use_last_error=True)
    library.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
    library.GetProcessMemoryInfo.restype = wintypes.BOOL
    counters = Counters()
    counters.cb = ctypes.sizeof(counters)
    if not library.GetProcessMemoryInfo(int(handle), ctypes.byref(counters), counters.cb):
        raise OSError(ctypes.get_last_error(), "owned private-memory sample failed")
    return int(counters.private)


class OwnedMemory:
    def __init__(self, budget, probe=private_bytes):
        self.budget = budget
        self.probe = probe
        self.lock = threading.Lock()
        self.children = {}
        self.stopped = threading.Event()
        self.failed = threading.Event()
        self.peak = 0
        self.peak_processes = []
        self.samples = 0
        self.errors = []
        self.reason = None
        self.thread = None

    def register(self, child):
        with self.lock:
            self.children[id(child)] = child
        self.check()

    def unregister(self, child):
        with self.lock:
            self.children.pop(id(child), None)

    def sample(self):
        with self.lock:
            children = list(self.children.values())
        try:
            processes = [{"pid": getattr(child, "pid", None),
                "private_bytes": self.probe(child)}
                for child in children if child.poll() is None]
            total = sum(row["private_bytes"] for row in processes)
        except Exception as error:
            with self.lock:
                if len(self.errors) < 8:
                    self.errors.append(str(error))
                self.reason = "owned memory coverage unavailable"
                self.failed.set()
            return
        with self.lock:
            self.samples += 1
            if total > self.peak:
                self.peak = total
                self.peak_processes = processes
            if total > self.budget:
                self.reason = "sampled owned private-memory budget exceeded"
                self.failed.set()

    def check(self):
        if self.failed.is_set():
            raise RuntimeError(self.reason)

    def start(self):
        self.sample()
        self.check()
        def loop():
            while not self.stopped.wait(0.2):
                self.sample()
        self.thread = threading.Thread(target=loop, name="owned-memory-sampler", daemon=True)
        self.thread.start()

    def finish(self):
        self.stopped.set()
        if self.thread is not None:
            self.thread.join(timeout=2)
        with self.lock:
            if self.thread is not None and self.thread.is_alive():
                self.reason = "owned memory sampler did not stop within bound"
                self.failed.set()
            return {"schema": "dm-owned-memory-samples-v1", "budget_bytes": self.budget,
                "sampled_peak_private_bytes": self.peak, "samples": self.samples,
                "processes_at_sampled_peak": list(self.peak_processes),
                "sample_interval_s": 0.2, "status": "failed" if self.failed.is_set() else "sampled",
                "reason": self.reason, "errors": list(self.errors),
                "strict_peak_proved": False,
                "scope": "owned daemon and registered harness children (compiler/client/inspector); 200ms samples include observation overhead; excludes unrelated processes and unregistered descendants"}
