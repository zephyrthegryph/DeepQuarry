"""Moves a group of base-type vars into a profile record (code/engine/declare/profiles.dm).

  python tools/dx/codemods/profile_record.py <spec> [--apply] [--files ...] [--dirs ...]

<spec> names an entry of SPECS below: the holder type, the record var, and var -> record field (a colour triple r_X/g_X/b_X is one
field holding an "#rrggbb" string). Over code/ (generated files and the spec's skip files are left alone):
  * three statements writing a triple (`r_hair = a` / `g_hair = b` / `b_hair = c`, same holder) become one setter call
    `looks.set_hair_color(rgb(a, b, c))` (`hex2num(copytext(X, 2, 4))`... becomes X; `L[1]`, `L[2]`, `L[3]` becomes rgb(L[1], L[2], L[3]));
  * `rgb(r_hair, g_hair, b_hair)` and `"[r_hair][g_hair][b_hair]"` read the field; `list(r_hair, g_hair, b_hair)` reads hex2rgb(field);
  * a single var's write `[ref.]x = v` / `x += v` becomes `[ref.]rec.set_<field>(...)` when the field is tracked, else `[ref.]rec.field = v`;
    a read becomes `[ref.]rec.field`.
A bare name is rewritten only inside a proc of a type under the holder; `X.name` only when X is not declared in the proc as a type outside
the holder; a name in AMBIGUOUS (another type declares a var of that name) only when X is known to be a holder. Whatever is left (a lone
colour channel, an ambiguous ref) is printed as residue for a hand edit. Strings, comments and nameof() are left alone. Dry run unless --apply.
"""
import _guard  # noqa: F401  (must be first: --help, dry run, write scope)
import os
import re
import sys

ROOTS = ("code",)
SPECS = {
    "appearance": dict(
        holder="/mob/living/carbon/human", rec="looks",
        triples={"hair": "hair_color", "grad": "grad_color", "facial": "facial_color", "eyes": "eyes_color", "skin": "skin_color",
                 "synth": "synth_color_rgb"},
        singles={"h_style": "hair_style", "f_style": "facial_style", "grad_style": "grad_style", "s_tone": "skin_tone",
                 "synth_color": "synth_color", "synth_markings": "synth_markings", "digitigrade": "digitigrade", "lip_style": "lip_style"},
        tracked=True,
        ambiguous={"s_tone", "digitigrade", "synth_markings", "synth_color", "grad_style", "h_style", "f_style"},
        known_refs={"owner", "human", "character", "H", "target_human", "temp_human", "target", "M", "new_character", "mannequin"},
        skip={"code/modules/mob/living/carbon/human/human_defines.dm", "code/modules/mob/living/carbon/human/profile_records.dm"},
    ),
}
_args = [a for a in sys.argv[1:] if not a.startswith("--")]
_spec_name = next((a for a in _args if a in SPECS), None)
if _spec_name is None:
    print("profile_record: name a spec: " + ", ".join(sorted(SPECS)))
    sys.exit(2)
SPEC = SPECS[_spec_name]
BASE = SPEC["holder"]
REC = SPEC["rec"]
TRIPLES = SPEC.get("triples", {})
SINGLES = SPEC.get("singles", {})
TRACKED = SPEC.get("tracked", False)
AMBIG = SPEC.get("ambiguous", set())
KNOWN = SPEC.get("known_refs", set())
SKIP = SPEC["skip"]
CHAN_NAMES = {c + "_" + t: (t, c) for t in TRIPLES for c in "rgb"}
ALL_NAMES = sorted(list(CHAN_NAMES) + list(SINGLES), key=len, reverse=True)
NAME_RE = "|".join(ALL_NAMES)
REF = r"(?:[A-Za-z_]\w*(?:\(\))?(?:\??\.[A-Za-z_]\w*(?:\(\))?)*)"
TYPE_LINE = re.compile(r"^(/[A-Za-z0-9_/]+)\s*(//.*)?$")


def code_files():
    for d, _, files in (w for r in ROOTS for w in os.walk(r)):
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
    out = list(code)
    in_str = None
    depth = 0
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


OWNER = [None]
LOCALS = {}
RESIDUE = []


def under_base(path):
    return path == BASE or path.startswith(BASE + "/")


def ref_ok(ref, name):
    """Whether [ref.]name names the holder's var."""
    ambiguous = name in AMBIG
    if not ref or ref == "src":
        if OWNER[0] is None:
            return False
        return under_base(OWNER[0])
    head = re.split(r"\??\.", ref)[0].replace("()", "")
    last = re.split(r"\??\.", ref)[-1].replace("()", "")
    if "." in ref:
        # a chain: only the last link's name tells (owner, human, ...)
        return (not ambiguous) or last in KNOWN or last.startswith("owner")
    t = LOCALS.get(head)
    if t is not None:
        return under_base(t) or (not ambiguous and (BASE.startswith(t + "/")))
    if ambiguous:
        return head in KNOWN or head.endswith("()") or (head.startswith("owner"))
    return True


