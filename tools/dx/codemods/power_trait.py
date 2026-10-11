"""Moves the machine power vars (idle_power_usage, active_power_usage, power_channel) off /obj/machinery into the uses_power() trait.

  python tools/dx/codemods/power_trait.py [--apply] [--files ...] [--dirs ...]

What it does, over code/ (generated files and the /obj/machinery declarations themselves are left to the hand edit):
  * a type definition block that sets any of the three vars (`\tidle_power_usage = 5`) loses those lines, and the type's CAPABILITIES
    block (found anywhere in the tree, else made right after the definition) gains `configure(uses_power(idle = 5, ...))`;
  * a statement that writes one (`active_power_usage = x`, `M.idle_power_usage += y`) becomes its setter;
  * a read becomes the trait read: `active_power_usage` -> `power_of(src).active`, `M.power_channel` -> `power_of(M).channel`,
    `initial(active_power_usage)` -> `power_of_type(type).active`, `initial(M.active_power_usage)` -> `power_of_type(M.type).active`.
Strings, comments and nameof()/NAMEOF() are left alone (they are change keys and docs). Dry run unless --apply.
"""
import _guard  # noqa: F401  (must be first: --help, dry run, write scope)
import os
import re
import sys

ROOT = "code"
FIELDS = {"idle_power_usage": "idle", "active_power_usage": "active", "power_channel": "channel"}
SETTER = {"idle_power_usage": "set_idle_power_usage", "active_power_usage": "set_active_power_usage", "power_channel": "set_power_channel"}
NAME_RE = "|".join(FIELDS)
SKIP_FILES = {"code/game/machinery/machinery.dm", "code/game/machinery/machinery_power.dm"}

TYPE_LINE = re.compile(r"^(/[A-Za-z0-9_/]+)\s*(//.*)?$")
OVERRIDE = re.compile(r"^\t(" + NAME_RE + r")\s*=\s*(.+?)\s*(//.*)?$")
CAPS = re.compile(r"^CAPABILITIES\((/[A-Za-z0-9_/]+)\)\s*$")


def code_files():
    for d, _, files in os.walk(ROOT):
        if "_generated" in d.replace("\\", "/"):
            continue
        for f in files:
            if f.endswith(".dm"):
                yield os.path.join(d, f).replace("\\", "/")


def read(p):
    with open(p, encoding="utf-8", errors="surrogateescape", newline="") as fh:
        return fh.read()


