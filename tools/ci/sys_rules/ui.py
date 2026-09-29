"""Declared UI model lint (doc/rewrite/systems.md section 3).

The whole old pattern:

- `tgui_interact_boilerplate`: a `tgui_interact()` override, or a window opened by hand
  (`SStgui.try_update_ui(`, `new /datum/tgui(`, `ui = new(user, src, ...)`) outside the tgui core
  and the declared-UI runtime. DECLARE_UI rows plus the ui_* hooks replace them.
- `ui_act_dispatch`: any `tgui_act()` override (the base /datum/tgui_act is the one dispatcher;
  rows, UI_ACT_FALLBACK, UI_ACT_FORWARD and UI_ACT_NESTED cover dispatch, forwarding and nesting).
- `text2num_params`: every shape of raw params parsing in the tgui message path:
  * any read of `params` inside a `tgui_act()` override (overrides only forward to another
    datum's tgui_act, which parses again);
  * a raw conversion of a params value anywhere (`text2num(params[`, `round(text2num(`,
    `locate(params[`, `locate_in_list(x, params[`, `text2path(params[`, `json_decode(params[`,
    `params2list(params[`);
  * in a UI_ACT handler: a key no UI_ACT row for that handler declares, a dynamic key
    (`params[var]`), a local copied from params and then parsed (`var/x = params["k"]` ...
    `text2num(x)`), or params handed wholesale to another proc (helpers take values).
"""
import re

RULES = {
    "tgui_interact_boilerplate": "declare the window with DECLARE_UI(type, interface, opts...) and the "
    "ui_prepare/ui_redirect/ui_opening/ui_title/ui_interface hooks instead of a tgui_interact() "
    "override or a hand-opened /datum/tgui (doc/rewrite/systems.md section 3)",
    "ui_act_dispatch": "one UI_ACT(type, action, handler, args...) row per action (UI_ACT_FORWARD to "
    "hand unknown actions to another datum, UI_ACT_NESTED / UI_SUBACT for nested ones) instead of "
    "a tgui_act() override",
    "text2num_params": "declare the arg on the UI_ACT row (UI_ARG_NUM/INT/TEXT/BOOL/CHOICE/REF/PATH/"
    "LIST/VALUE) and read the typed params[name] in the handler; never parse raw params",
}

# Where windows are legitimately built by hand: the tgui core (tgui datum, windows, input
# prompts, the subsystem) and the declared-UI runtime itself.
OPEN_EXEMPT = (
    "code/modules/tgui/",
    "code/modules/tgui_input/",
    "code/controllers/subsystems/tgui.dm",
    "code/datums/sys/ui.dm",
)

# The vendored TGS DMAPI: its `params` are world.Topic query strings from the TGS server, never a
# tgui message (the same exemption the hygiene lint makes).
NOT_TGUI = ("code/modules/tgs/",)

HEADER = re.compile(r"^(/[\w/]+?)/(?:proc/)?(\w+)\s*\(([^)]*)\)")
HANDLER = re.compile(r"^UI_(?:ACT|SUBACT)_(?:PROC|OVERRIDE|PREF_PROC)\(\s*(/[\w/]+)\s*,\s*(\w+)\s*\)")
SUBROW = re.compile(r'^UI_SUBACT\(\s*(/[\w/]+)\s*,\s*"[^"]*"\s*,\s*[^,]+,\s*(\w+)\s*(.*)\)\s*$')
ROW = re.compile(r'^UI_(?:ACT|SUBACT)\(\s*(/[\w/]+)\s*,(?:\s*"[^"]*"\s*,(?=\s*"))?\s*[^,]+,\s*(\w+)\s*(.*)\)\s*$')
ARGNAME = re.compile(r'UI_ARG_\w+\(\s*"([^"]+)"')
INTERACT = re.compile(r"^/[\w/]+?/(?:proc/)?tgui_interact\s*\(")
HAND_OPEN = re.compile(r"\bSStgui\.try_update_ui\s*\(|\bnew\s*/datum/tgui\s*\(|\bui\s*=\s*new\s*\(|var/datum/tgui/\w+\s*=\s*new\s*\(")
RAW = re.compile(
    r"\b(?:text2num|locate|text2path|json_decode|params2list)\s*\(\s*params\s*\??\["
    r"|\blocate_in_list\s*\([^;]*,\s*params\s*\??\["
    r"|\blocate_within\s*\([^;]*,\s*params\s*\??\["
)
READ = re.compile(r"\bparams\s*\??\[")
KEYREAD = re.compile(r'\bparams\s*\??\[\s*"([^"]+)"\s*\]')
DYNAMIC = re.compile(r'\bparams\s*\??\[\s*(?!")')


