"""Windows owner job for upgrade children, including client-autostart descendants."""
import time
import ctypes
from ctypes import wintypes

class Limits(ctypes.Structure):
    _fields_ = [("per_process_time", ctypes.c_longlong), ("per_job_time", ctypes.c_longlong),
        ("flags", wintypes.DWORD), ("min_working", ctypes.c_size_t), ("max_working", ctypes.c_size_t),
        ("active", wintypes.DWORD), ("affinity", ctypes.c_size_t), ("priority", wintypes.DWORD), ("scheduling", wintypes.DWORD)]
class Io(ctypes.Structure):
    _fields_ = [(name, ctypes.c_ulonglong) for name in ("read_ops", "write_ops", "other_ops", "read_bytes", "write_bytes", "other_bytes")]
class Extended(ctypes.Structure):
    _fields_ = [("basic", Limits), ("io", Io), ("process_memory", ctypes.c_size_t),
        ("job_memory", ctypes.c_size_t), ("peak_process", ctypes.c_size_t), ("peak_job", ctypes.c_size_t)]
class OwnedJob:
    def __init__(self):
        self.kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        k = self.kernel
        k.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]; k.CreateJobObjectW.restype = wintypes.HANDLE
        k.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
        k.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
        k.IsProcessInJob.argtypes = [wintypes.HANDLE, wintypes.HANDLE, ctypes.POINTER(wintypes.BOOL)]
        k.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]; k.OpenProcess.restype = wintypes.HANDLE
        k.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
        k.CloseHandle.argtypes = [wintypes.HANDLE]
        k.QueryInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD, ctypes.c_void_p]
        k.TerminateJobObject.argtypes = [wintypes.HANDLE, wintypes.UINT]
        self.handle = k.CreateJobObjectW(None, None)
        if not self.handle: raise ctypes.WinError(ctypes.get_last_error())
        limits = Extended(); limits.basic.flags = 0x2000 | 0x200; limits.job_memory = 4_000_000_000
        if not k.SetInformationJobObject(self.handle, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
            self.close(); raise ctypes.WinError(ctypes.get_last_error())
    def add(self, child):
        if not self.kernel.AssignProcessToJobObject(self.handle, int(child._handle)):
            child.kill(); child.wait(timeout=5); raise ctypes.WinError(ctypes.get_last_error())
    def resume(self, child):
        # Popen closes the primary thread handle; enumerate the still-suspended
        # child only, then reopen its primary thread for documented ResumeThread.
        class ThreadEntry(ctypes.Structure):
            _fields_ = [("size", wintypes.DWORD), ("usage", wintypes.DWORD),
                ("thread", wintypes.DWORD), ("owner", wintypes.DWORD),
                ("base", wintypes.LONG), ("delta", wintypes.LONG), ("flags", wintypes.DWORD)]
        k = self.kernel
        k.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD,wintypes.DWORD]; k.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
        k.Thread32First.argtypes = [wintypes.HANDLE,ctypes.POINTER(ThreadEntry)]
        k.Thread32Next.argtypes = [wintypes.HANDLE,ctypes.POINTER(ThreadEntry)]
        k.OpenThread.argtypes = [wintypes.DWORD,wintypes.BOOL,wintypes.DWORD]; k.OpenThread.restype = wintypes.HANDLE
        k.ResumeThread.argtypes = [wintypes.HANDLE]; k.ResumeThread.restype = wintypes.DWORD
        snapshot = k.CreateToolhelp32Snapshot(4,0)
        if snapshot == ctypes.c_void_p(-1).value: raise ctypes.WinError(ctypes.get_last_error())
        try:
            row = ThreadEntry(); row.size = ctypes.sizeof(row); ok = k.Thread32First(snapshot,ctypes.byref(row))
            matches = []
            while ok:
                if row.owner == child.pid: matches.append(row.thread)
                ok = k.Thread32Next(snapshot,ctypes.byref(row))
            if len(matches) != 1: raise RuntimeError("suspended child primary thread is not unique")
            thread = k.OpenThread(2,False,matches[0])
            if not thread: raise ctypes.WinError(ctypes.get_last_error())
            try:
                if k.ResumeThread(thread) != 1: raise RuntimeError("owned primary thread did not resume from one suspension")
            finally: k.CloseHandle(thread)
        finally: k.CloseHandle(snapshot)
    def image(self, pid):
        handle = self.kernel.OpenProcess(0x1000, False, pid)
        if not handle: raise ctypes.WinError(ctypes.get_last_error())
        try:
            member = wintypes.BOOL()
            if not self.kernel.IsProcessInJob(handle, self.handle, ctypes.byref(member)) or not member.value:
                raise RuntimeError("endpoint PID is not an owned upgrade descendant")
            size = wintypes.DWORD(32768); name = ctypes.create_unicode_buffer(size.value)
            if not self.kernel.QueryFullProcessImageNameW(handle, 0, name, ctypes.byref(size)):
                raise ctypes.WinError(ctypes.get_last_error())
            return name.value
        finally: self.kernel.CloseHandle(handle)
    def close(self):
        receipt = {"reaped": False, "error": None}
        if not self.handle: return {"reaped": True, "error": None}
        try:
            if not self.kernel.TerminateJobObject(self.handle, 1): raise ctypes.WinError(ctypes.get_last_error())
            # JOBOBJECT_BASIC_ACCOUNTING_INFORMATION: four 64-bit time counters,
            # then page faults, total processes, active processes and terminated.
            counters = ctypes.create_string_buffer(48)
            deadline = time.monotonic() + 5
            while True:
                if not self.kernel.QueryInformationJobObject(self.handle, 1, counters, 48, None):
                    raise ctypes.WinError(ctypes.get_last_error())
                active = ctypes.c_uint32.from_buffer(counters, 40).value
                if active == 0: receipt["reaped"] = True; break
                if time.monotonic() >= deadline: raise TimeoutError("owned job descendants did not exit")
                time.sleep(.01)
        except Exception as error: receipt["error"] = str(error)
        finally:
            self.kernel.CloseHandle(self.handle); self.handle = None
        return receipt
