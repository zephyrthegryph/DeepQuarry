#!/usr/bin/env python3
"""Verified appearance coverage, independent of regenerated tracked look_keys.
Local records are candidates only; official notes and actual result evidence establish trust.
Missing evidence conservatively selects full coverage. Never creates/reconstructs a stamp.
"""
import hashlib, json, pathlib, subprocess, sys, re
PINS=("/datum/unit_test/dq_look_state_pin", "/datum/unit_test/dq_look_tree_pin")
ROOT=pathlib.Path("data/look-verified")
VERSION=3
INPUTS=("code/modules/unit_tests/dq_look_sweep.dm", "code/modules/unit_tests/dq_look_pins.dm", "code/modules/unit_tests/dq_conversion_pins.dm", "code/modules/unit_tests/dq_snapshot_files.dm", ".gitattributes", "tools/dq_focused_test.sh", "tools/dq_look_verified_anchor.py", "tools/analyze", "tools/build", "tools/dmb", "code/engine/present")
GOLDENS=("code/modules/unit_tests/snapshots/look_states", "code/modules/unit_tests/snapshots/look_trees")
def golden_git_identities(commit):
    return {path: git("rev-parse", commit+":"+path) for path in GOLDENS}

def golden_output_identities():
    # Capture the exact successfully checked golden output, including authorized post-run blessing.
    # .gitattributes pins *.txt to LF; snapshots have regular nonexecutable text files only.
    def object_id(kind, data):
        return hashlib.sha1(kind.encode()+b" "+str(len(data)).encode()+b"\0"+data).digest()
    def tree(directory):
        entries=[]
        for child in directory.iterdir():
            if child.is_symlink(): raise ValueError("snapshot symlink is not regular golden output")
            name=child.name.encode("utf-8")
            if child.is_dir():
                entries.append((name+b"/", b"40000 "+name+b"\0"+tree(child)))
            elif child.is_file() and child.suffix==".txt":
                data=child.read_bytes().replace(b"\r\n",b"\n")
                entries.append((name,b"100644 "+name+b"\0"+object_id("blob",data)))
            else: raise ValueError("unexpected file in snapshot golden tree")
        return object_id("tree",b"".join(entry for _,entry in sorted(entries)))
    return {path: tree(pathlib.Path(path)).hex() for path in GOLDENS}

def fingerprints(commit):
    return {path: git("rev-parse", commit+":"+path) for path in INPUTS}
def result_commit_matches(commit, result):
    if not isinstance(result, dict): return False
    short=result.get("commit", "")
    return isinstance(commit, str) and isinstance(short, str) and bool(re.fullmatch(r"[0-9a-f]{10,40}", short)) and commit.startswith(short)

def git(*args):
    return subprocess.check_output(["git",*args],stderr=subprocess.DEVNULL).decode().strip()
def passing(result):
    if not isinstance(result, dict) or not isinstance(result.get("tests"), dict): return False
    rows = [result["tests"].get(p) for p in PINS]
    return all(isinstance(row, dict) and type(row.get("status")) is int and row["status"] == 0 and row.get("runtimes", 0) == 0 for row in rows)
def digest(data): return hashlib.sha256(data).hexdigest()
def note_batch(entries):
    """Read all fallback note blobs with one read-only Git process, preserving byte sizes."""
    if not entries: return []
    wanted = "".join(blob + "\n" for blob, _ in entries).encode("ascii")
    output = subprocess.check_output(["git", "cat-file", "--batch"], input=wanted, stderr=subprocess.DEVNULL)
    offset = 0
    decoded = []
    for expected_blob, commit in entries:
        end = output.find(b"\n", offset)
        if end < 0: raise ValueError("truncated note batch header")
        header = output[offset:end].decode("ascii").split()
        offset = end + 1
        if len(header) != 3 or header[0] != expected_blob or header[1] != "blob":
            raise ValueError("unexpected note batch object")
        size = int(header[2])
        if size < 0 or offset + size >= len(output): raise ValueError("truncated note blob")
        body = output[offset:offset + size]
        offset += size
        if output[offset:offset + 1] != b"\n": raise ValueError("missing note batch terminator")
        offset += 1
        try: decoded.append((commit, json.loads(body)))
        except (ValueError, UnicodeDecodeError): continue
    return decoded

def official_notes(ref, tested_commit):
    # Common case: merge-gates stamped the exact tested commit. Avoid inventorying any notes.
    try:
        yield tested_commit, json.loads(git("notes", "--ref=" + ref, "show", tested_commit))
    except (subprocess.CalledProcessError, ValueError): pass
    # Snapshot-only lane-ready stamps may sit on a child commit, so exact lookup alone is insufficient.
    try:
        entries = []
        for line in git("notes", "--ref=" + ref, "list").splitlines():
            row = line.split()
            if len(row) != 2 or not all(re.fullmatch(r"[0-9a-f]{40,64}", field) for field in row): continue
            if row[1] != tested_commit: entries.append((row[0], row[1]))
        yield from note_batch(entries)
    except (subprocess.CalledProcessError, ValueError, UnicodeDecodeError): return

def official(candidate):
    # Validate the source once per candidate, not once for every historical note.
    try:
        if not isinstance(candidate, dict) or candidate.get("version") != VERSION: return False
        if not re.fullmatch(r"[0-9a-f]{40,64}", candidate.get("commit", "")): return False
        if candidate.get("inputs") != fingerprints("HEAD"): return False
        if candidate.get("goldens") != golden_git_identities("HEAD"): return False
    except (subprocess.CalledProcessError, TypeError, OSError, ValueError): return False
    for ref in ("merge-gates", "lane-ready"):
        for commit, note in official_notes(ref, candidate["commit"]):
            try:
                if not isinstance(note, dict) or note.get("ok") is not True: continue
                if note.get("look_coverage", {}) != candidate: continue
                if note.get("tested_commit", note.get("commit")) != candidate["commit"]: continue
                git("merge-base", "--is-ancestor", commit, "HEAD")
                # Parse and hash the same read; do not reopen a file that could change between reads.
                result_bytes = pathlib.Path(note["tests_json"]).read_bytes()
                results = json.loads(result_bytes)
                if not passing(results) or digest(result_bytes) != candidate.get("results_sha256"): continue
                if not result_commit_matches(candidate["commit"], results): continue
                return True
            except (subprocess.CalledProcessError, ValueError, KeyError, OSError, IndexError, TypeError, AttributeError): continue
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
    (ROOT/(commit+".json")).write_text(json.dumps({"version":VERSION,"commit":commit,"plan_sha256":key,"both_pins_passed":True,"results":sys.argv[3],"results_sha256":digest(pathlib.Path(sys.argv[3]).read_bytes()),"inputs":fingerprints(commit),"goldens":golden_output_identities()}))
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
        if candidate.get("goldens")!=golden_output_identities(): raise ValueError()
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