def calls_of(code):
    """(callee, top-level argument text with nested calls blanked) for every call in `code`,
    nested calls included."""
    out = []
    for m in re.finditer(r"\b(\w+)\s*\(", code):
        depth = 1
        i = m.end()
        buf = []
        while i < len(code) and depth:
            c = code[i]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if not depth:
                    break
            if depth == 1 or (depth == 2 and c == "("):
                buf.append(c if depth == 1 else "")
            i += 1
        out.append((m.group(1), "".join(buf)))
    return out


def code_of(line):
    """The line without its // comment and with string literal contents blanked."""
    out = []
    quote = False
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                quote = False
                out.append(c)
        else:
            if line.startswith("//", i):
                break
            out.append(c)
            if c == '"':
                quote = True
        i += 1
    return "".join(out)


def strip_comment(line):
    """The line without its // comment (strings kept, so params["key"] stays readable)."""
    quote = False
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                quote = False
        elif c == '"':
            quote = True
        elif line.startswith("//", i):
            return line[:i]
        i += 1
    return line


def bodies(lines):
    """(kind, type, name, args, start, [(number, line)]) per top-level proc or handler."""
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        m = HANDLER.match(line)
        kind = None
        if m:
            kind, owner, name, args = "handler", m.group(1), m.group(2), ""
        else:
            m = HEADER.match(line)
            if m:
                kind, owner, name, args = "proc", m.group(1), m.group(2), m.group(3)
        if not kind:
            i += 1
            continue
        j = i + 1
        body = []
        while j < n and (not lines[j].strip() or lines[j][0] in "\t "):
            body.append((j + 1, lines[j]))
            j += 1
        yield kind, owner, name, args, i + 1, body
        i = j


def declared_keys(files):
    """(type, handler) -> set of declared arg names, from every UI_ACT row."""
    rows = {}
    for _rel, lines in files:
        for line in lines:
            m = SUBROW.match(line) or ROW.match(line)
            if m:
                rows.setdefault((m.group(1), m.group(2)), set()).update(ARGNAME.findall(m.group(3)))
            elif line.startswith("#define") and "TYPE_PROC_REF(/datum," in line:
                # Row-generating macros (DECLARE_UI_MODAL): their handlers live on /datum.
                for part in line.split("TYPE_PROC_REF(/datum,")[1:]:
                    handler = part.split(")")[0].strip()
                    rows.setdefault(("/datum", handler), set()).update(ARGNAME.findall(part))
    return rows


def keys_for(rows, owner, handler):
    out = set()
    for (row_type, row_handler), keys in rows.items():
        if row_handler != handler:
            continue
        if row_type == owner or owner.startswith(row_type + "/") or row_type.startswith(owner + "/"):
            out |= keys
    return out


