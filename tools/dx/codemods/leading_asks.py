#!/usr/bin/env python3
r"""The questions at the head of a handler -> asks() steps of its op (doc/rewrite/codemod_rules.md, "rerun_ask and act_ask -> asks()").

A handler written as a re-run asks its question by calling itself again with the answer kept: `rerun_ask(user, "k", PROC_REF(self), args, /datum/om/prompt/K, fields...)`
in a plain handler, `act_ask(ui.user, action, params, ui, "k", ...)` in a window button. The op form is `asks(/datum/prompt/K, fields = list(...), step = "k")` in the
op's Wait, and the code after the question is the effect: `then(PROC_REF(self))` runs once, after the last answer.

    parse_leading(lines, first, last, handler, actor, forms)  ->  (questions, "") or (None, residue code)
    build_ask(question, ...)                                  ->  (asks text, helper procs, "") or (None, None, residue code)

Only a question that stands first in the body (before any effect, check or local) moves: the op's requirements run before the question, the code before it
would run after. The answer is `var/x = A.step_value("k")` at the head of the new body, which keeps every later use of `x`. The guard that
followed the question (`if(isnull(x)) return`) goes: an unanswered question ends the op. `if(isnull(x) || rest)` keeps `if(rest)`.
"""
import _guard  # noqa: F401  dry run by default, --apply, --help, --files/--dirs scoping
import re
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ui_declare import split_args, strip_code, words_in  # noqa: E402

# call -> (index of the actor argument, of the step key, of the prompt kind, of the first field). The arguments between them are the re-run's bookkeeping.
FORMS = {
    "rerun_ask": (0, 1, 4, 5),
    "act_ask": (0, 4, 5, 6),
    "topic_ask": (0, 2, 3, 4),
    "verb_ask": (0, 1, 3, 4),
}
ASK_CALL = re.compile(r"\b(rerun_ask|act_ask|topic_ask|verb_ask|client_ask|rerun_ask_on|flow_ask)\(")
# old kind -> (new kind, old field -> new field)
KINDS = {
    "text": ("text", {"message": "question", "title": "title", "default": "default", "max_length": "max_len", "multiline": "multiline", "encode": "encode", "name_text": "name_text"}),
    "number": ("number", {"message": "question", "title": "title", "default": "default", "min": "min_value", "max": "max_value"}),
    "choice": ("choice", {"message": "question", "title": "title", "default": "default", "choices": "choices", "buttons": "buttons"}),
    "choice/alert": ("choice", {"message": "question", "title": "title", "default": "default", "choices": "choices"}),
    "color": ("color", {"message": "question", "title": "title", "default": "default"}),
    "confirm": ("yes_no", {"message": "question", "title": "title", "yes_text": "yes_text", "no_text": "no_text"}),
}
LITERAL = re.compile(r'^(?:"[^"\[\\]*"|-?\d+(?:\.\d+)?|[A-Z][A-Z0-9_]*|TRUE|FALSE|null)$')
IDENT = re.compile(r"^[a-z_]\w*$")


def call_inner(line, name):
    """(the text between the parentheses of the first `name(` call in `line`, the text after it), or None."""
    i = line.find(name + "(")
    if i < 0:
        return None
    start = i + len(name)
    depth = 0
    in_str = False
    k = start
    while k < len(line):
        c = line[k]
        if in_str:
            if c == chr(92):
                k += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return line[start + 1 : k], line[k + 1 :]
        k += 1
    return None


_UNDEFS = None


def local_macros():
    """Every macro some file #undefs: a file-local constant, gone by the time code/engine/_generated/declare.dm (which copies the op's fields) compiles."""
    global _UNDEFS
    if _UNDEFS is None:
        _UNDEFS = set()
        root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "code")
        for d, _, files in os.walk(root):
            for f in files:
                if f.endswith(".dm"):
                    with open(os.path.join(d, f), encoding="utf-8", errors="surrogateescape") as fh:
                        _UNDEFS.update(re.findall(r"^\s*#undef\s+(\w+)", fh.read(), re.M))
    return _UNDEFS


def is_literal(text):
    t = text.strip()
    if re.match(r"^[A-Z][A-Z0-9_]*$", t) and t in local_macros():
        return False
    if LITERAL.match(t):
        return True
    m = re.match(r"^list\((.*)\)$", t, re.S)
    if m:
        return all(is_literal(p) for p in split_args(m.group(1)) if p)
    return False


