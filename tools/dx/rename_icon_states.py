#!/usr/bin/env python3
"""One-time migration: rename icon states to readable capability layer names.

Driven by tools/dx/icon_state_renames.json ({"icons/x.dmi": {"old": "new"}}). Works on the icon
pipeline SOURCES (icons/**/*.dmi.toml; the .png is positional, so only the state name changes) and
never touches icons/gen/. Then rewrites references:
  * code: exact "old" string literals in .dm files that reference 'icons/x.dmi', on lines with icon
    context (icon_state, overlay, flick, image, appearance...), when no other dmi the file references
    also has a state "old". Everything else that might be a reference (interpolated strings such as
    "[icon_state]-panel", literals in files that reference several candidate dmis, literals without
    icon context) is LISTED as ambiguous, never changed.
  * maps: icon_state = "old" varedits on instances whose icon is that dmi (an icon = varedit, or the
    type's declared icon, resolved through the type tree parsed from code/).

  python tools/dx/rename_icon_states.py --dry-run         # list everything, write nothing
  python tools/dx/rename_icon_states.py                   # apply (migration waves only)
  python tools/dx/rename_icon_states.py --selftest
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
RENAMES_FILE = os.path.join(REPO, "tools", "dx", "icon_state_renames.json")

ICON_CONTEXT = re.compile(r"icon_state|overlay|flick\(|image\(|appearance|\bicon\b|state", re.I)
STATE_NAME_RX = re.compile(r'^(\s*name\s*=\s*)"((?:[^"\\]|\\.)*)"', re.M)
DMI_REF_RX = re.compile(r"'([^'\n]+\.dmi)'")
TYPE_LINE_RX = re.compile(r"^(/[A-Za-z0-9_/]+)\s*$")
ICON_VAR_RX = re.compile(r"^\s+icon\s*=\s*'([^'\n]+\.dmi)'")


def norm(p):
    return p.replace("\\", "/")


INTERP_RX = re.compile(r'"((?:[^"\\\n]|\\.)*\[(?:[^"\\\n]|\\.)*)"')


def interp_may_build(line, old):
    """An interpolated literal whose fixed head/tail fragments fit old ("[base]-panel" vs "x-panel")."""
    for m in INTERP_RX.finditer(line):
        s = m.group(1)
        head, tail = s.split("[", 1)[0], s.rsplit("]", 1)[-1] if "]" in s else ""
        if (tail and len(tail) >= 2 and old.endswith(tail) and old.startswith(head)) or (
            head and len(head) >= 2 and old.startswith(head) and old.endswith(tail)):
            return True
    return False


def toml_states(text):
    return [m.group(2) for m in STATE_NAME_RX.finditer(text)]


class Renamer:
    def __init__(self, repo, renames):
        self.repo = repo
        self.renames = {norm(k): v for k, v in renames.items() if not k.startswith("_")}
        self.errors, self.changes, self.ambiguous = [], [], []
        self.pending = {}  # abs path -> new text
        self._states_cache = {}

    def rel(self, p):
        return norm(os.path.relpath(p, self.repo))

    def states_of(self, dmi):
        if dmi not in self._states_cache:
            t = os.path.join(self.repo, dmi + ".toml")
            self._states_cache[dmi] = set(toml_states(open(t, encoding="utf-8").read())) if os.path.exists(t) else set()
        return self._states_cache[dmi]

    # ---- sources -------------------------------------------------------------------------
    def do_tomls(self):
        for dmi, table in self.renames.items():
            if dmi.startswith("icons/gen/"):
                self.errors.append("%s: icons/gen/ is generated; name the source dmi" % dmi); continue
            path = os.path.join(self.repo, dmi + ".toml")
            if not os.path.exists(path):
                self.errors.append("%s: no .dmi.toml source" % dmi); continue
            text = open(path, encoding="utf-8", newline="").read()
            existing = toml_states(text)
            for old in table:
                if old not in existing:
                    self.errors.append("%s: state %r not found" % (dmi, old))
            kept = set(existing) - set(table)
            dup = sorted(n for n in set(table.values()) if n in kept)
            dup += sorted(n for n, c in collections.Counter(table.values()).items() if c > 1)
            if dup:
                self.errors.append("%s: rename collides with existing state(s) %s" % (dmi, dup)); continue

            def sub(m):
                new = table.get(m.group(2))
                if new is None:
                    return m.group(0)
                self.changes.append("%s.toml: state %r -> %r" % (dmi, m.group(2), new))
                return '%s"%s"' % (m.group(1), new)
            new_text = STATE_NAME_RX.sub(sub, text)
            if new_text != text:
                self.pending[path] = new_text

    # ---- code ----------------------------------------------------------------------------
    def dm_files(self):
        return sorted(glob.glob(os.path.join(self.repo, "code", "**", "*.dm"), recursive=True))

    def unique_renames(self):
        """(old, new) pairs whose old state exists only in dmis that all rename it to new."""
        index = collections.defaultdict(set)
        for t in glob.glob(os.path.join(self.repo, "icons", "**", "*.dmi.toml"), recursive=True):
            if norm(t).split("/icons/", 1)[-1].startswith("gen/"):
                continue
            dmi = self.rel(t)[:-5]
            for st in toml_states(open(t, encoding="utf-8").read()):
                index[st].add(dmi)
        pairs = {}
        for dmi, table in self.renames.items():
            for old, new in table.items():
                if all(self.renames.get(d, {}).get(old) == new for d in index.get(old, ())):
                    pairs[old] = (new, dmi)
        return pairs

    def _interp(self, loc, line, old, dmi):
        entry = self.interp.setdefault(loc, [line.strip(), [], set()])
        entry[1].append(old)
        entry[2].add(dmi)

    def do_code(self):
        self.interp = {}
        unique = self.unique_renames()
        for fn in self.dm_files():
            text = self.pending.get(fn) or open(fn, encoding="utf-8", errors="replace", newline="").read()
            refs = set(norm(r) for r in DMI_REF_RX.findall(text))
            targets = [d for d in self.renames if d in refs]
            if not targets:
                # the file may still draw the state through a var icon (apc.icon): list, never change
                for i, line in enumerate(text.split("\n")):
                    if '"' not in line or not ICON_CONTEXT.search(line):
                        continue
                    for lit in re.findall(r'"([^"\[\]\n]+)"', line):
                        if lit in unique:
                            self.ambiguous.append("%s:%d: \"%s\" (file does not reference %s, but only renamed dmis have this state)"
                                                  % (self.rel(fn), i + 1, lit, unique[lit][1]))
                    if "[" in line:
                        for old_u, (_, dmi_u) in unique.items():
                            if interp_may_build(line, old_u):
                                self._interp("%s:%d" % (self.rel(fn), i + 1), line, old_u, dmi_u + " (no dmi reference)")
                continue
            lines = text.split("\n")
            changed = False
            for dmi in targets:
                others = [r for r in refs if r != dmi]
                for old, new in self.renames[dmi].items():
                    lit = '"%s"' % old
                    for i, line in enumerate(lines):
                        loc = "%s:%d" % (self.rel(fn), i + 1)
                        if lit in line:
                            clash = [o for o in others if old in self.states_of(o) and self.renames.get(o, {}).get(old) != new]
                            if clash:
                                self.ambiguous.append("%s: %s (file also references %s)" % (loc, lit, ", ".join(sorted(clash))))
                            elif not ICON_CONTEXT.search(line):
                                self.ambiguous.append("%s: %s (no icon context)" % (loc, lit))
                            else:
                                lines[i] = line.replace(lit, '"%s"' % new)
                                changed = True
                                self.changes.append("%s: %s -> \"%s\"  [%s]" % (loc, lit, new, dmi))
                        elif interp_may_build(line, old):
                            self._interp(loc, line, old, dmi)
            if changed:
                self.pending[fn] = "\n".join(lines)

    # ---- maps ----------------------------------------------------------------------------
    def type_icons(self):
        icons, cur = {}, None
        for fn in self.dm_files():
            for line in open(fn, encoding="utf-8", errors="replace"):
                m = TYPE_LINE_RX.match(line)
                if m:
                    cur = m.group(1); continue
                if line and not line[0].isspace():
                    cur = None; continue
                if cur:
                    mi = ICON_VAR_RX.match(line)
                    if mi and not line.startswith("\t\t"):
                        icons[cur] = norm(mi.group(1))
        return icons

    @staticmethod
    def resolve(icons, path):
        while path:
            if path in icons:
                return icons[path]
            path = path.rsplit("/", 1)[0]
        return None

    def do_maps(self, maps):
        icons = self.type_icons()
        block = re.compile(r"^(/[A-Za-z0-9_/]+)\{(.*?)\}", re.M | re.S)
        for fn in maps:
            text = open(fn, encoding="utf-8", newline="").read()

            def sub(m):
                body = m.group(2)
                mi = re.search(r"\bicon\s*=\s*'([^']+)'", body)
                dmi = norm(mi.group(1)) if mi else self.resolve(icons, m.group(1))
                table = self.renames.get(dmi)
                if not table:
                    return m.group(0)

                def st(ms):
                    new = table.get(ms.group(2))
                    if new is None:
                        return ms.group(0)
                    self.changes.append("%s: %s icon_state %r -> %r" % (self.rel(fn), m.group(1), ms.group(2), new))
                    return '%s"%s"' % (ms.group(1), new)
                return m.group(1) + "{" + re.sub(r'(\bicon_state\s*=\s*)"([^"]*)"', st, body) + "}"
            new = block.sub(sub, text)
            if new != text:
                self.pending[fn] = new

    def run(self, maps, write):
        self.do_tomls()
        if self.errors:
            return False
        self.do_code()
        for loc, (line, olds, dmis) in self.interp.items():
            olds = list(dict.fromkeys(olds))
            self.ambiguous.append("%s: interpolated state may build %d renamed state(s) (%s%s) [%s]: %s" % (
                loc, len(olds), ", ".join(repr(o) for o in olds[:3]), ", ..." if len(olds) > 3 else "",
                ", ".join(sorted(dmis))[:120], line))
        self.ambiguous = list(dict.fromkeys(self.ambiguous))
        self.do_maps(maps)
        if write:
            for p, t in self.pending.items():
                with open(p, "w", encoding="utf-8", newline="") as f:
                    f.write(t)
        return True


def report(r, write):
    for c in r.changes:
        print(("CHANGE " if write else "WOULD  ") + c)
    for a in r.ambiguous:
        print("AMBIG  " + a)
    for e in r.errors:
        print("ERROR  " + e)
    kinds = collections.Counter("toml" if ".toml:" in c else "map" if ".dmm:" in c else "code" for c in r.changes)
    print("summary: %d toml state(s), %d code site(s), %d map varedit(s), %d ambiguous, %d error(s), %d file(s) %s"
          % (kinds["toml"], kinds["code"], kinds["map"], len(r.ambiguous), len(r.errors), len(r.pending),
             "written" if write else "would change"))


def selftest():
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        def w(p, t):
            p = os.path.join(d, p); os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "w", encoding="utf-8", newline="").write(t)
        w("icons/obj/m.dmi.toml", 'width = 32\n\n[[state]]\nname = "m-spark"\n\n[[state]]\nname = "m-off"\n\n[[state]]\nname = "idle"\n')
        w("icons/obj/o.dmi.toml", '[[state]]\nname = "idle"\n')
        w("code/m.dm", "/obj/m\n\ticon = 'icons/obj/m.dmi'\n\ticon_state = \"m-off\"\n\n/obj/m/proc/f()\n"
                       "\tadd_overlay(\"m-spark\")\n\tto_chat(usr, \"m-spark\")\n\tflick(\"[icon_state]-spark\", src)\n")
        w("code/two.dm", "/obj/n\n\ticon = 'icons/obj/o.dmi'\n\tvar/x = 'icons/obj/m.dmi'\n\n/obj/n/proc/g()\n\ticon_state = \"idle\"\n")
        w("code/none.dm", "/obj/z/proc/h()\n\ticon_state = \"m-off\"\n")
        w("maps/t.dmm", '"a" = (\n/obj/m/sub{\n\ticon_state = "m-off"\n\t},\n/obj/z{\n\ticon_state = "m-off"\n\t},\n'
                        "/obj/z{\n\ticon = 'icons/obj/m.dmi';\n\ticon_state = \"m-spark\"\n\t})\n")
        ren = {"icons/obj/m.dmi": {"m-spark": "sparks", "m-off": "dark", "idle": "idle_x"}}
        r = Renamer(d, ren)
        ok = r.run([os.path.join(d, "maps/t.dmm")], write=True)
        rd = lambda p: open(os.path.join(d, p), encoding="utf-8").read()
        checks = [
            ok,
            'name = "sparks"' in rd("icons/obj/m.dmi.toml") and 'name = "idle_x"' in rd("icons/obj/m.dmi.toml"),
            'icon_state = "dark"' in rd("code/m.dm") and 'add_overlay("sparks")' in rd("code/m.dm"),
            'to_chat(usr, "m-spark")' in rd("code/m.dm"),           # no icon context: untouched
            'icon_state = "idle"' in rd("code/two.dm"),              # o.dmi also has idle: ambiguous
            'icon_state = "m-off"' in rd("code/none.dm"),            # file doesn't reference m.dmi
            rd("maps/t.dmm").count('"dark"') == 1 and '"sparks"' in rd("maps/t.dmm") and '"m-off"' in rd("maps/t.dmm"),
            any("no icon context" in a for a in r.ambiguous),
            any("also references" in a for a in r.ambiguous),
            any("interpolated" in a for a in r.ambiguous),
        ]
        # collisions and unknown states are refused before anything is written
        r2 = Renamer(d, {"icons/obj/m.dmi": {"dark": "sparks"}})
        checks.append(not r2.run([], write=False) and r2.errors)
        r3 = Renamer(d, {"icons/obj/m.dmi": {"nope": "x"}})
        checks.append(not r3.run([], write=False))
        # idempotent-safe: renaming again after applying finds nothing to do but errors on missing old
        ok = all(bool(c) for c in checks)
        if not ok:
            print("checks:", [bool(c) for c in checks]); report(r, True)
    print("selftest: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--renames", default=RENAMES_FILE)
    ap.add_argument("--maps", default="maps/**/*.dmm", help="glob of maps to rewrite (default: maps/**/*.dmm)")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    renames = json.load(open(a.renames, encoding="utf-8"))
    maps = sorted(glob.glob(os.path.join(REPO, a.maps), recursive=True))
    r = Renamer(REPO, renames)
    r.run(maps, write=not a.dry_run)
    report(r, not a.dry_run)
    return 1 if r.errors else 0


if __name__ == "__main__":
    sys.exit(main())
