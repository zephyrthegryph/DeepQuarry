"""Inline refusals lifted into requirements (doc/rewrite/systems.md section 6).

Rule (must stay at 0):

  inline_refusal   A refusal written inside an interaction effect proc instead of declared as a
                   requirement, so the Menu can't show why the interaction is unavailable:

                     - any REFUSE_IF(...) (the legacy macro is deleted; it must not come back);
                     - at the head of an effect proc (after its local `var/` declarations and
                       other guards), an `if(cond)` block with no `else` that only tells the actor
                       no (to_chat / balloon_alert / visible_message / audible_message /
                       show_message / playsound) and returns, in either layout:
                           if(cond)                      if(cond) return to_chat(user, ...)
                               to_chat(user, ...)        if(cond) { to_chat(user, ...); return }
                               return

                   An effect proc is any proc named by an interaction: PROC_REF(x) inside
                   DECLARE_INTERACTIONS / EXTEND_INTERACTIONS (or an INTERACT_* spec), or a
                   full-form `effect = /type/proc/x`, defined on the declaring type, an ancestor
                   or a subtype. Declare the condition with REQ_FIELD / REQ_FIELD_NOT /
                   REQ_FIELD_EQ / REQ_ACCESS / REQ_NOT_EMAGGED / REQ_ANCHORED / REQ_PANEL /
                   REQ_ON (code/__defines/sys_requirements.dm) instead.
"""
import re

RULES = {
    "inline_refusal": "declare the guard as a requirement clause (REQ_FIELD/REQ_FIELD_NOT/REQ_FIELD_EQ/"
                      "REQ_ACCESS/REQ_NOT_EMAGGED/REQ_ANCHORED/REQ_PANEL/REQ_ON) on the interaction "
                      "(systems.md section 6)",
}

DECL = re.compile(r"\b(?:DECLARE_INTERACTIONS|EXTEND_INTERACTIONS)\(\s*(/[\w/]+)")
SPEC = re.compile(r"\bINTERACT_[A-Z_]+\(")
PROC_REF = re.compile(r"\b(?:PROC_REF|TYPE_PROC_REF\([^,]*,)\s*\(?\s*(\w+)\s*\)|\.proc/(\w+)")
FULL_EFFECT = re.compile(r"^\s+effect\s*=\s*(/[\w/]+?)/(?:proc/)?(\w+)\s*(?://.*)?$")
DATUM_HEAD = re.compile(r"^(/datum/interaction[\w/]*)\s*$")
HEAD = re.compile(r"^(/[\w/]+?)/(?:proc/|verb/)?(\w+)\s*\(")
REFUSE_IF = re.compile(r"\bREFUSE_IF\s*\(")
MESSAGE = re.compile(r"\b(?:to_chat|balloon_alert|visible_message|audible_message|show_message|"
                     r"balloon_alert_to_viewers)\s*\(")
QUIET = re.compile(r"^(?:playsound|SEND_SOUND)\s*\(")
RETURN = re.compile(r"^return\b")
IF = re.compile(r"^if\s*\(")
# A condition that performs the action (drops the item, spends a stack, asks the player) reports
# that action failing, which is effect-time feedback, not a refusal a requirement could declare.
ACTING = re.compile(r"\b(?:drop_from_inventory|unEquip|drop_item|drop_held_item|put_in_\w+|remove_from_mob|"
                    r"use|use_charge|checked_use|use_tool|do_after|do_mob|tgui_\w+|input|alert|forceMove|"
                    r"try_\w+|attempt_\w+|consume\w*|transfer\w*|insert_item|user_unbuckle_mob|"
                    r"buckle_mob|Move|remove_fuel|use_resource|spend\w*|pay\w*|charge|om_task_timed)\s*\(")
ELSE = re.compile(r"^else\b")


def strip(line):
    """Code part of a line: comments and string contents dropped."""
    out = []
    i = 0
    quote = None
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = None
                out.append(c)
            i += 1
            continue
        if c == '"' or c == "'":
            quote = c
            out.append(c)
        elif line.startswith("//", i):
            break
        else:
            out.append(c)
        i += 1
    return "".join(out).rstrip()


