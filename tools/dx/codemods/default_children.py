#!/usr/bin/env python3
"""DECLARE_DEFAULT_CHILD(PATH, "var", DEFAULT) -> a declared starting occupant (doc 17: owns_one(nameof(v), type, starts = T)).

    DECLARE_DEFAULT_CHILD(/obj/machinery/floodlight, "cell", /obj/item/cell)
        ->  CAPABILITIES(/obj/machinery/floodlight)
                owns_one(nameof(cell), starts = /obj/item/cell)

The policy the var has today decides the form. A survey run (a unit test that builds every site's type and prints the var's ownership entry,
with a log line wherever a first write declared a var) gives it:

* an undeclared var, OWN_DELETE or OWN_SPILL: an owns_one / owns_many entry (on_destroy = ON_DESTROY_SPILL for a spill) in the type's
  CAPABILITIES block, appended to the one the type already has (anywhere in the tree), or a new block where the macro stood. A block
  entry for the same var gets `starts =` added instead. The same var's plain `. += owns(nameof(v))` line in a /PATH/ownership() of the
  file is dropped.
* OWN_CONTAINED (a contained part has no owns_one form until it becomes a slot): the legacy `owns(nameof(v), policy = OWN_CONTAINED,
  starts = T)` in /PATH/ownership(), added to the one the file has or made.

    python tools/dx/codemods/default_children.py --survey DUMP LEARN [--apply]

DUMP: the `OFDUMP|path|var|kind=..|policy=..|list=..|type=..` lines, LEARN: the `OFLEARN|type|var|kind` lines (test-run logs).
What it cannot place is printed as RESIDUE and left for hand work (its macro line is kept).
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import collections
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
MACRO = re.compile(r'^DECLARE_DEFAULT_CHILD\((/[A-Za-z0-9_/]+), ("[A-Za-z0-9_]+"|null), (.*)\)[ \t]*(//.*)?$')


def read_survey(dump_path, learn_path):
    dump = {}
    for line in open(dump_path, encoding="utf-8", errors="replace"):
        line = line.split('","data"')[0].strip()
        if "OFDUMP|" in line:
            line = line.split("OFDUMP|", 1)[1]
        p = line.split("|")
        if len(p) >= 3:
            dump[(p[0], p[1])] = p[2:]
    learned = collections.defaultdict(set)
    for line in open(learn_path, encoding="utf-8", errors="replace"):
        line = line.split('","data"')[0].strip()
        if "OFLEARN|" in line:
            line = line.split("OFLEARN|", 1)[1]
        p = line.split("|")
        if len(p) == 3 and p[2] == "1":
            learned[p[1]].add(p[0])
    return dump, learned


def starts_text(var, default):
    default = default.strip()
    m = re.fullmatch(r'"([A-Za-z0-9_]+)"', default)
    if m:
        return f"nameof({m.group(1)})"
    if default == "null":
        return f"nameof({var})"
    if default == "list()":
        return None
    return default


def classify(path, var, dump, learned):
    """('caps'|'legacy', policy, is_list, type) from the survey."""
    d = dump.get((path, var), ["NEW_FAILED"])
    was_learned = any(t == path or t.startswith(path + "/") for t in learned.get(var, ()))
    if d[0].startswith("kind=") and not was_learned:
        policy = d[1].split("=")[1]
        is_list = d[2].split("=")[1] == "1"
        typ = d[3].split("=", 1)[1] if len(d) > 3 else ""
        if policy in ("1", "2"):
            return "caps", policy, is_list, typ
        return "legacy", policy, is_list, typ
    return "caps", "1", False, ""  # undeclared (learned, or never written by the survey): the default policy


def add_arg(line, text):
    tail = line.rstrip()
    comment = ""
    cm = re.search(r"\s//.*$", tail)
    if cm:
        comment = tail[cm.start():]
        tail = tail[:cm.start()]
    close = tail.rfind(")")
    return tail[:close] + ", " + text + tail[close:] + comment


def block_end(lines, header_index):
    j = header_index + 1
    last = header_index
    while j < len(lines):
        if lines[j].startswith("\t"):
            last = j
        elif lines[j].strip() != "":
            break
        j += 1
    return last


def proc_span(lines, header):
    for i, l in enumerate(lines):
        if l.rstrip() == header:
            return i, block_end(lines, i)
    return None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    apply_ = "--apply" in sys.argv
    if "--survey" not in sys.argv or len(args) < 2:
        print(__doc__)
        return 2
    dump, learned = read_survey(args[0], args[1])
    files = {}
    for p in sorted(pathlib.Path(ROOT, "code").rglob("*.dm")):
        rel = p.relative_to(ROOT).as_posix()
        if rel.startswith("code/__defines/"):
            continue
        files[rel] = open(p, encoding="utf-8", errors="surrogateescape", newline="").read().split("\n")
    # sentinels
    by_path = collections.OrderedDict()  # path -> [(file, sentinel, var, default, comment)]
    n = 0
    for f, lines in files.items():
        for i, l in enumerate(lines):
            m = MACRO.match(l)
            if m:
                sentinel = f"@@DC{n}@@"
                n += 1
                lines[i] = sentinel
                by_path.setdefault(m.group(1), []).append((f, sentinel, m.group(2).strip('"'), m.group(3), m.group(4)))
    changed = {f for items in by_path.values() for (f, *_rest) in items}
    residue = []
    headers = {}
    for f, lines in files.items():
        for i, l in enumerate(lines):
            m = re.match(r"CAPABILITIES\((/[A-Za-z0-9_/]+)\)\s*$", l)
            if m:
                headers[m.group(1)] = f
    keep_macro = {}  # sentinel -> original text, for what is left to hand work
    for path, items in by_path.items():
        new_caps, new_legacy = [], []
        for (f, sentinel, var, default, comment) in items:
            mode, policy, is_list, typ = classify(path, var, dump, learned)
            st = starts_text(var, default)
            many = is_list or default.strip().startswith("list(")
            if mode == "legacy":
                new_legacy.append((f, var, policy, st, comment))
                continue
            parts = [f"nameof({var})"]
            if typ:
                parts.append(typ)
            if st:
                parts.append(f"starts = {st}")
            if policy == "2":
                parts.append("on_destroy = ON_DESTROY_SPILL")
            entry = "\t" + ("owns_many(" if many else "owns_one(") + ", ".join(parts) + ")" + (f" {comment}" if comment else "")
            hf = headers.get(path)
            placed = False
            if hf:
                lines = files[hf]
                hi = next(i for i, l in enumerate(lines) if re.match(r"CAPABILITIES\(%s\)\s*$" % re.escape(path), l))
                end = block_end(lines, hi)
                for k in range(hi + 1, end + 1):
                    em = re.match(r"\towns_(one|many)\(nameof\(%s\)" % re.escape(var), lines[k])
                    if em:
                        if "starts" in lines[k]:
                            residue.append(f"{f}: {path} {var}: the CAPABILITIES entry already has starts")
                        elif st:
                            lines[k] = add_arg(lines[k], f"starts = {st}")
                        placed = True
                        break
                if not placed:
                    lines.insert(end + 1, entry)
                    placed = True
                changed.add(hf)
            else:
                new_caps.append((f, entry))
            drop_legacy_line(files[f], path, var)
        # a new block / legacy proc goes where the group's first macro stood
        first_f, first_sentinel = items[0][0], items[0][1]
        text = []
        if new_caps:
            text += [f"CAPABILITIES({path})"] + [e for (_, e) in new_caps]
            headers[path] = first_f
        legacy_text = []
        for (f, var, policy, st, comment) in new_legacy:
            pol = {"3": "OWN_CONTAINED", "4": "OWN_KEEP"}.get(policy)
            if pol is None:
                residue.append(f"{f}: {path} {var}: policy {policy} has no legacy rewrite")
                continue
            sp = f", starts = {st}" if st else ""
            lines = files[f]
            span = proc_span(lines, f"{path}/ownership()")
            done = False
            if span:
                for k in range(span[0] + 1, span[1] + 1):
                    if re.match(r"\t\. \+= owns\(nameof\(%s\)," % re.escape(var), lines[k]):
                        if st:
                            lines[k] = add_arg(lines[k], f"starts = {st}")
                        done = True
                        break
                if not done:
                    lines.insert(span[1] + 1, f"\t. += owns(nameof({var}), policy = {pol}{sp})")
                    done = True
            if not done:
                legacy_text.append(f"\t. += owns(nameof({var}), policy = {pol}{sp})")
        if legacy_text:
            if text:
                text.append("")
            text += [f"{path}/ownership()", "\t. = ..()"] + legacy_text
        for (f, sentinel, var, default, comment) in items:
            lines = files[f]
            idx = lines.index(sentinel)
            if sentinel == first_sentinel and text:
                lines[idx:idx + 1] = text + [""]
            else:
                lines[idx:idx + 1] = []
                if 0 < idx < len(lines) and lines[idx].strip() == "" and lines[idx - 1].strip() == "":
                    del lines[idx]  # the macro sat between blank lines: keep one
    for f in sorted(changed):
        text = "\n".join(files[f])
        if apply_:
            open(ROOT / f, "w", encoding="utf-8", errors="surrogateescape", newline="").write(text)
    print(f"{sum(len(i) for i in by_path.values())} macro sites in {len(by_path)} types, {len(changed)} files changed{'' if apply_ else ' (dry run)'}")
    for r in residue:
        print("RESIDUE", r)


def drop_legacy_line(lines, path, var):
    """Drops the plain `. += owns(nameof(v))` of /PATH/ownership() (the block entry replaces it), and the proc when nothing is left."""
    span = proc_span(lines, f"{path}/ownership()")
    if not span:
        return
    i, j = span
    pat = re.compile(r"\t\. \+= owns\(nameof\(%s\)(, policy = OWN_(DELETE|SPILL))?(, is_list = TRUE)?\)\s*(//.*)?$" % re.escape(var))
    for k in range(i + 1, j + 1):
        if pat.match(lines[k]):
            del lines[k]
            j -= 1
            body = [l for l in lines[i + 1:j + 1] if l.strip() and l.strip() != ". = .."]
            if not body:
                del lines[i:j + 1]
            return


if __name__ == "__main__":
    sys.exit(main())
