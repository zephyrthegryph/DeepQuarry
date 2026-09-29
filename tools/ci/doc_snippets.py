#!/usr/bin/env python3
"""The ```dm blocks of doc/rewrite/*.md (dx_conventions.md §9, "doc_snippets"; design review H5 docs drift).

Three kinds of block, by the fence's tag:
  ```dm            a COMPLETE block: real, compilable DM. `--write` copies every complete block into
                   tools/ci/generated/doc_snippets.dm (gitignored), which deepquarry.dme includes only
                   under `#ifdef DOC_SNIPPETS`:
                       python tools/ci/doc_snippets.py --write
                       DQ_PREBUILT_VERDIGRIS=1 bash tools/build/build.sh dm -DDOC_SNIPPETS
                   Complete blocks that predate this lint (sketches that don't compile) are listed in
                   the baseline as `doc_legacy_block` and left out of the generated file; a legacy
                   block whose first line changes is new, and must compile or be tagged `fragment`.
  ```dm fragment   a sketch (part of a proc, a design not built yet): not compiled.
  ```dm before     the old way, shown for contrast: skipped entirely.
Any other tag is treated as a fragment.

Rule (a ratchet on tools/ci/doc_snippets_baseline.txt, target 0), for complete and fragment blocks:
  doc_unknown_name   a call names nothing that exists. A bare call `name(` must be a DM builtin, a
                     global proc or #define in code/, a proc or #define of the block itself, or a proc
                     on the lineage of the type whose proc the call sits in (any type's proc when the
                     block has no proc head). A member call `x.name(` must be a proc of some type in
                     code/ or the block, or a builtin member proc. This is what catches a doc teaching
                     a renamed or never-built API (`lock()` for `cap_lock()`, a preset that doesn't
                     exist). Types are not resolved: a member call on the wrong type passes.
A justified keep is `// ALLOW(doc_snippets): <reason>` on the doc line (or a comment line above it).

    python tools/ci/doc_snippets.py             # the check
    python tools/ci/doc_snippets.py --write     # generate tools/ci/generated/doc_snippets.dm
    python tools/ci/doc_snippets.py --report    # every unknown name, and the block counts
    python tools/ci/doc_snippets.py --seed      # (re)create the baseline (legacy blocks and names)
    python tools/ci/doc_snippets.py --update    # drop fixed/removed entries (never adds)
    python tools/ci/doc_snippets.py --selftest
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "sys_rules"))
import _dx_dm as dm  # noqa: E402
from allow_annotations import allowed, check_sites, read_sites, write_sites  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
DOCS = "doc/rewrite"
BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "doc_snippets_baseline.txt")
GENERATED = os.path.join(os.path.dirname(os.path.abspath(__file__)), "generated", "doc_snippets.dm")
RULES = {
    "doc_unknown_name": "the doc calls something that doesn't exist: use the real name, or build it first (docs drift, design review H5)",
}
LEGACY_RULE = "doc_legacy_block"

FENCE = re.compile(r"^(\s*)```dm(?:\s+(\w+))?\s*$")
FENCE_END = re.compile(r"^\s*```\s*$")
BARE_CALL = re.compile(r"(?<![\w./:@$#])([A-Za-z_]\w*)\s*\(")
MEMBER_CALL = re.compile(r"(?:(?:\?\.|\.)\s*|(?<=[\w\])]):)([A-Za-z_]\w*)\s*\(")
DEFINE = re.compile(r"^\s*#define\s+(\w+)")

KEYWORDS = {
    "if", "for", "while", "switch", "return", "else", "do", "in", "as", "to", "step", "throw", "try",
    "catch", "break", "continue", "goto", "set", "proc", "verb", "var", "spawn", "sleep", "new", "del",
    "list", "alist", "call", "call_ext", "nameof", "arglist", "locate", "istype", "input", "initial",
    "issaved", "typesof", "CRASH", "ASSERT", "EXCEPTION",
}
BUILTINS = set("""
abs addtext alert animate arccos arcsin arctan ascii2text astype block bounds bounds_dist browse
browse_rsc ceil ckey ckeyEx clamp cmptext cmptextEx copytext copytext_char cos fcopy fcopy_rsc fdel
fexists file file2text filter findlasttext findlasttextEx findtext findtextEx flick floor flist fract
ftime ftp generator get_dir get_dist get_step get_step_away get_step_rand get_step_to get_step_towards
get_steps_to gradient hascall hearers html_decode html_encode icon icon_states image isarea isfile
isicon isinf islist isloc ismob ismovable isnan isnull isnum isobj ispath ispointer istext isturf
jointext json_decode json_encode length length_char lentext list2params load_ext load_resource log
lowertext matrix max md5 min noise_hash nonspantext num2text obounds ohearers orange output oview
oviewers params2list pick pixloc bound_pixloc prob rand rand_seed range ref refcount regex
REGEX_QUOTE REGEX_QUOTE_REPLACEMENT replacetext replacetextEx rgb rgb2num roll round run shell
shutdown sign sin sorttext sorttextEx sound spantext spantext_char splicetext splicetext_char
splittext sqrt startup stat statpanel step_away step_rand step_to step_towards tan text text2ascii
text2file text2num text2path time2text trimtext trunc turn uppertext url_decode url_encode vector
view viewers walk walk_away walk_rand walk_to walk_towards winclone winexists winget winset winshow
values_cut_over values_cut_under values_dot values_product values_sum
""".split())
MEMBER_BUILTINS = set("""
Add Copy Cut Find Insert Join Remove RemoveAll Splice Swap Replace New Del Topic Blend Crop DrawBox
Flip GetPixel Height IconStates MapColors Scale SetIntensity Shift SwapColor Turn Width Export Import
Interpolate Invert Multiply Subtract Translate Execute NextRow GetColumn GetRowData Close Open
ErrorMsg RowsAffected Columns Read Write Stat IsBanned Reboot SetConfig GetConfig OpenPort
AddCredits ClearMedal GetMedal SetMedal GetScores SetScores Profile MeasureText Cache Rand
""".split())


class Block:
    __slots__ = ("rel", "start", "tag", "lines", "code_start")

    def __init__(self, rel, start, tag, lines, code_start):
        self.rel, self.start, self.tag, self.lines, self.code_start = rel, start, tag, lines, code_start

    @property
    def kind(self):
        if self.tag is None:
            return "complete"
        if self.tag == "before":
            return "before"
        return "fragment"

    def first_line(self):
        for line in self.lines:
            if line.strip():
                return " ".join(line.split())
        return ""


def blocks_in(rel, text):
    """Every ```dm block of one markdown file; line numbers are 1-based md lines."""
    out = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        m = FENCE.match(lines[i])
        if not m:
            i += 1
            continue
        indent = len(m.group(1))
        j = i + 1
        body = []
        while j < len(lines) and not FENCE_END.match(lines[j]):
            line = lines[j]
            body.append(line[indent:] if line[:indent].strip() == "" else line.lstrip())
            j += 1
        out.append(Block(rel, i + 1, m.group(2), body, i + 2))
        i = j + 1
    return out


def doc_blocks(root=ROOT):
    out = []
    for path in sorted(glob.glob(os.path.join(root, DOCS, "*.md"))):
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        with open(path, encoding="utf-8", errors="replace") as handle:
            out.extend(blocks_in(rel, handle.read()))
    return out


class Names:
    """What the code tree defines: global procs, type procs by name, #defines."""

    def __init__(self, tree):
        self.global_procs = set()
        self.type_procs = {}
        self.defines = set()
        for proc in tree.procs:
            if proc.is_global():
                self.global_procs.add(proc.name)
            else:
                self.type_procs.setdefault(proc.name, set()).add(proc.path)
        for rel, lines in tree.files:
            text = tree.raw_text(rel)
            if "#define" not in text:
                continue
            for line in lines:
                m = DEFINE.match(line)
                if m:
                    self.defines.add(m.group(1))


def unknown_names(block, names):
    """[(md line, name)] for each call in the block that resolves to nothing."""
    clean = dm.sanitize(block.lines)
    own_procs, own_types, own_defines = set(), {}, set()
    for line in block.lines:
        m = DEFINE.match(line)
        if m:
            own_defines.add(m.group(1))
    heads = {}
    for k, code in enumerate(clean):
        m = dm.PROC_HEAD.match(code.rstrip())
        if m and code[:1] not in " \t":
            path = m.group(1) or "/"
            path = "/" if path in ("/proc", "/verb") else path
            own_procs.add(m.group(2))
            own_types.setdefault(m.group(2), set()).add(path)
            heads[k] = path
    out = []
    current = None
    for k, code in enumerate(clean):
        if k in heads:
            current = heads[k]
            continue  # the definition itself
        if code[:1] not in " \t" and code.strip():
            current = None
        if code.lstrip().startswith("#define"):
            continue
        for m in BARE_CALL.finditer(code):
            name = m.group(1)
            if name in KEYWORDS or name in BUILTINS or name in own_procs or name in own_defines:
                continue
            if re.search(r"\bnew\s+$", code[:m.start()]):
                continue  # `new some_type_var(args)`: a type held in a var, not a call
            if name in names.global_procs or name in names.defines:
                continue
            if current and current != "/":
                chain = set(dm.lineage(current))
                if chain & (names.type_procs.get(name, set()) | own_types.get(name, set())):
                    continue
            elif name in names.type_procs:
                continue
            out.append((block.code_start + k, name))
        for m in MEMBER_CALL.finditer(code):
            name = m.group(1)
            if name in MEMBER_BUILTINS or name in names.type_procs or name in own_procs or name in names.global_procs:
                continue
            out.append((block.code_start + k, name))
    return out


def load_tree(root=ROOT):
    files = []
    for path in glob.glob(os.path.join(root, "code", "**", "*.dm"), recursive=True):
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        with open(path, encoding="utf-8", errors="replace") as handle:
            files.append((rel, handle.read().split("\n")))
    return dm.tree(files)


def doc_lines(rel, cache={}):
    if rel not in cache:
        with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as handle:
            cache[rel] = handle.read().split("\n")
    return cache[rel]


def analyse(blocks, names, raw_of=doc_lines):
    """({rule: [(rel, line)]}, [legacy candidate blocks], [complete blocks])."""
    sites = {rule: [] for rule in RULES}
    for block in blocks:
        if block.kind == "before":
            continue
        for line, _name in unknown_names(block, names):
            if not allowed(raw_of(block.rel), line, "doc_snippets"):
                sites["doc_unknown_name"].append((block.rel, line))
    complete = [b for b in blocks if b.kind == "complete"]
    return sites, complete


def legacy_keys(path=BASELINE):
    """{(rel, first line text)} of the grandfathered complete blocks (with multiplicity ignored)."""
    base = read_sites(path).get(LEGACY_RULE, {})
    return set(base)


def compiled_blocks(complete, legacy):
    return [b for b in complete if (b.rel, b.first_line()) not in legacy]


def generate(blocks, path=GENERATED):
    out = ["// GENERATED by tools/ci/doc_snippets.py --write from the complete ```dm blocks of doc/rewrite/*.md.",
           "// Do not edit; compiled only with -DDOC_SNIPPETS (see deepquarry.dme).", ""]
    for b in blocks:
        out.append("// %s:%d" % (b.rel, b.start))
        out.extend(b.lines)
        out.append("")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(out) + "\n")
    return len(blocks)


def write_baseline(sites, complete, shrink_only):
    """The name ratchet plus the legacy-block list, in one fingerprint file."""
    header = ["doc_snippets baseline (tools/ci/doc_snippets.py): doc_unknown_name is a ratchet (target 0);",
              "doc_legacy_block lists the complete blocks that predate the lint and aren't compiled (first line)."]
    legacy = legacy_keys()
    rows_sites = dict(sites)
    if shrink_only:
        keep = [b for b in complete if (b.rel, b.first_line()) in legacy]
    else:
        keep = complete
    write_sites(BASELINE, header, rows_sites, rules=list(RULES), shrink_only=shrink_only)
    with open(BASELINE, encoding="utf-8") as handle:
        text = handle.read().rstrip("\n")
    rows = sorted({"%s\t%s\t%s" % (LEGACY_RULE, b.rel, b.first_line()) for b in keep})
    with open(BASELINE, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text + ("\n" + "\n".join(rows) if rows else "") + "\n")


SELFTEST_DOC = """# Doc

```dm fragment
/obj/machinery/power/apc/capabilities()
	. = ..()
	. += cap_cover(open_tool = TOOL_CROWBAR)
	. += wall_machine(board = /obj/item/circuitboard/apc)
	. += lock(access = list(ACCESS_ENGINE))
```

  ```dm
  /obj/machinery/pump/proc/act_set_pressure(mob/user, pressure)
  	pressure = ui_number(pressure, 0, 100)
  	look.gauge("x", level = 1)
  	look.shine("y")
  	helper_of_block(pressure)
  	set_target_pressure(pressure)
  /obj/machinery/pump/proc/helper_of_block(value)
  	return round(value)
  ```

```dm before
/obj/machinery/pump/proc/ui_act(action, params)
	nonexistent_old_thing(params)
```
"""


def selftest():
    tree = dm.Tree([("code/x.dm", [
        "/proc/cap_cover(open_tool)", "\treturn",
        "/proc/ui_number(value, min_value, max_value)", "\treturn",
        "/datum/look/proc/gauge(name, level)", "\treturn",
        "/obj/machinery/proc/set_target_pressure(value)", "\treturn",
        "/obj/machinery/door/airlock/proc/lock(forced)", "\treturn",
        "#define TOOL_CROWBAR \"crowbar\"",
    ])])
    names = Names(tree)
    blocks = blocks_in("doc/rewrite/x.md", SELFTEST_DOC)
    assert [b.kind for b in blocks] == ["fragment", "complete", "before"], [b.kind for b in blocks]
    assert blocks[1].lines[0].startswith("/obj/machinery/pump/proc/act_set_pressure"), blocks[1].lines[0]
    raw = SELFTEST_DOC.split("\n")
    sites, complete = analyse(blocks, names, lambda rel: raw)
    got = sorted((line, raw[line - 1].strip().split("(")[0]) for _rel, line in sites["doc_unknown_name"])

    def at(snippet):
        return [k + 1 for k, line in enumerate(raw) if snippet in line][0]
    # wall_machine() doesn't exist; lock() exists only on airlocks, not on the APC's lineage;
    # look.shine() is no proc anywhere. cap_cover, ui_number, look.gauge, set_target_pressure
    # (on /obj/machinery), the block's own helper and round() resolve; the `before` block is skipped.
    assert [line for line, _ in got] == sorted([at("wall_machine("), at("lock(access"), at("look.shine")]), got
    assert len(complete) == 1 and complete[0].first_line().startswith("/obj/machinery/pump/proc/act_set_pressure")
    print("doc_snippets selftest ok")
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    tree = load_tree()
    names = Names(tree)
    blocks = doc_blocks()
    sites, complete = analyse(blocks, names)
    if "--seed" in argv or "--update" in argv:
        write_baseline(sites, complete, shrink_only="--update" in argv)
        return 0
    legacy = legacy_keys()
    compiled = compiled_blocks(complete, legacy)
    if "--write" in argv:
        count = generate(compiled)
        print("doc_snippets: wrote %d complete block(s) to %s" % (count, os.path.relpath(GENERATED, ROOT)))
        return 0
    if "--report" in argv:
        for rel, number in sites["doc_unknown_name"]:
            print("%s:%d: doc_unknown_name %s" % (rel, number, doc_lines(rel)[number - 1].strip()))
    kinds = {}
    for b in blocks:
        kinds[b.kind] = kinds.get(b.kind, 0) + 1
    print("doc_snippets: %d block(s): %s; %d complete block(s) compiled under -DDOC_SNIPPETS, %d legacy"
          % (len(blocks), ", ".join("%s %d" % kv for kv in sorted(kinds.items())), len(compiled),
             len(complete) - len(compiled)))
    failed = check_sites("doc_snippets", sites, BASELINE, RULES)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
