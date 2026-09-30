#!/usr/bin/env python3
"""Declared-dependencies lint (doc/rewrite/dx_conventions.md, "Declared dependencies").

A type lists what its derived procs read in `derived()` (code/datums/capabilities/derived.dm):

    /obj/item/laser_pointer/derived()
        . = ..()
        . += runs_while(nameof(energy))         // should_run()
        . += drawn_from(nameof(pointing))       // draw() and hidden_verbs()
        . += ui_from(nameof(energy))            // tgui_data()
        . += derive(nameof(power_state), nameof(stat), rel(nameof(power_area), nameof(/area::equip_on)))
        . += rust_push(nameof(target_pressure)) // push_to_rust()

Rules (a site is a file + line, baselined shrink-only in tools/ci/derived_reads_baseline.txt):

  undeclared_read      the body of should_run / draw / hidden_verbs / tgui_data / push_to_rust (or of
                       derive_<var>) reads a var of the type (`src.x`, or a bare `x` that is a var the
                       type or an ancestor declares) that the matching declaration doesn't list.
                       One site per (proc, var), at the first read. Declarations are inherited by
                       path, and a hop's link var counts as read by what hops through it.
  declared_untracked   a var named in derived() has no way to notify: it isn't TRACKED / SETTER, a
                       derive() value or a declared relation (OWN / REL) on the type or an ancestor.
                       (cap_state is exempt: cap_set() marks the holder.) A remote var of rel() /
                       rel_each() is checked against the type named in nameof(/type::var).
  hop_not_relation     rel() / rel_each() names a link var that isn't a declared relation (REL, REL_LIST,
                       REL_PAIR..., OWN...): a plain var can't tell the framework who to notify.
  exact_on_state_changed
                       a type that declares its dependencies overrides on_state_changed(bits): an exact
                       type is not woken by var changes for it, use push_to_rust() + rust_push().

Not checked (the runtime REFRESH DRIFT audit covers them, and names the likely undeclared read): reads
through procs the body calls, through string interpolation, and through other objects' vars.
A justified read carries `// ALLOW(derived_reads): <reason>` on its line or the comment line above.
Capability types (/datum/capability/...) are not scanned: their own vars are shared configuration, and
what they read of the holder is contributed through derived_reads(holder). code/modules/unit_tests is not
scanned (fixtures count calls in their procs). An assignment (`x = ...`, a named argument) is not a read.

    python tools/ci/derived_reads_lint.py                 # the CI check
    python tools/ci/derived_reads_lint.py --report        # every finding
    python tools/ci/derived_reads_lint.py --fix [files]   # add the missing reads to the source derived()
                                                          # block (files: fix every finding in them;
                                                          # none: fix the findings the baseline lacks)
    python tools/ci/derived_reads_lint.py --update        # drop fixed sites from the baseline
    python tools/ci/derived_reads_lint.py --selftest      # run the built-in fixtures
    python tools/ci/derived_reads_lint.py --fix-generated # rewrite code/_generated/reads.dm (see below)

Generated reads: every derived proc body's reads (declared or not) are written to code/_generated/reads.dm as
one `/type/generated_reads()` override per type, in the same drawn_from / ui_from / runs_while / rust_push /
derive vocabulary. They are implicit reads: they feed READERS() (code/datums/reactions), so TRACKED setters
publish exactly the keys something reads, without making a type's derived() exact. The CI check fails when the
committed file is stale (run --fix-generated and commit it).
"""
import bisect
import glob
import os
import re
import sys
from collections import OrderedDict, namedtuple

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only, chain  # noqa: E402
from allow_annotations import allowed, check_sites, write_sites  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "derived_reads_baseline.txt")
LINT = "derived_reads"
SKIP_SITE_DIRS = ("code/modules/unit_tests/",)
GENERATED_SKIP_DIRS = SKIP_SITE_DIRS + ("code/modules/benchmarks/",)
GENERATED = os.path.join(ROOT, "code", "_generated", "reads.dm")
GENERATED_REL = "code/_generated/reads.dm"
GENERATED_KIND_CALL = {"runs": "runs_while", "drawn": "drawn_from", "ui": "ui_from", "push": "rust_push"}

