"""Appearance keyed on declared state (doc/rewrite/systems.md section 1).

A declared field's setter refreshes the appearance by itself (code/datums/sys/appearance.dm): every
field a declaration reads, and every field an APPEARANCE_WATCH names, is in the type's watch mask,
and the presentation lane runs update_icon() once per frame for an atom whose watched channel was
raised. So a manual update_icon() next to a field write is the old pattern.

Rules (both must be 0, with an empty baseline):

  update_icon_call      A manual icon refresh where a declared field changed:
                          - in a proc that also writes a declared field (set_F(), F_add(),
                            F_remove(), om_set(E, "F", v)) on the same receiver, whose field raises
                            a channel on that receiver's type (anchored and density raise none on
                            non-machines, so they don't count there);
                          - anywhere in a setter-owning proc: a field's own setter, or a proc that
                            calls ..() into an ancestor's proc of the same name that writes a field
                            (power_change(), atom_break(), atom_fix() and friends).
                        Every shape counts: update_icon(), src.update_icon(), X.update_icon(),
                        X?.update_icon(), update_icon(args), queue_icon_update(), and a
                        PROC_REF(update_icon) handed to CALLBACK/INVOKE_ASYNC/om_after/addtimer.
                        Fix: delete the call; make sure the type's declarations (or an
                        APPEARANCE_WATCH for a procedural update_icon()) read the field.
  update_icon_override  An update_icon() override. Declare the appearance instead
                        (APPEARANCE_TEMPLATE / APPEARANCE_LEVEL / APPEARANCE_EMISSIVE /
                        APPEARANCE_SLOT / DECLARE_APPEARANCE / APPEARANCE_NONE); an override stays
                        only where drawing is genuinely procedural (contents compositing,
                        generated or blended sprites, per-instance colours and images), with
                        `// ALLOW(sys_update_icon): <reason>` on or above its definition line.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import field_write_lint as fwl  # noqa: E402

RULES = {
    "update_icon_call": "delete it: a declared field's setter refreshes the appearance "
                        "(APPEARANCE_WATCH the field for a procedural update_icon(); systems.md section 1)",
    "appearance_proc_overlays": "return the overlays from appearance_overlays(); the runtime owns cut/add (systems.md section 1)",
    "appearance_proc_state": "a provider draws, it changes no state: move the setter to where the state changes (systems.md section 1)",
    "update_icon_override": "declare the appearance (APPEARANCE_TEMPLATE/LEVEL/EMISSIVE/SLOT, DECLARE_APPEARANCE); "
                            "genuinely procedural drawing keeps `// ALLOW(sys_update_icon): <reason>` (systems.md section 1)",
}
# The one ALLOW name for a kept override (the spec's `ALLOW(sys_update_icon)`).
ALLOW_NAMES = {"update_icon": "a genuinely procedural update_icon() override"}

PROVIDER_OVERLAY = re.compile(r"(?<![\w.])(?:src\.)?(?:add_overlay|cut_overlays?|copy_overlays)\s*\(|(?<![\w.])(?:src\.)?overlays\s*(?:[-+]?=(?!=)|\.Cut\()")
RUNTIME = ("code/datums/sys/appearance.dm", "code/__defines/sys_appearance.dm")

REG = re.compile(r"^\s*(OM_FIELD|OM_FIELD_TYPED|OM_FLAG_FIELD|OM_FLAG_FIELD_BITS|OM_FIELD_SETTER|OM_DERIVE_FIELD)\((.*)$")
# macro -> (field arg index, channel arg index, has setters, flag setters)
SHAPE = {
    "OM_FIELD": (1, 3, True, False),
    "OM_FIELD_TYPED": (2, 4, True, False),
    "OM_FLAG_FIELD": (1, 3, True, True),
    "OM_FLAG_FIELD_BITS": (1, 3, True, True),
    "OM_FIELD_SETTER": (1, 2, True, False),
    "OM_DERIVE_FIELD": (1, 2, False, False),
}
OVERRIDE = re.compile(r"^(/[\w/]+?)/(?:proc/)?update_icon\s*\(")
# update_icon shapes: (receiver-group regex). Receiver None = src.
CALL_DOTTED = re.compile(r"((?:\w+\??\.)*\w+)\??\.(?:update_icon|queue_icon_update)\s*\(")
CALL_BARE = re.compile(r"(?<![\w.?])(?:update_icon|queue_icon_update)\s*\(")
CALL_REF = re.compile(r"(?:CALLBACK|INVOKE_ASYNC|om_after\w*|addtimer)\s*\(\s*(?:CALLBACK\s*\(\s*)?([\w.]+)\s*,[^\n]*?PROC_REF\s*\((?:[\w/]+\s*,\s*)?(?:update_icon|queue_icon_update)\s*\)")
SUPER = re.compile(r"(?<![\w.])\.\.\(\s*")
OM_SET = re.compile(r"\bom_set\(\s*([\w.]+)\s*,\s*\"(\w+)\"")
# Init-time draws are the first draw, not a reaction to a setter (declared appearances are drawn by
# the lifecycle init; a procedural one still draws itself here).
LIFECYCLE = {"Initialize", "New", "LateInitialize", "Destroy", "on_materialize", "on_dematerialize"}
DECL = re.compile(r"^\s*(APPEARANCE_WATCH|APPEARANCE_TEMPLATE|APPEARANCE_LEVEL|APPEARANCE_EMISSIVE|DECLARE_APPEARANCE|APPEARANCE_NONE)\(\s*(/[\w/]+)\s*(?:,(.*))?$")
TOKEN = re.compile(r"\{\s*(\w+)\s*(?:\?[^}]*)?\}")


def split_args(text):
    """Top-level comma split of a macro argument list (stops at the closing paren)."""
    args, depth, cur = [], 0, ""
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                args.append(cur.strip())
                return args
            depth -= 1
        if ch == "," and depth == 0:
            args.append(cur.strip())
            cur = ""
            continue
        cur += ch
    args.append(cur.strip())
    return args


def registrations(files):
    """setter proc name -> list of (declaring type, field, raises a channel)."""
    setters = {}
    for rel, lines in files:
        if rel == "code/__defines/om.dm":
            continue
        for line in lines:
            m = REG.match(line)
            if not m:
                continue
            fi, ci, has_setter, flag = SHAPE[m.group(1)]
            args = split_args(m.group(2))
            if len(args) <= max(fi, ci) or not has_setter:
                continue
            owner, field, channel = args[0], args[fi], args[ci]
            raises = channel not in ("0", "")
            names = ["set_" + field] + ([field + "_add", field + "_remove"] if flag else [])
            for name in names:
                setters.setdefault(name, []).append((owner, field, raises))
    return setters


def watches(files):
    """type -> (clears inherited, set of names its appearance declarations read or watch)."""
    out = {}
    for rel, lines in files:
        for line in lines:
            m = DECL.match(line)
            if not m:
                continue
            kind, owner, rest = m.group(1), m.group(2), m.group(3) or ""
            entry = out.setdefault(owner, [False, set()])
            if kind == "APPEARANCE_NONE":
                entry[0] = True
                entry[1] = set()
                continue
            args = split_args(rest)
            if kind == "APPEARANCE_WATCH":
                entry[1].update(re.findall(r'"(\w+)"', args[0] if args else ""))
            elif kind == "APPEARANCE_TEMPLATE":
                entry[1].update(t for t in TOKEN.findall(args[0] if args else "") if t != "initial")
            elif args:
                name = args[0].strip().strip('"')
                if re.match(r"^\w+$", name) and name != "null":
                    entry[1].add(name)
                if kind == "APPEARANCE_LEVEL" and len(args) > 2:
                    entry[1].update(t for t in TOKEN.findall(args[2]) if t != "initial")
    return out


def watched(decls, recv_type, field):
    """TRUE when `field` is read or watched by the appearance of `recv_type` (None: any type)."""
    if recv_type is None:
        return any(field in names for _, names in decls.values())
    path = fwl.canon(recv_type)
    chain = []
    while True:
        chain.append(path)
        if path.count("/") <= 1:
            break
        path = path.rsplit("/", 1)[0]
    canon_decls = _canon_decls(decls)
    for p in chain:  # nearest first
        entry = canon_decls.get(p)
        if not entry:
            continue
        if field in entry[1]:
            return True
        if entry[0]:
            return False
    return False


_CANON = {}


def _canon_decls(decls):
    key = id(decls)
    if key not in _CANON:
        _CANON[key] = {fwl.canon(t): v for t, v in decls.items()}
    return _CANON[key]


def descends(child, parent):
    c, p = fwl.canon(child), fwl.canon(parent)
    return c == p or c.startswith(p + "/")


def capable(setters, decls, name, recv_type):
    """TRUE when setter `name` on a receiver of `recv_type` (None: unknown) raises a channel and
    the receiver's appearance reads or watches the field, so the setter refreshes it."""
    regs = setters.get(name)
    if not regs:
        return False
    if recv_type is None:
        related = regs
    else:
        related = [reg for reg in regs if descends(recv_type, reg[0])]
    return any(r and watched(decls, recv_type, field) for _, field, r in related)


