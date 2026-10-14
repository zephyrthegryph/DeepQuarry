"""Pool configuration checks; no images, workers or compiler processes launched."""
import contextlib
import io
import unittest
from pathlib import Path
from unittest.mock import patch

from . import build_step


class IconWorkerTests(unittest.TestCase):
    def test_default_and_explicit_worker_bounds(self):
        self.assertEqual(build_step.configured_workers({}), 4)
        for count in (1, 3, 4, 32):
            self.assertEqual(build_step.configured_workers({"DQ_ICON_WORKERS": str(count)}), count)
        for raw in ("", "0", "-1", "+4", "04", " 4", "4 ", "1.5", "33", "10000", "4" * 5000):
            with self.subTest(raw=raw[:20]):
                with self.assertRaisesRegex(ValueError, "DQ_ICON_WORKERS"):
                    build_step.configured_workers({"DQ_ICON_WORKERS": raw})

    def test_invalid_worker_count_rejects_before_source_scan(self):
        with patch.dict(build_step.os.environ, {"DQ_ICON_WORKERS": "0"}), \
                patch.object(build_step, "_gather_tomls") as gather:
            with self.assertRaisesRegex(ValueError, "DQ_ICON_WORKERS"):
                build_step.run([Path("icons")], Path("E:/dq-cache/fake-icons"))
            gather.assert_not_called()

    def test_actual_pool_construction_uses_configured_count_not_cpu_count(self):
        pools = []

        class FakePool:
            def __init__(self, kind, max_workers):
                pools.append((kind, max_workers))

            def __enter__(self):
                return self

            def __exit__(self, *unused):
                return False

            def map(self, function, values, **unused):
                return map(function, values)

        tomls = [Path("icons") / f"fake{index}.dmi.toml" for index in range(31)]
        for workers, check_workers in ((3, 12), (4, 16), (32, 16)):
            pools.clear()
            with patch.dict(build_step.os.environ, {"DQ_ICON_WORKERS": str(workers)}), \
                    patch.object(build_step.os, "cpu_count", return_value=256), \
                    patch.object(build_step, "_gather_tomls", return_value=tomls), \
                    patch.object(build_step, "_check_one", side_effect=lambda pair: (*pair, True, "fake-hash")), \
                    patch.object(build_step, "_repack_one", side_effect=lambda item: (item[0], None)), \
                    patch.object(build_step, "_sweep_stale", return_value=0), \
                    patch.object(build_step, "ThreadPoolExecutor", side_effect=lambda **kw: FakePool("thread", **kw)), \
                    patch.object(build_step, "ProcessPoolExecutor", side_effect=lambda **kw: FakePool("process", **kw)), \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(build_step.run([Path("icons")], Path("E:/dq-cache/fake-icons")), 0)
            self.assertEqual(pools, [("thread", check_workers), ("process", workers)])


if __name__ == "__main__":
    unittest.main()
