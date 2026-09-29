#!/usr/bin/env python3
"""Tracked-var write lint (doc/rewrite/dx_conventions.md §1, final_design.md §1).

`TRACKED(T, var, channel)` (code/__defines/capabilities.dm) declares that `var` on type T (and its
subtypes) is written only through its setter `T/proc/set_<var>(value)`, which calls changed().
`SETTER(T, var)` registers a hand-written `T/proc/set_<var>(value)` as var's setter and makes var
tracked exactly the same way. A hand-written `/T/proc/set_<var>(` (or a subtype override of it) is
the setter body. Reads are unrestricted.

Counted, for every tracked var V of type T, outside a setter body of V:
  * `V = x`, `src.V = x`, `V += x`, `V -= x` (and the other compound ops), `V++`, `V--`, `++V`, `--V`
    inside a proc of T or a subtype (a proc-local `var/V` shadows it and is skipped);
  * `X.V = x` (and the same ops) anywhere, when X resolves to T or a subtype: a proc argument or a
    local declared `var/<type>/X` / `<type>/X` in the same proc.
A derive() value (`. += derive(nameof(var), ...)` in a derived() proc, code/datums/capabilities/derived.dm)
is tracked with no setter at all: the framework is its only writer, so every write in DM is counted.
Not counted: type-level var defaults and declarations, `==` compares, #define lines, comments and
strings, and lines carrying `// ALLOW(tracked): <reason>` (tools/ci/allow_annotations.py).

The baseline is empty: the target is 0.

    python tools/ci/tracked_lint.py             # the CI check
    python tools/ci/tracked_lint.py --report    # every tracked var and setter found
    python tools/ci/tracked_lint.py --selftest  # run the built-in fixtures
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402
from allow_annotations import allowed  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
LINT = "tracked"

TRACKED_LINE = re.compile(r"^\s*(?:TRACKED\(\s*(/[\w/]+)\s*,\s*(\w+)\s*,|SETTER\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\))")
DERIVE_VAR = re.compile(r"\bderive\(\s*nameof\(\s*(?:/[\w/]+::)?(\w+)\s*\)")
# A top-level proc definition: /type/proc/name(, /type/verb/name( or /type/name( (an override).
PROC_DEF = re.compile(r"^(/[\w/]*?)/(?:(?:proc|verb)/)?(\w+)\s*\((.*)$")
TYPE_DEF = re.compile(r"^/[\w/]+\s*$")
OPS = r"(?:=(?!=)|\+=|-=|\*=|/=|\|=|&=|\^=|<<=|>>=|\+\+|--)"
LOCAL_DECL = re.compile(r"\bvar/(?:[\w/]*/)?(\w+)\b")
TYPED_NAME = re.compile(r"(?:\bvar)?(/[\w/]+)/(\w+)\b")
ARG_TYPED = re.compile(r"(?:^|[(,])\s*(?:var/)?((?:/?[\w]+/)*[\w]+)/(\w+)\s*(?==|,|\)|$|\bas\b)")


def is_subtype(path, base):
    return path == base or path.startswith(base + "/")


def normalize_type(path):
    path = path.strip()
    if not path.startswith("/"):
        path = "/" + path
    return path.rstrip("/")


def parse_procs(code_text):
    """Yields (type, proc_name, arg_text, [(line_no, line_text)]) for each top-level proc, and
    ignores type blocks (var defaults are not writes)."""
    lines = code_text.split("\n")
    current = None
    for number, line in enumerate(lines, 1):
        if line and not line[0].isspace():
            if current:
                yield current
                current = None
            stripped = line.rstrip()
            if stripped.startswith("#") or TYPE_DEF.match(stripped):
                continue
            m = PROC_DEF.match(stripped)
            if m:
                owner = m.group(1) or "/"
                args = m.group(3)
                current = (owner, m.group(2), args, [])
            continue
        if current and line.strip():
            current[3].append((number, line))
    if current:
        yield current


def tracked_from_text(raw, tracked):
    """Adds the vars `raw` declares tracked (TRACKED lines, derive() values) to {var: {types}}."""
    if "TRACKED(" in raw or "SETTER(" in raw:
        for line in raw.split("\n"):
            if line.lstrip().startswith("#define"):
                continue
            m = TRACKED_LINE.match(line)
            if m:
                add_tracked(tracked, m)
    if "derive(" in raw:
        for owner, proc_name, _args, body in parse_procs(code_only(raw)):
            if proc_name != "derived" or owner == "/":
                continue
            for m in DERIVE_VAR.finditer("\n".join(text for _, text in body)):
                tracked.setdefault(m.group(1), set()).add(normalize_type(owner))


def collect(files):
    """{var: [types]} from TRACKED lines and derive() values; the raw texts."""
    tracked = {}
    texts = {}
    for path, rel in files:
        with open(path, encoding="utf-8", errors="replace") as handle:
            raw = handle.read()
        texts[rel] = raw
        tracked_from_text(raw, tracked)
    return tracked, texts


def add_tracked(tracked, m):
    """Records the var of a TRACKED_LINE match (TRACKED or SETTER) on its type."""
    var = m.group(2) or m.group(4)
    path = m.group(1) or m.group(3)
    tracked.setdefault(var, set()).add(normalize_type(path))


def tracked_type_of(tracked, var, owner):
    for base in tracked.get(var, ()):
        if is_subtype(owner, base):
            return base
    return None


def scan(tracked, texts):
    """[(rel, line_no, message)] for every write outside a setter; also the setters seen."""
    hits, setters = [], []
    if not tracked:
        return hits, setters
    names = "|".join(sorted(map(re.escape, tracked)))
    bare = re.compile(rf"(?<![\w.])(?:src\.)?({names})\s*{OPS}|(?:\+\+|--)\s*(?<![\w.])(?:src\.)?({names})\b")
    dotted = re.compile(rf"(?<![\w.])(\w+)\.({names})\s*{OPS}|(?:\+\+|--)\s*(\w+)\.({names})\b")
    for rel, raw in sorted(texts.items()):
        if not any(v in raw for v in tracked):
            continue
        raw_lines = raw.split("\n")
        for owner, proc_name, args, body in parse_procs(code_only(raw)):
            owner = normalize_type(owner) if owner != "/" else "/"
            is_setter_of = None
            if proc_name.startswith("set_"):
                var = proc_name[4:]
                if tracked_type_of(tracked, var, owner):
                    is_setter_of = var
                    setters.append((rel, owner, proc_name))
            locals_ = set()
            typed = {}
            for m in ARG_TYPED.finditer(args):
                typed[m.group(2)] = normalize_type(m.group(1))
                locals_.add(m.group(2))
            for number, line in body:
                if line.lstrip().startswith("#"):
                    continue
                for m in LOCAL_DECL.finditer(line):
                    locals_.add(m.group(1))
                for m in TYPED_NAME.finditer(line):
                    typed[m.group(2)] = normalize_type(m.group(1))
                for m in bare.finditer(line):
                    var = m.group(1) or m.group(2)
                    if var == is_setter_of:
                        continue
                    written_via_src = "src." + var in m.group(0)
                    if var in locals_ and not written_via_src:
                        continue
                    if re.search(rf"\bvar/(?:[\w/]*/)?{re.escape(var)}\b", line):
                        continue
                    base = tracked_type_of(tracked, var, owner)
                    if base and not allowed(raw_lines, number, LINT):
                        hits.append((rel, number, "%s written outside %s/proc/set_%s()" % (var, base, var)))
                for m in dotted.finditer(line):
                    holder = m.group(1) or m.group(3)
                    var = m.group(2) or m.group(4)
                    if holder == "src":
                        continue  # the bare pattern counts src.V
                    holder_type = typed.get(holder)
                    base = tracked_type_of(tracked, var, holder_type) if holder_type else None
                    if base and not allowed(raw_lines, number, LINT):
                        hits.append((rel, number, "%s.%s written outside %s/proc/set_%s()" % (holder, var, base, var)))
    return hits, setters


def dm_files():
    for top in ("code", "maps"):
        for path in glob.glob(os.path.join(ROOT, top, "**", "*.dm"), recursive=True):
            yield path, os.path.relpath(path, ROOT).replace(os.sep, "/")


SELFTEST = {
    "code/a.dm": """