def norm_recv(recv):
    if not recv or recv == "src":
        return "src"
    return recv[4:] if recv.startswith("src.") else recv


def procs(files):
    """Yields (rel, owner, proc name, header args, [(line number, code line)])."""
    for rel, lines in files:
        text = fwl.code_only("\n".join(lines))
        owner = name = args = None
        body = []
        start = 0
        for no, line in enumerate(text.split("\n"), 1):
            if line and not line[0].isspace():
                if owner:
                    yield rel, owner, name, args, start, body
                owner = None
                m = fwl.PROC_DEF_RE.match(line)
                if m and not line.startswith("#"):
                    owner, name, args, body, start = fwl.norm(m.group(1)), m.group(2), m.group(3), [], no
                    rest = args.split(")", 1)[1] if ")" in args else ""
                    if rest.strip():
                        body.append((no, rest))
                continue
            if owner:
                body.append((no, line))
        if owner:
            yield rel, owner, name, args, start, body


def receiver_type(owner, locals_, line, start, recv):
    if recv == "src":
        return owner
    head = recv.split(".")[0].rstrip("?")
    if "." in recv:
        return fwl.chain_type(owner, locals_, recv.rsplit(".", 1)[0] + ".", recv.rsplit(".", 1)[1])
    return locals_.get(head) or fwl.member_type(owner, head)


