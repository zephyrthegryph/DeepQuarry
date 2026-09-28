"""Verbs through grants (doc/rewrite/systems.md §19). See tools/ci/sys_lint.py."""
import re

RULES = {
    "add_verb_pair": "om_grant(mob, GRANT_VERB, verb, source) / om_revoke(); the source's removal or deletion revokes (doc/rewrite/systems.md §19)",
}

PATTERN = re.compile(r"\badd_verb\s*\(|\bremove_verb\s*\(|\bverbs\s*(\+|-|\|)=|\bverbs\.(Add|Remove)\s*\(")
EXEMPT = ("code/_helpers/verbs.dm",)


def scan(files):
    out = {rule: [] for rule in RULES}
    for rel, lines in files:
        if rel in EXEMPT:
            continue
        for number, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            if PATTERN.search(code):
                out["add_verb_pair"].append((rel, number))
    return out
