#!/usr/bin/env python3
"""Every reference the Byondapi hands native code is persistent (BYOND 516.1674+) and must be released with ByondValue_DecRef.
byondapi-rs's ByondValue is Copy with no Drop, so a raw read pins the DM object forever (a map atom read out of a turf's contents
leaked this way). verdigris/ffi/callback/src/held.rs is the one place that releases: `Held` / `HeldList` own a value and release it on
drop, and the `HeldRead` trait (held_list, held_var_id, held_call_id, held_index, held_pairs, ...) returns them.

This check rejects, in every Rust source under verdigris/ outside held.rs, a call of the raw API that returns a reference
(read_var, read_var_id, get_list_values, get_list, read_list*, call, call_id, call_global*, pop_list, builtin_new*,
ByondValue::new_list, byond_block, byond_locate*, the raw list iterators iter()/values() with `?`) and a hand-written
increment_ref/decrement_ref/decrement_tempref. No annotation silences it: use the Held form.

  python3 tools/ci/check_byond_refs.py [--root DIR]     # check DIR (default: the repo)
  python3 tools/ci/check_byond_refs.py --selftest        # prove it catches a raw read and passes the wrapper form
"""
import os
import re
import sys
import tempfile

EXEMPT = ("verdigris/ffi/callback/src/held.rs",)
SCAN_DIRS = ("verdigris/ffi", "verdigris/verdigris", "verdigris/domains")

NAMES = (r"get_list_values|get_list|read_var_id|read_var|read_list_id|read_list_index_internal|read_list_index|read_list|"
         r"call_id|call|pop_list|decrement_ref|increment_ref|decrement_tempref")
RULES = [
    ("raw method", re.compile(r"\.(?:%s)\s*\(" % NAMES)),
    ("raw global call", re.compile(r"\bcall_global(?:_id)?\s*\(")),
    ("raw constructor", re.compile(r"\bbuiltin_new(?:arglist)?\s*\(|\bByondValue::new_list\s*\(|\bbyond_(?:block|locatein|locateby|locatexyz)\s*\(")),
    ("raw list iterator", re.compile(r"\.(?:iter|values)\(\)\s*(?:\?|\.wrap_err|\.map_err|\.unwrap|\.expect)")),
]
HINT = "read it through crate::held::HeldRead (held_list, held_var_id, held_call_id, held_index, held_pairs, held_values) or Held::new_list / hand_list"


def strip_comments(text):
    out = []
    for line in text.split("\n"):
        i = line.find("//")
        out.append(line if i < 0 else line[:i])
    return "\n".join(out)


def scan_text(text, rel):
    code = strip_comments(text.replace("\r\n", "\n"))
    hits = []
    for label, rx in RULES:
        for m in rx.finditer(code):
            line = code.count("\n", 0, m.start()) + 1
            hits.append("%s:%d: %s `%s`" % (rel, line, label, m.group(0).strip()))
    return hits


def scan_file(path, rel):
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return []
    return scan_text(text, rel)


def check(root):
    hits = []
    for d in SCAN_DIRS:
        for dirpath, dirnames, filenames in os.walk(os.path.join(root, d)):
            dirnames[:] = [x for x in dirnames if x not in ("target", "target-lead", "macros")]
            for fn in filenames:
                if not fn.endswith(".rs"):
                    continue
                path = os.path.join(dirpath, fn)
                rel = os.path.relpath(path, root).replace(os.sep, "/")
                if rel in EXEMPT:
                    continue
                hits += scan_file(path, rel)
    return hits


def selftest():
    bad = [
        "let l = thing.get_list_values()?;",
        'let v = turf.read_var_id(byond_string!("x"))?;',
        "let r = src.call_id(id, &[])?;",
        "let it = list.iter()?;",
        "let it = list\n    .values()\n    ?;",
        "x.decrement_ref();",
        "let l = ByondValue::new_list()?;",
        "let g = call_global_id(id, &[])?;",
    ]
    good = [
        "let l = thing.held_list()?;",
        'let v = turf.held_var_id(byond_string!("x"))?;',
        "let n = x.read_number_id(id)?;",
        "// thing.get_list_values() is only named in a comment",
        "let l = Held::new_list()?;",
        "for v in slice.iter() {}",
    ]
    ok = True
    for snippet in bad:
        if not scan_text("fn f() {\n%s\n}\n" % snippet, "bad.rs"):
            print("selftest: missed a raw read: %r" % snippet)
            ok = False
    for snippet in good:
        if scan_text("fn f() {\n%s\n}\n" % snippet, "good.rs"):
            print("selftest: flagged the wrapper form: %r" % snippet)
            ok = False
    # The whole-tree walk finds a bad file, and the wrapper module itself is exempt.
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "verdigris", "ffi", "src")
        cb = os.path.join(tmp, "verdigris", "ffi", "callback", "src")
        os.makedirs(src)
        os.makedirs(cb)
        with open(os.path.join(cb, "held.rs"), "w") as f:
            f.write("fn f() { v.get_list_values(); x.decrement_ref(); }\n")
        with open(os.path.join(src, "lib.rs"), "w") as f:
            f.write("fn f() { v.read_var_id(1); }\n")
        found = check(tmp)
        if len(found) != 1 or "lib.rs" not in found[0]:
            print("selftest: tree walk expected exactly lib.rs flagged, got %r" % found)
            ok = False
    print("check_byond_refs selftest: %s" % ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv):
    if "--selftest" in argv:
        return selftest()
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    if "--root" in argv:
        root = argv[argv.index("--root") + 1]
    hits = check(os.path.abspath(root))
    if hits:
        print("check_byond_refs: raw Byondapi reference reads outside verdigris/ffi/callback/src/held.rs "
              "(every API reference is persistent and leaks its DM object unless released):")
        for h in hits:
            print("  " + h)
        print("fix: " + HINT)
        return 1
    print("check_byond_refs: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
