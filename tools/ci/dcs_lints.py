"""DCS ratchet (doc/rewrite/object_model_core.md sec 16, completion_plan sec 3.2).

Synchronous "now" reactions are OM events (om_emit, before/ events with
EVENT_VETO); deferred or state-driven reactions are channels, watches or
om_after. DCS signals and components survive only in the DCS core (CORE below: path
prefixes whose sites are not counted) and at sites marked
`// ALLOW(dcs): <reason>` (tools/ci/allow_annotations.py).

Counts (ceilings in tools/ci/dcs_lints_baseline.txt; may fall, never rise):
    register_signal  RegisterSignal( / RegisterSignals( calls
    add_component    AddComponent( / AddComponentFrom( / LoadComponent( calls
    add_element      AddElement( calls

Usage:
    python tools/ci/dcs_lints.py                 # the CI check
    python tools/ci/dcs_lints.py --report NAME   # every site of one count
    python tools/ci/dcs_lints.py --update        # rewrite the baseline
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import code_only  # noqa: E402
from allow_annotations import allowed  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "dcs_lints_baseline.txt")

PATTERNS = {
    "register_signal": re.compile(r"(?<![\w/])RegisterSignals?\s*\("),
    "add_component": re.compile(r"(?<![\w/])(?:AddComponent|AddComponentFrom|LoadComponent)\s*\("),
    "add_element": re.compile(r"(?<![\w/])AddElement\s*\("),
}


CORE = (
    "code/datums/components/_component.dm",  # component core
    "code/datums/elements/_element.dm",  # element core
    "code/datums/signals.dm",  # signal core
    "code/controllers/subsystem/dcs.dm",  # SSdcs
)


def sites():
    found = {k: [] for k in PATTERNS}
    for path in sorted(glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True)):
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        if rel.startswith(CORE):
            continue
        raw = open(path, encoding="utf-8", errors="replace").read()
        raw_lines = raw.split("\n")
        text = code_only(raw)
        for lineno, line in enumerate(text.split("\n"), 1):
            if "#define" in line or allowed(raw_lines, lineno, "dcs"):
                continue
            for name, pat in PATTERNS.items():
                for _ in pat.finditer(line):
                    found[name].append(f"{rel}:{lineno}")
    return found


def main():
    found = sites()
    counts = {k: len(v) for k, v in found.items()}
    if "--report" in sys.argv:
        for s in found[sys.argv[sys.argv.index("--report") + 1]]:
            print(s)
        return 0
    if "--update" in sys.argv:
        with open(BASELINE, "w", encoding="utf-8", newline="\n") as f:
            f.write("# DCS ratchet ceilings (tools/ci/dcs_lints.py). Lower with --update.\n")
            for k, v in counts.items():
                f.write(f"{k} {v}\n")
        print(counts)
        return 0
    base = {}
    for line in open(BASELINE, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            k, v = line.split()
            base[k] = int(v)
    bad = False
    for k, v in counts.items():
        ceil = base.get(k, 0)
        status = "OK" if v <= ceil else "FAIL"
        print(f"{k}: {v} (ceiling {ceil}) {status}")
        if v > ceil:
            bad = True
            print(f"  {k} rose: use an OM event/watch instead (object_model_core.md sec 16)")
        elif v < ceil:
            print(f"  {k} fell: lower the ceiling with --update")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
