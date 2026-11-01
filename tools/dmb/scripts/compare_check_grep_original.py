#!/usr/bin/env python3
"""Strict complete original/native check_grep comparison; no row filtering."""
import argparse,json
from pathlib import Path

def rows(path,prefix):
    result={}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith(prefix):continue
        row=json.loads(line[len(prefix):]);case=row.get("case")
        if case not in ("basic","configured","lossy") or case in result:raise ValueError("unknown or repeated complete fixture")
        if set(row)!={"case","report","failed","sites","notes","allow_used"}:raise ValueError("complete producer shape changed")
        if not isinstance(row["failed"],bool) or not isinstance(row["report"],str):raise ValueError("invalid complete judgement")
        for field in ("sites","notes","allow_used"):
            if not isinstance(row[field],list):raise ValueError("ordered producer field is absent")
        result[case]=row
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--native",type=Path,required=True);parser.add_argument("--original",type=Path,nargs="+",required=True);args=parser.parse_args()
    native=rows(args.native,"NATIVE_CHECK_GREP_FULL=");old={}
    for path in args.original:
        part=rows(path,"OLD_CHECK_GREP_FULL=")
        if old.keys()&part.keys():raise ValueError("original fixture repeats")
        old.update(part)
    if set(native)!={"basic","configured","lossy"} or set(old)!=set(native):raise ValueError("all three complete fixtures are mandatory")
    for case in old:
        if old[case]!=native[case]:
            fields=[field for field in old[case] if old[case][field]!=native[case][field]]
            raise AssertionError(f"{case}: complete original/native mismatch: {fields}")
        print(f"{case}: exact whole ordered sites, notes, ALLOW, custom report and judgement PASS")
if __name__=="__main__":main()