/obj/machinery/pump
	var/target_pressure = 100
	var/other = 1
TRACKED(/obj/machinery/pump, target_pressure, CHANGE_MACHINE_SETTINGS)

/obj/machinery/pump/bigger
	target_pressure = 200

/obj/machinery/pump/proc/bad_direct()
	target_pressure = 5
	src.target_pressure += 1
	target_pressure++
	--target_pressure

/obj/machinery/pump/proc/good_read()
	if(target_pressure == 5)
		other = target_pressure
	set_target_pressure(7)

/obj/machinery/pump/proc/shadowed()
	var/target_pressure = 3
	target_pressure -= 1

/obj/machinery/pump/proc/allowed_write()
	target_pressure = 1 // ALLOW(tracked): fixture keep

/obj/machinery/pump/bigger/proc/subtype_write()
	target_pressure = 9

/obj/machinery/pump/bigger/set_target_pressure(value)
	target_pressure = value * 2
	return TRUE

/obj/other_thing/proc/unrelated()
	target_pressure = 4

/proc/external(obj/machinery/pump/P, obj/other_thing/Q)
	P.target_pressure = 3
	Q.target_pressure = 3
	var/obj/machinery/pump/bigger/B = P
	B.target_pressure -= 2
	unknown.target_pressure = 1
	// P.target_pressure = 8 in a comment
	var/s = "P.target_pressure = 8"

