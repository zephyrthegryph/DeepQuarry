"""Extract observed top ten sampled frames from processed Firefox/samply JSON.
Uses recorded sample weights (or one/sample). Reports inclusive and leaf weights;
these are sampling observations, not exact CPU seconds or stage wall time.
"""
import argparse
from collections import Counter
import gzip
import json
import re
from pathlib import Path


def debug_id(value):
    # DebugId display and Firefox breakpad form differ only in separators/case.
    return str(value).replace("-", "").upper()


def named(value):
    return bool(value) and value not in ("<unknown>","unknown") and not re.fullmatch(r"(?:[^!]+!)?0x[0-9a-fA-F]+",value)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile")
    parser.add_argument("--receipt",help="Use actual cold compiler or body-client execution interval")
    parser.add_argument("--symbols",help="Official samply .syms.json precog sidecar")
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    path=Path(args.profile)
    opener=gzip.open if path.suffix==".gz" else open
    with opener(path,"rt",encoding="utf-8") as stream:profile=json.load(stream)
    symbol_libraries={}
    if args.symbols:
        sidecar=json.loads(Path(args.symbols).read_text(encoding="utf-8"))
        if not isinstance(sidecar,dict) or not isinstance(sidecar.get("data"),list) or not isinstance(sidecar.get("string_table"),list):
            raise ValueError("Expected samply PrecogSymbolInfo data/string_table schema")
        table=sidecar["string_table"]
        for library in sidecar["data"]:
            key=(library["debug_name"],debug_id(library["debug_id"]))
            addresses={}
            for rva,index in library["known_addresses"]:
                info=library["symbol_table"][index]
                addresses[int(rva)]=table[info["symbol"]]
            if key in symbol_libraries:raise ValueError("Duplicate sidecar library identity")
            symbol_libraries[key]=addresses
    bounds=None
    if args.receipt:
        receipt=json.loads(Path(args.receipt).read_text())
        origin=profile.get("meta",{}).get("startTime")
        if not isinstance(origin,(int,float)):raise ValueError("Profile has no Unix-ms startTime for alignment")
        if receipt.get("scenario")=="cold":
            execution=receipt.get("compiler_execution",{})
            if execution.get("status")!="completed":raise ValueError("No completed cold compiler interval")
            bounds=(execution["started_unix"]*1000-origin,execution["ended_unix"]*1000-origin)
        else:
            marks={event["name"]:event for event in receipt["events"]}
            if "body_start" not in marks or "body_end" not in marks:raise ValueError("No completed body interval")
            bounds=(marks["body_start"]["unix"]*1000-origin,marks["body_end"]["unix"]*1000-origin)
    inclusive,leaf=Counter(),Counter();seen=0;unknown=0;thread_errors=[];resolved=0;unresolved=0
    for thread in profile.get("threads",[]):
        try:
            samples=thread["samples"];stacks=thread["stackTable"];frames=thread["frameTable"];funcs=thread["funcTable"];strings=thread["stringArray"]
            times=samples.get("time")
            if times is None:
                times=[];total=0
                for delta in samples["timeDeltas"]:total+=delta;times.append(total)
            weights=samples.get("weight") or [1]*len(samples["stack"])
            for index,stack in enumerate(samples["stack"]):
                if bounds and not bounds[0]<=times[index]<=bounds[1]:continue
                if stack is None:unknown+=1;continue
                names=[];visited=set()
                while stack is not None:
                    if stack in visited:raise ValueError("cyclic stack")
                    visited.add(stack)
                    frame=stacks["frame"][stack];func=frames["func"][frame];name=strings[funcs["name"][func]]
                    native_index=frames["nativeSymbol"][frame] if "nativeSymbol" in frames else None
                    if native_index is not None and "nativeSymbols" in thread:
                        native_name=thread["nativeSymbols"]["name"][native_index]
                        name=strings[native_name] if isinstance(native_name,int) else native_name
                    resource=funcs.get("resource",[])[func] if funcs.get("resource") else None
                    lib_index=thread.get("resourceTable",{}).get("lib",[])[resource] if resource is not None and resource>=0 else None
                    library=profile.get("libs",[])[lib_index] if lib_index is not None and lib_index>=0 else {}
                    library_id=debug_id(library.get("breakpadId",""))
                    library_name=library.get("name","<unattributed>")
                    address=frames.get("address",[])[frame] if frames.get("address") else None
                    if isinstance(address,int) and address>=0:
                        name=symbol_libraries.get((library.get("debugName",""),library_id),{}).get(address,name)
                    frame_key=(library_name,library_id,name)
                    if re.fullmatch(r"(?:[^!]+!)?0x[0-9a-fA-F]+",name) or name in ("<unknown>","unknown",""):unresolved+=1
                    else:resolved+=1
                    names.append(frame_key)
                    stack=stacks["prefix"][stack]
                weight=weights[index] if weights[index] is not None else 1
                seen+=1
                if names:leaf[names[0]]+=weight
                for name in set(names):inclusive[name]+=weight
        except (KeyError,IndexError,TypeError,ValueError) as error:
            thread_errors.append({"thread":thread.get("name"),"error":str(error)})
    report={"profile":str(path.resolve()),"interval_ms":bounds,"samples_observed":seen,
            "null_stack_samples":unknown,"thread_errors":thread_errors,
            "stack_coverage_complete":not thread_errors and not unknown and seen>0,
            "symbol_coverage":{"resolved_frame_observations":resolved,"unresolved_frame_observations":unresolved,"complete":resolved>0 and unresolved==0},
            "coverage_complete":not thread_errors and not unknown and seen>0 and resolved>0 and unresolved==0,
            "top10_named_frames_gate_passed":not thread_errors and seen>0 and len(inclusive)>=10 and all(named(key[2]) for key,_ in inclusive.most_common(10)) and any(named(key[2]) and re.search(r"dm[-_]compile(?:d)?|compiler[-_]integration",key[0],re.I) for key,_ in inclusive.most_common(10)),
            "compiler_named_frames_observed":sum(1 for key in inclusive if named(key[2]) and re.search(r"dm[-_]compile(?:d)?|compiler[-_]integration",key[0],re.I)),
            "symbols_sidecar":args.symbols,
            "units":"sample weights; functions remain partitioned by library name and debug identity",
            "top10_inclusive":[{"library":key[0],"debug_id":key[1],"frame":key[2],"named":named(key[2]),"weight":weight,"leaf_weight":leaf[key]} for key,weight in inclusive.most_common(10)],
            "top10_leaf":[{"library":key[0],"debug_id":key[1],"frame":key[2],"named":named(key[2]),"weight":weight} for key,weight in leaf.most_common(10)]}
    Path(args.output).write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")

if __name__=="__main__":main()
