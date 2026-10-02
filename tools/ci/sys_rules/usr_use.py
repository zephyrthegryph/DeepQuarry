"""sys_lint module: `usr` outside a verb (AGENTS.md section 3a, "Avoid `usr` outside verb procs").

Rule:
  usr_outside_verb   the word `usr` in code that is not a verb's body.

`usr` is whoever started the current chain of calls, which is only meaningful at the very top of a
verb (and a couple of other BYOND entry points). Anywhere else it is a hidden argument: whoever
calls the proc later (a timer, a Topic, another verb, a test) silently changes what it means. Pass
the acting mob as a `user` parameter, or use `src`.

A verb body is any proc that carries `set name`/`set category`/`set src`/`set desc`/`set hidden`/
`set popup_menu`/`set instant`, anything under `/verb/`, and the body of an `ADMIN_VERB(...)` or
`DECLARE_VERB...` macro. Preprocessor lines and the macro library (`code/__defines/`) are skipped:
a `#define` is read in the caller's context. Text inside a string is ignored; an embedded
`[usr]` is code and counts.

Static limits: a proc that is a verb only because DECLARE_VERB grants it, and has no `set` line, is
seen as an ordinary proc; macro-generated procs other than the verb macros above are scanned as
loose code. The baseline (tools/ci/sys_baseline/usr_use.txt) holds the legacy sites; target 0.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _dx_dm as dm  # noqa: E402

RULES = {
    "usr_outside_verb": "take the acting mob as a `user` argument (or use `src`); `usr` is only meaningful at the top of a verb (AGENTS.md 3a)",
}

USR = re.compile(r"(?<![\w.])usr(?!\w)")
SET_STMT = re.compile(r"^\s*set\s+(?:name|category|src|desc|hidden|popup_menu|instant)\b")
VERB_MACRO = re.compile(r"^(?:ADMIN_VERB\w*|DECLARE_\w*VERB\w*)\(")
SKIP_PREFIXES = ("code/__defines/",)


def verb_lines(raw, clean):
    """The set of 1-based line numbers that belong to a verb's body (or a verb macro's)."""
    out = set()
    for proc in dm.procs_in("", raw, clean):
        end = proc.body_start + len(proc.body) - 1
        verb = "/verb/" in proc.head.split("(", 1)[0] or any(SET_STMT.match(line) for line in proc.body)
        if verb:
            out.update(range(proc.line, end + 1))
    # A macro-defined verb: `ADMIN_VERB(` at column 0 and the indented body under it.
    i, n = 0, len(clean)
    while i < n:
        if VERB_MACRO.match(clean[i]):
            j = i + 1
            while j < n and (not clean[j].strip() or clean[j][:1] in " \t"):
                j += 1
            out.update(range(i + 1, j + 1))
            i = j
            continue
        i += 1
    return out


def scan_lines(rel, raw, clean):
    hits = [n for n, code in enumerate(clean, 1) if USR.search(code) and not code.lstrip().startswith("#")]
    if not hits:
        return []
    verb = verb_lines(raw, clean)
    return [(rel, n) for n in hits if n not in verb]


def scan(files):
    out = {"usr_outside_verb": []}
    tree = dm.tree(files)
    for rel, raw in files:
        if rel.startswith(SKIP_PREFIXES):
            continue
        if "usr" not in tree.raw_text(rel):
            continue
        out["usr_outside_verb"].extend(scan_lines(rel, raw, tree.clean[rel]))
    return out


def selftest():
    fixture = [
        "/mob/proc/plain()",                               # 1
        "\tvar/mob/M = usr",                               # 2 bad
        "\tto_chat(usr, \"the usr word in text\")",        # 3 bad (the call), not the text
        "/mob/proc/ability()",                             # 4
        "\tset name = \"Ability\"",                        # 5
        "\tset category = \"Abilities\"",                  # 6
        "\tvar/mob/M = usr",                               # 7 ok: a verb body
        "/mob/verb/shout()",                               # 8
        "\tto_chat(usr, \"hi\")",                          # 9 ok: under /verb/
        "ADMIN_VERB(smite, R_FUN, \"Smite\", \"x\", y)",   # 10
        "\tlog_admin(\"[key_name(usr)]\")",                # 11 ok: a verb macro body
        "/proc/helper(x)",                                 # 12
        "\tvar/t = \"usr\"",                               # 13 ok: text only
        "\tlog_admin(\"[usr]\")",                          # 14 bad: an embedded expression
        "#define WHO usr",                                 # 15 ok: preprocessor
        "\t// usr is mentioned in a comment",              # 16 ok: a comment
        "\tvar/x = src.usr_count",                         # 17 ok: another identifier
    ]
    got = [n for _rel, n in scan_lines("x.dm", fixture, dm.sanitize(fixture))]
    assert got == [2, 3, 14], got
    return "usr_use"