# Statements that can stand between a setter and the refresh without changing what is drawn: block
# headers, locals, the proc's return value, messages, sounds, logs and power draw.
HEADER = re.compile(r"^\s*(?:if\s*\(.*\)|else(?:\s+if\s*\(.*\))?|for\s*\(.*\)|while\s*\(.*\)|switch\s*\(.*\)|do|spawn\s*\(.*\))\s*$")
LOCAL = re.compile(r"^\s*var/")
RETVAL = re.compile(r"^\s*\.\s*=")
HARMLESS_CALLS = (
    "to_chat", "visible_message", "audible_message", "balloon_alert", "balloon_alert_to_viewers",
    "playsound", "play_sfx", "log_game", "log_admin", "log_and_message_admins", "message_admins",
    "investigate_log", "add_fingerprint", "use_power", "use_power_oneoff", "MACHINE_WAKE",
    "om_changed", "SStgui.update_uis", "update_uis", "say", "atom_say", "flick", "add_hiddenprint",
)
HARMLESS = re.compile(r"^\s*(?:(?:src|user|usr|\w+)\.)?(?:" + "|".join(re.escape(c) for c in HARMLESS_CALLS) + r")\s*\(.*\)\s*$")


def indent_of(line):
    return len(line) - len(line.lstrip("\t "))


RETURN = re.compile(r"^\s*return\b")


def after_setter(body, index, recv, setter_lines):
    """TRUE when the refresh at body[index] follows a watched-field setter on `recv` and nothing on
    the way could change what is drawn. Walking back through the refresh's block: a setter on
    `recv` in the same block is the refresh's cause (TRUE). One inside the if/else blocks just
    before it counts only when the rest of the walk, up to the block's start, is harmless too (the
    refresh follows nothing but conditional setters). A refresh inside a later conditional block
    (reached by crossing its header) is conditional on something else: FALSE."""
    scope = indent_of(body[index][1])
    seen_nested = False
    i = index - 1
    while i >= 0:
        no, line = body[i]
        i -= 1
        if not line.strip():
            continue
        depth = indent_of(line)
        if depth < scope:
            break
        receivers = setter_lines.get(no)
        if receivers is not None:
            if recv in receivers:
                if depth == scope:
                    return True
                seen_nested = True
            continue
        if CALL_BARE.search(line) or CALL_DOTTED.search(line):
            continue  # another receiver's refresh
        if HEADER.match(line) or LOCAL.match(line) or RETVAL.match(line) or HARMLESS.match(line):
            continue
        if depth > scope and RETURN.match(line):
            continue  # that branch never reaches the refresh
        return False
    return seen_nested


