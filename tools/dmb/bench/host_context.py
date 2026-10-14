"""Boundary-only Windows host observations; never continuous isolation proof."""
import ctypes
from ctypes import wintypes
import os
import time


class ProcessEntry(ctypes.Structure):
    _fields_ = [("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD),
                ("th32ProcessID", wintypes.DWORD), ("th32DefaultHeapID", ctypes.c_size_t),
                ("th32ModuleID", wintypes.DWORD), ("cntThreads", wintypes.DWORD),
                ("th32ParentProcessID", wintypes.DWORD), ("pcPriClassBase", wintypes.LONG),
                ("dwFlags", wintypes.DWORD), ("szExeFile", wintypes.WCHAR * 260)]


class MemoryStatus(ctypes.Structure):
    _fields_ = [("dwLength", wintypes.DWORD), ("dwMemoryLoad", wintypes.DWORD)] + [
        (name, ctypes.c_ulonglong) for name in ("ullTotalPhys", "ullAvailPhys",
        "ullTotalPageFile", "ullAvailPageFile", "ullTotalVirtual", "ullAvailVirtual",
        "ullAvailExtendedVirtual")]


class FileTime(ctypes.Structure):
    _fields_ = [("low", wintypes.DWORD), ("high", wintypes.DWORD)]
    def ticks(self):
        return (int(self.high) << 32) | int(self.low)


def process_cpu(kernel, pid, error):
    handle = kernel.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        return {"cpu_total_s": None, "error": error()}
    try:
        created, exited, system, user = (FileTime() for _ in range(4))
        if not kernel.GetProcessTimes(handle, ctypes.byref(created), ctypes.byref(exited), ctypes.byref(system), ctypes.byref(user)):
            return {"cpu_total_s": None, "error": error()}
        return {"cpu_total_s": (system.ticks() + user.ticks()) / 10_000_000,
                "creation_time_100ns": created.ticks()}
    finally:
        kernel.CloseHandle(handle)


def _kernel():
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    declarations = {
        "CreateToolhelp32Snapshot": ([wintypes.DWORD, wintypes.DWORD], wintypes.HANDLE),
        "Process32FirstW": ([wintypes.HANDLE, ctypes.POINTER(ProcessEntry)], wintypes.BOOL),
        "Process32NextW": ([wintypes.HANDLE, ctypes.POINTER(ProcessEntry)], wintypes.BOOL),
        "OpenProcess": ([wintypes.DWORD, wintypes.BOOL, wintypes.DWORD], wintypes.HANDLE),
        "GetProcessTimes": ([wintypes.HANDLE] + [ctypes.POINTER(FileTime)] * 4, wintypes.BOOL),
        "CloseHandle": ([wintypes.HANDLE], wintypes.BOOL),
        "GetDiskFreeSpaceExW": ([wintypes.LPCWSTR] + [ctypes.POINTER(ctypes.c_ulonglong)] * 3, wintypes.BOOL),
        "GlobalMemoryStatusEx": ([ctypes.POINTER(MemoryStatus)], wintypes.BOOL),
    }
    for name, (arguments, result) in declarations.items():
        function = getattr(kernel, name)
        function.argtypes, function.restype = arguments, result
    return kernel


def _sample(kernel=None, last_error=None):
    result = {"schema": "dm-host-boundary-context-v1", "sample_unix_s": time.time(),
              "scope": "boundary-only sample; not proof of continuous isolation",
              "continuous_isolation_proved": False, "compiler_processes": [], "errors": []}
    if kernel is None:
        if os.name != "nt":
            result["errors"].append("Windows host APIs unavailable")
            return result
        kernel = _kernel()
    error = last_error or ctypes.get_last_error
    handle = kernel.CreateToolhelp32Snapshot(2, 0)  # TH32CS_SNAPPROCESS
    if handle == ctypes.c_void_p(-1).value:
        result["errors"].append(f"process snapshot failed: {error()}")
    else:
        try:
            entry = ProcessEntry()
            entry.dwSize = ctypes.sizeof(entry)
            available = kernel.Process32FirstW(handle, ctypes.byref(entry))
            count = 0
            while available:
                count += 1
                if count > 10000:
                    result["errors"].append("process enumeration limit exceeded")
                    break
                if entry.szExeFile.casefold() in ("cargo.exe", "rustc.exe"):
                    result["compiler_processes"].append({"pid": int(entry.th32ProcessID),
                        "name": entry.szExeFile, "thread_count": int(entry.cntThreads),
                        **process_cpu(kernel, int(entry.th32ProcessID), error)})
                available = kernel.Process32NextW(handle, ctypes.byref(entry))
            if not available and error() != 18:  # ERROR_NO_MORE_FILES
                result["errors"].append(f"process enumeration failed: {error()}")
        finally:
            if not kernel.CloseHandle(handle):
                result["errors"].append(f"process snapshot close failed: {error()}")
    result["compiler_processes"].sort(key=lambda row: row["pid"])
    free, total, total_free = (ctypes.c_ulonglong() for _ in range(3))
    if kernel.GetDiskFreeSpaceExW("E:\\", ctypes.byref(free), ctypes.byref(total), ctypes.byref(total_free)):
        result["disk_e"] = {"available_bytes": free.value, "total_bytes": total.value,
                            "total_free_bytes": total_free.value}
    else:
        result["errors"].append(f"E: disk sample failed: {error()}")
    memory = MemoryStatus()
    memory.dwLength = ctypes.sizeof(memory)
    if kernel.GlobalMemoryStatusEx(ctypes.byref(memory)):
        result["memory"] = {"available_physical_bytes": int(memory.ullAvailPhys),
                            "total_physical_bytes": int(memory.ullTotalPhys)}
    else:
        result["errors"].append(f"memory sample failed: {error()}")
    return result


def sample(kernel=None, last_error=None):
    try:
        return _sample(kernel, last_error)
    except Exception as failure:
        # Optional evidence must not change the compiler run or its result.
        return {"schema": "dm-host-boundary-context-v1", "sample_unix_s": time.time(),
                "scope": "boundary-only sample; not proof of continuous isolation",
                "continuous_isolation_proved": False, "compiler_processes": [],
                "errors": [f"host context unavailable: {failure}"]}