def write(p, text):
    with open(p, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write(text)


def split_code_comment(line):
    """(code, comment) of one line: the first // outside a string starts the comment."""
    in_str = None
    i = 0
    while i < len(line):
        c = line[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == in_str:
                in_str = None
        elif c in "\"'":
            in_str = c
        elif c == "/" and line[i:i + 2] == "//":
            return line[:i], line[i:]
        i += 1
    return line, ""


def mask_strings(code):
    """The code with string contents and nameof()/NAMEOF() arguments blanked, so a rewrite never touches them; returns (masked, spans)."""
    out = list(code)
    in_str = None
    depth = 0  # [ ] embedded expressions inside a string are code
    i = 0
    while i < len(code):
        c = code[i]
        if in_str:
            if c == "\\":
                out[i] = "\0"
                if i + 1 < len(code):
                    out[i + 1] = "\0"
                i += 2
                continue
            if c == "[":
                depth += 1
            elif c == "]" and depth:
                depth -= 1
            elif c == in_str and not depth:
                in_str = None
            elif not depth:
                out[i] = "\0"
        elif c in "\"'":
            in_str = c
        i += 1
    masked = "".join(out)
    for m in re.finditer(r"(?i)\bnameof\s*\(", masked):
        j = m.end()
        lvl = 1
        while j < len(masked) and lvl:
            if masked[j] == "(":
                lvl += 1
            elif masked[j] == ")":
                lvl -= 1
            if lvl:
                masked = masked[:j] + "\0" + masked[j + 1:]
            j += 1
    return masked


REF = r"(?:[A-Za-z_]\w*(?:\(\))?(?:\??\.[A-Za-z_]\w*(?:\(\))?)*)"


def rewrite_code(code):
    masked = mask_strings(code)
    if not re.search(r"\b(" + NAME_RE + r")\b", masked):
        return code
    # statement writes: [ref.]name op= value (the whole rest of the statement)
    m = re.match(r"^(\s*)(?:(" + REF + r")\??\.)?(" + NAME_RE + r")\s*([-+*/]?)=(?!=)\s*(.+?)\s*$", code)
    if m and re.match(r"^(\s*)(?:(" + REF + r")\??\.)?(" + NAME_RE + r")\s*([-+*/]?)=(?!=)", masked):
        indent, ref, name, op, value = m.groups()
        value = rewrite_reads(value, mask_strings(value))
        target = (ref + ".") if ref else ""
        if op:
            holder = ref or "src"
            value = "power_of(%s).%s %s (%s)" % (holder, FIELDS[name], op, value)
        return "%s%s%s(%s)" % (indent, target, SETTER[name], value)
    return rewrite_reads(code, masked)


def rewrite_reads(code, masked):
    out = []
    pos = 0
    pat = re.compile(r"(\binitial\s*\(\s*)?(?:(" + REF + r")\??\.)?\b(" + NAME_RE + r")\b(\s*\))?")
    for m in pat.finditer(masked):
        start, end = m.span()
        before = masked[start - 1] if start else ""
        if before == "." or before.isalnum() or before == "_":
            continue
        init, ref, name, close = m.groups()
        if ref and ref.startswith("set_"):
            continue
        if init and close:
            holder = (ref + ".type") if ref else "type"
            repl = "power_of_type(%s).%s" % (holder, FIELDS[name])
        else:
            holder = ref or "src"
            repl = "power_of(%s).%s" % (holder, FIELDS[name])
            if init:
                repl = code[start:m.start(2) if ref else m.start(3)] + repl
            if close:
                repl += code[m.end(3):end]
        out.append(code[pos:start])
        out.append(repl)
        pos = end
    out.append(code[pos:])
    return "".join(out)


def main():
    files = {p: read(p) for p in code_files()}
    caps_at = {}
    for p, text in files.items():
        for i, line in enumerate(text.split("\n")):
            m = CAPS.match(line.rstrip("\r"))
            if m:
                caps_at[m.group(1)] = (p, i)
    entries = {}  # type -> list of "name = value"
    new = {}
    for p, text in files.items():
        if p in SKIP_FILES:
            continue
        lines = text.split("\n")
        cur = None
        keep = []
        for raw in lines:
            line = raw.rstrip("\r")
            tm = TYPE_LINE.match(line)
            if tm and "/proc/" not in line and "/verb/" not in line:
                cur = tm.group(1)
            elif line and not line.startswith("\t") and not line.startswith(" "):
                cur = None
            om = OVERRIDE.match(line) if cur else None
            if om and cur.startswith("/obj/machinery"):
                entries.setdefault(cur, []).append((FIELDS[om.group(1)], om.group(2)))
                continue
            code, comment = split_code_comment(line)
            if cur is None or line.startswith("\t"):
                code = rewrite_code(code) if (code.startswith("\t") or code.startswith(" ")) else code
            keep.append(code + comment + ("\r" if raw.endswith("\r") else ""))
        new[p] = keep
    # entries into blocks
    made_blocks = {}
    for t, rows in entries.items():
        args = ", ".join("%s = %s" % (k, v) for k, v in rows)
        entry = "\tconfigure(uses_power(%s))" % args
        if t in caps_at:
            p, i = caps_at[t]
            made_blocks.setdefault(p, []).append(("after_caps", t, entry))
        else:
            # after the type's definition block in the first file that defines it with an override
            for p in new:
                if any(TYPE_LINE.match(l.rstrip("\r")) and TYPE_LINE.match(l.rstrip("\r")).group(1) == t for l in new[p]):
                    made_blocks.setdefault(p, []).append(("after_def", t, entry))
                    break
    for p, adds in made_blocks.items():
        lines = new[p]
        for kind, t, entry in adds:
            cr = "\r" if lines and lines[0].endswith("\r") else ""
            if kind == "after_caps":
                idx = next(i for i, l in enumerate(lines) if l.rstrip("\r") == "CAPABILITIES(%s)" % t)
                lines.insert(idx + 1, entry + cr)
            else:
                idx = next(i for i, l in enumerate(lines) if TYPE_LINE.match(l.rstrip("\r")) and TYPE_LINE.match(l.rstrip("\r")).group(1) == t)
                j = idx + 1
                while j < len(lines) and (lines[j].startswith("\t") or lines[j].startswith(" ") or lines[j].rstrip("\r") == "" and j + 1 < len(lines) and lines[j + 1].startswith("\t")):
                    j += 1
                lines[j:j] = [cr, "CAPABILITIES(%s)%s" % (t, cr), entry + cr]
    changed = 0
    for p, lines in new.items():
        text = "\n".join(lines)
        if text != files[p]:
            changed += 1
            write(p, text)
    print("power_trait: %d types declared, %d files changed" % (len(entries), changed))


if __name__ == "__main__":
    main()
