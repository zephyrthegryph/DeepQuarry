#!/usr/bin/env python3
"""Verified appearance coverage, independent of regenerated tracked look_keys.
Local records are candidates only; official notes and actual result evidence establish trust.
Missing evidence conservatively selects full coverage. Never creates/reconstructs a stamp.
"""
import hashlib, json, pathlib, subprocess, sys, re
PINS=("/datum/unit_test/dq_look_state_pin", "/datum/unit_test/dq_look_tree_pin")
ROOT=pathlib.Path("data/look-verified")
VERSION=2
INPUTS=("code/modules/unit_tests/dq_look_sweep.dm", "code/modules/unit_tests/dq_look_pins.dm", "code/modules/unit_tests/dq_conversion_pins.dm", "tools/dq_focused_test.sh", "tools/dq_look_verified_anchor.py", "tools/analyze", "tools/build", "tools/dmb", "code/engine/present")
def fingerprints(commit):
    return {path: git("rev-parse", commit+":"+path) for path in INPUTS}
def result_commit_matches(commit, result):
    if not isinstance(result, dict): return False
    short=result.get("commit", "")
    return bool(re.fullmatch(r"[0-9a-f]{10,40}", short)) and commit.startswith(short)

def git(*args):
    return subprocess.check_output(["git",*args],stderr=subprocess.DEVNULL).decode().strip()
def passing(result):
    if not isinstance(result, dict) or not isinstance(result.get("tests"), dict): return False
    rows = [result["tests"].get(p) for p in PINS]
    return all(isinstance(row, dict) and type(row.get("status")) is int and row["status"] == 0 and row.get("runtimes", 0) == 0 for row in rows)
def digest(data): return hashlib.sha256(data).hexdigest()
def official(candidate):
    # A candidate's tested commit may be the parent of the snapshot-only stamped commit.
    # Actual notes relate those commits; ancestry alone does not establish coverage.
    for ref in ("lane-ready","merge-gates"):
        try: entries=git("notes","--ref="+ref,"list").splitlines()
        except subprocess.CalledProcessError: continue
        for entry in entries:
            try:
                commit=entry.split()[1]
                note=json.loads(git("notes","--ref="+ref,"show",commit))
                if note.get("ok") is not True: continue
                coverage=note.get("look_coverage",{})
                if coverage != candidate: continue
                if candidate.get("version") != VERSION or candidate.get("inputs") != fingerprints("HEAD"): continue
                if note.get("tested_commit", note.get("commit")) != candidate["commit"]: continue
                git("merge-base","--is-ancestor",commit,"HEAD")
                results=json.loads(pathlib.Path(note["tests_json"]).read_text())
                if not passing(results) or digest(pathlib.Path(note["tests_json"]).read_bytes()) != candidate.get("results_sha256"): continue
                if not result_commit_matches(candidate["commit"],results): continue
                return True
            except (subprocess.CalledProcessError,ValueError,KeyError,OSError,IndexError,TypeError,AttributeError): continue
    return False
if sys.argv[1]=="record":
    plan=pathlib.Path(sys.argv[2]).read_bytes()
    result=json.loads(pathlib.Path(sys.argv[3]).read_text())
    commit=git("rev-parse","HEAD")
    if not passing(result) or not result_commit_matches(commit,result):
        raise SystemExit("look coverage record refused: both pins must actually pass on this commit")
    # Any production edit since compilation invalidates this candidate.
    changed=git("diff","--name-only").splitlines()+git("diff","--cached","--name-only").splitlines()
    if any(not p.startswith("code/modules/unit_tests/snapshots/") for p in changed):
        raise SystemExit("look coverage record refused: non-snapshot tracked edits")
    ROOT.mkdir(parents=True,exist_ok=True)
    key=digest(plan); (ROOT/(commit+".tsv")).write_bytes(plan)
    (ROOT/(commit+".json")).write_text(json.dumps({"version":VERSION,"commit":commit,"plan_sha256":key,"both_pins_passed":True,"results":sys.argv[3],"results_sha256":digest(pathlib.Path(sys.argv[3]).read_bytes()),"inputs":fingerprints(commit)}))
elif sys.argv[1]=="export":
    # The existing official stamping path calls this only after its real gate completed.
    # No candidate or failed/skipped pins means no coverage property, not failure of other tests.
    try:
        result_path=pathlib.Path(sys.argv[2]); result=json.loads(result_path.read_text())
        short=result.get("commit", "")
        if not re.fullmatch(r"[0-9a-f]{10,40}",short) or not passing(result): raise ValueError()
        commit=git("rev-parse",short+"^{commit}")
        git("merge-base","--is-ancestor",commit,"HEAD")
        candidate=json.loads((ROOT/(commit+".json")).read_text())
        plan=(ROOT/(commit+".tsv")).read_bytes()
        if candidate.get("version")!=VERSION or candidate.get("inputs")!=fingerprints(commit): raise ValueError()
        if digest(plan)!=candidate.get("plan_sha256") or digest(result_path.read_bytes())!=candidate.get("results_sha256"): raise ValueError()
        print(json.dumps(candidate))
    except (OSError,ValueError,subprocess.CalledProcessError,KeyError,TypeError,AttributeError): print("null")
elif sys.argv[1]=="select":
    destination=pathlib.Path(sys.argv[2]); destination.unlink(missing_ok=True)
    records={}
    for path in ROOT.glob("*.json"):
        try:
            record=json.loads(path.read_text()); plan=path.with_suffix(".tsv").read_bytes()
            if record.get("both_pins_passed") is True and digest(plan)==record.get("plan_sha256"):
                records[record["commit"]]=(record,plan)
        except (OSError,ValueError,KeyError,TypeError,AttributeError): pass
    # Nearest reachable actual verified run; no record means full concrete-plan probing.
    for commit in git("rev-list","HEAD").splitlines():
        if commit in records and official(records[commit][0]):
            destination.write_bytes(records[commit][1]); print("verified look anchor:",commit); break
    else: print("no trustworthy look anchor; full concrete-plan probing",file=sys.stderr)
else: raise SystemExit("expected select or record")