def note_locals(code):
    for m in re.finditer(r"\bvar/((?:[A-Za-z_]\w*/)*)([A-Za-z_]\w*)", code):
        path = "/" + m.group(1).rstrip("/") if m.group(1) else None
        if path and path != "/list":
            LOCALS[m.group(2)] = path
        elif not path:
            LOCALS[m.group(2)] = "/untyped"
    for m in re.finditer(r"\bfor\s*\(\s*var/((?:[A-Za-z_]\w*/)*)([A-Za-z_]\w*)", code):
        if m.group(1):
            LOCALS[m.group(2)] = "/" + m.group(1).rstrip("/")


def target(ref):
    return (ref + "." if ref else "") + REC + "."


def strip_chan(value, chan):
    """hex2num(copytext(X, 2, 4)) -> X (channel r), and the same for g/b; L[1] -> (L, 1)."""
    m = re.match(r"^hex2num\(\s*copytext\(\s*(.+?)\s*,\s*(\d)\s*,\s*(\d)\s*\)\s*\)$", value)
    if m:
        want = {"r": ("2", "4"), "g": ("4", "6"), "b": ("6", "8")}[chan]
        if (m.group(2), m.group(3)) == want:
            return ("hex", m.group(1))
    m = re.match(r"^(" + REF + r")\[(\d)\]$", value)
    if m and m.group(2) == str("rgb".index(chan) + 1):
        return ("idx", m.group(1))
    m = re.match(r"^(?:(" + REF + r")\??\.)?([rgb])_(\w+)$", value)
    if m and m.group(2) == chan and m.group(3) in TRIPLES:
        return ("copy", (m.group(1), m.group(3)))
    return ("raw", value)


WRITE_RE = re.compile(r"^(\s*)(?:(" + REF + r")\??\.)?(" + NAME_RE + r")\s*([-+*/]?)=(?!=)\s*(.+?)\s*$")


def merge_triples(lines, path):
    """Three consecutive statement lines writing r_X, g_X, b_X of one holder -> one setter line."""
    out = []
    i = 0
    while i < len(lines):
        raw = lines[i]
        line = raw.rstrip("\r")
        code, comment = split_code_comment(line)
        m = WRITE_RE.match(code)
        done = False
        if m and m.group(3) in CHAN_NAMES and CHAN_NAMES[m.group(3)][1] == "r" and not m.group(4) and i + 2 < len(lines):
            t = CHAN_NAMES[m.group(3)][0]
            ref = m.group(2)
            parts = [m.group(5)]
            ok = True
            for k, chan in ((1, "g"), (2, "b")):
                c2, _ = split_code_comment(lines[i + k].rstrip("\r"))
                m2 = WRITE_RE.match(c2)
                if not (m2 and m2.group(3) == chan + "_" + t and m2.group(2) == ref and not m2.group(4) and m2.group(1) == m.group(1)):
                    ok = False
                    break
                parts.append(m2.group(5))
            if ok:
                kinds = [strip_chan(v, c) for v, c in zip(parts, "rgb")]
                if all(k[0] == "hex" for k in kinds) and kinds[0][1] == kinds[1][1] == kinds[2][1]:
                    value = kinds[0][1]
                elif all(k[0] == "copy" for k in kinds) and kinds[0][1] == kinds[1][1] == kinds[2][1]:
                    src_ref, tt = kinds[0][1]
                    value = target(src_ref) + TRIPLES[tt]
                else:
                    value = "rgb(%s, %s, %s)" % tuple(rewrite_reads(p, mask_strings(p)) for p in parts)
                field = TRIPLES[t]
                if TRACKED:
                    new = "%s%sset_%s(%s)" % (m.group(1), target(ref), field, value)
                else:
                    new = "%s%s%s = %s" % (m.group(1), target(ref), field, value)
                cr = "\r" if raw.endswith("\r") else ""
                tail = " ".join(x for x in [comment] + [split_code_comment(lines[i + k].rstrip("\r"))[1] for k in (1, 2)] if x)
                out.append(new + ((" " + tail) if tail else "") + cr)
                i += 3
                done = True
        if not done:
            out.append(raw)
            i += 1
    return out


