#!/usr/bin/env python3
"""One-time migration: rewrite map varedits of removed base state vars into cap_state.

Driven by tools/dx/capability_varmap.json; bit values come from code/__defines/cap_bits.dm.
Works textually on the .dmm dictionary (TGM multi-line and classic single-line), so the rest of
the file is byte-identical. Idempotent: a converted map converts to itself.

  python tools/dx/convert_map_capabilities.py --dry-run maps/southern_cross/*.dmm
  python tools/dx/convert_map_capabilities.py --report            # tree-wide counts over maps/
  python tools/dx/convert_map_capabilities.py FILE.dmm ...          # rewrite in place (migration waves)
  python tools/dx/convert_map_capabilities.py --selftest
See tools/dx/README.md.
"""
import argparse
import collections
import glob
import json
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BITS_FILE = os.path.join(REPO, "code", "__defines", "cap_bits.dm")
VARMAP_FILE = os.path.join(REPO, "tools", "dx", "capability_varmap.json")

FALSY = {"0", "null", "FALSE", '""', "0.0"}


def parse_cap_bits(path=BITS_FILE):
    bits = {}
    rx = re.compile(r"^\s*#define\s+(CAP_[A-Z0-9_]+)\s+\(?\s*1\s*<<\s*(\d+)\s*\)?")
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = rx.match(line)
            if m:
                bits[m.group(1)] = 1 << int(m.group(2))
    return bits


def split_top(s, sep):
    """Split on sep outside quotes/brackets."""
    out, depth, cur, q, i = [], 0, [], None, 0
    while i < len(s):
        c = s[i]
        if q:
            cur.append(c)
            if c == "\\" and i + 1 < len(s):
                cur.append(s[i + 1]); i += 2; continue
            if c == q:
                q = None
        elif c in "\"'":
            q = c; cur.append(c)
        elif c in "([{":
            depth += 1; cur.append(c)
        elif c in ")]}":
            depth -= 1; cur.append(c)
        elif c == sep and depth == 0:
            out.append("".join(cur)); cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return out


def find_close(s, start):
    """Index of the '}' matching the '{' at start."""
    depth, q, i = 0, None, start
    while i < len(s):
        c = s[i]
        if q:
            if c == "\\":
                i += 2; continue
            if c == q:
                q = None
        elif c in "\"'":
            q = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("unbalanced varedit block at %d" % start)


class Converter:
    def __init__(self, varmap, bits, numeric=False):
        self.bits = bits
        self.numeric = numeric
        self.rules = {k: v for k, v in varmap.items() if not k.startswith("_")}
        for prefix, rule in self.rules.items():
            for var, spec in rule.items():
                for name in self._spec_bits(var, spec):
                    if name not in bits:
                        raise SystemExit("varmap %s.%s names unknown bit %s" % (prefix, var, name))

    @staticmethod
    def _spec_bits(var, spec):
        if var == "_default_bits":
            return list(spec)
        if isinstance(spec, dict):
            return [b for v in spec.values() if v for b in v.split("|")]
        if isinstance(spec, str) and spec.startswith("CAP_"):
            return [spec]
        return []

    def rule_for(self, path):
        best = None
        for prefix in self.rules:
            if path == prefix or path.startswith(prefix + "/"):
                if best is None or len(prefix) > len(best):
                    best = prefix
        return best

    def value_to_bits(self, value):
        value = value.strip()
        total = 0
        for part in value.split("|"):
            part = part.strip().strip("()")
            if not part:
                continue
            if part in self.bits:
                total |= self.bits[part]
            else:
                total |= int(part, 0)
        return total

    def bits_to_value(self, n):
        if n == 0:
            return "0"
        if self.numeric:
            return str(n)
        names = [k for k, v in sorted(self.bits.items(), key=lambda kv: kv[1]) if n & v]
        # keep one name per value (aliases would double-count)
        seen, out = 0, []
        for k in names:
            if not (seen & self.bits[k]):
                out.append(k); seen |= self.bits[k]
        rest = n & ~seen
        if rest:
            out.append(str(rest))
        return "|".join(out)

    def convert_block(self, path, vars_):
        """vars_: list of (name, value). Returns (new_vars, stats Counter, warnings)."""
        stats, warns = collections.Counter(), []
        prefix = self.rule_for(path)
        if prefix is None:
            return vars_, stats, warns
        rule = self.rules[prefix]
        default = 0
        for name in rule.get("_default_bits", []):
            default |= self.bits[name]
        state, had_cap, touched, out = default, False, False, []
        for name, value in vars_:
            if name == "cap_state":
                try:
                    state = self.value_to_bits(value)
                except ValueError:
                    warns.append("%s: unparseable cap_state = %s (left alone)" % (path, value))
                    return vars_, collections.Counter(), warns
                had_cap = True
                continue
            spec = rule.get(name)
            if spec is None or spec == "keep":
                out.append((name, value)); continue
            v = value.strip()
            if spec == "drop":
                stats["drop:" + name] += 1; touched = True; continue
            if isinstance(spec, dict):
                if v not in spec:
                    warns.append("%s: %s = %s has no value mapping (left alone)" % (path, name, v))
                    out.append((name, value)); continue
                for bitname in (b for b in spec.values() if b):
                    state &= ~self.value_to_bits(bitname)
                if spec[v]:
                    state |= self.value_to_bits(spec[v])
            else:
                if v in FALSY:
                    state &= ~self.bits[spec]
                else:
                    state |= self.bits[spec]
            stats["%s->%s" % (name, spec if isinstance(spec, str) else "map")] += 1
            touched = True
        if not touched and not had_cap:
            return vars_, stats, warns
        if state != default:
            out.append(("cap_state", self.bits_to_value(state)))
            out.sort(key=lambda nv: nv[0])  # mapmerge keeps varedits sorted
        if had_cap and not touched:
            # idempotence: re-emit the existing value in canonical form only
            pass
        return out, stats, warns


