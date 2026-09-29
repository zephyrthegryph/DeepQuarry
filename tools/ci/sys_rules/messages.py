"""sys_lint module: message templates (doc/rewrite/systems.md section 15).

Rule `visible_pair` flags a hand-written actor message: a `visible_message(` call, outside the
act_message runtime (code/modules/messages/), that is any of

  1. a pair: it passes a self message, i.e. a second argument that isn't null to a mob's
     visible_message (a bare call inside a /mob proc, or `R.visible_message` where R is
     `user`, `usr` or declared as a mob in the proc);
  2. an actor naming itself or its user: the text interpolates `[R]` for the receiver R of
     `R.visible_message`, `[src]` in a bare call inside a /mob proc, or `[user]` / `[usr]`;
  3. the second half of a `to_chat(X, ...)` + `X.visible_message(...)` pair (same X, the
     next statement);
  4. the retired interaction message fields: any `message_self` / `message_others` /
     `start_messages(` / `fill_message(` token in code (use `feedback` / `start_feedback`).

Write act_message(user, target, MSG_SELF(...), MSG_OTHERS(...), MSG_BLIND(...)) with the
%U% / %T% / %I% tokens instead, or act_message_t() with a declared /datum/msg template.
"""
import re

RULES = {
    "visible_pair": "act_message(user, target, MSG_SELF(), MSG_OTHERS(), MSG_BLIND()) or act_message_t() (doc/rewrite/systems.md section 15)",
}

RUNTIME_PREFIX = "code/modules/messages/"
CALL = re.compile(r"(?:\b([A-Za-z_]\w*)\s*\.\s*)?\bvisible_message\s*\(")
PROC_HEAD = re.compile(r"^(/[\w/]+?)(?:/proc|/verb)?/(\w+)\s*\(([^)]*)\)")
OLD_FIELDS = re.compile(r"(?<![\w.])(message_self|message_others|start_messages|fill_message)\b")
TO_CHAT = re.compile(r"^\s*to_chat\s*\(\s*([A-Za-z_]\w*)\s*,")
BS = chr(92)
MOB_NAMES = ("user", "usr")


def split_args(text, start):
    """Top-level args of the call whose '(' ends at `start`. Returns (args, end_index)."""
    args, cur, depth, i, n = [], [], 0, start, len(text)
    in_str = False
    br = 0
    while i < n:
        ch = text[i]
        if in_str:
            cur.append(ch)
            if ch == BS:
                if i + 1 < n:
                    cur.append(text[i + 1])
                i += 2
                continue
            if ch == "[":
                br += 1
            elif ch == "]" and br:
                br -= 1
            elif ch == '"' and not br:
                in_str = False
            i += 1
            continue
        if ch == '"':
            in_str = True
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                args.append("".join(cur).strip())
                return args, i
            depth -= 1
        elif ch == "," and depth == 0:
            args.append("".join(cur).strip())
            cur = []
            i += 1
            continue
        elif ch == "\n" and text[i - 1:i] != BS and depth == 0 and not args and not "".join(cur).strip():
            pass
        cur.append(ch)
        i += 1
    args.append("".join(cur).strip())
    return args, i


def named(arg, name):
    return re.search(r"\[\s*" + re.escape(name) + r"\s*\]", arg) is not None


def scan(files):
    out = {rule: [] for rule in RULES}
    for rel, lines in files:
        rel = rel.replace(BS, "/")
        if rel.startswith(RUNTIME_PREFIX) or not rel.endswith(".dm"):
            continue
        for idx, line in enumerate(lines):
            code = line.split("//", 1)[0]
            if OLD_FIELDS.search(code) and "ALLOW(sys_visible_pair)" not in line:
                out["visible_pair"].append((rel, idx + 1))
        text = "\n".join(lines)
        if "visible_message" not in text:
            continue
        # Line start offsets, and the enclosing proc for each line.
        starts = [0]
        for line in lines:
            starts.append(starts[-1] + len(line) + 1)
        proc_type = [None] * (len(lines) + 1)
        proc_start = [0] * (len(lines) + 1)
        cur_type, cur_start = None, 0
        for idx, line in enumerate(lines):
            m = PROC_HEAD.match(line)
            if m:
                cur_type, cur_start = m.group(1), idx
            elif line and not line[0].isspace() and not line.startswith("//") and not line.startswith("#"):
                cur_type = None
            proc_type[idx], proc_start[idx] = cur_type, cur_start
        line_of = 0
        for m in CALL.finditer(text):
            while starts[line_of + 1] <= m.start():
                line_of += 1
            line = lines[line_of]
            code_before = line[: m.start() - starts[line_of]]
            if "//" in code_before or code_before.lstrip().startswith("/"):
                continue
            if "ALLOW(sys_visible_pair)" in line:
                continue
            recv = m.group(1)
            args, _ = split_args(text, m.end())
            first = args[0] if args else ""
            second = args[1] if len(args) > 1 else ""
            ptype = proc_type[line_of] or ""
            in_mob = ptype.startswith("/mob")
            recv_is_mob = False
            if recv:
                if recv in MOB_NAMES:
                    recv_is_mob = True
                else:
                    head = "\n".join(lines[proc_start[line_of]: line_of + 1])
                    recv_is_mob = re.search(r"\bmob/[\w/]*\b" + re.escape(recv) + r"\b", head) is not None
            elif in_mob:
                recv_is_mob = True
            flagged = False
            # 1. a self message
            if recv_is_mob and second and second != "null" and not second.startswith("exclude"):
                flagged = True
            # 2. the actor names itself or its user
            joined = " ".join(args[:3])
            if recv and recv_is_mob and named(joined, recv) and recv != "src":
                flagged = True
            if (not recv or recv == "src") and in_mob and named(joined, "src"):
                flagged = True
            if named(joined, "user") or named(joined, "usr"):
                flagged = True
            # 3. to_chat(X) then X.visible_message
            if not flagged and line_of > 0:
                prev = line_of - 1
                while prev > 0 and not lines[prev].strip():
                    prev -= 1
                tc = TO_CHAT.match(lines[prev])
                if tc and (tc.group(1) == (recv or "src")):
                    flagged = True
            if flagged:
                out["visible_pair"].append((rel, line_of + 1))
    return out
