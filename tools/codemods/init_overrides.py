#!/usr/bin/env python3
r"""Initialize() overrides -> declarations or a justified keep (Phase C; doc/rewrite/final_api.html section 6 "Lifecycle",
the init lint in tools/analyze/src/lints/init.rs; rules in doc/rewrite/codemod_rules.md "Initialize() overrides").

    python tools/codemods/init_overrides.py [--apply] [--class C ...] [--sites] [--others] [--paths prefix ...]

Each column-0 `/T/Initialize(` header without an `ALLOW(init/...)` is classified:

  safe-auto
    redundant      the body is only `. = ..()` / `return ..()`: the override is deleted.
    ctor_args      it takes constructor arguments past `mapload` and its body reads them: `// ALLOW(init/CTOR_ARGS)` above
                   the header, the reason naming the arguments.
    instance_rand  every statement (past the `..()` call) writes a var of src from a random roll (rand, pick, prob,
                   randpixel_xy...), possibly under an `if(prob())`: `// ALLOW(init/INSTANCE_STATE)` naming the vars.
    instance_place every statement writes a var of src from where it is placed (loc, get_turf, get_area, x/y/z, mapload) or
                   is gated on mapload: `// ALLOW(init/INSTANCE_STATE)` naming the vars.
    timer          the body is `..()` plus exactly one `after(src, D, PROC_REF(x))` (or `then(PROC_REF(x))`): an
                   `after_init(D, then(PROC_REF(x)))` entry in the type's CAPABILITIES block (made when it has none), the
                   override deleted, and `x()` taking `(datum/act/timer/A)` when it took nothing.
  needs-review     everything else (the residue, by code: --sites lists them).

Idempotent: a kept header is skipped, a deleted one is gone. Run `analyze gen` afterwards.
"""
import argparse
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dmlib import (  # noqa: E402
    File,
    ROOT,
    block_end,
    capabilities_index,
    dm_files,
    procs_in,
    statements,
    strip_code,
    word_in,
)

PARENT = re.compile(r"^(\.\s*=\s*\.\.\((.*)\)|return\s+\.\.\((.*)\)|\.\.\((.*)\))$")
RETURN_DOT = re.compile(r"^return\s*\.?$")
ASSIGN = re.compile(r"^(?:src\.)?([a-z_]\w*)\s*(=|\+=|-=|\|=|\*=)\s*(?!=)(.+)$")
RAND_SRC = re.compile(r"(?<![\w.])(rand|pick|prob|rand_\w+|roll|pickweight|gaussian|random_\w+|rand_hex_color|get_random_\w+)\s*\(")
PLACE_SRC = re.compile(r"(?<![\w.])(loc|get_turf|get_area|mapload|x|y|z)(?!\w)")
RAND_CALLS = re.compile(r"^(randpixel_xy|random_offset|pixel_randomize)\(\s*\)$")
COND = re.compile(r"^(if|else if)\s*\((.*)\)\s*$")
TIMER = re.compile(r"^after\(\s*src\s*,\s*(.+?)\s*,\s*(?:then\(\s*)?PROC_REF\((\w+)\)\s*\)?\s*\)$")
SKIP_VARS = {"loc", "contents", "vars", "type", "parent_type", "tag", "verbs", "x", "y", "z"}


def classify(proc):
    """(class, detail) for one override."""
    f = proc.file
    header = proc.header
    above = f.lines[proc.start - 1] if proc.start else ""
    if "ALLOW(init" in header or (above.lstrip().startswith("//") and "ALLOW(init" in above):
        return "kept", None
    params = proc.params()
    if params is None:
        return "review", "header_spans_lines"
    stmts = statements(f, proc.start + 1, proc.end)
    if any(s.indent < 1 for s in stmts):
        return "review", "odd_indent"
    body_text = "\n".join(s.code for s in stmts)
    if "#" in "".join(f.lines[proc.start + 1 : proc.end]).replace("#define", ""):
        if any(f.lines[k].lstrip().startswith("#") for k in range(proc.start + 1, proc.end)):
            return "review", "preprocessor"
    extra = [p for p in params[1:] if p != "..."]
    if extra:
        used = [p for p in extra if word_in(body_text, p)]
        if used:
            return "ctor_args", extra
        # Unused constructor parameters: `..()` passes the call's arguments on by itself, so they can go.
        if re.search(r"\.\.\(\s*[^)\s]", body_text):
            return "review", "ctor_args_unused"
        cls, detail = classify_body(proc, stmts)
        if cls == "review":
            return "review", "ctor_args_unused"
        return cls, detail
    return classify_body(proc, stmts)


