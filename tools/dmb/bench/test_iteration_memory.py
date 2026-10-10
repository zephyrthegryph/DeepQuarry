import unittest
from iteration_memory import OwnedMemory, request_concurrency


class Child:
    def __init__(self, value, exited=False):
        self.value = value
        self.exited = exited

    def poll(self):
        return 0 if self.exited else None


class MemoryTests(unittest.TestCase):
    def test_total_owned_memory_exceeds_budget_without_claiming_strict_peak(self):
        guard = OwnedMemory(100, lambda child: child.value)
        daemon, client = Child(70), Child(40)
        guard.register(daemon)
        guard.register(client)
        guard.sample()
        with self.assertRaisesRegex(RuntimeError, "budget exceeded"):
            guard.check()
        receipt = guard.finish()
        self.assertEqual(receipt["sampled_peak_private_bytes"], 110)
        self.assertFalse(receipt["strict_peak_proved"])

    def test_exited_and_unregistered_children_do_not_duplicate_ownership(self):
        guard = OwnedMemory(100, lambda child: child.value)
        daemon, child = Child(60), Child(50, exited=True)
        guard.register(daemon)
        guard.register(daemon)
        guard.register(child)
        guard.sample()
        self.assertEqual(guard.finish()["sampled_peak_private_bytes"], 60)
        guard.unregister(daemon)
        guard.sample()
        guard.check()

    def test_missing_probe_is_explicit_failed_coverage(self):
        def unavailable(_child):
            raise OSError("probe unavailable")
        guard = OwnedMemory(100, unavailable)
        guard.register(Child(1))
        guard.sample()
        with self.assertRaisesRegex(RuntimeError, "coverage unavailable"):
            guard.check()
        self.assertEqual(guard.finish()["errors"], ["probe unavailable"])

    def test_six_clients_queue_but_oneshot_physical_worker_launches_are_bounded(self):
        self.assertEqual(request_concurrency(6, 2, False), 6)
        self.assertEqual(request_concurrency(6, 2, True), 4)
        self.assertEqual(request_concurrency(6, 8, True), 1)
        for workers in (2, 8):
            self.assertLessEqual(request_concurrency(6, workers, True) * workers, 8)


if __name__ == "__main__":
    unittest.main()
