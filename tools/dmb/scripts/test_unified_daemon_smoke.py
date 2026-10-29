"""Pure smoke-envelope checks; no processes, files or daemons are started."""
import importlib.util
import json
from pathlib import Path
import unittest
from unittest import mock
import subprocess

_spec = importlib.util.spec_from_file_location("unified_daemon_smoke", Path(__file__).with_name("unified_daemon_smoke.py"))
smoke = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(smoke)

class EnvelopeTests(unittest.TestCase):
    def test_queries_pin_both_current_revisions(self):
        value = smoke.request(Path("project.dme"), Path("engine.bin"),
                              {"semantic_revision": "s", "source_revision": "r"}, [])
        self.assertEqual(value["expected_revision"], "s")
        self.assertEqual(value["expected_source_revision"], "r")
        self.assertTrue(value["bootstrap_catalog"])

    def test_policy_pin_is_optional_for_legacy_but_exact_when_present(self):
        pins = {"semantic_revision": "s", "source_revision": "r"}
        self.assertNotIn("expected_policy_revision", smoke.request(Path("p"), Path("e"), pins, []))
        pins["policy_revision"] = "policy"
        self.assertEqual(smoke.request(Path("p"), Path("e"), pins, [])["expected_policy_revision"], "policy")
        reply = {"revision": "s", "source_revision": "r", "complete": False,
                 "policy_revision": "foreign", "jsonl": ""}
        with self.assertRaises(AssertionError):
            smoke.assert_reply(reply, pins)
        reply["policy_revision"] = "policy"
        reply["jsonl"] = '{"row":"source_native_untyped_fixture","policy_revision":"foreign"}'
        with self.assertRaises(AssertionError):
            smoke.assert_reply(reply, pins)

    def test_mismatched_revision_and_false_completeness_are_rejected(self):
        pins = {"semantic_revision": "s", "source_revision": "r"}
        for reply in [{"revision": "old", "source_revision": "r", "complete": False},
                      {"revision": "s", "source_revision": "old", "complete": False},
                      {"revision": "s", "source_revision": "r", "complete": True}]:
            with self.assertRaises(AssertionError):
                smoke.assert_reply(reply, pins)

    def test_finding_retraction_does_not_mean_full_policy_coverage(self):
        rows = [{"row": "source_native_untyped_fixture", "full_policy_parity": False, "findings": []},
                {"row": "source_native_checker_fixture", "full_checker_parity": False, "diagnostics": []}]
        smoke.assert_findings(rows, False)
        rows[0]["full_policy_parity"] = True
        with self.assertRaises(AssertionError):
            smoke.assert_findings(rows, False)

    def test_positive_observation_requires_expected_typed_field_and_checker_family(self):
        rows = [{"row": "source_native_untyped_fixture", "full_policy_parity": False,
                 "findings": [{"identity": "/datum/ipc_probe::saved", "rule": "typed", "file": "smoke_policy.dm"}]},
                {"row": "source_native_checker_fixture", "full_checker_parity": False,
                 "diagnostics": [{"family": "ambiguous_not_bitwise"}]}]
        smoke.assert_findings(rows, True)
        rows[0]["findings"][0]["identity"] = "unrelated"
        with self.assertRaises(AssertionError):
            smoke.assert_findings(rows, True)

class CompiledOwnerTests(unittest.TestCase):
    def test_compiled_discovery_requires_publication_and_exact_pins(self):
        reply={"snapshot_outcome":"published","last_request_outcome":"published",
               "publication_pair":"pair", "revision":"1"*32,"source_revision":"2"*32,"policy_revision":"3"*32}
        self.assertEqual(smoke.compiled_pins(reply), {"semantic_revision":"1"*32,
                         "source_revision":"2"*32,"policy_revision":"3"*32})
        for field,value in [("snapshot_outcome","query_prepared"),("last_request_outcome","failed"),
                            ("publication_pair",None),("source_revision",None),("policy_revision",None)]:
            with self.assertRaises(AssertionError):
                smoke.compiled_pins(dict(reply,**{field:value}))

class CompileIpcTests(unittest.TestCase):
    def test_real_compile_precedes_unpinned_discovery_with_explicit_budget(self):
        owner=object.__new__(smoke.Smoke)
        owner.root=Path("owned-scratch")
        owner.calls=[]
        owner.policy_intent={"files":[],"search_folders":[]}
        calls=[]
        reply={"snapshot_outcome":"published","last_request_outcome":"published",
               "publication_pair":"pair", "revision":"1"*32,"source_revision":"2"*32,"policy_revision":"3"*32}
        def run(args,**kwargs):
            calls.append(args)
            owner.calls.append({"args":args})
            return subprocess.CompletedProcess(args,0,json.dumps(reply) if args[0]=="query" else "compiled","")
        owner.run=run
        writes=[]
        with mock.patch.object(Path,"is_file",return_value=True), mock.patch.object(Path,"write_text",side_effect=lambda data,**kwargs:writes.append(json.loads(data))):
            pins=owner.compile_and_discover(Path("source/fixture.dme"),Path("engine.bin"))
        self.assertEqual([args[0] for args in calls],["compile","query"])
        self.assertIn("--request-timeout-seconds",calls[0])
        self.assertEqual(calls[0][calls[0].index("--request-timeout-seconds")+1],"45")
        self.assertIn("--artifact-directory",calls[0])
        self.assertEqual(writes[0]["expected_revision"],None)
        self.assertEqual(writes[0]["source_queries"],[])
        self.assertEqual(pins["source_revision"],"2"*32)

