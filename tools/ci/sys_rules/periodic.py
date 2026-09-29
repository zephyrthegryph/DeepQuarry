"""Periodic work declared by state (doc/rewrite/systems.md section 5).

Three shapes of the one pattern "periodic work started and stopped by hand around a piece of
state". Each is replaced by DECLARE_PERIODIC_WHILE / DECLARE_PERIODIC_WHILE_ALL / DECLARE_REPEAT
(code/__defines/sys_periodic.dm), which start and stop the work from the state's change channel.

`periodic_guard`   A periodic_step() / machine_step() body whose top-level statement is
                   `if(<state>) return PROCESS_KILL`, where <state> reads only fields: bare vars
                   (`on`, `!active`, `src.x`), `operable()` and `has_stat(...)`, joined by
                   `||` / `&&`. The body stops itself when a field goes false; the declaration
                   stops it instead.
`om_after_rearm`   A self-re-arming timer loop: `om_after(src, ..., PROC_REF(p))` (or
                   om_after_slot) inside `p` whose extra arguments are only constants or `p`'s own
                   parameters passed on unchanged. A re-arm that passes a per-step progression
                   (a counter `i + 1`, `left - 1`, `++n`, a local computed this step) is a
                   finite sequence, not a loop over state, and is not this pattern.
`periodic_toggle`  A hand start/stop on a state toggle: om_task_periodic(src, ...),
                   om_task_periodic_stop(src), MACHINE_WAKE(src) or MACHINE_SLEEP(src) directly
                   next to a write of a var (`x = ...`, `set_x(...)`, `x_add/x_remove(...)`) or as
                   the first statement of an `if(<state>)` / `else` branch over fields; and every
                   hand stop (om_task_periodic_stop(src), MACHINE_SLEEP(src)) outside the body
                   itself (periodic_step/machine_step) and the lifecycle teardown hooks
                   (on_dematerialize, lifecycle_dematerialize, on_destroy, lifecycle_prerelease):
                   something ended the work, and that something is the state to declare.
"""
import re

RULES = {
    "periodic_guard": "DECLARE_PERIODIC_WHILE(type, cadence, \"field\") and drop the guard "
                      "(doc/rewrite/systems.md section 5)",
    "om_after_rearm": "DECLARE_REPEAT(type, delay, proc, \"field\") instead of a self-re-arming "
                      "om_after() (doc/rewrite/systems.md section 5)",
    "derived_hand_raise": "declare the derived field's inputs (OM_DERIVE_FIELD(T, F, list(\"input\", ...))) as "
                          "fields; their setters raise it (doc/rewrite/systems.md section 5)",
    "periodic_toggle": "declare the state (DECLARE_PERIODIC_WHILE / DECLARE_REPEAT) and let its "
                       "setter start/stop the work (doc/rewrite/systems.md section 5)",
}

# The runtime and the scheduler core start/stop work on purpose.
SKIP = ("code/datums/sys/periodic.dm", "code/datums/om/", "code/game/machinery/machine_pipeline.dm")

HEAD = re.compile(r"^(/[\w/]+?)/(?:proc/|verb/)?(\w+)\s*\(([^)]*)\)")
STEP_PROCS = ("periodic_step", "machine_step")

# A field term: `x`, `!x`, `src.x`, `operable()`, `has_stat(BITS)`.
TERM = r"!?\s*(?:src\.)?(?:[A-Za-z_]\w*(?!\s*[\(\.\[])|operable\(\s*\)|has_stat\(\s*[\w|\s]*\))"
STATE_COND = re.compile(r"^\(*\s*%s\s*\)*(?:\s*(?:\|\||&&)\s*\(*\s*%s\s*\)*)*$" % (TERM, TERM))
IF_HEAD = re.compile(r"^(?:else\s+)?if\s*\((.*)\)\s*(.*)$")
NOT_VARS = {"TRUE", "FALSE", "null", "src", "usr", "world"}

START_STOP = re.compile(
    r"\b(?:om_task_periodic(?:_stop)?\s*\(\s*src\b|MACHINE_WAKE\s*\(\s*src\s*\)|MACHINE_SLEEP\s*\(\s*src\s*\))")
WRITE = re.compile(
    r"^(?:src\.)?([A-Za-z_]\w*)\s*(?:=(?!=)|\+=|-=|\|=|&=|\^=|\+\+|--)"
    r"|^(?:src\.)?set_(\w+)\s*\(|^(?:src\.)?(\w+)_(?:add|remove)\s*\(")
