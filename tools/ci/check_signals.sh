#!/bin/bash
set -euo pipefail

RED="\033[0;31m"
NC="\033[0m"

# Signal audit (roadmap L4). Every COMSIG_* define whose value is a signal name
# (a string, or a macro that builds one) must be sent somewhere (SEND_SIGNAL,
# SEND_GLOBAL_SIGNAL, or a macro wrapping either) and listened to somewhere
# (RegisterSignal, RegisterSignals, or a `COMSIG_X = PROC_REF(...)` connection
# list). COMSIG_* defines whose value is a number are return flags and are
# skipped. Signals only reached through computed names go in
# tools/ci/signal_allowlist.txt, one per line, with a comment saying why.
# It also checks the declared argument counts in code/datums/signal_args.dm.
if ! python3 - <<'PY'
import glob, re, sys

def code_only(text):
    """Blanks comments and string literals (keeping newlines and the code in
    [] embeds), so parentheses and tokens inside them cannot confuse the scan."""
    out, i, n = [], 0, len(text)
    stack = []  # "code" for a [] embed, else the closing quote of an open string
    while i < n:
        c = text[i]
        if stack and stack[-1] != "code":
            close = stack[-1]
            if c == "\\":
                i += 2
                continue
            if c == "[":
                stack.append("code")
            elif text.startswith(close, i):
                stack.pop()
                out.append('""')
                i += len(close)
                continue
            elif c == "\n":
                out.append(c)
            i += 1
            continue
        if c == "]" and stack:
            stack.pop()
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("\n" * text.count("\n", i, j))
            i = j
            continue
        elif text.startswith('{"', i):
            stack.append('"}')
            i += 2
            continue
        elif c == '"':
            stack.append('"')
            i += 1
            continue
        elif c == "'":
            j = text.find("'", i + 1)
            i = n if j < 0 else j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out)

files = [p.replace("\\", "/") for root in ("code", "interface", "maps") for p in glob.glob(f"{root}/**/*.dm", recursive=True)]
raw, texts = {}, {}
for path in files:
    with open(path, encoding="utf-8", errors="ignore") as f:
        raw[path] = f.read()
    texts[path] = code_only(raw[path])

define_re = re.compile(r'^[ \t]*#define[ \t]+(COMSIG_\w+)(\([^)]*\))?[ \t]+(\S)', re.M)
signals = {}
for path, text in raw.items():
    for m in define_re.finditer(text):
        if m.group(3) == '"':
            signals.setdefault(m.group(1), path)

# Two defines with the same string are one signal: listeners of either get both.
value_re = re.compile(r'^[ \t]*#define[ \t]+(COMSIG_\w+)[ \t]+("[^"]*")', re.M)
by_value = {}
for path, text in raw.items():
    for m in value_re.finditer(text):
        by_value.setdefault(m.group(2), set()).add(m.group(1))
duplicate_values = [f"{value} is defined by {', '.join(sorted(names))}" for value, names in sorted(by_value.items()) if len(names) > 1]

# Macros that wrap a send or a register count as that call.
senders = {"SEND_SIGNAL", "SEND_GLOBAL_SIGNAL"}
listeners = {"RegisterSignal", "RegisterSignals"}
wrap_re = re.compile(r'^[ \t]*#define[ \t]+(\w+)\(.*$', re.M)
changed = True
while changed:
    changed = False
    for text in raw.values():
        for m in wrap_re.finditer(text):
            name, body = m.group(1), m.group(0)
            for group in (senders, listeners):
                if name not in group and any(re.search(rf"\b{w}\s*\(", body) for w in group):
                    group.add(name)
                    changed = True

token_re = re.compile(r"\bCOMSIG_\w+")
def spans(text, names):
    call_re = re.compile(r"\b(" + "|".join(sorted(names)) + r")\s*\(")
    for m in call_re.finditer(text):
        i, depth = m.end(), 1
        while depth and i < len(text):
            depth += {"(": 1, ")": -1}.get(text[i], 0)
            i += 1
        yield text[m.end():i]

