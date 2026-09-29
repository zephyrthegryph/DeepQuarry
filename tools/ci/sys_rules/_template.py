"""Template for a sys_lint system module (copy to <system>.py). See tools/ci/sys_lint.py."""
import re

RULES = {
    "example_rule": "what to write instead (doc/rewrite/systems.md §N)",
}

PATTERN = re.compile(r"\bexample_old_pattern\s*\(")


def scan(files):
    out = {rule: [] for rule in RULES}
    for rel, lines in files:
        for number, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            if PATTERN.search(code):
                out["example_rule"].append((rel, number))
    return out