BLOCK_RX = re.compile(r"(/[A-Za-z0-9_/]+)\{")


def parse_vars(body):
    res = []
    for part in split_top(body, ";"):
        part = part.strip()
        if not part:
            continue
        name, _, value = part.partition("=")
        res.append((name.strip(), value.strip()))
    return res


def render_vars(vars_, multiline):
    if multiline:
        return "\n" + ";\n".join("\t%s = %s" % nv for nv in vars_) + "\n\t"
    return "; ".join("%s = %s" % nv for nv in vars_)


def convert_text(text, conv):
    stats, warns = collections.Counter(), []
    out, pos = [], 0
    # only the dictionary part (before the first grid "(1,1,1)") holds varedits
    grid = re.search(r"^\(\d+,\d+,\d+\)", text, re.M)
    end = grid.start() if grid else len(text)
    for m in BLOCK_RX.finditer(text, 0, end):
        if m.start() < pos:
            continue
        open_i = m.end() - 1
        close_i = find_close(text, open_i)
        body = text[open_i + 1:close_i]
        vars_ = parse_vars(body)
        new_vars, s, w = conv.convert_block(m.group(1), vars_)
        stats.update(s); warns.extend(w)
        out.append(text[pos:open_i + 1])
        if new_vars != vars_ and new_vars:
            out.append(render_vars(new_vars, "\n" in body))
            out.append(text[close_i])
            pos = close_i + 1
        elif new_vars != vars_:
            # no varedits left: drop the braces entirely
            out[-1] = out[-1][:-1]
            pos = close_i + 1
        else:
            pos = open_i + 1
    out.append(text[pos:])
    return "".join(out), stats, warns


def load_converter(numeric=False, varmap_path=VARMAP_FILE):
    with open(varmap_path, encoding="utf-8") as f:
        return Converter(json.load(f), parse_cap_bits(), numeric=numeric)


def process(files, conv, write, verbose):
    total = collections.Counter()
    changed = 0
    for fn in files:
        with open(fn, encoding="utf-8", newline="") as f:
            text = f.read()
        new, stats, warns = convert_text(text, conv)
        n = sum(stats.values())
        total.update(stats)
        if verbose and (n or warns):
            print("%s: %d varedit(s)" % (os.path.relpath(fn, REPO), n))
            for k, v in sorted(stats.items()):
                print("    %-40s %d" % (k, v))
            for w in warns:
                print("    WARN " + w)
        if new != text:
            changed += 1
            if write:
                with open(fn, "w", encoding="utf-8", newline="") as f:
                    f.write(new)
    return total, changed


