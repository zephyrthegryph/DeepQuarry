import unittest
import host_context


class Kernel:
    def __init__(self, snapshot=99):
        self.snapshot = snapshot
        self.closed = []
        self.rows = [(8, "RUSTC.EXE", 3), (9, "unrelated.exe", 99), (7, "cargo.exe", 2)]
        self.index = 0
        self.error = 0

    def CreateToolhelp32Snapshot(self, flags, pid):
        assert (flags, pid) == (2, 0)
        return self.snapshot

    def row(self, pointer):
        if self.index == len(self.rows):
            self.error = 18
            return False
        entry = pointer._obj
        assert entry.dwSize > 0
        entry.th32ProcessID, entry.szExeFile, entry.cntThreads = self.rows[self.index]
        return True

    def Process32FirstW(self, handle, pointer):
        return self.row(pointer)

    def Process32NextW(self, handle, pointer):
        self.index += 1
        return self.row(pointer)

    def CloseHandle(self, handle):
        self.closed.append(handle)
        return True

    def OpenProcess(self, access, inherit, pid):
        assert access == 0x1000 and inherit is False
        if pid == 8:
            self.error = 5
            return 0
        return pid + 1000

    def GetProcessTimes(self, handle, created, exited, system, user):
        created._obj.low = 123
        system._obj.low = 5_000_000
        user._obj.low = 15_000_000
        return True

    def GetDiskFreeSpaceExW(self, path, available, total, free):
        assert path == "E:\\"
        available._obj.value, total._obj.value, free._obj.value = 12, 30, 15
        return True

    def GlobalMemoryStatusEx(self, pointer):
        assert pointer._obj.dwLength > 0
        pointer._obj.ullAvailPhys, pointer._obj.ullTotalPhys = 100, 200
        return True


class ContextTests(unittest.TestCase):
    def test_named_processes_cpu_disk_memory_and_closed_handles(self):
        kernel = Kernel()
        result = host_context.sample(kernel, lambda: kernel.error)
        self.assertFalse(result["continuous_isolation_proved"])
        self.assertEqual([row["pid"] for row in result["compiler_processes"]], [7, 8])
        self.assertEqual(result["compiler_processes"][0]["cpu_total_s"], 2)
        self.assertEqual(result["compiler_processes"][0]["creation_time_100ns"], 123)
        self.assertIsNone(result["compiler_processes"][1]["cpu_total_s"])
        self.assertEqual(result["compiler_processes"][1]["error"], 5)
        self.assertEqual(kernel.closed, [1007, 99])
        self.assertEqual(result["disk_e"]["total_bytes"], 30)
        self.assertEqual(result["memory"]["available_physical_bytes"], 100)
        self.assertEqual(result["errors"], [])

    def test_invalid_snapshot_never_closes_invalid_handle(self):
        kernel = Kernel(host_context.ctypes.c_void_p(-1).value)
        result = host_context.sample(kernel, lambda: 5)
        self.assertEqual(kernel.closed, [])
        self.assertEqual(result["compiler_processes"], [])
        self.assertIn("process snapshot failed: 5", result["errors"])
        self.assertIn("disk_e", result)

    def test_process_query_failure_closes_its_owned_handle(self):
        kernel = Kernel()
        kernel.GetProcessTimes = lambda *args: False
        result = host_context.process_cpu(kernel, 7, lambda: 5)
        self.assertIsNone(result["cpu_total_s"])
        self.assertEqual(kernel.closed, [1007])

    def test_enumeration_is_bounded_even_if_api_never_ends(self):
        kernel = Kernel()
        kernel.rows = [(9, "unrelated.exe", 1)]
        kernel.Process32NextW = kernel.Process32FirstW
        result = host_context.sample(kernel, lambda: kernel.error)
        self.assertIn("process enumeration limit exceeded", result["errors"])
        self.assertEqual(kernel.closed, [99])

    def test_optional_observation_failure_cannot_abort_a_build(self):
        kernel = Kernel()
        kernel.GetDiskFreeSpaceExW = lambda *args: (_ for _ in ()).throw(OSError("unavailable"))
        result = host_context.sample(kernel, lambda: kernel.error)
        self.assertFalse(result["continuous_isolation_proved"])
        self.assertIn("unavailable", result["errors"][0])
        self.assertIn(99, kernel.closed)


if __name__ == "__main__":
    unittest.main()
