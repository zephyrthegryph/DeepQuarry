"""Focused fixtures; not executed by this change."""
import json
from pathlib import Path
import tempfile
import unittest
from normalize_runtime import identity, read_runtime

class RuntimeNormalization(unittest.TestCase):
    def test_keeps_location_while_stripping_dynamic_values(self):
        key=identity("runtime error: value 42 at [0x123]\nproc name: example (/proc/example)\n  source file: code/example.dm,17\n")
        self.assertEqual(key,("value <number> at <ref>","/proc/example","code/example.dm",17))

    def test_structured_log_does_not_double_count_raw_mirror(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            message="runtime error: bad 3\nproc name: example (/proc/example)\n  source file: code/example.dm,17\n"
            (root/"runtime.log.json").write_text(json.dumps({"msg":message})+"\n")
            (root/"runtime-errors.log").write_text("01:02:03 code/example.dm:17 bad 3\n")
            counts,_,coverage=read_runtime(root)
            self.assertEqual(sum(counts.values()),1)
            self.assertTrue(coverage["raw_channel_not_added"])
            self.assertEqual(coverage["ownership_unavailable"],1)

    def test_raw_only_does_not_claim_procedure_coverage(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            (root/"runtime-errors.log").write_text("01:02:03 code/example.dm:17 bad 3\n")
            _,_,coverage=read_runtime(root)
            self.assertFalse(coverage["complete"])
            self.assertEqual(coverage["unlocated_procedure"],1)

    def test_blank_origin_raw_records_remain_unlocated_and_separate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            (root/"runtime-errors.log").write_text(
                "03:15:20 code/example.dm:154 list index out of bounds\n"
                "03:15:20 : list index out of bounds\n"
                ": list index out of bounds\n"
                "unrecognized diagnostic\n")
            counts,_,coverage=read_runtime(root, raw_only=True)
            self.assertEqual(counts[("list index out of bounds",None,"code/example.dm",154)],1)
            self.assertEqual(counts[("list index out of bounds",None,None,None)],2)
            self.assertEqual(coverage["raw_events"],3)
            self.assertEqual(coverage["parse_errors"],1)
            self.assertEqual(coverage["unlocated_source"],2)
            self.assertEqual(coverage["unlocated_procedure"],3)
            self.assertEqual(coverage["ownership_unavailable"],3)
            self.assertEqual(coverage["test_owned"],0)
            self.assertFalse(coverage["complete"])

if __name__ == "__main__":
    unittest.main()
