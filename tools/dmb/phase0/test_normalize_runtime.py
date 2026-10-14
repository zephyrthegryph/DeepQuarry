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

    def test_explicit_test_events_remain_attributed_and_conflicts_unassigned(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            records = [
                {"msg": "runtime error: owned 7", "test": "/datum/unit_test/one"},
                {"msg": "runtime error: owned 8", "test_path": "/datum/unit_test/two"},
                {"msg": "runtime error: absent 9"},
                {"msg": "runtime error: conflict", "test": "/datum/unit_test/one",
                 "test_path": "/datum/unit_test/two"},
            ]
            (root / "runtime.log.json").write_text("".join(json.dumps(row) + "\n" for row in records))
            attribution = {}
            counts, _, _ = read_runtime(root, attribution=attribution)
            self.assertEqual(sum(counts.values()), 4)
            self.assertEqual(attribution["attributed_total"], 2)
            self.assertEqual(attribution["unassigned_total"], 2)
            self.assertEqual(set(attribution["attributed_tests"]),
                             {"/datum/unit_test/one", "/datum/unit_test/two"})
            first = attribution["attributed_tests"]["/datum/unit_test/one"][0]
            self.assertEqual(first["raw_message_examples_first16"], ["runtime error: owned 7"])
            self.assertIn("conflicting-explicit-owners", attribution["unassigned"])

    def test_temporal_overlap_never_assigns_blank_error_to_test(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "tests.log").write_text(
                "[2026-10-01 03:15:19.462] Running 1/2: /datum/unit_test/one\n"
                "[2026-10-01 03:15:20.500] Running 2/2: /datum/unit_test/two\n"
                "[2026-10-01 03:15:22.000] Unit-test suite finished: 2 test types, failures: no.\n")
            (root / "runtime-errors.log").write_text("03:15:20 : list index out of bounds\n")
            attribution = {}
            _, _, coverage = read_runtime(root, raw_only=True, attribution=attribution)
            self.assertEqual(coverage["test_owned"], 0)
            self.assertEqual(attribution["attributed_total"], 0)
            self.assertEqual(attribution["unassigned_total"], 1)
            self.assertEqual(attribution["temporal_interval_associations"][0]["candidate_tests"],
                             ["/datum/unit_test/one", "/datum/unit_test/two"])

    def test_open_interval_and_different_clock_date_do_not_create_ownership(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "tests.log").write_text(
                "[2026-10-01 03:15:19.462] Running 1/1: /datum/unit_test/one\n")
            event = {"msg": "runtime error: blank", "ts": "2026-09-30 22:15:20.000"}
            (root / "runtime.log.json").write_text(json.dumps(event) + "\n")
            attribution = {}
            read_runtime(root, attribution=attribution)
            self.assertEqual(attribution["open_interval_test"], "/datum/unit_test/one")
            self.assertEqual(attribution["temporal_interval_associations"], [])
            self.assertEqual(attribution["unassigned_total"], 1)


if __name__ == "__main__":
    unittest.main()