/obj/machinery/valve
	var/open = FALSE
SETTER(/obj/machinery/valve, open)

/obj/machinery/valve/proc/set_open(value)
	open = value
	update_pipes()

/obj/machinery/valve/proc/bad_open()
	open = TRUE

/proc/external_valve(obj/machinery/valve/V)
	V.open = FALSE
	if(V.open == TRUE)
		return
""",
    "code/b.dm": """
/obj/gadget
	var/total = 0

/obj/gadget/derived()
	. = ..()
	. += derive(nameof(total), nameof(level))

/obj/gadget/proc/oops()
	total = 5
""",
}

SELFTEST_EXPECT = [
    ("code/a.dm", 11, "target_pressure"),
    ("code/a.dm", 12, "target_pressure"),
    ("code/a.dm", 13, "target_pressure"),
    ("code/a.dm", 14, "target_pressure"),
    ("code/a.dm", 29, "target_pressure"),
    ("code/a.dm", 39, "P.target_pressure"),
    ("code/a.dm", 42, "B.target_pressure"),
    ("code/a.dm", 56, "open"),
    ("code/a.dm", 59, "V.open"),
    ("code/b.dm", 10, "total"),
]


def selftest():
    tracked = {}
    for text in SELFTEST.values():
        tracked_from_text(text, tracked)
    hits, setters = scan(tracked, SELFTEST)
    got = [(rel, n, msg.split(" ")[0]) for rel, n, msg in hits]
    ok = got == SELFTEST_EXPECT and len(setters) == 2
    if not ok:
        print("tracked_lint selftest FAILED")
        print("  expected:", SELFTEST_EXPECT)
        print("  got:     ", got)
        print("  setters: ", setters)
        return 1
    print("tracked_lint selftest passed (%d fixtures)" % len(SELFTEST_EXPECT))
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    tracked, texts = collect(dm_files())
    hits, setters = scan(tracked, texts)
    if "--report" in argv:
        for var in sorted(tracked):
            print("tracked: %s on %s" % (var, ", ".join(sorted(tracked[var]))))
        for rel, owner, proc_name in setters:
            print("setter: %s/%s (%s)" % (owner, proc_name, rel))
    for rel, number, msg in hits:
        print("%s:%d: %s (write it through the setter, or `// ALLOW(tracked): <reason>`)" % (rel, number, msg))
    print("tracked vars: %d, writes outside setters: %d (target 0)" % (len(tracked), len(hits)))
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
