#!/usr/bin/env python3
"""Whole original public reports/usage and all three baseline modes; no filtering."""
import json
import re
import sys
from pathlib import Path
CASES={"basic","configured","lossy","original_context"}
MODES={"seed","update","migrate"}
PREFIX="runner_host::query_snapshot::workspace_raw_tests::check_grep_tests::"
def read(path): return Path(path).read_text(encoding="utf-8-sig")
def documents(text,marker):
    return [json.loads(line[len(marker):]) for line in text.splitlines() if line.startswith(marker)]
def passed(text,name):
    summaries=re.findall(r"^test result: ([a-z]+)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured;[^\n]*$",text,re.M)
    tests=re.findall(r"^test (\S+) \.\.\. (\S+)\s*$",text,re.M)
    if summaries != [("ok","1","0","0","0")] or tests != [(PREFIX+name,"ok")]:
        raise ValueError("exactly one named public producer test must pass without failures or ignored tests")
def keyed(values,baseline):
    result={}
    for value in values:
        fields={"case","mode","text","configuration"} if baseline else {"case","text","clean","allow_usage"}
        if not isinstance(value,dict) or set(value)!=fields or value["case"] not in CASES or not isinstance(value["text"],str): raise ValueError("invalid whole document")
        key=(value["case"],value["mode"]) if baseline else value["case"]
        if key in result: raise ValueError("duplicate whole document")
        if baseline:
            if value["mode"] not in MODES or not isinstance(value["configuration"],str): raise ValueError("invalid baseline document")
        else:
            if type(value["clean"]) is not bool or not isinstance(value["allow_usage"],list): raise ValueError("invalid report completion")
            for row in value["allow_usage"]:
                if not isinstance(row,list) or len(row)!=3 or row[0]!="check_grep" or not isinstance(row[1],str) or not re.fullmatch(r"[0-9a-f]{40}",row[1]) or type(row[2]) is not int or row[2]<1: raise ValueError("invalid exact ALLOW usage")
        result[key]=value
    expected={(case,mode) for case in CASES for mode in MODES} if baseline else CASES
    if set(result)!=expected: raise ValueError("missing or extra whole documents")
    return result
def main():
    if len(sys.argv)!=19: raise ValueError("usage: compare_public_check_grep.py NATIVE_CHECK_LOG NATIVE_BASELINE_LOG OLD_REPORT_LOGS[4] OLD_BASELINE_LOGS[12]")
    check,baseline=map(read,sys.argv[1:3]);passed(check,"actual_public_check_grep_complete_shared_original_reports_include_ordered_allow_usage");passed(baseline,"actual_public_check_grep_baseline_whole_original_projection_preserves_seed_update_migrate")
    native_check=keyed(documents(check,"NATIVE_PUBLIC_CHECK_GREP_REPORT="),False);native_baseline=keyed(documents(baseline,"NATIVE_CHECK_GREP_BASELINE="),True)
    old_check=[];old_baseline=[]
    for path in sys.argv[3:7]:
        rows=documents(read(path),"OLD_PUBLIC_CHECK_GREP_REPORT=")
        if len(rows)!=1: raise ValueError("one actual original public report required per command")
        old_check.extend(rows)
    for path in sys.argv[7:19]:
        rows=documents(read(path),"OLD_CHECK_GREP_BASELINE=")
        if len(rows)!=1: raise ValueError("one actual original baseline required per command")
        old_baseline.extend(rows)
    if native_check!=keyed(old_check,False): raise ValueError("whole public check text/clean/ordered usage differs")
    if native_baseline!=keyed(old_baseline,True): raise ValueError("whole baseline text/configuration differs")
    print("PASS: 4 whole reports/ordered usage and 12 whole baseline/configuration records")
if __name__=="__main__": main()