SELFTEST_BITS = "#define CAP_COVER_OPEN (1<<0)\n#define CAP_PANEL_OPEN (1<<1)\n#define CAP_LOCKED (1<<2)\n#define CAP_WELDED (1<<6)\n#define CAP_BOLTED (1<<7)\n#define CAP_COVER_REMOVED (1<<14)\n"
SELFTEST_MAP = {
    "/obj/machinery/door/airlock": {"locked": "CAP_BOLTED", "welded": "CAP_WELDED", "p_open": "CAP_PANEL_OPEN", "operating": "drop"},
    "/obj/machinery/power/apc": {"_default_bits": ["CAP_LOCKED"], "locked": "CAP_LOCKED",
                                 "opened": {"0": None, "1": "CAP_COVER_OPEN", "2": "CAP_COVER_REMOVED"}},
}
SELFTEST_IN = '''//MAP CONVERTED BY dmm2tgm.py THIS HEADER COMMENT PREVENTS RECONVERSION, DO NOT REMOVE
"a" = (
/obj/machinery/door/airlock/external{
	id_tag = "x;y}";
	locked = 1;
	name = "Airlock {A}";
	req_access = list(13,"a;b");
	welded = 1
	},
/obj/machinery/door/airlock{
	operating = 0
	},
/obj/machinery/door/airlock{
	cap_state = CAP_PANEL_OPEN;
	locked = 1;
	p_open = 1
	},
/obj/machinery/power/apc{
	locked = 0;
	opened = 2
	},
/obj/machinery/power/apc{
	locked = 1
	},
/obj/structure/closet{
	locked = 1
	},
/turf/simulated/floor)
"b" = (/obj/machinery/door/airlock{locked = 1; name = "q"},/turf/space)

(1,1,1) = {"
a
b
"}
'''
SELFTEST_OUT = '''//MAP CONVERTED BY dmm2tgm.py THIS HEADER COMMENT PREVENTS RECONVERSION, DO NOT REMOVE
"a" = (
/obj/machinery/door/airlock/external{
	cap_state = CAP_WELDED|CAP_BOLTED;
	id_tag = "x;y}";
	name = "Airlock {A}";
	req_access = list(13,"a;b")
	},
/obj/machinery/door/airlock,
/obj/machinery/door/airlock{
	cap_state = CAP_PANEL_OPEN|CAP_BOLTED
	},
/obj/machinery/power/apc{
	cap_state = CAP_COVER_REMOVED
	},
/obj/machinery/power/apc,
/obj/structure/closet{
	locked = 1
	},
/turf/simulated/floor)
"b" = (/obj/machinery/door/airlock{cap_state = CAP_BOLTED; name = "q"},/turf/space)

(1,1,1) = {"
a
b
"}
'''


def selftest():
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        bp = os.path.join(d, "bits.dm")
        with open(bp, "w") as f:
            f.write(SELFTEST_BITS)
        conv = Converter(SELFTEST_MAP, parse_cap_bits(bp))
    got, stats, warns = convert_text(SELFTEST_IN, conv)
    ok = True
    if got != SELFTEST_OUT:
        ok = False
        print("FAIL: conversion output differs\n--- got ---\n" + got)
    again, s2, _ = convert_text(got, conv)
    if again != got or sum(s2.values()):
        ok = False
        print("FAIL: not idempotent\n" + again)
    num = Converter(SELFTEST_MAP, conv.bits, numeric=True)
    if "cap_state = 192" not in convert_text(SELFTEST_IN, num)[0]:
        ok = False
        print("FAIL: --numeric")
    # the real varmap must load against the real cap_bits.dm
    load_converter()
    print("selftest: %s (%d conversions)" % ("PASS" if ok else "FAIL", sum(stats.values())))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*")
    ap.add_argument("--dry-run", action="store_true", help="print a per-map summary, write nothing")
    ap.add_argument("--report", action="store_true", help="count convertible varedits tree-wide (maps/)")
    ap.add_argument("--numeric", action="store_true", help="emit cap_state as an integer instead of CAP_ names")
    ap.add_argument("--varmap", default=VARMAP_FILE)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    conv = load_converter(a.numeric, a.varmap)
    if a.report:
        files = sorted(glob.glob(os.path.join(REPO, "maps", "**", "*.dmm"), recursive=True))
        total, changed = process(files, conv, write=False, verbose=False)
        print("maps/: %d varedit(s) in %d of %d map(s)" % (sum(total.values()), changed, len(files)))
        for k, v in sorted(total.items()):
            print("    %-40s %d" % (k, v))
        return 0
    if not a.files:
        ap.error("no files (or use --report / --selftest)")
    total, changed = process(a.files, conv, write=not a.dry_run, verbose=True)
    print("%s: %d varedit(s), %d map(s) %s" % ("dry-run" if a.dry_run else "done", sum(total.values()),
                                              changed, "would change" if a.dry_run else "changed"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
