"""TYPE_TABLE / COW_LIST lint (doc/rewrite/systems.md section 7).

static_getter          a proc that returns a proc-local `var/static/list` constant table.
const_list_alloc       a proc that builds the same non-empty constant `list(...)` on every call
                       and returns it.
not_worth_it_annotation an instance_list ALLOW whose reason is "not worth it" on a per-subtype
                       constant table (use TYPE_TABLE / COW_LIST instead).
"""
import re

RULES = {
    "static_getter": "declare TYPE_TABLE(type, name, value) and read TYPE_TABLE_GET(src, name), "
                     "or a GLOBAL_LIST_INIT when the table is not per type (systems.md section 7)",
    "const_list_alloc": "a constant list built per call: TYPE_TABLE / GLOBAL_LIST_INIT, handing "
                        "out a Copy() only where callers mutate it (systems.md section 7)",
    "not_worth_it_annotation": "per-subtype constant table: TYPE_TABLE + COW_LIST, then drop the "
                               "instance_list ALLOW (systems.md section 7)",
}

STATIC_DECL = re.compile(r"^(\s+)var/static/list/(\w+)\s*=\s*list\(")
RETURN_LIST = re.compile(r"^\s+(?:return|\.\s*=)\s*list\(")
NOT_WORTH = re.compile(r"ALLOW\(instance_list\):.*not worth it", re.I)
# A constant list literal: strings without interpolation, numbers, UPPER_CASE defines, type
# paths, nested list(), operators. Any lowercase identifier (a var or proc call) disqualifies.
STRING = re.compile(r'"(?:[^"\\[]|\.)*"')
PATH = re.compile(r"(?<![\w/])/[a-z_][\w/]*")
TOKEN_OK = re.compile(r"^[\sA-Z0-9_.=,+\-*|()&~<>]*$")


def gather(lines, start, col):
    """Text of the balanced list( ... ) that starts at lines[start][col]."""
    depth = 0
    out = []
    for index in range(start, min(start + 400, len(lines))):
        line = lines[index].split("//", 1)[0] if index != start else lines[index][col:].split("//", 1)[0]
        for position, char in enumerate(line):
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    out.append(line[: position + 1])
                    return " ".join(out), index
        out.append(line.rstrip("\\"))
    return None, start


def constant(text):
    if text is None:
        return False
    if '"' in text and "[" in STRING.sub("", text) and False:
        return False
    body = STRING.sub("S", text)
    if '"' in body or "{" in body:
        return False
    body = PATH.sub("P", body)
    body = re.sub(r"\blist\(", "(", body)
    inner = body.strip()
    if inner.replace(" ", "") in ("()",):
        return False  # an empty list is a fresh mutable result, not a table
    return bool(TOKEN_OK.match(body.replace("S", "A").replace("P", "A")))


def scan(files):
    out = {rule: [] for rule in RULES}
    for rel, lines in files:
        for number, line in enumerate(lines, 1):
            if NOT_WORTH.search(line):
                out["not_worth_it_annotation"].append((rel, number))
            match = STATIC_DECL.match(line)
            if match:
                text, _ = gather(lines, number - 1, line.index("list(", match.start(2)))
                if not constant(text):
                    continue
                indent = len(match.group(1).expandtabs(4))
                name = match.group(2)
                ret = re.compile(r"^\s+return\s+" + name + r"\s*$")
                for later in lines[number:]:
                    stripped = later.strip()
                    if stripped and not later.startswith(("\t", " ")):
                        break  # left the proc
                    if ret.match(later.split("//", 1)[0]):
                        out["static_getter"].append((rel, number))
                        break
                continue
            if RETURN_LIST.match(line.split("//", 1)[0]):
                text, _ = gather(lines, number - 1, line.index("list("))
                if constant(text):
                    out["const_list_alloc"].append((rel, number))
    return out
