#!/usr/bin/env python3
"""Compare actual preport full registration with native shared metadata, no golden fabrication."""
import argparse,json
from pathlib import Path

def record(path,prefix):
    rows=[]
    for line in path.read_text(encoding="utf-8").splitlines():
        if prefix not in line:continue
        row=json.loads(line.split(prefix,1)[1])
        if set(row)!={"engine_hash","names","registered_fields"}:raise ValueError("metadata producer shape changed")
        if not isinstance(row["engine_hash"],str) or not row["engine_hash"]:raise ValueError("actual source build identity absent")
        names=row["names"]
        if not isinstance(names,list) or not names or not all(isinstance(x,str) for x in names) or names!=sorted(set(names)):raise ValueError("complete sorted known names absent")
        fields=row["registered_fields"]
        if not isinstance(fields,list) or not fields:raise ValueError("actual full registration field evidence absent")
        for field in fields:
            if set(field)!={"name","allow"} or not isinstance(field["name"],str) or not isinstance(field["allow"],list) or not all(isinstance(x,str) for x in field["allow"]):raise ValueError("invalid registered metadata field")
        if sorted({name for field in fields for name in field["allow"]})!=names:raise ValueError("actual registry fields disagree with complete names")
        rows.append(row)
    if len(rows)!=1:raise ValueError("exactly one complete metadata producer record required")
    return rows[0]

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--original",type=Path,required=True);parser.add_argument("--native",type=Path,required=True);args=parser.parse_args()
    original=record(args.original,"OLD_ALLOW_REGISTRY=");native=record(args.native,"NATIVE_ALLOW_REGISTRY=")
    for field in ("names","registered_fields"):
        if original[field]!=native[field]:raise AssertionError(f"complete preport metadata mismatch: {field}")
    print(f"exact original/native full registry metadata PASS ({len(native['names'])} names, {len(native['registered_fields'])} registrations)")
if __name__=="__main__":main()
