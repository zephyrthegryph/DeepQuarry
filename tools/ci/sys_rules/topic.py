"""TOPIC_ACTION registry lint (doc/rewrite/systems.md §20)."""
import re

RULES = {
    "topic_override": "declare TOPIC_ACTION(type, href_key, PROC_REF(handler), TOPIC_REF/NUM/TEXT/RIGHTS...) "
    "rows instead of overriding Topic() (doc/rewrite/systems.md §20)",
}

PATTERN = re.compile(r"^/[\w/]*?/(?:proc/)?Topic\s*\(")


def scan(files):
    out = {rule: [] for rule in RULES}
    for rel, lines in files:
        for number, line in enumerate(lines, 1):
            if PATTERN.match(line):
                out["topic_override"].append((rel, number))
    return out