# derived proc -> the declaration kind its reads belong to.
PROC_KIND = {"should_run": "runs", "draw": "drawn", "hidden_verbs": "drawn", "tgui_data": "ui", "push_to_rust": "push"}
ENTRY_KIND = {"runs_while": "runs", "drawn_from": "drawn", "ui_from": "ui", "rust_push": "push", "derive": "derive"}
KIND_CALL = {"runs": "runs_while", "drawn": "drawn_from", "ui": "ui_from", "push": "rust_push"}
# Reads that need no declaration: capability bits are set through cap_set(), which marks the holder.
EXEMPT_VARS = {"cap_state", "cap_data"}

HINTS = {
    "undeclared_read": "declare it in derived() (`--fix` adds it), or keep with // ALLOW(derived_reads): <reason>",
    "declared_untracked": "make it TRACKED / SETTER, a derive() value or a declared relation (OWN / REL)",
    "hop_not_relation": "declare the link var REL / REL_LIST / OWN; a hop only follows a declared relation",
    "exact_on_state_changed": "use push_to_rust() with rust_push(...): an exact type is not woken for on_state_changed",
}

Proc = namedtuple("Proc", "rel owner name args start body")
Entry = namedtuple("Entry", "rel line kind name local remote hops")
Finding = namedtuple("Finding", "rel line rule owner proc var kind message")

PROC_DEF = re.compile(r"^(/[\w/]*?)/(?:(?:proc|verb)/)?(\w+)\s*\((.*)$")
TYPE_DEF = re.compile(r"^/[\w/]+\s*$")
VAR_DECL = re.compile(r"^var((?:/[A-Za-z_]\w*)+)\s*(?:\[[^\]]*\])?\s*(?:=|$|as\b)")
HEADER = re.compile(r"^(/?[A-Za-z_][\w/]*)\s*(?:$|=|\()")
MODIFIERS = {"tmp", "static", "global", "const", "final"}
TRACKED_LINE = re.compile(r"^(?:TRACKED|SETTER)\(\s*(/[\w/]+)\s*,\s*(\w+)")
RELATION_LINE = re.compile(r"^(?:OWN|OWN_POLICY|OWN_IF|REL|REL_LIST|REL_PAIR|REL_PAIR_LIST|REL_SET|REL_KEYED|REL_KEYED_LIST)\(\s*(/[\w/]+)\s*,\s*(\w+)")
CALL = re.compile(r"(?<![\w.])(runs_while|drawn_from|ui_from|rust_push|derive)\s*\(")
NAMEOF = re.compile(r"^nameof\(\s*(?:(/[\w/]+)::)?(\w+)\s*\)$")
STRIP_CALLS = re.compile(r"\b(?:nameof|initial)\s*\([^()]*\)")
LOCAL_DECL = re.compile(r"\bvar/(?:[\w/]*/)?(\w+)")
READ = re.compile(r"(?<![\w.:/])(?:src\.)?([A-Za-z_]\w*)\b(?!\s*\()(?!\s*::)(?!\s*=(?!=))")


# ---------------------------------------------------------------- parsing

def parse_vars(lines):
    """{type: set(var names)} declared in one file's code_only() lines."""
    found = {}
    cur = None
    in_proc = False
    block_indent = None
    for raw in lines:
        if not raw.strip():
            continue
        stripped = raw.lstrip("\t ")
        indent = len(raw) - len(stripped)
        text = stripped.rstrip()
        if text.startswith("#"):
            continue
        if indent == 0:
            block_indent = None
            in_proc = False
            cur = None
            m = HEADER.match(text)
            if not m:
                continue
            full = m.group(1)
            if not full.startswith("/"):
                full = "/" + full
            segs = full.strip("/").split("/")
            if "proc" in segs or "verb" in segs or text[len(m.group(1)):].lstrip().startswith("("):
                in_proc = True
                continue
            if "var" in segs:
                k = segs.index("var")
                name = decl_name(segs[k + 1:])
                if name:
                    found.setdefault("/" + "/".join(segs[:k]), set()).add(name)
                continue
            cur = full.rstrip("/")
            continue
        if in_proc or cur is None:
            continue
        if block_indent is not None and indent > block_indent:
            m = re.match(r"^((?:[A-Za-z_]\w*/)*[A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:=|$)", text)
            if m:
                name = decl_name(m.group(1).split("/"))
                if name:
                    found.setdefault(cur, set()).add(name)
            continue
        block_indent = None
        if indent != 1 and not raw.startswith("    "):
            continue
        if re.match(r"^var(/(tmp|static|global|const))*\s*$", text):
            block_indent = indent
            continue
        m = VAR_DECL.match(text)
        if m:
            name = decl_name(m.group(1).strip("/").split("/"))
            if name:
                found.setdefault(cur, set()).add(name)
    return found