sent, heard = set(), set()
for text in texts.values():
    for span in spans(text, senders):
        sent.update(token_re.findall(span))
    for span in spans(text, listeners):
        heard.update(token_re.findall(span))
    heard.update(re.findall(r"\b(COMSIG_\w+)\s*=\s*(?:TYPE_|GLOBAL_)?PROC_REF\b", text))

# Argument counts: every fixed-name signal declares one in signal_arg_counts(),
# and every static send passes that many. Computed-name signals (macros with a
# parameter) must at least agree across their send sites.
def split_top(args):
    parts, depth, current = [], 0, ""
    for c in args:
        depth += 1 if c in "([{" else -1 if c in ")]}" else 0
        if c == "," and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += c
    parts.append(current)
    return [p.strip() for p in parts]

table_path = "code/datums/signal_args.dm"
declared = {m.group(1): int(m.group(2)) for m in re.finditer(r"^\s*(COMSIG_\w+)\s*=\s*(\d+),", raw[table_path], re.M)}
computed = {m.group(1) for text in raw.values() for m in re.finditer(r'^[ \t]*#define[ \t]+(COMSIG_\w+)\(', text, re.M)}
arity_bad = []
first_seen = {}
send_re = re.compile(r"\b(SEND_SIGNAL|SEND_GLOBAL_SIGNAL)\s*\(")
for path, text in texts.items():
    for m in send_re.finditer(text):
        line_start = text.rfind("\n", 0, m.start()) + 1
        if text[line_start:m.start()].lstrip().startswith("#define"):
            continue
        i, depth = m.end(), 1
        while depth and i < len(text):
            depth += {"(": 1, ")": -1}.get(text[i], 0)
            i += 1
        parts = split_top(text[m.end():i - 1])
        is_global = m.group(1) == "SEND_GLOBAL_SIGNAL"
        sig_expr = parts[0] if is_global else (parts[1] if len(parts) > 1 else "")
        count = len(parts) - (1 if is_global else 2)
        where = f"{path}:{text.count(chr(10), 0, m.start()) + 1}"
        for name in token_re.findall(sig_expr):
            expected = declared.get(name)
            if expected is None and name in computed:
                expected = first_seen.setdefault(name, (count, where))[0]
            if expected is not None and expected != count:
                arity_bad.append(f"{where}: {name} sent with {count} argument(s); declared {expected}")
for name in sorted(set(signals) - computed - set(declared)):
    arity_bad.append(f"{signals[name]}: {name} has no argument count in {table_path}")
for name in sorted(set(declared) - set(signals)):
    arity_bad.append(f"{table_path}: {name} is not a defined signal; remove it")

allowed = set()
with open("tools/ci/signal_allowlist.txt", encoding="utf-8") as f:
    for line in f:
        name = line.split("#", 1)[0].strip()
        if name:
            allowed.add(name)

bad = arity_bad
for name in sorted(signals):
    if name in allowed:
        continue
    if name not in sent:
        bad.append(f"{signals[name]}: {name} is never sent")
    if name not in heard:
        bad.append(f"{signals[name]}: {name} is never listened to")
for name in sorted(allowed - set(signals)):
    bad.append(f"tools/ci/signal_allowlist.txt: {name} is not a defined signal; remove it")
for name in sorted(allowed & sent & heard):
    bad.append(f"tools/ci/signal_allowlist.txt: {name} is sent and listened to; remove it")
bad.extend(duplicate_values)
if bad:
    print("\n".join(bad))
    sys.exit(1)
print(f"{len(signals)} signals checked, {len(allowed)} allowlisted.")
PY
then
	echo -e "${RED}ERROR: signal audit failed. Wire each dead signal up or delete it, and keep code/datums/signal_args.dm in step (see doc/rewrite/state.md section 8).${NC}"
	exit 1
fi
echo "No dead signals."