def classify_body(proc, stmts):
    top = [s for s in stmts if s.indent == 1]
    parent = [s for s in top if PARENT.match(s.code)]
    if len(parent) != 1:
        return "review", "parent_call_count"
    pm = PARENT.match(parent[0].code)
    pargs = next(g for g in pm.groups()[1:] if g is not None)
    if pargs.strip() not in ("", "mapload"):
        return "review", "parent_args"
    rest = [s for s in stmts if s is not parent[0] and not RETURN_DOT.match(s.code)]
    if any("return" in s.code.split("(")[0] for s in rest):
        return "review", "returns"
    if not rest:
        return "redundant", None
    # After-init timer
    if len(rest) == 1 and rest[0].indent == 1:
        m = TIMER.match(rest[0].code)
        if m:
            return "timer", (m.group(1), m.group(2))
    # Instance state: assignments to src vars from a random roll or the placement, possibly under if/else.
    kinds = set()
    names = []
    i = 0
    work = [(s.code, s.indent) for s in rest]
    while work:
        code, indent = work.pop(0)
        c = split_cond(code)
        if c:
            cond, tail = c
            if RAND_SRC.search(cond):
                kinds.add("rand")
            elif PLACE_SRC.search(cond):
                kinds.add("place")
            else:
                cond_ok = re.fullmatch(r"!?\s*[\w.]+(\s*(==|!=)\s*[\w\"/.]+)?", cond.strip())
                if not cond_ok:
                    return "review", "condition"
            if tail:
                work.insert(0, (tail, indent + 1))
            continue
        if code == "else":
            continue
        if code.startswith("else "):
            work.insert(0, (code[5:].strip(), indent + 1))
            continue
        if RAND_CALLS.match(code):
            kinds.add("rand")
            names.append("its pixel offset")
            continue
        a = ASSIGN.match(code)
        if not a:
            return "review", "statement"
        var, rhs = a.group(1), a.group(3)
        if var in SKIP_VARS or "(" in var:
            return "review", "special_var"
        if RAND_SRC.search(rhs):
            kinds.add("rand")
        elif PLACE_SRC.search(rhs):
            kinds.add("place")
        elif indent == 1:
            # A constant write at top level is a type fact, not instance state.
            return "review", "constant_write"
        if var not in names:
            names.append(var)
    if not kinds or not names:
        return "review", "constant_write"
    if "rand" in kinds:
        return "instance_rand", names
    return "instance_place", names


def split_cond(code):
    """`if(cond) tail` / `else if(cond) tail` -> (cond, tail), the condition's brackets balanced; None for anything else."""
    m = re.match(r"^(?:else\s+)?if\s*\(", code)
    if not m:
        return None
    depth, k = 1, m.end()
    while k < len(code) and depth:
        depth += {"(": 1, ")": -1}.get(code[k], 0)
        k += 1
    if depth:
        return None
    return code[m.end() : k - 1], code[k:].strip()


def join_names(names):
    names = [n for n in names]
    if len(names) == 1:
        return names[0]
    return ", ".join(names[:-1]) + " and " + names[-1]


def reason(cls, detail):
    if cls == "ctor_args":
        args = join_names(detail)
        verb = "is a constructor argument" if len(detail) == 1 else "are constructor arguments"
        return "// ALLOW(init/CTOR_ARGS): %s %s from whoever builds it" % (args, verb)
    if cls == "instance_rand":
        return "// ALLOW(init/INSTANCE_STATE): %s rolled at random for each instance" % join_names(detail)
    if cls == "instance_place":
        return "// ALLOW(init/INSTANCE_STATE): %s taken from where this instance is placed" % join_names(detail)
    raise ValueError(cls)


def delete_proc(f, proc):
    """Remove the override and a doc comment directly attached above it; collapse the blank lines left behind."""
    start = proc.start
    while start > 0 and f.lines[start - 1].lstrip().startswith("///") and not f.lines[start - 1].startswith(("\t", " ")):
        start -= 1
    end = proc.end
    while end < len(f.lines) and f.lines[end].strip() == "":
        end += 1
    keep_blank = start > 0 and f.lines[start - 1].strip() != "" and end < len(f.lines)
    f.lines[start:end] = [""] if keep_blank else []
    f.dirty = True
    return start, keep_blank


