"""Verbs through grants (doc/rewrite/systems.md §19). See tools/ci/sys_lint.py.

The verb store (code/datums/om/grant_verbs.dm) is the only writer of a `verbs` list. Anywhere
else, any write is a finding: `verbs +=`, `-=`, `|=`, `&=`, `^=`, assigning `verbs`, the list
procs (`Add`, `Remove`, `Cut`, `Insert`, `Swap`, `Splice`, `Copy` into it), the removed
`add_verb()` / `remove_verb()` helpers, and `new /x/proc/y(target, ...)` (which puts a renamed
verb on target). No ALLOW is accepted for this rule: there is no exception to the store.
"""
import re

RULES = {
    "verb_write": "om_grant(target, GRANT_VERB | GRANT_VERB_HIDE, verb, source) / om_revoke(), or DECLARE_VERB* on the type; the store is the only verbs writer (doc/rewrite/systems.md §19)",
}

# ALLOW(sys_verb_write) does not suppress a finding (read by tools/ci/sys_lint.py).
NO_ALLOW = ("verb_write",)

PATTERN = re.compile(
    r"\badd_verb\s*\("
    r"|\bremove_verb\s*\("
    r"|\bverbs\s*(\+|-|\||&|\^)="
    r"|\bverbs\s*=(?!=)"
    r"|\bverbs\s*\.\s*(Add|Remove|Cut|Insert|Swap|Splice)\s*\("
    r"|\bverbs\s*\[[^\]]*\]\s*=(?!=)"
    r"|\bnew\s*/[\w/]*/(proc|verb)/\w+\s*\("
)
STRING = re.compile(r'"(?:[^"\\]|\\.)*"')
STORE = ("code/datums/om/grant_verbs.dm",)


def scan(files):
    out = {rule: [] for rule in RULES}
    for rel, lines in files:
        if rel in STORE:
            continue
        for number, line in enumerate(lines, 1):
            code = STRING.sub('""', line).split("//", 1)[0]
            if PATTERN.search(code):
                out["verb_write"].append((rel, number))
    return out
