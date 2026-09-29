"""One-shot converter: `/type/declare_ownership(decl)` blocks -> `/type/ownership()` and
`/type/relations()` list overrides (doc/rewrite/ownership.md §1.2, §4.1).

    own(decl, nameof(v), ...)       -> . += owns(nameof(v), ...)      (no policy: policy = OWN_NONE)
    shared(decl, nameof(v), ...)    -> . += shares(nameof(v), ...)
    proto(decl, nameof(v), ...)     -> . += proto(nameof(v), ...)
    rel(decl, nameof(v), list = TRUE, pair = P, ...)  -> . += rel_many(nameof(v), back = P, ...)
    rel(decl, nameof(v), pair = P, ...)               -> . += rel_one(nameof(v), back = P, ...)
    rel(decl, nameof(v), list = TRUE, symmetric = TRUE) -> . += rel_many(nameof(v), back = nameof(/type::v))
    rel(decl, keyed = nameof(k))    -> . += rel_key(nameof(k))

Usage: python tools/dx/convert_ownership_decls.py [--dry-run]
"""
import glob
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
HEAD = re.compile(r"^(/[\w/]+)/declare_ownership\((?:datum/own_decls/)?decl\)\s*$")
CALL = re.compile(r"^(\s*)(own|shared|proto|rel)\(\s*decl\s*(?:,\s*(.*?))?\)(\s*//.*)?$")


def split_args(text):
    """Top-level comma split (keeps nested parens and strings together)."""
    out, depth, cur, quote = [], 0, "", None
    for ch in text:
        if quote:
            cur += ch
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
            cur += ch
        elif ch in "([":
            depth += 1
            cur += ch
        elif ch in ")]":
            depth -= 1
            cur += ch
        elif ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def convert_call(holder, func, args):
    """Returns (block, new call text): block is 'own' or 'rel'."""
    parts = split_args(args or "")
    positional = [p for p in parts if not re.match(r"^\w+\s*=", p)]
    named = [(m.group(1), m.group(2)) for m in (re.match(r"^(\w+)\s*=\s*(.*)$", p) for p in parts) if m]
    opts = dict(named)
    var = positional[0] if positional else None
    if func == "own":
        if not any(k in opts for k in ("policy", "policy_proc", "if_var")):
            named = [("policy", "OWN_NONE")] + named
        return "own", "owns(%s)" % ", ".join([var] + ["%s = %s" % kv for kv in named])
    if func == "shared":
        return "own", "shares(%s)" % ", ".join([var] + ["%s = %s" % kv for kv in named])
    if func == "proto":
        return "own", "proto(%s)" % ", ".join([var] + ["%s = %s" % kv for kv in named])
    # rel
    if var is None:
        return "rel", "rel_key(%s)" % opts["keyed"]
    is_list = opts.get("list") == "TRUE" or opts.get("symmetric") == "TRUE"
    out = []
    for key, value in named:
        if key == "list":
            continue
        if key == "pair":
            out.append(("back", value))
        elif key == "symmetric":
            vm = re.match(r"^nameof\((\w+)\)$", var)
            out.append(("back", "nameof(%s::%s)" % (holder, vm.group(1))))
        else:
            out.append((key, value))
    return "rel", "%s(%s)" % ("rel_many" if is_list else "rel_one", ", ".join([var] + ["%s = %s" % kv for kv in out]))


def convert_file(path):
    with open(path, encoding="utf-8", newline="") as handle:
        text = handle.read()
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.split(nl)
    out = []
    i = 0
    changed = 0
    while i < len(lines):
        m = HEAD.match(lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        holder = m.group(1)
        i += 1
        own_lines, rel_lines, pending = [], [], []
        while i < len(lines):
            line = lines[i]
            if line.strip() == "":
                if i + 1 < len(lines) and lines[i + 1].startswith("\t") and not HEAD.match(lines[i + 1]):
                    i += 1
                    continue
                break
            if not line.startswith("\t"):
                break
            stripped = line.strip()
            if stripped == "..()":
                i += 1
                continue
            if stripped.startswith("//"):
                pending.append(line)
                i += 1
                continue
            cm = CALL.match(line)
            if not cm:
                raise SystemExit("%s:%d: cannot convert: %s" % (path, i + 1, stripped))
            block, call = convert_call(holder, cm.group(2), cm.group(3))
            target = own_lines if block == "own" else rel_lines
            target.extend(pending)
            pending = []
            target.append("\t. += %s%s" % (call, cm.group(4) or ""))
            i += 1
        emitted = []
        if own_lines:
            emitted += ["%s/ownership()" % holder, "\t. = ..()"] + own_lines
        if rel_lines:
            if emitted:
                emitted.append("")
            emitted += ["%s/relations()" % holder, "\t. = ..()"] + rel_lines
        emitted += pending
        out.extend(emitted)
        changed += 1
    if changed:
        with open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write(nl.join(out))
    return changed


def main(argv):
    dry = "--dry-run" in argv
    total = 0
    for top in ("code", "maps"):
        for path in sorted(glob.glob(os.path.join(ROOT, top, "**", "*.dm"), recursive=True)):
            with open(path, encoding="utf-8", errors="replace") as handle:
                if "declare_ownership(" not in handle.read():
                    continue
            if dry:
                print(os.path.relpath(path, ROOT))
                continue
            n = convert_file(path)
            total += n
    print("converted %d declare_ownership blocks" % total)


if __name__ == "__main__":
    main(sys.argv[1:])
