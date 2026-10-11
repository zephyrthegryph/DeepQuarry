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
        self.candidate={"version":3,"commit":self.commit,"plan_sha256":hashlib.sha256(b"/obj/example\tkey\tfield\n").hexdigest(),"inputs":self.inputs,"goldens":{p:"b"*40 for p in NS["GOLDENS"]},"both_pins_passed":True,"results":str(self.result_path),"results_sha256":NS["digest"](self.result_path.read_bytes())}
        self.note={"ok":True,"tested_commit":self.commit,"look_coverage":self.candidate.copy(),"tests_json":str(self.result_path)}
        self.ancestor=True; self.have_note=True
        self.calls=[]
        self.original=NS["git"];NS["git"]=self.git;self.addCleanup(lambda:NS.__setitem__("git",self.original))
        self.old_batch=NS["note_batch"];NS["note_batch"]=lambda entries: [(commit,self.note) for _,commit in entries];self.addCleanup(lambda:NS.__setitem__("note_batch",self.old_batch))
    def git(self,*args):
        self.calls.append(args)
        if args[0]=="notes":
            if args[-1]=="list":return "c"*40+" "+self.commit if self.have_note else ""
            if "show" in args:
                if not self.have_note:raise NS["subprocess"].CalledProcessError(1,args)
                return json.dumps(self.note)
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

    def test_exact_pass_does_not_list_or_batch_notes(self):
        NS["note_batch"]=lambda entries: self.fail("exact verified note must not batch")
        self.assertTrue(NS["official"](self.candidate))
        self.assertFalse(any(call[0]=="notes" and call[-1]=="list" for call in self.calls))
    def test_snapshot_child_note_still_authenticated(self):
        original=self.git
        child="d"*40
        def fake(*args):
            if args[0]=="notes" and "show" in args:raise NS["subprocess"].CalledProcessError(1,args)
            if args[0]=="notes" and args[-1]=="list":return "c"*40+" "+child
            return original(*args)
        NS["git"]=fake
        self.assertTrue(NS["official"](self.candidate))
    def test_snapshot_child_off_branch_refused(self):
        self.ancestor=False
        self.assertFalse(NS["official"](self.candidate))
    def test_source_fingerprints_evaluated_once(self):
        self.have_note=False
        self.assertFalse(NS["official"](self.candidate))
        self.assertEqual(sum(call[0]=="rev-parse" for call in self.calls),len(NS["INPUTS"])+len(NS["GOLDENS"]))

    def test_changed_committed_goldens_refuse_anchor(self):
        original=self.git
        def changed(*args):
            if args[0]=="rev-parse" and any(args[1].endswith(":"+p) for p in NS["GOLDENS"]):return "c"*40
            return original(*args)
        NS["git"]=changed
        self.assertFalse(NS["official"](self.candidate))
    def test_malformed_commit_shapes_refuse_cleanly(self):
        for value in (None,123,[],{}):
            self.assertFalse(NS["result_commit_matches"](self.commit,{"commit":value}))
            self.assertFalse(NS["result_commit_matches"](value,{"commit":self.commit[:10]}))

class NoteBatchDecoding(unittest.TestCase):
    def setUp(self):
        self.old=NS["subprocess"].check_output
        self.addCleanup(lambda:setattr(NS["subprocess"],"check_output",self.old))
    def batch(self,data,entries):
        calls=[]
        def fake(*args,**kwargs):calls.append((args,kwargs));return data
        NS["subprocess"].check_output=fake
        result=NS["note_batch"](entries)
        self.assertEqual(len(calls),1)
        self.assertEqual(calls[0][0][0],["git","cat-file","--batch"])
        return result
    def test_multiple_unicode_notes_single_process(self):
        entries=[("a"*40,"c"*40),("b"*40,"d"*40)]
        bodies=[json.dumps({"reason":"é"},ensure_ascii=False).encode(),b'{"ok":true}']
        data=b"".join((blob+" blob "+str(len(body))+"\n").encode()+body+b"\n" for (blob,_),body in zip(entries,bodies))
        self.assertEqual(self.batch(data,entries),[("c"*40,{"reason":"é"}),("d"*40,{"ok":True})])
    def test_wrong_object_identity_rejected(self):
        with self.assertRaises(ValueError):self.batch(("b"*40+" blob 2\n{}\n").encode(),[("a"*40,"c"*40)])
    def test_truncated_blob_rejected(self):
        with self.assertRaises(ValueError):self.batch(("a"*40+" blob 8\n{}\n").encode(),[("a"*40,"c"*40)])
    def test_missing_newline_rejected(self):
        with self.assertRaises(ValueError):self.batch(("a"*40+" blob 2\n{}x").encode(),[("a"*40,"c"*40)])
    def test_empty_inventory_starts_no_process(self):
        NS["subprocess"].check_output=lambda *args,**kwargs:self.fail("empty inventory")
        self.assertEqual(NS["note_batch"]([]),[])

class GoldenOutputIdentities(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.directory=pathlib.Path(self.temp.name)/"goldens";self.directory.mkdir()
        self.previous=NS["GOLDENS"];NS["GOLDENS"]=(str(self.directory),)
        self.addCleanup(lambda:NS.__setitem__("GOLDENS",self.previous))
    def identity(self):return NS["golden_output_identities"]()[str(self.directory)]
    def test_empty_tree_matches_known_git_identity(self):
        self.assertEqual(self.identity(),"4b825dc642cb6eb9a060e54bf8d69288fbee4904")
    def test_lf_crlf_same_committed_text_identity(self):
        p=self.directory/"fixture.txt";p.write_bytes(b"first\r\nsecond\r\n");before=self.identity()
        p.write_bytes(b"first\nsecond\n");self.assertEqual(self.identity(),before)
    def test_blessed_output_identity_changes_before_commit(self):
        p=self.directory/"fixture.txt";p.write_bytes(b"old\n");before=self.identity()
        p.write_bytes(b"intended new\n");self.assertNotEqual(self.identity(),before)
    def test_creation_order_does_not_change_tree_identity(self):
        (self.directory/"b.txt").write_bytes(b"b\n");(self.directory/"a.txt").write_bytes(b"a\n");before=self.identity()
        (self.directory/"b.txt").unlink();(self.directory/"b.txt").write_bytes(b"b\n");self.assertEqual(self.identity(),before)
    def test_unexpected_nontext_output_refused(self):
        (self.directory/"unsafe.bin").write_bytes(b"x")
        with self.assertRaises(ValueError):self.identity()

if __name__=="__main__":unittest.main()
