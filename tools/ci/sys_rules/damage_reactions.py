"""Declared damage reactions (doc/rewrite/systems.md section 12).

entry_override: an override of a damage entry point (bullet_act, emp_act, ex_act, fire_act,
blob_act, hitby, attack_generic, electrocute_act) that does a *fixed thing*: something that does
not depend on the hit beyond its entry and severity, so a declaration says it instead
(DAMAGE_REACTION / REFLECTS / EMP_DISABLE, or a protection flag). Precisely, an override is
flagged unless it is *procedural*, i.e. at least one of:

  P1  it reads the hit: any of its own parameters other than `severity` / `recursive` / `forced`
      (the projectile, the thrown atom, the attacker, the damage, the temperature, the blob ...)
      appears in the body outside a parent call's argument list; or
  P2  it returns a hit-flow value to the entry's caller: `return X` with X anything other than
      nothing, `.`, a parent call, `0`, `FALSE` or `null` (PROJECTILE_CONTINUE, a computed
      result, a blocked amount ...).

Every other shape is flagged, whatever its layout:
  - a pure pass-through (only the parent call, in any form: `..()`, `. = ..()`, `return ..()`,
    `..(args)`) -- delete it;
  - an immunity (an empty body, or a bare `return`, with no parent call) -- a protection flag
    (`resistance_flags`, `emp_protection_flags`, `uses_integrity`) or a blocking reaction;
  - a side effect on top of, or instead of, the default hit that reads at most `severity`
    (sparks, alarms, toggles, EMPED + recovery timers, severity ladders) -- a DAMAGE_REACTION
    or EMP_DISABLE, whose proc reads the packet (packet.severity);
  - the reflect boilerplate: a bullet_act that redirects the projectile back towards
    `P.starting` and reads nothing else of it but its type, name, damage type and `reflected`
    -- REFLECTS.

The adapters themselves (the definitions on /atom, /atom/movable, /obj, /turf, /mob and
/mob/living, which build the packet) are not overrides of anything and are not scanned.
"""
import re

RULES = {
    "entry_override": "declare it next to the type: DAMAGE_REACTION(type, trigger, PROC_REF(x)) / "
                      "REFLECTS(type, kinds, chance) / EMP_DISABLE(type, duration, field), or a "
                      "protection flag (doc/rewrite/systems.md section 12)",
}

ENTRIES = ("bullet_act", "emp_act", "ex_act", "fire_act", "blob_act", "hitby", "attack_generic",
           "electrocute_act")
ADAPTER_ROOTS = {"/atom", "/atom/movable", "/obj", "/turf", "/mob", "/mob/living"}
FREE_PARAMS = {"severity", "recursive", "forced"}

HEADER = re.compile(r"^(/[\w/]+?)/(" + "|".join(ENTRIES) + r")\s*\((.*)$")
STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')
PARENT_CALL = re.compile(r"\.\.\(")
RETURN = re.compile(r"(?<![\w.])return\b\s*(.*)$")
REFLECT_ALLOWED_MEMBERS = {"starting", "name", "reflected", "redirect", "obj_damage_type"}


def param_names(signature):
    """Names of the parameters in `signature` (the text after the header's opening paren)."""
    depth = 1
    text = []
    for c in signature:
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                break
        text.append(c)
    names = []
    for part in "".join(text).split(","):
        part = part.split("=", 1)[0].strip()
        if not part:
            continue
        part = part.split(" as ", 1)[0].strip()
        names.append(part.split("/")[-1].strip())
    return [n for n in names if re.match(r"^[A-Za-z_]\w*$", n)]


def code_of(line):
    line = STRING.sub('""', line)
    return line.split("//", 1)[0]


def strip_parent_args(code):
    """The line with every parent call's argument list removed (`..(P, def_zone)` -> `..()`)."""
    out = []
    i = 0
    while i < len(code):
        m = PARENT_CALL.search(code, i)
        if not m:
            out.append(code[i:])
            break
        out.append(code[i:m.end()])
        depth = 1
        j = m.end()
        while j < len(code) and depth:
            if code[j] == "(":
                depth += 1
            elif code[j] == ")":
                depth -= 1
            j += 1
        out.append(")")
        i = j
    return "".join(out)


def is_reflect_boilerplate(body, name):
    """The reflect shape: a redirect back towards `name.starting`, reading nothing else of it."""
    text = "\n".join(body)
    if not re.search(r"\b%s\s*\.\s*redirect\s*\(" % re.escape(name), text):
        return False
    if not re.search(r"\b%s\s*\.\s*starting\b" % re.escape(name), text):
        return False
    for m in re.finditer(r"\b%s\b(\s*\.\s*(\w+))?" % re.escape(name), text):
        member = m.group(2)
        if member is None:
            before = text[max(0, m.start() - 40):m.start()]
            # istype(P, ...), act_message(src, P, ...) and visible_message("[P]") read no state
            if re.search(r"(istype|act_message|visible_message|span_\w+)\s*\([^()]*$", before):
                continue
            return False
        if member not in REFLECT_ALLOWED_MEMBERS:
            return False
    return True


def procedural(body, params):
    reads = [p for p in params if p not in FREE_PARAMS]
    lines = [strip_parent_args(code_of(line)) for line in body]
    for line in lines:
        m = RETURN.search(line)
        if not m:
            continue
        value = m.group(1).strip().rstrip(";").strip()
        while value.startswith("(") and value.endswith(")"):
            value = value[1:-1].strip()
        if value in ("", ".", "..()", "0", "FALSE", "null"):
            continue
        if reads and is_reflect_boilerplate(lines, reads[0]):
            continue
        return True
    for name in reads:
        pattern = re.compile(r"(?<![\w.])%s\b" % re.escape(name))
        if any(pattern.search(line) for line in lines):
            if is_reflect_boilerplate(lines, name):
                continue
            return True
    return False


def scan(files):
    out = {rule: [] for rule in RULES}
    for rel, lines in files:
        for index, line in enumerate(lines):
            m = HEADER.match(line)
            if not m:
                continue
            path = m.group(1)
            if path.endswith("/proc") or "/proc/" in path + "/" or "/verb" in path:
                continue  # a definition, not an override
            if path in ADAPTER_ROOTS:
                continue
            body = []
            j = index + 1
            while j < len(lines) and (lines[j].startswith(("\t", " ")) or not lines[j].strip()):
                body.append(lines[j])
                j += 1
            if procedural(body, param_names(m.group(3))):
                continue
            out["entry_override"].append((rel, index + 1))
    return out
