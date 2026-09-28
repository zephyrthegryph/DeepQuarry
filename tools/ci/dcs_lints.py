"""DCS ban (doc/rewrite/object_model_core.md sec 10 and 16).

The DCS (signals, components, elements, SSdcs) is deleted. Synchronous "now"
reactions are OM events: om_emit()/OM_EMIT() on the entity, before/ events for
results or vetoes, om_hook() for a datum reacting to another entity's event.
Deferred or state-driven reactions are channels, watches or om_after(). Entity
logic is a behaviour with its state on the entity, or an owned datum.

Any use of the old API in code/ fails. There is no ceiling and no allow annotation:
    register_signal  RegisterSignal( / RegisterSignals( / UnregisterSignal(
    send_signal      SEND_SIGNAL( / SEND_GLOBAL_SIGNAL( / SIGNAL_HANDLER
    add_component    AddComponent( / AddComponentFrom( / LoadComponent( / GetComponent( /
                     GetComponents( / GetExactComponent( / /datum/component
    add_element      AddElement( / RemoveElement( / /datum/element
    comsig           a COMSIG_* or SIGNAL_ADDTRAIT/SIGNAL_REMOVETRAIT name in code

Comments and strings are ignored.

Usage:
    python tools/ci/dcs_lints.py                 # the CI check
    python tools/ci/dcs_lints.py --report NAME   # every site of one kind
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

PATTERNS = {
    "register_signal": re.compile(r"(?<![\w/])(?:RegisterSignals?|UnregisterSignal)\s*\("),
    "send_signal": re.compile(r"(?<![\w/])(?:SEND_SIGNAL|SEND_GLOBAL_SIGNAL)\s*\(|\bSIGNAL_HANDLER\b"),
    "add_component": re.compile(
        r"(?<![\w/])(?:AddComponent|AddComponentFrom|LoadComponent|GetComponents?|GetExactComponent)\s*\("
        r"|/datum/component\b"
    ),
    "add_element": re.compile(r"(?<![\w/])(?:AddElement|RemoveElement)\s*\(|/datum/element\b"),
    "comsig": re.compile(r"\b(?:COMSIG_[A-Z0-9_]+|SIGNAL_ADDTRAIT|SIGNAL_REMOVETRAIT)\b"),
}


def sites():
    found = {k: [] for k in PATTERNS}
    for path in sorted(glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True)):
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        raw = open(path, encoding="utf-8", errors="replace").read()
        text = code_only(raw)
        for lineno, line in enumerate(text.split("\n"), 1):
            for name, pat in PATTERNS.items():
                for _ in pat.finditer(line):
                    found[name].append(f"{rel}:{lineno}")
    return found


def main():
    found = sites()
    if "--report" in sys.argv:
        for s in found[sys.argv[sys.argv.index("--report") + 1]]:
            print(s)
        return 0
    bad = False
    for k, v in found.items():
        print(f"{k}: {len(v)} {'OK' if not v else 'FAIL'}")
        for s in v[:20]:
            print(f"  {s}")
        if v:
            bad = True
    if bad:
        print("The DCS is gone: use OM events, om_hook() and behaviours (object_model_core.md sec 10, 16)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