def related(a, b):
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")


def effect_procs(files):
    """proc name -> set of declaring types."""
    found = {}
    for rel, lines in files:
        decl = None
        datum = False
        for line in lines:
            m = DECL.search(line)
            if m:
                decl = m.group(1)
            if decl and (SPEC.search(line) or DECL.search(line)):
                for ref in PROC_REF.finditer(line):
                    found.setdefault(ref.group(1) or ref.group(2), set()).add(decl)
            if decl and not line.rstrip().endswith("\\"):
                decl = None
            if line and not line[0].isspace():
                datum = bool(DATUM_HEAD.match(line))
            if datum:
                m = FULL_EFFECT.match(line)
                if m:
                    found.setdefault(m.group(2), set()).add(m.group(1))
    return found


def statements(body):
    """Top-level statements of a proc body: lists of (line_no, code, depth)."""
    stmts = []
    for no, raw in body:
        code = strip(raw)
        if not code.strip():
            continue
        depth = len(code) - len(code.lstrip("\t"))
        if depth <= 1 or not stmts:
            stmts.append([(no, code.strip(), depth)])
        else:
            stmts[-1].append((no, code.strip(), depth))
    return stmts


def only_refusal(parts):
    """TRUE when the statements only say no (a message, maybe a sound) and end in return."""
    if not parts or not RETURN.match(parts[-1]):
        return False
    told = False
    for part in parts:
        if MESSAGE.search(part):
            told = True
            if not re.match(r"^[\w.?\[\]]*\s*(?:to_chat|balloon_alert|visible_message|audible_message|"
                            r"show_message|balloon_alert_to_viewers)\s*\(", part) and not RETURN.match(part):
                return False
        elif RETURN.match(part):
            continue
        elif not QUIET.match(part):
            return False
    return told


def guard_parts(stmt):
    """The body of an `if` statement as simple statements, or None if it isn't a plain guard."""
    first = stmt[0][1]
    depth = 0
    for i, c in enumerate(first):
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                cond = first[:i + 1]
                rest = first[i + 1:].strip()
                break
    else:
        return None
    parts = []
    if rest:
        rest = rest.strip("{} ")
        parts += [p.strip() for p in rest.split(";") if p.strip()]
    for _, code, _ in stmt[1:]:
        code = code.strip("{} ")
        parts += [p.strip() for p in code.split(";") if p.strip()]
    return cond, parts


def scan(files):
    out = {"inline_refusal": []}
    effects = effect_procs(files)
    for rel, lines in files:
        for no, line in enumerate(lines, 1):
            if REFUSE_IF.search(strip(line)) and "#define" not in line:
                out["inline_refusal"].append((rel, no))
        i = 0
        n = len(lines)
        while i < n:
            line = lines[i]
            m = HEAD.match(line)
            if not m or m.group(2) not in effects or not any(related(m.group(1), t) for t in effects[m.group(2)]):
                i += 1
                continue
            body = []
            j = i + 1
            while j < n and (not lines[j] or lines[j][0].isspace()):
                body.append((j + 1, lines[j]))
                j += 1
            stmts = statements(body)
            for k, stmt in enumerate(stmts):
                code = stmt[0][1]
                if code.startswith("var/") or code.startswith("set ") or code.startswith("SHOULD_") \
                        or code.startswith("SIGNAL_HANDLER"):
                    continue
                if not IF.match(code):
                    break
                if k + 1 < len(stmts) and ELSE.match(stmts[k + 1][0][1]):
                    break
                guard = guard_parts(stmt)
                if guard is None:
                    break
                cond, parts = guard
                if ACTING.search(cond):
                    continue
                if not parts or not RETURN.match(parts[-1]) and not RETURN.match(parts[0]):
                    break
                if only_refusal(parts) or (len(parts) == 1 and RETURN.match(parts[0]) and MESSAGE.search(parts[0])):
                    out["inline_refusal"].append((rel, stmt[0][0]))
            i = j
    return out
