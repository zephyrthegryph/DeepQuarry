"""State schema lint (roadmap L1, doc/rewrite/state.md section 2).

A latent-safe type's saved state is its saved vars: every var that is not
`tmp`, `static`, `global` or `const`, declared on the type or any ancestor. The
serializer refuses references it has no codec for, so a saved var that holds
an object would make every instance of the type fail to serialize. This lint
finds those vars statically:

    A saved var on a latent-safe type (or one of its ancestors) whose declared
    type is an object (`var/datum/...`, `var/obj/...`, `var/list/datum/...`,
    ...) must be `tmp`, or be given a codec in the type's `state_codecs()`, or
    hold a registry singleton the serializer encodes by ID, or be listed in
    tools/ci/state_ref_allowlist.txt with a reason.

A type is latent-safe when a type block sets `latent_safe = TRUE`; subtypes
inherit it by path until one sets `latent_safe = FALSE`.

Usage:
    python tools/ci/state_schema_lint.py            # the CI check
    python tools/ci/state_schema_lint.py --report   # counts per base type
    python tools/ci/state_schema_lint.py --vars /obj/item   # dump a type's vars
"""
import glob
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
ALLOWLIST = os.path.join(ROOT, "tools", "ci", "state_ref_allowlist.txt")

MODIFIERS = {"tmp", "static", "global", "const", "final"}
UNSAVED = {"tmp", "static", "global", "const"}
# Object type roots. A declared type under one of these holds a reference.
REF_ROOTS = ("/datum", "/atom", "/obj", "/mob", "/turf", "/area", "/image",
             "/icon", "/client", "/sound", "/matrix", "/mutable_appearance",
             "/savefile", "/regex", "/database", "/exception", "/callback",
             "/weakref", "/decl")
# Types the serializer encodes by registry ID (code/datums/state/codecs.dm,
# /datum/state_codec/registry). Keep in step with state_registry_id().
REGISTRY_TYPES = ("/datum/material", "/datum/decl", "/decl", "/datum/species")
# Base types whose vars are reported by --report (the tmp hygiene pass).
BASE_TYPES = ("/datum", "/atom", "/atom/movable", "/obj", "/obj/item",
              "/obj/machinery", "/mob")