def decl_name(segs):
    segs = list(segs)
    while segs and segs[0] in MODIFIERS:
        segs.pop(0)
    return segs[-1] if segs else None


def parse_procs(rel, code):
    """Every top-level proc: Proc(rel, owner, name, args text, start line, [(line no, text)])."""
    cur = None
    for number, line in enumerate(code.split("\n"), 1):
        if line and not line[0].isspace():
            if cur:
                yield cur
                cur = None
            text = line.rstrip()
            if text.startswith("#") or TYPE_DEF.match(text):
                continue
            m = PROC_DEF.match(text)
            if m:
                cur = Proc(rel, m.group(1) or "/", m.group(2), m.group(3), number, [])
            continue
        if cur and line.strip():
            cur.body.append((number, line))
    if cur:
        yield cur


def split_args(text):
    """Top-level comma split of `text` (the inside of a call)."""
    parts, depth, cur = [], 0, ""
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    return [p.strip() for p in parts]


def call_args(text, open_idx):
    """The text between the parenthesis at `open_idx` and its match, and the index after the match."""
    depth = 0
    for i in range(open_idx, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return text[open_idx + 1:i], i + 1
    return text[open_idx + 1:], len(text)


def parse_entries(proc):
    """The Entry list of one derived() body."""
    lines = [text for _, text in proc.body]
    numbers = [no for no, _ in proc.body]
    text = "\n".join(lines)
    starts, offset = [], 0
    for line in lines:
        starts.append(offset)
        offset += len(line) + 1
    entries = []
    pos = 0
    while True:
        m = CALL.search(text, pos)
        if not m:
            break
        inner, end = call_args(text, m.end() - 1)
        pos = end
        kind = ENTRY_KIND[m.group(1)]
        args = split_args(inner)
        name = None
        if kind == "derive":
            first = NAMEOF.match(args[0]) if args else None
            name = first.group(2) if first else None
            args = args[1:]
        local, remote, hops = set(), [], []
        for arg in args:
            n = NAMEOF.match(arg)
            if n:
                local.add(n.group(2))
                continue
            h = re.match(r"^(rel|rel_each)\((.*)\)$", arg, re.S)
            if h:
                parts = split_args(h.group(2))
                link = NAMEOF.match(parts[0]) if parts else None
                far = NAMEOF.match(parts[1]) if len(parts) > 1 else None
                if link:
                    hops.append(link.group(2))
                    local.add(link.group(2))
                if far:
                    remote.append((far.group(1), far.group(2)))
        line = numbers[bisect.bisect_right(starts, m.start()) - 1] if numbers else proc.start
        entries.append(Entry(proc.rel, line, kind, name, local, remote, hops))
    return entries


def body_reads(proc, known):
    """{var: first line} for each var in `known` the proc body reads (see the module doc)."""
    locals_ = set()
    depth, cur, params = 0, "", []
    for ch in proc.args:
        if ch == "(":
            depth += 1
        elif ch == ")":
            if depth == 0:
                break
            depth -= 1
        if ch == "," and depth == 0:
            params.append(cur)
            cur = ""
        else:
            cur += ch
    params.append(cur)
    for p in params:
        p = re.split(r"\s+as\s+", p.split("=")[0].strip())[0]
        if p:
            locals_.add(p.split("/")[-1].strip())
    reads = OrderedDict()
    for number, line in proc.body:
        if line.lstrip().startswith("#"):
            continue
        prev = None
        while prev != line:
            prev = line
            line = STRIP_CALLS.sub("", line)
        for m in LOCAL_DECL.finditer(line):
            locals_.add(m.group(1))
        for m in READ.finditer(line):
            name = m.group(1)
            if name in known and name not in locals_ and name not in reads and name not in EXEMPT_VARS:
                reads[name] = number
    return reads


class Model:
    """Everything parsed from a set of files."""

    def __init__(self):
        self.raw = {}
        self.vars = {}       # type -> {var}
        self.tracked = {}    # type -> {var}
        self.relations = {}  # type -> {var}
        self.procs = []
        self.entries = {}    # type -> [Entry]
        self.derived_procs = {}  # type -> Proc

    def add(self, rel, raw):
        self.raw[rel] = raw
        code = code_only(raw)
        lines = code.split("\n")
        for owner, names in parse_vars(lines).items():
            self.vars.setdefault(owner, set()).update(names)
        for line in lines:
            if line.startswith("#"):
                continue
            m = TRACKED_LINE.match(line)
            if m:
                self.tracked.setdefault(m.group(1), set()).add(m.group(2))
            m = RELATION_LINE.match(line)
            if m:
                self.relations.setdefault(m.group(1), set()).add(m.group(2))
        for proc in parse_procs(rel, code):
            owner = proc.owner.rstrip("/") or "/"
            proc = proc._replace(owner=owner)
            self.procs.append(proc)
            if proc.name == "derived" and owner != "/":
                self.derived_procs[owner] = proc
                self.entries.setdefault(owner, []).extend(parse_entries(proc))

    def union(self, table, path):
        out = set()
        for ancestor in chain(path):
            out |= table.get(ancestor, set())
        return out

    def declared(self, path, kind):
        """The vars the type (and its ancestors) declare for `kind`; for derive: {value: its reads}."""
        if kind == "derive":
            out = {}
            for ancestor in chain(path):
                for e in self.entries.get(ancestor, ()):
                    if e.kind == "derive" and e.name:
                        out.setdefault(e.name, set()).update(e.local)
            return out
        out = set()
        for ancestor in chain(path):
            for e in self.entries.get(ancestor, ()):
                if e.kind == kind:
                    out |= e.local
        return out

    def exact(self, path):
        return any(self.entries.get(a) for a in chain(path))


# ---------------------------------------------------------------- the rules

def analyze(model):
    findings = []

    def raw_allowed(rel, line):
        return allowed(model.raw[rel].split("\n"), line, LINT)

    for proc in model.procs:
        if proc.owner == "/" or proc.rel.startswith(SKIP_SITE_DIRS) or proc.owner.startswith("/datum/capability"):
            continue  # a capability's own vars are shared configuration; its reads of the holder are derived_reads()
        kind = PROC_KIND.get(proc.name)
        value = proc.name[len("derive_"):] if proc.name.startswith("derive_") else None
        if not kind and not value:
            continue
        known = model.union(model.vars, proc.owner)
        if value:
            reads_of = model.declared(proc.owner, "derive").get(value)
            if reads_of is None:
                continue  # a derive_<x> proc with no derive(nameof(x)) is not a derived value
            allowed_reads, label = reads_of, "derive_%s" % value
            wanted_kind = "derive"
        else:
            allowed_reads, label = model.declared(proc.owner, kind), proc.name
            wanted_kind = kind
        for name, line in body_reads(proc, known).items():
            if name in allowed_reads or raw_allowed(proc.rel, line):
                continue
            findings.append(Finding(proc.rel, line, "undeclared_read", proc.owner, label, name, wanted_kind,
                                    "%s.%s reads %s, which derived() doesn't declare for it" % (proc.owner, label, name)))
    for proc in model.procs:
        if proc.name == "on_state_changed" and proc.owner != "/" and not proc.rel.startswith(SKIP_SITE_DIRS)                 and model.exact(proc.owner) and not raw_allowed(proc.rel, proc.start):
            findings.append(Finding(proc.rel, proc.start, "exact_on_state_changed", proc.owner, proc.name, None, None,
                                    "%s declares its dependencies but overrides on_state_changed()" % proc.owner))
    for owner, entries in model.entries.items():
        for e in entries:
            if e.rel.startswith(SKIP_SITE_DIRS) or raw_allowed(e.rel, e.line):
                continue
            derive_names = set(model.declared(owner, "derive"))
            relations = model.union(model.relations, owner)
            tracked = model.union(model.tracked, owner)
            for link in e.hops:
                if link not in relations:
                    findings.append(Finding(e.rel, e.line, "hop_not_relation", owner, None, link, e.kind,
                                            "%s hops through %s, which is not a declared relation" % (owner, link)))
            for name in sorted(e.local):
                if name in EXEMPT_VARS or name in tracked or name in derive_names or name in relations:
                    continue
                findings.append(Finding(e.rel, e.line, "declared_untracked", owner, None, name, e.kind,
                                        "%s declares %s, which is not TRACKED, derived or a relation" % (owner, name)))
            for far_type, name in e.remote:
                if not far_type or name in EXEMPT_VARS:
                    continue
                far_ok = name in model.union(model.tracked, far_type) or name in set(model.declared(far_type, "derive")) \
                    or name in model.union(model.relations, far_type)
                if not far_ok:
                    findings.append(Finding(e.rel, e.line, "declared_untracked", owner, None, "%s::%s" % (far_type, name), e.kind,
                                            "%s reads %s::%s through a hop, which is not TRACKED, derived or a relation" % (owner, far_type, name)))
    findings.sort(key=lambda f: (f.rel, f.line, f.rule, f.var or ""))
    return findings


# ---------------------------------------------------------------- --fix

def fix_texts(model, findings):
    """{rel: new raw text} adding each undeclared read to its type's source derived() block."""
    wanted = OrderedDict()  # (owner, kind, derive name or None) -> [vars]
    for f in findings:
        if f.rule != "undeclared_read":
            continue
        derive_name = f.proc[len("derive_"):] if f.kind == "derive" else None
        wanted.setdefault((f.owner, f.kind, derive_name), [])
        if f.var not in wanted[(f.owner, f.kind, derive_name)]:
            wanted[(f.owner, f.kind, derive_name)].append(f.var)
    by_owner = OrderedDict()
    for (owner, kind, derive_name), names in wanted.items():
        by_owner.setdefault(owner, []).append((kind, derive_name, names))
    edits = {}  # rel -> [(after line (0 = none), insert before line, [new lines], merge)]
    for owner, wants in by_owner.items():
        block = model.derived_procs.get(owner)
        if block:
            rel, raw_lines = block.rel, model.raw[block.rel].split("\n")
            for kind, derive_name, names in wants:
                target = None
                for number, _ in block.body:
                    text = raw_lines[number - 1]
                    m = re.match(r"^(\s*\. \+= (%s)\()(.*)\)\s*$" % ("derive" if kind == "derive" else KIND_CALL[kind]), text)
                    if m and (kind != "derive" or re.match(r"^nameof\(\s*(?:/[\w/]+::)?%s\s*\)" % re.escape(derive_name), m.group(3))):
                        target = (number, m)
                        break
                extra = ", ".join("nameof(%s)" % n for n in names)
                if target:
                    number, m = target
                    edits.setdefault(rel, []).append(("merge", number, m.group(1) + m.group(3) + ", " + extra + ")"))
                else:
                    call = KIND_CALL.get(kind)
                    line = "\t. += %s(%s)" % (call, extra) if call else "\t. += derive(nameof(%s), %s)" % (derive_name, extra)
                    edits.setdefault(rel, []).append(("after", block.body[-1][0], line))
        else:
            first = min((p for p in model.procs if p.owner == owner and (p.name in PROC_KIND or p.name.startswith("derive_"))),
                        key=lambda p: (p.rel, p.start), default=None)
            if not first:
                continue
            lines = ["%s/derived()" % owner, "\t. = ..()"]
            for kind, derive_name, names in wants:
                extra = ", ".join("nameof(%s)" % n for n in names)
                if kind == "derive":
                    lines.append("\t. += derive(nameof(%s), %s)" % (derive_name, extra))
                else:
                    lines.append("\t. += %s(%s)" % (KIND_CALL[kind], extra))
            lines.append("")
            edits.setdefault(first.rel, []).append(("before", first.start, lines))
    out = {}
    for rel, todo in edits.items():
        raw_lines = model.raw[rel].split("\n")
        # Bottom-up, so earlier line numbers stay valid.
        for op, number, payload in sorted(todo, key=lambda t: -t[1]):
            if op == "merge":
                raw_lines[number - 1] = payload
            elif op == "after":
                raw_lines.insert(number, payload)
            else:
                raw_lines[number - 1:number - 1] = payload
        out[rel] = "\n".join(raw_lines)
    return out


# ---------------------------------------------------------------- generated reads

def generated_text(model):
    """The text of code/_generated/reads.dm: each non-test, non-capability type's derived-proc reads."""
    per_owner = OrderedDict()  # owner -> OrderedDict((kind, derive name) -> [vars])
    for proc in sorted(model.procs, key=lambda p: (p.owner, p.rel, p.start)):
        if proc.owner == "/" or proc.rel.startswith(GENERATED_SKIP_DIRS) or proc.rel == GENERATED_REL or proc.owner.startswith("/datum/capability"):
            continue
        kind = PROC_KIND.get(proc.name)
        value = proc.name[len("derive_"):] if proc.name.startswith("derive_") else None
        if not kind and not value:
            continue
        known = model.union(model.vars, proc.owner)
        if value:
            if value not in known:
                continue
            kind = "derive"
        slot = per_owner.setdefault(proc.owner, OrderedDict()).setdefault((kind, value), [])
        for name in body_reads(proc, known):
            if name not in slot:
                slot.append(name)
    out = [
        "// GENERATED by tools/ci/derived_reads_lint.py --fix-generated. Do not edit by hand.",
        "// What each type's should_run / draw / hidden_verbs / tgui_data / push_to_rust / derive_<x> read, as implicit",
        "// reads for READERS() (code/datums/reactions). CI fails when this file is stale.",
        "",
    ]
    for owner in sorted(per_owner):
        lines = []
        for (kind, value), names in sorted(per_owner[owner].items(), key=lambda kv: (kv[0][0], kv[0][1] or "")):
            if not names:
                continue
            args = ", ".join("nameof(%s)" % n for n in sorted(names))
            if kind == "derive":
                lines.append("\t. += derive(nameof(%s), %s)" % (value, args))
            else:
                lines.append("\t. += %s(%s)" % (GENERATED_KIND_CALL[kind], args))
        if lines:
            out.append("%s/generated_reads()" % owner)
            out.append("\t. = ..()")
            out.extend(lines)
            out.append("")
    return "\n".join(out)


def generated_stale(model):
    """True when the committed generated file differs from what the sources say."""
    try:
        with open(GENERATED, encoding="utf-8", newline="") as handle:
            current = handle.read().replace("\r\n", "\n")
    except OSError:
        return True
    return current != generated_text(model)


# ---------------------------------------------------------------- driver

def load(paths=None):
    model = Model()
    for path in sorted(paths or glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True)):
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        if rel == GENERATED_REL:
            continue
        with open(path, encoding="utf-8", errors="replace", newline="") as handle:
            model.add(rel, handle.read().replace("\r\n", "\n"))
    return model


