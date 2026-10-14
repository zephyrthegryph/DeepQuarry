#!/usr/bin/env python3
"""Dead constructor arguments and the overrides that only forward them (final_api section 6, "param() and make()").

Sites come from the `lifeforms` lint (tools/analyze, sem/ctor_args.rs):

  ctor_dead_arg       new /T(loc, a, b): an argument at a position no param(pos =) of /T takes and no New()/Initialize() of /T reads.
                      Trailing dead arguments are removed; a dead one before a live one becomes `null` (no argument: the position
                      keeps its default), so the live one keeps its position.
  ctor_forward_only   /T/Initialize(mapload, a): trailing parameters only handed to ..(). They are dropped from the header, and a
                      `..(mapload, a)` that passes exactly the old parameters in order becomes `..()` (which passes the caller's
                      arguments by itself). Any other use of a dropped name is residue.
  param_pos_override  param(nameof(v), pos = N) on a subtype whose ancestor maps N too: `, overrides = TRUE` is added.

Dry run by default; --apply writes. A site the script cannot rewrite exactly is printed as residue and left alone.

    python3 tools/dx/codemods/ctor_args.py [--analyze PATH] [--apply]
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
SITE = re.compile(r"^(code/\S+?):(\d+): \[lifeforms/(ctor_dead_arg|ctor_forward_only|param_pos_override)\] (.*)$")
DEAD_TAG = re.compile(r"\[ctor-dead (\S+) (\d+) ([\d,]+)\]")
FWD_TAG = re.compile(r"\[ctor-forward ([\w,]+)\]")
OVR = re.compile(r"param\(nameof\((\w+)\), pos = (\d+)\)")


def analyze_binary():
    if "--analyze" in sys.argv:
        return sys.argv[sys.argv.index("--analyze") + 1]
    out = subprocess.run(["bash", "tools/ci/analyze.sh"], cwd=ROOT, capture_output=True, text=True)
    return out.stdout.strip().splitlines()[-1]


def sites():
    out = subprocess.run([analyze_binary(), "check", "--lint", "lifeforms"], cwd=ROOT, capture_output=True, text=True).stdout
    found = []
    for line in out.splitlines():
        m = SITE.match(line)
        if m:
            found.append((m.group(1), int(m.group(2)), m.group(3), m.group(4)))
    return found


def skip_string(text, i):
    """i at an opening quote: the index after its closing quote (DM strings, with [] embeds and escapes)."""
    q = text[i]
    i += 1
    depth = 0
    while i < len(text):
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == "[":
            depth += 1
        elif c == "]" and depth:
            depth -= 1
        elif c == q and not depth:
            return i + 1
        i += 1
    return i


def split_call(text, open_paren):
    """Argument spans [(start, end)] of the call whose '(' is at open_paren, and the index of its ')'."""
    args = []
    depth = 0
    start = open_paren + 1
    i = open_paren + 1
    while i < len(text):
        c = text[i]
        if c in "\"'":
            i = skip_string(text, i)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                if text[start:i].strip():
                    args.append((start, i))
                return args, i
            depth -= 1
        elif c == "," and depth == 0:
            args.append((start, i))
            start = i + 1
        i += 1
    return None, None


def line_offsets(text):
    offs = [0]
    for i, c in enumerate(text):
        if c == "\n":
            offs.append(i + 1)
    return offs


def fix_dead(text, offs, line, ty, passed, dead):
    """One `new` on `line`: the edited text, or None (residue)."""
    start = offs[line - 1]
    end = offs[line] if line < len(offs) else len(text)
    seg = text[start:end]
    short = ty
    pats = [re.compile(r"\bnew\s+" + re.escape(short) + r"\s*\("), re.compile(r"\bnew\s*\(")]
    for pat in pats:
        for m in pat.finditer(seg):
            open_paren = start + m.end() - 1
            args, close = split_call(text, open_paren)
            if args is None or len(args) - 1 != passed:
                continue
            given = [text[a:b].strip() for a, b in args]
            keep = list(given)
            for pos in dead:
                # A call in a dead argument may do something: leave it for a person to read.
                if re.search(r"[\w\]]\s*\(", given[pos]):
                    return None
                keep[pos] = None
            # Trailing dead arguments go, and so do the literal nulls left before them (null is no argument).
            while len(keep) > 1 and (keep[-1] is None or keep[-1] == "null"):
                keep.pop()
            keep = ["null" if k is None else k for k in keep]
            if keep == given:
                return None
            return text[:open_paren + 1] + ", ".join(keep) + text[close:]
    return None


HEADER = re.compile(r"^(?P<path>/[\w/]+?)/(?:proc/)?(?P<name>New|Initialize)\((?P<params>[^)]*)\)")


def param_name(p):
    p = p.split("=")[0].strip()
    return re.split(r"[/\s]", p)[-1] if p else ""


def fix_forward(text, offs, line, drop):
    start = offs[line - 1]
    end = offs[line] if line < len(offs) else len(text)
    hdr = text[start:end]
    m = HEADER.match(hdr)
    if not m:
        return None, "header not on one line"
    params = [p for p in m.group("params").split(",")]
    names = [param_name(p) for p in params]
    if len(names) <= len(drop) or names[-len(drop):] != drop:
        return None, "dropped params are not the trailing ones"
    kept = params[: len(params) - len(drop)]
    new_hdr = hdr[: m.start("params")] + ",".join(kept).strip() + hdr[m.end("params"):]
    # The body: up to the next line as shallow as the header.
    body_start = end
    j = line
    while j < len(offs):
        ln = text[offs[j]: offs[j + 1] if j + 1 < len(offs) else len(text)]
        stripped = ln.strip()
        if stripped and not stripped.startswith("//") and not ln[0] in " \t":
            break
        j += 1
    body_end = offs[j] if j < len(offs) else len(text)
    body = text[body_start:body_end]
    exact = re.compile(r"\.\.\(\s*" + r"\s*,\s*".join(re.escape(n) for n in names) + r"\s*\)")
    # `..(mapload, x)` with `x = default` passes the default when the caller gave nothing; `..()` would not.
    if exact.search(body) and any("=" in p for p in params[len(params) - len(drop):]):
        return None, "a dropped parameter has a default that ..() forwards explicitly"
    body2 = exact.sub("..()", body)
    code_only = "\n".join(re.sub(r'"(?:[^"\\]|\\.)*"', '""', ln.split("//")[0]) for ln in body2.split("\n"))
    for n in drop:
        if re.search(r"(?<![\w./])" + re.escape(n) + r"(?![\w])", code_only):
            return None, f"{n} is still used after the rewrite"
    return text[:start] + new_hdr + body2 + text[body_end:], None


def fix_override(text, offs, line, var, pos):
    start = offs[line - 1]
    pat = re.compile(r"param\(\s*nameof\(\s*" + re.escape(var) + r"\s*\)")
    m = pat.search(text, start)
    if not m:
        return None
    open_paren = m.start() + len("param")
    args, close = split_call(text, open_paren)
    if args is None:
        return None
    flat = [text[a:b].replace(" ", "") for a, b in args]
    if f"pos={pos}" not in flat or any(f.startswith("overrides=") for f in flat):
        return None
    return text[:close] + ", overrides = TRUE" + text[close:]


def main():
    by_file = {}
    for rel, line, rule, msg in sites():
        by_file.setdefault(rel, []).append((line, rule, msg))
    done = residue = 0
    for rel, items in sorted(by_file.items()):
        path = ROOT / rel
        text = path.read_text(encoding="utf-8")
        crlf = "\r\n" in text
        if crlf:
            text = text.replace("\r\n", "\n")
        # Bottom-up, so an edit never moves a later site's line.
        for line, rule, msg in sorted(items, key=lambda x: -x[0]):
            offs = line_offsets(text)
            new = None
            why = "no exact match"
            if rule == "ctor_dead_arg":
                m = DEAD_TAG.search(msg)
                if m:
                    new = fix_dead(text, offs, line, m.group(1), int(m.group(2)), [int(x) for x in m.group(3).split(",")])
            elif rule == "ctor_forward_only":
                m = FWD_TAG.search(msg)
                if m:
                    new, why2 = fix_forward(text, offs, line, m.group(1).split(","))
                    why = why2 or why
            else:
                m = re.search(r"param\(nameof\((\w+)\), pos = (\d+)\)", msg)
                if m:
                    new = fix_override(text, offs, line, m.group(1), m.group(2))
            if new is None:
                residue += 1
                print(f"RESIDUE {rel}:{line} [{rule}] {why}: {msg[:160]}")
                continue
            text = new
            done += 1
            print(f"rewrite {rel}:{line} [{rule}]")
        if crlf:
            text = text.replace("\n", "\r\n")
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(text)
    print(f"ctor_args: {done} site(s) rewritten, {residue} residue{'' if _guard.APPLY else ' (dry run: nothing written; --apply writes)'}")
    return 0 if residue == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