def code_only(text):
    """Blanks comments and string contents, keeping newlines and string
    delimiters, so the line structure survives."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("\n" * text.count("\n", i, j))
            i = j
            continue
        if text.startswith('{"', i):
            j = text.find('"}', i + 2)
            j = n if j < 0 else j + 2
            out.append('""' + "\n" * text.count("\n", i, j))
            i = j
            continue
        if c == '"':
            j, depth = i + 1, 0
            while j < n:
                if text[j] == "\\":
                    if j + 1 < n and text[j + 1] == "\n":
                        out.append("\n")
                    j += 2
                    continue
                if text[j] == "[":
                    depth += 1
                elif text[j] == "]" and depth:
                    depth -= 1
                elif text[j] == '"' and not depth:
                    break
                elif text[j] == "\n":
                    break
                j += 1
            out.append('""')
            # A string cut off by the end of the line keeps its newline.
            i = j if j < n and text[j] == "\n" else j + 1
            continue
        if c == "'":
            j = text.find("'", i + 1)
            i = n if j < 0 else j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


class Var:
    __slots__ = ("owner", "name", "mods", "vtype", "is_list", "path", "line")

    def __init__(self, owner, name, mods, vtype, is_list, path, line):
        self.owner, self.name, self.mods = owner, name, mods
        self.vtype, self.is_list = vtype, is_list
        self.path, self.line = path, line

    @property
    def saved(self):
        return not (self.mods & UNSAVED)

    @property
    def holds_ref(self):
        return under(self.vtype, REF_ROOTS)

    @property
    def registry(self):
        return under(self.vtype, REGISTRY_TYPES)


def under(path, roots):
    """True if `path` is one of `roots` or a subtype of one (whole path segments)."""
    return bool(path) and any(path == r or path.startswith(r + "/") for r in roots)


VAR_DECL = re.compile(r"^var((?:/[A-Za-z_]\w*)+)\s*(?:\[[^\]]*\])?\s*(?:=|$|as\b)")
HEADER = re.compile(r"^(/?[A-Za-z_][\w/]*)\s*(?:$|=|\()")


def split_decl(segs, block_mods=()):
    mods = set(block_mods)
    while segs and segs[0] in MODIFIERS:
        mods.add(segs.pop(0))
    if not segs:
        return None
    name = segs[-1]
    tsegs = segs[:-1]
    is_list = False
    if tsegs and tsegs[0] == "list":
        is_list = True
        tsegs = tsegs[1:]
    vtype = "/" + "/".join(tsegs) if tsegs else ""
    return name, mods, vtype, is_list


def parse(paths):
    """Returns ({type: [Var]}, {type: {codec var names}}, {type: bool latent_safe})."""
    decls, codecs, latent = {}, {}, {}
    for path in paths:
        with open(path, encoding="utf-8", errors="ignore") as f:
            lines = code_only(f.read()).split("\n")
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        cur = None          # current type block
        in_proc = None      # (type, proc name) whose body we are in
        block_mods = None   # modifiers of an open `var` / `var/tmp` block
        block_indent = 0
        for no, raw in enumerate(lines, 1):
            if not raw.strip():
                continue
            stripped = raw.lstrip("\t ")
            indent = len(raw) - len(stripped)
            text = stripped.rstrip()
            if text.startswith("#"):
                continue
            if indent == 0:
                block_mods = None
                in_proc = None
                cur = None
                m = HEADER.match(text)
                if not m:
                    continue
                full = m.group(1)
                if not full.startswith("/"):
                    full = "/" + full
                segs = full.strip("/").split("/")
                if "proc" in segs or "verb" in segs or text[len(m.group(1)):].lstrip().startswith("("):
                    k = segs.index("proc") if "proc" in segs else (segs.index("verb") if "verb" in segs else len(segs) - 1)
                    owner = "/" + "/".join(segs[:k])
                    in_proc = (owner, segs[-1])
                    continue
                if "var" in segs:
                    k = segs.index("var")
                    owner = "/" + "/".join(segs[:k])
                    d = split_decl(segs[k + 1:])
                    if d:
                        decls.setdefault(owner, []).append(Var(owner, *d, rel, no))
                    continue
                cur = full.rstrip("/")
                continue
            if in_proc:
                continue
            if cur is None:
                continue
            if block_mods is not None and indent > block_indent:
                m = re.match(r"^((?:[A-Za-z_]\w*/)*[A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:=|$)", text)
                if m:
                    d = split_decl(m.group(1).split("/"), block_mods)
                    if d:
                        decls.setdefault(cur, []).append(Var(cur, *d, rel, no))
                continue
            block_mods = None
            if indent != 1 and not raw.startswith("    "):
                continue
            if re.match(r"^var(/(tmp|static|global|const))*\s*$", text):
                block_mods = set(text.split("/")[1:])
                block_indent = indent
                continue
            m = VAR_DECL.match(text)
            if m:
                d = split_decl(m.group(1).strip("/").split("/"))
                if d:
                    decls.setdefault(cur, []).append(Var(cur, *d, rel, no))
                continue
            m = re.match(r"^latent_safe\s*=\s*(TRUE|FALSE|1|0)\b", text)
            if m:
                latent[cur] = m.group(1) in ("TRUE", "1")
    # Codec names appear as string keys: `list("forensic_data" = /datum/state_codec/owned)`.
    return decls, codecs, latent


def parse_codec_keys(paths):
    """state_codecs() keys are string literals, which code_only() blanks, so
    they are read from the raw text of each state_codecs() proc."""
    codecs = {}
    head = re.compile(r"^(/[\w/]+)/state_codecs\(\)", re.M)
    for path in paths:
        with open(path, encoding="utf-8", errors="ignore") as f:
            text = f.read()
        for m in head.finditer(text):
            owner = m.group(1).replace("/proc", "")
            end = re.search(r"^\S", text[m.end():], re.M)
            body = text[m.end(): m.end() + (end.start() if end else len(text))]
            for key in re.findall(r'"(\w+)"\s*=\s*/datum/state_codec', body):
                codecs.setdefault(owner, set()).add(key)
    return codecs


def ancestors(path):
    segs = path.strip("/").split("/")
    return ["/" + "/".join(segs[:i]) for i in range(1, len(segs) + 1)]


def chain(path):
    """The type and its ancestors, root first. Everything inherits /datum,
    except the built-in roots that do not (none of ours)."""
    out = ancestors(path)
    if out[0] != "/datum":
        if out[0] in ("/obj", "/mob", "/turf", "/area"):
            out = ["/datum", "/atom", "/atom/movable"][: 3 if out[0] in ("/obj", "/mob") else 2] + out
        elif out[0] == "/atom":
            out = ["/datum"] + out
    return out


def load_allowlist():
    allowed = {}
    if not os.path.exists(ALLOWLIST):
        return allowed
    with open(ALLOWLIST, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)
            entry, reason = line[0].strip(), (line[1].strip() if len(line) > 1 else "")
            if entry:
                allowed[entry] = reason
    return allowed


def dm_files():
    return [p for p in glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True)]


def effective_latent(path, latent):
    val = False
    for a in chain(path):
        if a in latent:
            val = latent[a]
    return val


def main(argv):
    paths = dm_files()
    decls, _, latent = parse(paths)
    codecs = parse_codec_keys(paths)
    allowed = load_allowlist()

    def has_codec(owner, name, subject):
        for a in chain(subject):
            if name in codecs.get(a, ()):
                return True
        return False

    if len(argv) > 1 and argv[1] == "--vars":
        for a in chain(argv[2]):
            for v in decls.get(a, []):
                print(f"{a}\t{v.name}\t{'/'.join(sorted(v.mods))}\t{'list' if v.is_list else ''}{v.vtype}\t{v.path}:{v.line}")
        return 0

    if len(argv) > 1 and argv[1] == "--report":
        total_tmp = total_saved_ref = 0
        for base in BASE_TYPES:
            vs = decls.get(base, [])
            tmp = [v for v in vs if "tmp" in v.mods]
            refs = [v for v in vs if v.saved and v.holds_ref and not v.registry]
            total_tmp += len(tmp)
            total_saved_ref += len(refs)
            print(f"{base}: {len(vs)} vars, {len(tmp)} tmp, {len(refs)} saved reference vars")
            for v in refs:
                tag = "allowlisted" if f"{v.owner}/{v.name}" in allowed else "codec" if has_codec(v.owner, v.name, v.owner) else "OPEN"
                print(f"    {v.name} ({'list of ' if v.is_list else ''}{v.vtype}) {v.path}:{v.line} [{tag}]")
        print(f"total: {total_tmp} tmp, {total_saved_ref} saved reference vars on base types")
        return 0

    safe_types = sorted(t for t in set(decls) | set(latent) if effective_latent(t, latent))
    failures, used, checked = [], set(), set()
    for t in safe_types:
        for a in chain(t):
            for v in decls.get(a, []):
                key = (t if a == t else a, v.name)
                if not v.saved or not v.holds_ref or v.registry:
                    continue
                if has_codec(a, v.name, t):
                    continue
                entry = f"{a}/{v.name}"
                if entry in allowed:
                    used.add(entry)
                    continue
                if (a, v.name) in checked:
                    continue
                checked.add((a, v.name))
                failures.append(f"{v.path}:{v.line}: {entry} holds a reference "
                                f"({'list of ' if v.is_list else ''}{v.vtype}) and is saved on latent-safe {t}; "
                                "make it tmp, give it a codec in state_codecs(), or allowlist it")
    stale = sorted(set(allowed) - used)
    for entry in stale:
        failures.append(f"{ALLOWLIST}: {entry} is allowlisted but no latent-safe type saves it; remove the entry")
    print(f"state schema lint: {len(safe_types)} latent-safe types, {len(used)} allowlisted vars, {len(failures)} problems")
    for f in failures:
        print(f)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