def sites_of(findings):
    sites = {}
    for f in findings:
        sites.setdefault(f.rule, []).append((f.rel, f.line))
    for rule in HINTS:
        sites.setdefault(rule, [])
    return sites


def main(argv):
    if "--selftest" in argv:
        return selftest()
    model = load()
    if "--fix-generated" in argv:
        os.makedirs(os.path.dirname(GENERATED), exist_ok=True)
        text = generated_text(model)
        with open(GENERATED, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        print("derived_reads --fix-generated: wrote %s (%d lines)" % (GENERATED_REL, text.count("\n")))
        return 0
    findings = analyze(model)
    if "--report" in argv:
        for f in findings:
            print("%s:%d: [%s] %s" % (f.rel, f.line, f.rule, f.message))
    if "--fix" in argv:
        files = [a for a in argv if not a.startswith("--")]
        if files:
            chosen = [f for f in findings if f.rel in {os.path.relpath(os.path.abspath(p), ROOT).replace("\\", "/") for p in files}]
        else:
            import allow_annotations
            base = allow_annotations.read_sites(BASELINE)
            chosen = []
            for f in findings:
                key = (f.rel, allow_annotations.site_text(f.rel, f.line))
                if base.get(f.rule, {}).get(key, 0) <= 0:
                    chosen.append(f)
        new_texts = fix_texts(model, chosen)
        for rel, text in new_texts.items():
            with open(os.path.join(ROOT, rel), "w", encoding="utf-8", newline="\n") as handle:
                handle.write(text)
            print("fixed %s" % rel)
        print("derived_reads --fix: %d file(s) edited; vars it declared still need TRACKED / a relation "
              "(rerun the lint: declared_untracked lists them)" % len(new_texts))
        return 0
    sites = sites_of(findings)
    if "--update" in argv or "--seed" in argv:
        rows = write_sites(BASELINE, [
            "Legacy derived-proc reads a type's derived() doesn't declare (tools/ci/derived_reads_lint.py).",
            "rule<TAB>file<TAB>normalized line. Shrink-only: after a sweep, `python tools/ci/derived_reads_lint.py --update`.",
        ], sites, rules=list(HINTS), shrink_only="--seed" not in argv)
        print("derived_reads lint baseline: %d sites" % rows)
        return 0
    failed = check_sites("derived_reads", sites, BASELINE, HINTS)
    if generated_stale(model):
        print("derived_reads: %s is stale; run `python tools/ci/derived_reads_lint.py --fix-generated` and commit it" % GENERATED_REL)
        failed = True
    return 1 if failed else 0


# ---------------------------------------------------------------- self-test

FIXTURE_BASE = """
/obj/pointer
	var/energy = 8
	var/max_energy = 8
	var/pointing = FALSE
	var/spare = 0

TRACKED(/obj/pointer, energy, CHANGE_EFFECTS)
TRACKED(/obj/pointer, pointing, CHANGE_EFFECTS)

/obj/pointer/should_run()
	return energy < max_energy

/obj/pointer/draw(datum/look/look)
	..()
	if(pointing)
		look.state("on")
"""

FIXTURE_DECLARED = FIXTURE_BASE + """
/obj/pointer/derived()
	. = ..()
	. += runs_while(nameof(energy), nameof(max_energy))
	. += drawn_from(nameof(pointing))
"""

FIXTURE_SUBTYPE = FIXTURE_DECLARED + """
/obj/pointer/big
	var/glow = FALSE

/obj/pointer/big/draw(datum/look/look)
	..()
	if(pointing && glow)
		look.state("big")

/obj/pointer/big/derived()
	. = ..()
	. += drawn_from(nameof(glow))
"""

FIXTURE_MISC = """
/obj/thing
	var/level = 0
	var/extra = 0
	var/total = 0
	var/spare = 0
	var/obj/thing/parent
	var/list/kids

TRACKED(/obj/thing, level, CHANGE_EFFECTS)
REL(/obj/thing, parent)

/obj/thing/derived()
	. = ..()
	. += derive(nameof(total), nameof(level))
	. += drawn_from(nameof(total), nameof(spare), rel(nameof(parent), nameof(/obj/thing::level)), rel(nameof(kids), nameof(/obj/thing::mystery)))
	. += ui_from(nameof(cap_state))

/obj/thing/derive_total()
	return level + extra

/obj/thing/on_state_changed(bits)
	return

/obj/thing/tgui_data(mob/user)
	var/level = 5
	// ALLOW(derived_reads): fixture keep
	. = list("level" = level, "n" = total)
	. += total
"""


def check(name, condition, detail=""):
    if not condition:
        print("derived_reads_lint selftest FAILED: %s %s" % (name, detail))
        return False
    return True


def model_of(texts):
    model = Model()
    for rel, text in texts.items():
        model.add(rel, text)
    return model


def selftest():
    ok = True
    # 1. A read the declaration lacks is caught, with its rule, var and proc.
    model = model_of({"code/a.dm": FIXTURE_BASE})
    found = [(f.rule, f.var, f.proc) for f in analyze(model)]
    ok &= check("missing declaration", ("undeclared_read", "energy", "should_run") in found and
                ("undeclared_read", "pointing", "draw") in found, found)
    ok &= check("only the read vars", all(v in ("energy", "pointing", "max_energy") for _, v, _ in found), found)
    # 2. Declared, the same code is clean; an inherited declaration covers a subtype.
    model = model_of({"code/a.dm": FIXTURE_DECLARED})
    ok &= check("declared is clean", not [f for f in analyze(model) if f.rule == "undeclared_read"], analyze(model))
    model = model_of({"code/a.dm": FIXTURE_SUBTYPE})
    found = [f for f in analyze(model) if f.rule == "undeclared_read"]
    ok &= check("inherited declarations", not found, found)
    # 3. A read the subtype's own declaration lacks.
    text = FIXTURE_SUBTYPE.replace("	. += drawn_from(nameof(glow))\n", "")
    found = [(f.rule, f.var) for f in analyze(model_of({"code/a.dm": text}))]
    ok &= check("subtype missing", ("undeclared_read", "glow") in found, found)
    # 4. --fix adds it to the block, and the result is clean and stable.
    model = model_of({"code/a.dm": text})
    fixed = fix_texts(model, analyze(model))
    ok &= check("fix edits the derived block", "drawn_from(nameof(glow))" in fixed.get("code/a.dm", ""), fixed)
    again = analyze(model_of(fixed)) if fixed else None
    ok &= check("fixed text is clean", again is not None and not [f for f in again if f.rule == "undeclared_read"], again)
    ok &= check("fix is stable", fix_texts(model_of(fixed), analyze(model_of(fixed))) == {}, "")
    # 5. --fix on a type with no derived() block writes one, merging each kind.
    model = model_of({"code/a.dm": FIXTURE_BASE})
    fixed = fix_texts(model, analyze(model))
    ok &= check("fix creates the block", "/obj/pointer/derived()" in fixed.get("code/a.dm", ""), fixed)
    again = analyze(model_of(fixed))
    ok &= check("created block is clean", not [f for f in again if f.rule == "undeclared_read"], again)
    # 6. The other rules: a hop through a plain var, an untracked declared var, an untracked remote var,
    #    an exact type overriding on_state_changed, a derive_<x> body reading past its reads.
    found = analyze(model_of({"code/b.dm": FIXTURE_MISC}))
    rules = {(f.rule, f.var) for f in found}
    ok &= check("hop through a plain var", ("hop_not_relation", "kids") in rules, rules)
    ok &= check("relation hop is fine", ("hop_not_relation", "parent") not in rules, rules)
    ok &= check("untracked declared var", ("declared_untracked", "spare") in rules, rules)
    ok &= check("untracked remote var", ("declared_untracked", "/obj/thing::mystery") in rules, rules)
    ok &= check("tracked, derived and exempt reads are fine", ("declared_untracked", "total") not in rules and
                ("declared_untracked", "cap_state") not in rules and ("declared_untracked", "level") not in rules, rules)
    ok &= check("exact type overriding on_state_changed", ("exact_on_state_changed", None) in rules, rules)
    ok &= check("derive body read past its reads", ("undeclared_read", "extra") in rules and
                any(f.rule == "undeclared_read" and f.proc == "derive_total" for f in found), rules)
    # 7. A local that shadows a var is not a read; an ALLOW keeps a read.
    ok &= check("locals and ALLOW", not any(f.rule == "undeclared_read" and f.proc == "tgui_data" for f in found), found)
    # 8. A type with no derived() at all reports its reads (the legacy baseline holds them).
    ok &= check("legacy type reports", any(f.rule == "undeclared_read" for f in analyze(model_of({"code/a.dm": FIXTURE_BASE}))), "")
    # 9. Generated reads list every read of a derived proc, declared or not, one override per type.
    text = generated_text(model_of({"code/a.dm": FIXTURE_DECLARED}))
    ok &= check("generated reads", "/obj/pointer/generated_reads()" in text and "runs_while(nameof(energy), nameof(max_energy))" in text
                and "drawn_from(nameof(pointing))" in text, text)
    ok &= check("generated is stable", generated_text(model_of({"code/a.dm": FIXTURE_DECLARED})) == text, "")
    if ok:
        print("derived_reads_lint selftest passed")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
