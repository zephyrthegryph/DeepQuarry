"""Fake API cleanup checks only; not actual daemon upgrade coverage."""
import ctypes
import unittest
from upgrade_owned_job import OwnedJob

class Kernel:
    def __init__(self, fail=False): self.fail = fail; self.closed = []; self.terminated = []; self.samples = 0
    def TerminateJobObject(self, handle, status): self.terminated.append((handle,status)); return True
    def QueryInformationJobObject(self, handle, kind, counters, size, written):
        self.samples += 1
        if self.fail: raise OSError("query failed")
        ctypes.c_uint32.from_buffer(counters,40).value = 0
        return True
    def CloseHandle(self, handle): self.closed.append(handle)

class Tests(unittest.TestCase):
    def owner(self, kernel):
        owner = OwnedJob.__new__(OwnedJob); owner.kernel = kernel; owner.handle = 71; return owner
    def test_job_reap_proof_and_handle_cleanup(self):
        kernel = Kernel(); owner = self.owner(kernel)
        self.assertTrue(owner.close()["reaped"])
        self.assertEqual(kernel.terminated, [(71,1)])
        self.assertEqual(kernel.closed,[71]); self.assertIsNone(owner.handle)
    def test_failed_reap_query_never_claims_cleanup(self):
        kernel = Kernel(True); owner = self.owner(kernel)
        result = owner.close()
        self.assertFalse(result["reaped"]); self.assertIn("query failed",result["error"])
        self.assertEqual(kernel.closed,[71])

if __name__ == "__main__": unittest.main()
