"""Parser policy only; never launches compilers or runtime."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("list_index_contract", Path(__file__).with_name("run.py"))
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


class Origins(unittest.TestCase):
    def observe(self, origin):
        root = Path("E:/dq-cache/dmb-list-index-policy")
        root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=root) as directory:
            file = Path(directory) / "runtime.log"
            raw = (origin + "\nruntime error: list index out of bounds\nDQ_RETIRE finished\n").encode()
            file.write_bytes(raw)
            result = driver.observations(file)
            self.assertEqual(file.read_bytes(), raw)
            return result

    def test_actual_origin_normalizes_directory_only(self):
        row = self.observe(r"DQ_INDEX_ORIGIN E:\owned\probe.dm|26|list index out of bounds")
        self.assertEqual(row["engine_runtime_origins"], [
            {"source": "probe.dm", "line": 26, "message": "list index out of bounds"}])

    def test_blank_zero_foreign_and_absent_origins_decline(self):
        for origin in ("DQ_INDEX_ORIGIN |0|error", "DQ_INDEX_ORIGIN probe.dm|0|error",
                       "DQ_INDEX_ORIGIN other.dm|26|error", ""):
            with self.subTest(origin=origin), self.assertRaises(ValueError):
                self.observe(origin)


if __name__ == "__main__":
    unittest.main()
