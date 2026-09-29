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
IDENT = re.compile(r"(?<![\w.])[A-Za-z_]\w*")
DEFINE = re.compile(r"^[A-Z][A-Z0-9_]+$")
LITERALS = {"null", "TRUE", "FALSE", "list", "alist"}


def gather(lines, start, col):
    """Text of the balanced list( ... ) that starts at lines[start][col], its last line index,
    and whatever follows the closing paren on that line (comments removed)."""
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
                    gather.tail = line[position + 1:].strip()
                    return " ".join(out), index
        out.append(line.rstrip("\\"))
    gather.tail = ""
    return None, start


def constant(text):
    """A non-empty list literal of strings (no interpolation), numbers, UPPER_CASE defines and
    type paths. Any other identifier (a var, a proc call) disqualifies it."""
    if text is None:
        return False
    body = STRING.sub(" 0 ", text)
    if '"' in body or "{" in body:
        return False
    body = PATH.sub(" 0 ", body)
    if re.sub(r"\s", "", body) in ("list()", "alist()"):
        return False  # an empty list is a fresh mutable result, not a table
    for ident in IDENT.findall(body):
        if ident not in LITERALS and not DEFINE.match(ident):
            return False
    return not re.search(r"\w\s*\(", re.sub(r"\b(a?list)\(", "(", body))


PROC_HDR = re.compile(r"^/[\w/]*\w\((.*)\)")
OVERRIDE_HDR = re.compile(r"^/[\w/]+/(?!proc/|verb/)\w+\(\s*\)")
GLOB_RETURN = re.compile(r"^\s+return\s+(?:GLOB|global)\.(\w+)\s*$")
GLOBAL_LIST_DECL = re.compile(r"\bGLOBAL_LIST(?:_INIT|_EMPTY|_INIT_TYPED|_EMPTY_TYPED)?\(\s*(\w+)")
STATIC_ANY = re.compile(r"^(\s+)var/static/list/(\w+)\b")
DOT_WRITE = re.compile(r"^\s*\.\s*(\[|\+=|-=|\|=|\.Add\(|\.Insert\()")
LOCAL_CONST = re.compile(r"^(\s+)var/list/(\w+)\s*=\s*list\(")
WRITE = r"\s*(\+=|-=|\|=|&=|\^=|\.Add\(|\.Remove\(|\.Cut\(|\.Insert\(|\.Swap\(|\.Splice\(|\.Copy\(|\[[^\]]*\]\s*(=[^=]|\+=|-=)|\.len\s*[-+]?=|\s*=[^=])"


def proc_body(lines, index):
    """Indices of the rest of the proc body after line `index`."""
    out = []
    for later in range(index + 1, len(lines)):
        text = lines[later]
        if text.strip() and not text.startswith(("\t", " ")):
            break
        out.append(later)
    return out


def scan(files):
    out = {rule: [] for rule in RULES}
    global_lists = set()
    for rel, lines in files:
        for line in lines:
            if "GLOBAL_LIST" in line:
                global_lists.update(GLOBAL_LIST_DECL.findall(line))
    for rel, lines in files:
        in_proc = False
        header = None
        for number, line in enumerate(lines, 1):
            if line.strip() and not line.startswith(("\t", " ")):
                in_proc = bool(PROC_HDR.match(line)) and not line.lstrip().startswith("//")
                header = line if in_proc else None
            if NOT_WORTH.search(line):
                out["not_worth_it_annotation"].append((rel, number))
            if not in_proc:
                continue
            code = line.split("//", 1)[0]
            # A per-type override that hands out a global list.
            glob = GLOB_RETURN.match(code)
            if glob and glob.group(1) in global_lists and header and OVERRIDE_HDR.match(header)                     and lines[number - 2] == header:
                out["static_getter"].append((rel, number))
                continue
            match = STATIC_ANY.match(code)
            if match:
                ret = re.compile(r"^\s+return\s+" + match.group(2) + r"\s*$")
                if any(ret.match(lines[k].split("//", 1)[0]) for k in proc_body(lines, number - 1)):
                    out["static_getter"].append((rel, number))
                continue
            if RETURN_LIST.match(code):
                text, end = gather(lines, number - 1, line.index("list("))
                if constant(text) and not gather.tail:
                    if not code.lstrip().startswith("return") and any(
                            DOT_WRITE.search(lines[k].split("//", 1)[0]) for k in proc_body(lines, end)):
                        continue  # `. = list(...)` seeding a result the proc then fills in
                    out["const_list_alloc"].append((rel, number))
                continue
            match = LOCAL_CONST.match(code)
            if match:
                text, end = gather(lines, number - 1, line.index("list("))
                if not constant(text):
                    continue
                name = match.group(2)
                touched = re.compile(r"\b" + name + WRITE + r"|return\s+" + name + r"\b|[(,]\s*" + name
                                     + r"\s*[,)]|=\s*" + name + r"\s*$")
                if not any(touched.search(lines[k].split("//", 1)[0]) for k in proc_body(lines, end)):
                    out["const_list_alloc"].append((rel, number))
    return out