def rewrite_reads(code, masked):
    # whole-triple reads first
    def triple_pat(wrap_l, sep, wrap_r):
        return re.compile(wrap_l + r"(?:(" + REF + r")\??\.)?r_(\w+)" + sep + r"(?:(" + REF + r")\??\.)?g_(\w+)" + sep +
                          r"(?:(" + REF + r")\??\.)?b_(\w+)" + wrap_r)
    for pat, kind in ((triple_pat(r"\brgb\(\s*", r"\s*,\s*", r"\s*\)"), "rgb"),
                      (triple_pat(r"\blist\(\s*", r"\s*,\s*", r"\s*\)"), "list"),
                      (triple_pat(r"\[", r"\]\[", r"\]"), "key"),
                      (triple_pat(r"\[", r"\], \[", r"\]"), "key")):
        while True:
            mm = pat.search(masked)
            if not mm:
                break
            r1, t1, r2, t2, r3, t3 = mm.groups()
            if not (t1 == t2 == t3 and t1 in TRIPLES and r1 == r2 == r3 and ref_ok(r1, "r_" + t1)):
                # blank this match in the mask so the loop moves on
                masked = masked[:mm.start()] + "\0" + masked[mm.start() + 1:]
                continue
            read = target(r1) + TRIPLES[t1]
            if kind == "rgb":
                repl = read
            elif kind == "list":
                repl = "hex2rgb(%s)" % read
            else:
                repl = "[%s]" % read
            code = code[:mm.start()] + repl + code[mm.end():]
            masked = masked[:mm.start()] + repl + masked[mm.end():]
    out = []
    pos = 0
    pat = re.compile(r"(?:(" + REF + r")\??\.)?\b(" + NAME_RE + r")\b")
    for m in pat.finditer(masked):
        start, end = m.span()
        before = masked[start - 1] if start else ""
        if before == "." or before.isalnum() or before == "_" or before == "/":
            continue
        ref, name = m.groups()
        if ref and (ref.startswith("set_") or ref.endswith("." + REC) or ref == REC):
            continue
        if name in LOCALS and not ref:
            continue  # a local of that name shadows the holder's var
        if not ref_ok(ref, name):
            if ref or OWNER[0]:
                RESIDUE.append("%s: ambiguous %s" % (CUR_FILE[0], code.strip()))
            continue
        if name in CHAN_NAMES:
            RESIDUE.append("%s: lone channel %s" % (CUR_FILE[0], code.strip()))
            continue
        out.append(code[pos:start])
        out.append(target(ref) + SINGLES[name])
        pos = end
    out.append(code[pos:])
    return "".join(out)


CUR_FILE = [None]


def rewrite_code(code):
    note_locals(code)
    masked = mask_strings(code)
    if not re.search(r"\b(" + NAME_RE + r")\b", masked):
        return code
    m = WRITE_RE.match(code)
    if m and WRITE_RE.match(masked) and m.group(3) in SINGLES:
        indent, ref, name, op, value = m.groups()
        if (name not in LOCALS or ref) and ref_ok(ref, name):
            value = rewrite_reads(value, mask_strings(value))
            field = SINGLES[name]
            if op:
                value = "%s%s %s (%s)" % (target(ref), field, op, value)
            if TRACKED:
                return "%s%sset_%s(%s)" % (indent, target(ref), field, value)
            return "%s%s%s = %s" % (indent, target(ref), field, value)
    return rewrite_reads(code, masked)


def main():
    changed = 0
    for p in code_files():
        if p in SKIP:
            continue
        text = read(p)
        if not re.search(r"\b(" + NAME_RE + r")\b", text):
            continue
        CUR_FILE[0] = p
        lines = text.split("\n")
        lines = merge_triples(lines, p)
        keep = []
        OWNER[0] = None
        LOCALS.clear()
        for raw in lines:
            line = raw.rstrip("\r")
            tm = TYPE_LINE.match(line)
            if tm and "/proc/" not in line and "/verb/" not in line:
                OWNER[0] = None
            elif line and not line.startswith("\t") and not line.startswith(" ") and not line.startswith("//") and not line.startswith("#"):
                pm = re.match(r"^(/[A-Za-z0-9_/]+?)/(?:proc/|verb/)?([A-Za-z_]\w*)\((.*)$", line)
                OWNER[0] = pm.group(1) if pm and not pm.group(1).startswith("/proc") else None
                LOCALS.clear()
                if pm:
                    for am in re.finditer(r"((?:[A-Za-z_]\w*/)+)([A-Za-z_]\w*)", pm.group(3)):
                        LOCALS[am.group(2)] = "/" + am.group(1).rstrip("/")
            code, comment = split_code_comment(line)
            if code.startswith("\t") or code.startswith(" "):
                code = rewrite_code(code)
            keep.append(code + comment + ("\r" if raw.endswith("\r") else ""))
        new = "\n".join(keep)
        if new != text:
            changed += 1
            write(p, new)
    for r in RESIDUE:
        print("residue " + r)
    print("profile_record %s: %d files changed, %d residue lines" % (_spec_name, changed, len(RESIDUE)))


if __name__ == "__main__":
    main()