def typed_param_helpers(files):
    """Procs taking `list/params` that may receive a handler's typed params: every use of params
    is a key read (params["k"]), an act_ask()/rerun_ask() re-run argument, or a hand-off to
    another such helper. Returns name -> keys it reads (itself and the helpers it calls)."""
    passthrough = ("act_ask", "om_act_ask", "rerun_ask", "list")
    cands = {}
    for _rel, lines in files:
        for kind, _owner, name, args, _start, body in bodies(lines):
            if kind != "proc" or not re.search(r"(?:^|,)\s*(?:list/)?params\s*(?:,|$)", args):
                continue
            keys = set()
            callees = set()
            ok = True
            for _n, line in body:
                text = strip_comment(line)
                if not re.search(r"\bparams\b", text):
                    continue
                if RAW.search(text) or DYNAMIC.search(text):
                    ok = False
                    break
                keys |= set(KEYREAD.findall(text))
                rest = code_of(KEYREAD.sub("", text))
                total = len(re.findall(r"\bparams\b", rest))
                covered = 0
                for callee, argtext in calls_of(rest):
                    hits = len(re.findall(r"(?:^|,)\s*params\s*(?=,|$)", argtext))
                    if not hits:
                        continue
                    covered += hits
                    if callee not in passthrough:
                        callees.add(callee)
                if covered != total:
                    ok = False
                    break
            if ok:
                cands[name] = (keys, callees)
    changed = True
    while changed:
        changed = False
        for name, (keys, callees) in list(cands.items()):
            if any(c not in cands for c in callees):
                del cands[name]
                changed = True
    out = {}
    for name in cands:
        seen = set()
        todo = [name]
        keys = set()
        while todo:
            n = todo.pop()
            if n in seen:
                continue
            seen.add(n)
            keys |= cands[n][0]
            todo.extend(cands[n][1])
        out[name] = keys
    return out


def scan(files):
    out = {rule: [] for rule in RULES}
    rows = declared_keys(files)
    helpers = typed_param_helpers(files)
    for rel, lines in files:
        if rel.startswith(NOT_TGUI):
            continue
        exempt_open = rel.startswith(OPEN_EXEMPT)
        for number, line in enumerate(lines, 1):
            code = code_of(line)
            if INTERACT.match(line) and not line.startswith("/datum/proc/tgui_interact("):
                out["tgui_interact_boilerplate"].append((rel, number))
            elif not exempt_open and HAND_OPEN.search(code):
                out["tgui_interact_boilerplate"].append((rel, number))
            if RAW.search(strip_comment(line)):
                out["text2num_params"].append((rel, number))
        for kind, owner, name, args, start, body in bodies(lines):
            if kind == "proc" and name == "tgui_act" and owner != "/datum":
                out["ui_act_dispatch"].append((rel, start))
                for number, line in body:
                    text = strip_comment(line)
                    if READ.search(text) and not RAW.search(text):
                        out["text2num_params"].append((rel, number))
                continue
            if kind != "handler":
                continue
            allowed_keys = keys_for(rows, owner, name)
            aliases = {}
            for number, line in body:
                text = strip_comment(line)
                if RAW.search(text):
                    continue  # already counted
                flagged = False
                for key in KEYREAD.findall(text):
                    if key not in allowed_keys:
                        flagged = True
                if DYNAMIC.search(text):
                    flagged = True
                m = re.search(r'var/(?:[\w/]+/)?(\w+)\s*=\s*params\s*\??\[\s*"([^"]+)"\s*\]\s*$', text.strip())
                if m:
                    aliases[m.group(1)] = number
                for alias in aliases:
                    if re.search(r"\b(?:text2num|locate|text2path|json_decode)\s*\(\s*" + alias + r"\s*\)", text):
                        flagged = True
                blank = code_of(line)
                for callee, argtext in calls_of(blank):
                    if callee in ("tgui_act", "act_ask", "om_act_ask", "rerun_ask", "list"):
                        continue
                    if callee in helpers and helpers[callee] <= allowed_keys:
                        continue
                    if re.search(r"(?:^|,)\s*params\s*(?:,|$)", argtext):
                        flagged = True
                if flagged:
                    out["text2num_params"].append((rel, number))
    return out
