"""Offline tests for the proposed helper; parent runs these after reviewing integration.
No repository mutation, build, generation, native test world or stamp creation.
"""
import hashlib,json,os,pathlib,tempfile,unittest
SOURCE=pathlib.Path(__file__).with_name("dq_look_verified_anchor.py")
NS={"__name__":"anchor_source_review"}
exec(SOURCE.read_text().split('if sys.argv[1]=="record":')[0],NS)

class VerifiedAnchor(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.result_path=pathlib.Path(self.temp.name)/"result.json"
        self.commit="a"*40
        self.result={"commit":self.commit[:10],"tests":{p:{"status":0,"runtimes":0} for p in NS["PINS"]}}
        self.result_path.write_text(json.dumps(self.result))
        self.inputs={p:"b"*40 for p in NS["INPUTS"]}
        self.candidate={"version":2,"commit":self.commit,"plan_sha256":hashlib.sha256(b"/obj/example\tkey\tfield\n").hexdigest(),"inputs":self.inputs,"both_pins_passed":True,"results":str(self.result_path),"results_sha256":NS["digest"](self.result_path.read_bytes())}
        self.note={"ok":True,"tested_commit":self.commit,"look_coverage":self.candidate.copy(),"tests_json":str(self.result_path)}
        self.ancestor=True; self.have_note=True
        self.original=NS["git"];NS["git"]=self.git;self.addCleanup(lambda:NS.__setitem__("git",self.original))
    def git(self,*args):
        if args[0]=="notes":
            if args[-1]=="list":return "c"*40+" "+self.commit if self.have_note else ""
            if "show" in args:return json.dumps(self.note)
        if args[:2]==("merge-base","--is-ancestor"):
            if not self.ancestor:raise NS["subprocess"].CalledProcessError(1,args)
            return ""
        if args[0]=="rev-parse":return "b"*40
        raise AssertionError(args)
    def persist(self):self.result_path.write_text(json.dumps(self.result))
    def test_actual_pass(self):self.assertTrue(NS["official"](self.candidate))
    def test_malformed_results_do_not_pass(self):
        for result in (None, [], {}, {"tests": []}, {"tests": {p: None for p in NS["PINS"]}}):
            self.assertFalse(NS["passing"](result))
    def test_boolean_status_is_not_a_pass(self):
        self.result["tests"][NS["PINS"][0]]["status"]=False
        self.assertFalse(NS["passing"](self.result))
    def test_missing_pin(self):
        del self.result["tests"][NS["PINS"][0]];self.persist();self.assertFalse(NS["official"](self.candidate))
    def test_skipped_pin(self):
        self.result["tests"][NS["PINS"][0]]["status"]=2;self.persist();self.assertFalse(NS["official"](self.candidate))
    def test_failed_pin(self):
        self.result["tests"][NS["PINS"][0]]["status"]=1;self.persist();self.assertFalse(NS["official"](self.candidate))
    def test_known_failure_is_not_pin_pass(self):
        self.result["tests"][NS["PINS"][0]]["status"]=1;self.result["counts"]={"failed":1};self.persist();self.assertFalse(NS["official"](self.candidate))
    def test_runtime_is_not_pass(self):
        self.result["tests"][NS["PINS"][0]]["runtimes"]=1;self.persist();self.assertFalse(NS["official"](self.candidate))
    def test_forged_local_candidate(self):
        forged=self.candidate.copy();forged["plan_sha256"]="f"*64;self.assertFalse(NS["official"](forged))
    def test_no_official_note(self):self.have_note=False;self.assertFalse(NS["official"](self.candidate))
    def test_changed_fixture_fingerprint(self):
        self.candidate["inputs"]={**self.inputs,NS["INPUTS"][0]:"c"*40};self.note["look_coverage"]=self.candidate.copy();self.assertFalse(NS["official"](self.candidate))
    def test_mutated_result(self):
        self.result["extra"]="changed";self.persist();self.assertFalse(NS["official"](self.candidate))
    def test_nonancestor(self):self.ancestor=False;self.assertFalse(NS["official"](self.candidate))
    def test_missing_result_evidence(self):self.result_path.unlink();self.assertFalse(NS["official"](self.candidate))
    def test_empty_short_commit_not_trusted(self):self.assertFalse(NS["result_commit_matches"](self.commit,{"commit":""}))
    def test_too_short_commit_not_trusted(self):self.assertFalse(NS["result_commit_matches"](self.commit,{"commit":"aaa"}))
    def test_nonhex_short_commit_not_trusted(self):self.assertFalse(NS["result_commit_matches"](self.commit,{"commit":"zzzzzzzzzz"}))
    def test_regenerated_tracked_keys_do_not_establish_anchor(self):
        self.have_note=False
        tracked=pathlib.Path(self.temp.name)/"look_keys.txt";tracked.write_text("/obj/example\tkey\tfield\n")
        self.assertFalse(NS["official"](self.candidate),"Equal freshly regenerated keys without verified coverage must not establish zero-stale")

if __name__=="__main__":unittest.main()
