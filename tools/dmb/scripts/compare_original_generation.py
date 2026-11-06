#!/usr/bin/env python3
"""Strict complete artifact/ordered-diagnostic comparison for genuine Original generation."""
import argparse,json,re
from pathlib import Path
CASES={"real","absent","noninclude","invalid_utf8"}
NAMES={"actions","auto_tracked","declare","declare_ids","deps","derived_reads","plans","reads","stats","system_accessors","tracked_lists","ui_types"}
SELECTOR="actual_original_generation_all_thirteen_real_and_synthetic_subjects_settle_then_reuse_same_bodies"
def strict_json(text):
 def fields(pairs):
  out={}
  for key,value in pairs:
   if key in out:raise ValueError("duplicate JSON field")
   out[key]=value
  return out
 def constant(value):raise ValueError("nonfinite JSON value")
 return json.loads(text,object_pairs_hook=fields,parse_constant=constant)
def rows(text,prefix):
 found={}
 for line in text.splitlines():
  if not line.startswith(prefix):continue
  value=strict_json(line[len(prefix):])
  if set(value)!={"case","generator","files","diagnostics"}:raise ValueError("foreign artifact schema")
  key=(value["case"],value["generator"])
  if key[0] not in CASES or key[1] not in NAMES or key in found:raise ValueError("duplicate/foreign artifact role")
  if not isinstance(value["files"],list) or not isinstance(value["diagnostics"],list):raise ValueError("invalid complete output arrays")
  seen=set()
  for row in value["files"]:
   if not isinstance(row,list) or len(row)!=2 or not all(isinstance(item,str) for item in row):raise ValueError("invalid file row")
   if row[0] in seen:raise ValueError("duplicate actual output path")
   seen.add(row[0])
  for row in value["diagnostics"]:
   if not isinstance(row,list) or len(row)!=3 or not isinstance(row[0],str) or type(row[1]) is not int or row[1]<0 or not isinstance(row[2],str):raise ValueError("invalid ordered diagnostic row")
  found[key]=value
 if set(found)!={(case,name) for case in CASES for name in NAMES}:raise ValueError("all four complete thirteen-generator cases are mandatory")
 return found
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--original",type=Path,required=True);parser.add_argument("--native",type=Path,required=True);args=parser.parse_args()
 old=args.original.read_text(encoding="utf8");native=args.native.read_text(encoding="utf8")
 summaries=re.findall(r"^test result: (\w+)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured;",native,re.M)
 statuses=re.findall(r"^test ([^\r\n ]+) \.\.\. (\w+)$",native,re.M)
 if summaries!=[("ok","1","0","0","0")] or len(statuses)!=1 or statuses[0][0].split("::")[-1]!=SELECTOR or statuses[0][1]!="ok":raise ValueError("native proof is not exactly the full successful Original generation test")
 settled=[strict_json(line.split("=",1)[1]) for line in old.splitlines() if line.startswith("OLD_GENERATION_FIXEDPOINT_SETTLED=")]
 if len(settled)!=4 or any(not isinstance(value,dict) or set(value)!={"schema","settled","passes","stage_zero","stage_one","generators"} or value.get("schema")!="original-generation-fixedpoint-v1" or value.get("settled") is not True or type(value.get("passes")) is not int or not 1<=value["passes"]<=5 or type(value.get("stage_zero")) is not int or value["stage_zero"]!=7 or type(value.get("stage_one")) is not int or value["stage_one"]!=5 or not isinstance(value.get("generators"),list) or not all(isinstance(name,str) for name in value["generators"]) or len(value["generators"])!=len(NAMES) or set(value["generators"])!=NAMES for value in settled):raise ValueError("four genuine complete original settled receipts are mandatory")
 a=rows(old,"OLD_ORIGINAL_GENERATION_FULL=");b=rows(native,"NATIVE_ORIGINAL_GENERATION_FULL=")
 if a!=b:
  for key in sorted(a):
   if a[key]!=b[key]:raise ValueError(f"complete actual artifact/ordered diagnostics differ: {key}")
 print("PASS: complete original/native four-subject thirteen-generator outputs and ordered diagnostics")
if __name__=="__main__":main()