STOP = re.compile(r"\b(?:om_task_periodic_stop\s*\(\s*src\s*\)|MACHINE_SLEEP\s*\(\s*src\s*\))")
# Where a hand stop is the body's own decision or the lifecycle's teardown, not a state toggle.
STOP_OK = STEP_PROCS + ("on_dematerialize", "lifecycle_dematerialize", "on_destroy", "lifecycle_prerelease")
REARM = re.compile(r"\bom_after(?:_slot)?\s*\(\s*src\s*,(.*)$")
PROC_ARG = re.compile(r"(?:PROC_REF|TYPE_PROC_REF)\s*\(\s*(?:[\w/]+\s*,\s*)?(\w+)\s*\)")
CONSTANT = re.compile(r"^(?:[A-Z_][A-Z0-9_]*|-?\d+(?:\.\d+)?|TRUE|FALSE|null|\"[^\"]*\")$")


def _cond_is_state(cond):
    cond = cond.strip()
    if not cond or not STATE_COND.match(cond):
        return False
    words = re.findall(r"[A-Za-z_]\w*", cond)
    return any(w not in NOT_VARS and w not in ("operable", "has_stat") and not w.isupper() for w in words) or \
        "operable" in cond or "has_stat" in cond


def _split_args(text):
    """Top-level comma split of the text after `om_after(src,` up to its closing paren."""
    depth = 0
    out, cur = [], ""
    for ch in text:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            if depth == 0:
                out.append(cur)
                return [a.strip() for a in out]
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
            continue
        cur += ch
    out.append(cur)
    return [a.strip() for a in out]


def _params(sig):
    names = []
    for part in sig.split(","):
        part = part.split("=", 1)[0].strip()
        if not part:
            continue
        names.append(part.split("/")[-1].split(" as ")[0].strip())
    return names


def _procs(lines):
    """Yields (name, params, body) with body = [(number, raw)] for each top-level proc."""
    cur = None
    for number, line in enumerate(lines, 1):
        if line and not line[0].isspace():
            if cur:
                yield cur
                cur = None
            m = HEAD.match(line)
            if m and not line.lstrip().startswith("#"):
                cur = (m.group(2), _params(m.group(3)), [])
            continue
        if cur is not None:
            cur[2].append((number, line))
    if cur:
        yield cur


def _stmts(body):
    """Non-blank, non-comment statement lines: (number, indent, code)."""
    out = []
    for number, raw in body:
        code = raw.split("//", 1)[0].rstrip()
        if not code.strip():
            continue
        indent = len(raw) - len(raw.lstrip("\t"))
        out.append((number, indent, code.strip()))
    return out


def _scan_guard(name, stmts, hits):
    if name not in STEP_PROCS:
        return
    local_names = set()
    for _n, _i, c in stmts:
        for m in re.finditer(r"(?<![\w/])var/(?:[\w/]+/)?(\w+)", c):
            local_names.add(m.group(1))
    for idx, (number, indent, code) in enumerate(stmts):
        if indent != 1:
            continue
        m = IF_HEAD.match(code)
        if not m or code.startswith("else"):
            continue
        cond, tail = m.group(1), m.group(2).strip()
        if tail:
            kill = re.match(r"^return\s+PROCESS_KILL\b", tail)
        else:
            nxt = stmts[idx + 1] if idx + 1 < len(stmts) else None
            after = stmts[idx + 2] if idx + 2 < len(stmts) else None
            kill = nxt and nxt[1] == 2 and re.match(r"^return\s+PROCESS_KILL\b", nxt[2]) and \
                (not after or after[1] <= 1)
        if kill and _cond_is_state(cond) and not (set(re.findall(r"[A-Za-z_]\w*", cond)) & local_names):
            hits.append(number)


def _unchanged(arg, k, params):
    """An argument a loop passes on as is: a non-numeric constant, or the same parameter."""
    if not arg:
        return True
    if k < len(params) and arg == params[k]:
        return True
    return bool(CONSTANT.match(arg)) and not re.match(r"^-?\d", arg)


def _scan_rearm(name, params, stmts, hits):
    for number, _indent, code in stmts:
        m = REARM.search(code)
        if not m:
            continue
        args = _split_args(m.group(1))
        target = None
        rest = []
        for i, arg in enumerate(args):
            p = PROC_ARG.search(arg)
            if p and target is None:
                target = p.group(1)
                rest = args[i + 1:]
                break
        if target != name:
            continue
        if all(_unchanged(a, k, params) for k, a in enumerate(rest)):
            hits.append(number)