def handler_defs(name):
    """(rel, index) of every `/X/proc/name(` or `/X/name(` definition in code/."""
    out = []
    pat = re.compile(r"^/[\w/]+/(?:proc/)?" + re.escape(name) + r"\s*\(([^)]*)\)")
    for root, _, fs in os.walk(os.path.join(ROOT, "code")):
        for fn in fs:
            if fn.endswith(".dm"):
                p = os.path.join(root, fn)
                with open(p, encoding="utf-8", errors="surrogateescape") as fh:
                    for k, line in enumerate(fh):
                        if name in line and pat.match(line):
                            out.append((os.path.relpath(p, ROOT).replace("\\", "/"), k, pat.match(line).group(1)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--class", dest="classes", nargs="*", default=["redundant", "ctor_args", "instance_rand", "instance_place", "timer"])
    ap.add_argument("--sites", action="store_true")
    ap.add_argument("--others", action="store_true", help="include other agents' folders")
    ap.add_argument("--paths", nargs="*", default=["code/"])
    ap.add_argument("--residue", help="write the residue as JSON here")
    ap.add_argument("--limit", type=int, default=0, help="stop after this many converted files")
    a = ap.parse_args()

    files = dm_files(a.paths, others=a.others)
    counts = collections.Counter()
    residue = collections.Counter()
    residue_sites = []
    cap_idx = None
    touched = []
    open_files = {}

    def get(relpath):
        if relpath not in open_files:
            open_files[relpath] = File(relpath)
        return open_files[relpath]

    for relpath in files:
        if a.limit and len(touched) >= a.limit:
            break
        f = get(relpath)
        if "Initialize" not in "\n".join(f.lines):
            continue
        procs = [p for p in procs_in(f) if p.name == "Initialize" and p.kind is None]
        changed = False
        for proc in reversed(procs):  # bottom-up: indices stay valid
            cls, detail = classify(proc)
            if cls == "kept":
                continue
            if cls == "review":
                residue[detail] += 1
                residue_sites.append({"file": relpath, "line": proc.start + 1, "type": proc.type, "code": detail})
                if a.sites:
                    print("review\t%s\t%s\t%s:%d" % (detail, proc.type, relpath, proc.start + 1))
                continue
            counts[cls] += 1
            if a.sites:
                print("%s\t%s\t%s:%d" % (cls, proc.type, relpath, proc.start + 1))
            if not a.apply or cls not in a.classes:
                continue
            extra = [p for p in (proc.params() or [])[1:] if p != "..."]
            if extra and cls != "ctor_args":
                # Drop the unused constructor parameters first (the header keeps `mapload` and a `...`).
                keep = ["mapload"] + (["..."] if "..." in proc.params() else [])
                hdr = f.lines[proc.start]
                head, _, tail = hdr.partition("(")
                depth, k = 1, 0
                while k < len(tail) and depth:
                    depth += {"(": 1, ")": -1}.get(tail[k], 0)
                    k += 1
                f.lines[proc.start] = head + "(" + ", ".join(keep) + ")" + tail[k:]
                f.dirty = True
            if cls == "redundant":
                delete_proc(f, proc)
            elif cls in ("ctor_args", "instance_rand", "instance_place"):
                f.lines.insert(proc.start, reason(cls, detail))
                f.dirty = True
            elif cls == "timer":
                delay, handler = detail
                if cap_idx is None:
                    cap_idx = capabilities_index()
                entry = "\tafter_init(%s, then(PROC_REF(%s)))" % (delay, handler)
                where = cap_idx.get(proc.type)
                if where and where[0] != relpath:
                    g = get(where[0])
                    g.lines.insert(block_end(g, where[1]), entry)
                    g.dirty = True
                    delete_proc(f, proc)
                elif where:
                    # Same file: delete first if the block is below the override, then insert.
                    hdr = where[1]
                    if hdr > proc.start:
                        n_before = len(f.lines)
                        delete_proc(f, proc)
                        hdr -= n_before - len(f.lines)
                        f.lines.insert(block_end(f, hdr), entry)
                    else:
                        f.lines.insert(block_end(f, hdr), entry)
                        delete_proc(f, proc)
                else:
                    at, blank = delete_proc(f, proc)
                    block = ["CAPABILITIES(%s)" % proc.type, entry]
                    if blank:
                        f.lines[at + 1 : at + 1] = block + [""]
                        cap_idx[proc.type] = (relpath, at + 1)
                    else:
                        f.lines[at:at] = block + ([""] if at < len(f.lines) else [])
                        cap_idx[proc.type] = (relpath, at)
                    f.dirty = True
                for hrel, k, params in handler_defs(handler):
                    if params.strip() == "":
                        g = get(hrel)
                        g.lines[k] = g.lines[k].replace(handler + "()", handler + "(datum/act/timer/A)", 1)
                        g.dirty = True
            changed = True
        if changed:
            touched.append(relpath)
    if a.apply:
        for g in open_files.values():
            g.save()
    print("init_overrides: safe-auto %s; needs-review %d %s" % (dict(counts), sum(residue.values()), dict(residue.most_common())))
    if a.apply:
        print("files changed: %d" % len([g for g in open_files.values() if g.dirty]))
    if a.residue:
        with open(a.residue, "w") as fh:
            json.dump(residue_sites, fh, indent=1)


if __name__ == "__main__":
    main()