def parse_leading(lines, first, last, handler, actor, forms=("rerun_ask", "act_ask")):
    """The run of question statements at the head of lines[first..last]. Returns (list of questions, "") or (None, residue code). A question is a dict with
    the call's pieces, `remove` (line indices that go) and `rewrite` (index -> new text, the guard that keeps its other condition)."""
    asks = []
    i = first
    while i <= last:
        code = strip_code(lines[i], keep=True).strip()
        if code == "":
            i += 1
            continue
        m = re.match(r"^var/((?:[\w/]+/)?)(\w+)\s*=\s*(" + "|".join(forms) + r")\((.*)$", code)
        if not m:
            break
        got = call_inner(code, m.group(3))
        if not got or got[1].strip():
            return None, "ask_expr"
        args = split_args(got[0])
        actor_i, key_i, prompt_i, field_i = FORMS[m.group(3)]
        if len(args) <= prompt_i:
            return None, "ask_expr"
        if args[actor_i] not in (actor, "ui.user"):
            return None, "ask_actor"
        km = re.match(r'^"([A-Za-z0-9_]+)"$', args[key_i])
        if not km:
            return None, "ask_key"
        if m.group(3) == "rerun_ask" and (args[2] != "PROC_REF(%s)" % handler or not (args[3] == "args" or re.match(r"^list\(\s*" + re.escape(actor) + r"\s*\)$", args[3]))):
            return None, "ask_rerun"
        if m.group(3) == "act_ask" and (args[1] != "action" or args[2] not in ("params", "act_params") or args[3] != "ui"):
            return None, "ask_rerun"
        pk = re.match(r"^/datum/om/prompt/([\w/]+)$", args[prompt_i])
        if not pk or pk.group(1) not in KINDS:
            return None, "ask_kind"
        fields = []
        for fa in args[field_i:]:
            fm = re.match(r"^(\w+)\s*=\s*(.+)$", fa, re.S)
            if not fm:
                return None, "ask_fields"
            fields.append((fm.group(1), fm.group(2).strip()))
        # the guard: `if(isnull(x)) return [value]`, or two lines, or `if(isnull(x) || rest)` over a return (the rest stays)
        name = m.group(2)
        j = i + 1
        while j <= last and strip_code(lines[j]).strip() == "":
            j += 1
        guard = strip_code(lines[j]).strip() if j <= last else ""
        gm = re.match(r"^if\s*\(\s*isnull\(\s*" + re.escape(name) + r"\s*\)\s*(?:\|\|\s*(.*))?\)\s*(return\b.*)?$", guard)
        if not gm:
            return None, "ask_guard"
        rest_cond = gm.group(1)
        remove = []
        rewrite = {}
        if gm.group(2):
            if rest_cond is not None:
                return None, "ask_guard"
            remove = list(range(i, j + 1))
            used = j + 1
        else:
            k = j + 1
            while k <= last and strip_code(lines[k]).strip() == "":
                k += 1
            if k > last or not re.match(r"^return\b.*$", strip_code(lines[k]).strip()):
                return None, "ask_guard"
            used = k + 1
            if rest_cond is None:
                remove = list(range(i, k + 1))
            else:
                if rest_cond.count("(") != rest_cond.count(")"):
                    return None, "ask_guard"
                remove = list(range(i, j))
                indent = re.match(r"^[ \t]*", lines[j]).group(0)
                rewrite[j] = indent + "if(" + rest_cond + ")"
        asks.append({"form": m.group(3), "type": m.group(1), "name": name, "key": km.group(1), "kind": pk.group(1), "fields": fields, "remove": remove, "rewrite": rewrite})
        i = used
    return asks, ""


def edited_lines(lines, first, last, asks):
    """lines[first..last] with the questions' statements and guards gone (the rewritten guard in place)."""
    gone = set()
    rewrite = {}
    for a in asks:
        gone.update(a["remove"])
        rewrite.update(a["rewrite"])
    return [rewrite.get(k, lines[k]) for k in range(first, last + 1) if k not in gone]


def build_ask(ask, holder_vars, helper_prefix, holder_type, actor, held):
    """(the asks(...) part, the helper procs it needs, "") or (None, None, a residue code)."""
    new_kind, names = KINDS[ask["kind"]]
    fields = []
    helpers = []
    seen = set()
    explicit_name_text = any(o == "name_text" for o, _ in ask["fields"])
    for old, expr in ask["fields"]:
        if old not in names:
            return None, None, "ask_field_" + old
        new = names[old]
        if new in seen:
            return None, None, "ask_fields"
        seen.add(new)
        expr = expr.strip()
        if old == "max_length" and ask["kind"] == "text" and not explicit_name_text:
            # the old rule: a name-length limit strips name tokens; any other limit without name_text is residue
            if expr != "MAX_NAME_LEN":
                return None, None, "name_text_unknown"
            fields.append(("max_len", "MAX_NAME_LEN"))
            fields.append(("name_text", "TRUE"))
            seen.add("name_text")
            continue
        if is_literal(expr) and not (expr.startswith('"') and expr.strip('"') in holder_vars):
            fields.append((new, expr))
        elif IDENT.match(expr) and expr in holder_vars:
            fields.append((new, "nameof(%s)" % expr))
        else:
            proc = "%s_%s" % (helper_prefix, new)
            heads = []
            if words_in(expr, actor):
                heads.append("var/mob/%s = A.actor" % actor)
            if held and words_in(expr, held):
                heads.append("var/obj/item/%s = A.held" % held)
            helpers.append("%s/proc/%s(datum/act/op/A)" % (holder_type, proc) + "".join("\n\t" + h for h in heads) + "\n\treturn " + expr)
            fields.append((new, "computed(PROC_REF(%s))" % proc))
    if ask["kind"] == "choice/alert":
        fields.append(("buttons", "TRUE"))
    if not any(n == "timeout" for n, _ in fields):
        fields.append(("timeout", "0"))
    text = 'asks(/datum/prompt/%s, fields = list(%s), step = "%s")' % (new_kind, ", ".join('"%s" = %s' % (n, v) for n, v in fields), ask["key"])
    return text, helpers, ""


def answer_local(ask):
    """The statement that gives the effect the answer the question used to return."""
    return "var/%s%s = A.step_value(\"%s\")" % (ask["type"], ask["name"], ask["key"])