def _branch_is_state(stmts, idx):
    """TRUE when stmts[idx] is the first statement of an if/else branch over fields."""
    number, indent, _code = stmts[idx]
    if idx == 0:
        return False
    pn, pindent, pcode = stmts[idx - 1]
    if pindent != indent - 1:
        return False
    m = IF_HEAD.match(pcode)
    if m and not m.group(2).strip():
        return _cond_is_state(m.group(1))
    if pcode == "else":
        # Find the matching if at pindent.
        for j in range(idx - 2, -1, -1):
            jn, jindent, jcode = stmts[j]
            if jindent < pindent:
                return False
            if jindent == pindent:
                mm = IF_HEAD.match(jcode)
                if mm and not jcode.startswith("else"):
                    return _cond_is_state(mm.group(1))
    return False


def _is_write(code):
    m = WRITE.match(code)
    if not m:
        return False
    word = m.group(1) or m.group(2) or m.group(3)
    return word not in ("var", ".") and not code.startswith("var/")


def _scan_toggle(name, stmts, hits):
    for idx, (number, indent, code) in enumerate(stmts):
        if not START_STOP.search(code):
            continue
        if STOP.search(code) and name not in STOP_OK:
            # A hand stop outside the body and the lifecycle's own teardown: the state that ended the
            # work is what should be declared.
            hits.append(number)
            continue
        near = []
        if idx > 0 and stmts[idx - 1][1] == indent:
            near.append(stmts[idx - 1][2])
        if idx + 1 < len(stmts) and stmts[idx + 1][1] == indent:
            near.append(stmts[idx + 1][2])
        if any(_is_write(c) for c in near) or _branch_is_state(stmts, idx):
            hits.append(number)


DERIVE = re.compile(r"^OM_DERIVE_FIELD\(\s*(/[\w/]+)\s*,\s*(\w+)\s*,\s*(.*)\)\s*(?://.*)?$")
RAISE = re.compile(r"om_changed\(\s*src\s*,")


def _derived_inputs(files):
    """type path -> set of input field names of the derived fields it (or an ancestor) declares."""
    out = {}
    for _rel, lines in files:
        for line in lines:
            m = DERIVE.match(line.strip())
            if m:
                out.setdefault(m.group(1), set()).update(re.findall(r"\"(\w+)\"", m.group(3)))
                out[m.group(1)].add("")  # marks a type with derived fields
    return out


def _inputs_for(path, derived):
    names = set()
    for root, inputs in derived.items():
        if path == root or path.startswith(root + "/"):
            names |= inputs
    return names


def _scan_hand_raise(lines, derived, hits, rel):
    """om_changed(src, ...) in a proc of a type with derived fields, when it is a hand refresh:
    a CHANGE_EXPLICIT raise, or any raise within two statements of a write of a derived input."""
    path = None
    for number, line in enumerate(lines, 1):
        if line and not line[0].isspace():
            m = HEAD.match(line)
            path = m.group(1) if m else None
            if path and "/proc" in path:
                path = path.split("/proc")[0]
            continue
        if not path:
            continue
        code = line.split("//", 1)[0]
        if not RAISE.search(code):
            continue
        inputs = _inputs_for(path, derived)
        if not inputs:
            continue
        if "CHANGE_EXPLICIT" in code:
            hits.append((rel, number))
            continue
        names = inputs - {""}
        near = [lines[i].split("//", 1)[0].strip() for i in range(max(0, number - 3), min(len(lines), number + 2)) if i != number - 1]
        for c in near:
            m = WRITE.match(c)
            word = m and (m.group(1) or m.group(2) or m.group(3))
            if word and word in names:
                hits.append((rel, number))
                break


def scan(files):
    out = {rule: [] for rule in RULES}
    derived = _derived_inputs(files)
    for rel, lines in files:
        if rel.startswith(SKIP):
            continue
        text = "\n".join(lines)
        if "om_changed" in text and derived:
            _scan_hand_raise(lines, derived, out["derived_hand_raise"], rel)
        if not any(k in text for k in ("PROCESS_KILL", "om_after", "om_task_periodic", "MACHINE_WAKE", "MACHINE_SLEEP")):
            continue
        for name, params, body in _procs(lines):
            stmts = _stmts(body)
            g, r, t = [], [], []
            _scan_guard(name, stmts, g)
            _scan_rearm(name, params, stmts, r)
            _scan_toggle(name, stmts, t)
            out["periodic_guard"] += [(rel, n) for n in g]
            out["om_after_rearm"] += [(rel, n) for n in r]
            out["periodic_toggle"] += [(rel, n) for n in t]
    return out