class NamedPolicyTests(unittest.TestCase):
    def test_new_selectors_bind_captured_config_paths_and_same_body(self):
        questions=smoke.named_questions(Path("source/p.dme"),7)
        self.assertEqual(questions[0]["NativeNamedRule"]["configuration"],str(Path("source/lint_scopes.toml")))
        self.assertEqual(questions[1]["NativeConfiguredChecker"]["ordinal"],7)
        self.assertIsNone(questions[1]["NativeConfiguredChecker"]["configuration"])

    def test_named_and_configured_findings_cannot_claim_full_coverage_or_ignore_config(self):
        rows=[{"row":"source_native_named_rule","full_lint_parity":False,"coverage":"captured_compiled_declarations",
               "findings":[{"rule":"records_data_only","rel":"smoke_records.dm","line":2,"msg":"","key":"","ident":""}]},
              {"row":"source_native_configured_checker","full_checker_parity":False,"configuration_schema":"complete_pinned_checker_schema",
               "configuration_present":True,"configuration_explicit":False,
               "diagnostics":[{"family":"ambiguous_not_bitwise","severity":"hint"}]}]
        smoke.assert_named_findings(rows)
        for target,key,value in [(0,"full_lint_parity",True),(1,"full_checker_parity",True),(1,"configuration_present",False)]:
            bad=json.loads(json.dumps(rows));bad[target][key]=value
            with self.assertRaises(AssertionError):smoke.assert_named_findings(bad)
        rows[1]["diagnostics"][0]["severity"]="warning"
        with self.assertRaises(AssertionError):smoke.assert_named_findings(rows)

class RawCapturedPolicyTests(unittest.TestCase):
    def test_raw_only_query_uses_proven_missing_captured_configuration(self):
        query=smoke.named_questions(Path("source/p.dme"),0)[2]["NativeRawPolicyFixture"]
        self.assertEqual(query["lints"],["scheduler"])
        self.assertEqual(query["configuration"],str(Path("source/optional.toml")))
        row={"row":"source_native_raw_policy_fixture","full_policy_parity":False,"baseline_applied":False,
             "configuration_scope":"proven_missing_configuration","requested_lints":["scheduler"],"scope":"explicit_captured_files",
             "results":[{"name":"scheduler","sites":[{"line":2,"rel":"code/raw_probe.dm"}]}]}
        smoke.assert_raw_findings([row])
        row["baseline_applied"]=True
        with self.assertRaises(AssertionError):smoke.assert_raw_findings([row])

class ConfiguredControlBatchTests(unittest.TestCase):
    def test_control_union_is_one_question_with_event_order_not_family_order(self):
        questions=smoke.named_questions(Path("source/p.dme"),0,9)
        batch=questions[-1]["NativeConfiguredControlBatch"]
        self.assertEqual(batch["ordinal"],9)
        self.assertEqual(batch["families"],["if_condition_determinate","control_condition_static","unreachable_code"])
        row={"row":"source_native_configured_control_batch","full_checker_parity":False,
             "ordering":"primary_control_event_order","flow_reuse":"request_local_union", "diagnostics":[
                 {"family":"control_condition_static","severity":"hint","expanded_span":[1,2]},
                 {"family":"if_condition_determinate","severity":"warning","expanded_span":[1,2]}]}
        smoke.assert_control_batch([row])
        row["diagnostics"].reverse()
        with self.assertRaises(AssertionError):smoke.assert_control_batch([row])

class BudgetTests(unittest.TestCase):
    def test_expired_overall_budget_launches_no_new_process(self):
        owner=object.__new__(smoke.Smoke)
        owner.deadline=10
        with mock.patch.object(smoke.time,"monotonic",return_value=11), mock.patch.object(smoke.subprocess,"run") as spawn:
            with self.assertRaisesRegex(TimeoutError,"request budget"):
                owner.run(["prepare-query"])
            spawn.assert_not_called()

    def test_retirement_polls_share_one_absolute_owned_deadline(self):
        owner=object.__new__(smoke.Smoke)
        calls=[]
        now=[100.0]
        def run(args,**kwargs):
            calls.append((args,kwargs))
            now[0]+=4
            return subprocess.CompletedProcess(args,0,"absent" if len(calls)==2 else "draining","")
        owner.run=run
        with mock.patch.object(smoke.time,"monotonic",side_effect=lambda:now[0]), mock.patch.object(smoke.time,"sleep",side_effect=lambda seconds:now.__setitem__(0,now[0]+seconds)):
            owner.retire()
        self.assertEqual(len(calls),2)
        for args,kwargs in calls:
            self.assertEqual(args,["--daemon-retire"])
            self.assertTrue(kwargs["cleanup"])
            self.assertEqual(kwargs["cleanup_deadline"],115.0)

    def test_expired_cleanup_budget_launches_no_retire_process(self):
        owner=object.__new__(smoke.Smoke)
        with mock.patch.object(smoke.time,"monotonic",return_value=15), mock.patch.object(smoke.subprocess,"run") as spawn:
            with self.assertRaisesRegex(TimeoutError,"cleanup budget"):
                owner.run(["--daemon-retire"],cleanup=True,cleanup_deadline=15)
            spawn.assert_not_called()

if __name__ == "__main__":
    unittest.main()
