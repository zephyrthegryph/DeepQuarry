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
if ! python3 - <<'PY'
import glob, re, sys

files = [p for root in ("code", "interface", "maps") for p in glob.glob(f"{root}/**/*.dm", recursive=True)]
texts = {}
for path in files:
    with open(path, encoding="utf-8", errors="ignore") as f:
        text = f.read()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    texts[path] = re.sub(r"//[^\n]*", "", text)

define_re = re.compile(r'^[ \t]*#define[ \t]+(COMSIG_\w+)(\([^)]*\))?[ \t]+(\S)', re.M)
signals = {}
for path, text in texts.items():
    for m in define_re.finditer(text):
        if m.group(3) == '"':
            signals.setdefault(m.group(1), path)

# Macros that wrap a send or a register count as that call.
senders = {"SEND_SIGNAL", "SEND_GLOBAL_SIGNAL"}
listeners = {"RegisterSignal", "RegisterSignals"}
wrap_re = re.compile(r'^[ \t]*#define[ \t]+(\w+)\(.*$', re.M)
changed = True
while changed:
    changed = False
    for text in texts.values():
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

allowed = set()
with open("tools/ci/signal_allowlist.txt", encoding="utf-8") as f:
    for line in f:
        name = line.split("#", 1)[0].strip()
        if name:
            allowed.add(name)

bad = []
for name in sorted(signals):
    if name in allowed:
        continue
    if name not in sent:
        bad.append(f"{signals[name]}: {name} is never sent")
    if name not in heard:
        bad.append(f"{signals[name]}: {name} is never listened to")
for name in sorted(allowed - set(signals)):
    bad.append(f"tools/ci/signal_allowlist.txt: {name} is not a defined signal; remove it")
if bad:
    print("\n".join(bad))
    sys.exit(1)
print(f"{len(signals)} signals checked.")
PY
then
	echo -e "${RED}ERROR: dead signals found. Wire each one up or delete it (see doc/rewrite/state.md section 8).${NC}"
	exit 1
fi
echo "No dead signals."
