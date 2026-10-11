"""Moves mob vars onto the client HUD datum (/datum/hud), driven by the compiler's "undefined var" errors.

  python tools/dx/codemods/move_to_hud.py <compile log> [--apply] [--files ...] [--dirs ...]

Run after the vars were deleted from /mob and declared as hud_element()s on /datum/hud and the tree compiled once: every
`file:line:error: <expr>: undefined var` naming one of VARS is rewritten on that line.
  * `rel_set(H, nameof(v), x)` / `rel_set(src, nameof(H.v), x)` -> `rel_set(hud_of(H), nameof(/datum/hud::v), x)` (the hud of src is
    `hud_used`); rel_clear/rel_add/rel_remove alike;
  * `H.v` -> `hud_of(H)?.v` and a bare `v` (src's) -> `hud_used?.v`; a `.` straight after becomes `?.` (a mob without a client has no hud).
  * a `var/T/v = ...` local or a proc argument named v is left alone (the compiler does not report it).
Lines it cannot rewrite exactly are printed as residue. Dry run unless --apply.
"""
import _guard  # noqa: F401  (must be first: --help, dry run, write scope)
import re
import sys

VARS = {
    "hands", "pullin", "internals", "healths", "throw_icon", "pain", "item_use_icon", "radio_use_icon", "gun_move_icon",
    "gun_setting_icon", "ling_chem_display", "borer_chem_display", "wiz_energy_display", "wiz_instability_display",
    "autowhisper_display", "plane_holder", "vis_enabled", "planes_visible", "zone_sel", "shadekin_display", "lleill_display",
    "xenochimera_danger_display",
}
REF = r"[A-Za-z_]\w*(?:\(\))?(?:(?:\?\.|\.)[A-Za-z_]\w*(?:\(\))?)*"
ERR = re.compile(r"^(?P<file>[^:]+\.dm):(?P<line>\d+):error: (?P<expr>.*?): (?:undefined var|requires a var)")


def hud(ref):
    return "hud_used" if ref in (None, "src") else "hud_of(%s)" % ref


def rewrite(line, v):
    orig = line
    # rel_x(H, nameof(v) ...) and rel_x(src, nameof(H.v) ...)
    def rel(m):
        fn, holder, inner = m.group(1), m.group(2).strip(), m.group(3)
        ref = holder
        if "." in inner:
            ref = inner.rsplit(".", 1)[0]
        return "%s(%s, nameof(/datum/hud::%s)" % (fn, hud(ref), v)
    line = re.sub(r"\b(rel_set|rel_clear|rel_add|rel_remove|rel_take)\(\s*([^,()]+(?:\(\))?)\s*,\s*nameof\(\s*((?:" + REF + r"\.)?" + v + r")\s*\)", rel, line)
    # H.v / H?.v reads and writes
    def dotted(m):
        return "%s?.%s%s" % (hud(m.group(1)), v, "?." if m.group(2) else "")
    line = re.sub(r"(?<![\w.:/])(" + REF + r")\??\.(?:" + v + r")\b(\.)?(?!\()", lambda m: dotted(m) if not m.group(1).startswith("hud_") and m.group(1) != "datum" else m.group(0), line)
    # bare v (src's)
    def bare(m):
        return "hud_used?.%s%s" % (v, "?." if m.group(1) else "")
    line = re.sub(r"(?<![\w.:/?])(?<!::)\b" + v + r"\b(?!\s*\()(\.)?", bare, line) if re.search(r"(?<![\w.:/?])\b" + v + r"\b", line.replace("/datum/hud::" + v, "")) else line
    # fix: undo a bare rewrite inside the new nameof(/datum/hud::v)
    line = line.replace("nameof(/datum/hud::hud_used?.%s)" % v, "nameof(/datum/hud::%s)" % v)
    line = line.replace("hud_of(src)", "hud_used")
    return line if line != orig else None


def main():
    log = [a for a in sys.argv[1:] if not a.startswith("--") and not a.endswith(".dm")][0]
    sites = {}
    for raw in open(log, encoding="utf-8", errors="replace"):
        m = ERR.match(raw.strip())
        if not m:
            continue
        expr = m.group("expr").strip()
        names = [x.replace("()", "") for x in re.split(r"\??\.", expr)]
        hit = [x for x in names if x in VARS]
        if expr == "nameof":
            path = m.group("file").replace("\\", "/")
            text = open(path, encoding="utf-8", errors="replace").read().split("\n")[int(m.group("line")) - 1]
            hit = [x for x in VARS if re.search(r"nameof\((?:[\w.]*\.)?" + x + r"\)", text)]
        if not hit:
            continue
        v = hit[0]
        sites.setdefault(m.group("file").replace("\\", "/"), {}).setdefault(int(m.group("line")), set()).add(v)
    residue = []
    changed = 0
    for path, lines_at in sites.items():
        with open(path, encoding="utf-8", errors="surrogateescape", newline="") as fh:
            lines = fh.read().split("\n")
        for n, vs in lines_at.items():
            text = lines[n - 1]
            new = text
            for v in sorted(vs):
                r = rewrite(new, v)
                if r is None:
                    residue.append("%s:%d: %s: %s" % (path, n, v, text.strip()))
                else:
                    new = r
            lines[n - 1] = new
        with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
            fh.write("\n".join(lines))
        changed += 1
    for r in residue:
        print("residue " + r)
    print("move_to_hud: %d files, %d sites, %d residue" % (changed, sum(len(x) for x in sites.values()), len(residue)))


if __name__ == "__main__":
    main()