SUPER_LINE = re.compile(r"^\s*(?:\.\s*=\s*\.\.\(|\.\.\(|if\s*\(\s*\(?\s*(?:\.\s*=\s*)?\.\.\()")


def scan(files):
    from allow_annotations import allowed  # imported here: allow_annotations loads this module
    out = {rule: [] for rule in RULES}
    setters = registrations(files)
    decls = watches(files)
    setter_re = re.compile(r"(?:((?:\w+\??\.)*\w+)\??\.)?(?<![\w])(" + "|".join(sorted(setters, key=len, reverse=True)) + r")\s*\(")
    raw = dict(files)
    parsed = []
    # Pass 1: the watched-field writes per line, and which (type, proc) write one on src.
    owning = {}
    for rel, owner, name, args, start, body in procs(files):
        locals_ = {}
        for tm in fwl.TYPED_NAME_RE.finditer(args or ""):
            locals_[tm.group(2)] = fwl.norm(tm.group(1))
        setter_lines = {}  # line number -> set of normalized receivers written there
        for no, line in body:
            for tm in fwl.TYPED_NAME_RE.finditer(line):
                if "var/" in line[max(0, tm.start() - 4):tm.start() + 4]:
                    locals_[tm.group(2)] = fwl.norm(tm.group(1))
            for m in setter_re.finditer(line):
                if line[:m.start(2)].rstrip().endswith("proc/"):
                    continue
                recv = norm_recv(m.group(1))
                if capable(setters, decls, m.group(2), receiver_type(owner, locals_, line, m.start(), recv)):
                    setter_lines.setdefault(no, set()).add(recv)
            for m in OM_SET.finditer(line):
                recv = norm_recv(m.group(1))
                if capable(setters, decls, "set_" + m.group(2), receiver_type(owner, locals_, line, m.start(), recv)):
                    setter_lines.setdefault(no, set()).add(recv)
        is_setter = name in setters and capable(setters, decls, name, owner)
        writes_src = any("src" in r for r in setter_lines.values())
        if (writes_src or is_setter) and name not in LIFECYCLE:
            owning[(fwl.canon(owner), name)] = True
        parsed.append((rel, owner, name, start, body, setter_lines, is_setter))

    def inherits(owner, name):
        path = fwl.canon(owner)
        while path.count("/") > 1:
            path = path.rsplit("/", 1)[0]
            if owning.get((path, name)):
                return True
        return False

    for rel, owner, name, start, body, setter_lines, is_setter in parsed:
        if name == "update_icon" and rel not in RUNTIME and owner != "/atom":
            if not allowed(raw[rel], start, "sys_update_icon"):
                out["update_icon_override"].append((rel, start))
        if name == "appearance_overlays" and rel not in RUNTIME:
            for no, line in body:
                if PROVIDER_OVERLAY.search(line):
                    out["appearance_proc_overlays"].append((rel, no))
                if no in setter_lines or OM_SET.search(line):
                    out["appearance_proc_state"].append((rel, no))
        if rel in RUNTIME or name in LIFECYCLE:
            continue
        # A setter-owning proc: a watched field's own setter, or an override that calls ..() (not
        # `return ..()`) into an ancestor's proc of the same name that writes one (power_change(),
        # atom_break(), ...); the refreshes after that ..() count.
        inherited = inherits(owner, name)
        owns = is_setter
        for index, (no, line) in enumerate(body):
            if inherited and SUPER_LINE.match(line):
                owns = True
            hits = []
            for cm in CALL_REF.finditer(line):
                hits.append(norm_recv(cm.group(1)))
            if not hits:
                for cm in CALL_DOTTED.finditer(line):
                    hits.append(norm_recv(cm.group(1)))
                for cm in CALL_BARE.finditer(line):
                    if line[:cm.start()].rstrip().endswith("proc/"):
                        continue
                    hits.append("src")
            for recv in hits:
                if (recv == "src" and owns) or recv in setter_lines.get(no, ()) or after_setter(body, index, recv, setter_lines):
                    out["update_icon_call"].append((rel, no))
                    break
    return out
