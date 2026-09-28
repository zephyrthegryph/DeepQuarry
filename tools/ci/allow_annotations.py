r"""The one justified-keep annotation every tools/ci lint reads
(doc/rewrite/object_model_core.md sec 16, "Justified keeps").

A site a lint would count or refuse is kept, with a reason, by a comment on the
site's own line or on a comment-only line directly above it:

    spawn(0) // ALLOW(scheduler): world.Export() is a blocking external call

    // ALLOW(lifecycle): the round-end sweep deletes every mob
    qdel(M)

Inside a multi-line macro, where `//` would swallow the `\` continuation, the
block form `/* ALLOW(scheduler): reason */` works the same. The reason after the
colon is required. Lint names are LINTS below. Ratchet
baselines (the *_baseline.txt files) list the unannotated legacy sites as
fingerprints (check_sites() / write_sites() below); an annotation takes its site
out of the ratchet for good.

    python tools/ci/allow_annotations.py            # check every annotation's syntax
    python tools/ci/allow_annotations.py --report   # count annotations per lint
"""
import glob
import os
import re
import sys
from collections import Counter

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Every lint that reads the annotation, by the name the annotation uses.
LINTS = {
    "api": "tools/ci/api_lints.py",
    "cache": "tools/ci/cache_lint.py (hand-rolled shared caches outside DECLARE_SHARED_CACHE)",
    "check_grep": "tools/ci/check_grep.sh (same line only)",
    "containment": "tools/ci/containment_lint.py",
    "cooldown": "tools/ci/cooldown_lint.py",
    "decl": "tools/ci/decl_lint.py (Initialize()/on_destroy() work a lifecycle declaration now does)",
    "declared_refs": "tools/ci/declared_refs_lint.py (undeclared object-typed vars)",
    "handle_kinds": "tools/ci/handle_kinds_lint.py (handles to singletons; handles that are a new datum's only owner)",
    "instance_list": "tools/ci/instance_list_lint.py",
    "interactions": "tools/ci/interactions_lint.py (DECLARE_INTERACTIONS replacing an ancestor's specs)",
    "latent": "tools/ci/latent_lint.py",
    "lifecycle": "tools/ci/lifecycle_counts_lint.py (qdel( sites; Destroy() overrides are banned outright)",
    "om_internal": "tools/ci/om_internal_lint.py (_om_* scheduler internals outside code/datums/om)",
    "object_keyed_lists": "tools/ci/declared_refs_lint.py (object-keyed instance lists)",
    "organ_slots": "tools/ci/organ_slots_lint.py (the deleted internal organ lists; ceiling 0)",
    "ownership_cycle": "tools/ci/ownership_cycle_lint.py (type-level DECLARE_REF(..., OWNED) cycles)",
    "pollers": "tools/ci/pollers_lint.py",
    "radial": "tools/ci/leftovers_lints.py (radial menus that are not action pickers)",
    "registry": "tools/ci/registry_lint.py",
    "scheduler": "tools/ci/scheduler_lints.py",
    "silent_catch": "tools/ci/silent_catch_lint.py (catches that swallow an exception)",
    "spatial": "tools/ci/spatial_lint.py",
    "state_ref": "tools/ci/state_schema_lint.py",
    "subsystem_fire": "tools/ci/subsystem_fire_lint.py (fire() outside the core allowlist)",
}

# `// ALLOW(a, b): reason`; the reason is checked separately so a bare one is an error.
ALLOW = re.compile(r"(?://+|/\*)\s*ALLOW\(\s*([\w\s,]*?)\s*\)\s*(:?)\s*(.*?)\s*(?:\*/.*)?$")


def parse(line):
    """(set of lint names, reason) for the annotation on `line`, or None."""
    m = ALLOW.search(line)
    if not m:
        return None
    names = {n.strip() for n in m.group(1).split(",") if n.strip()}
    return names, (m.group(3) if m.group(2) else "")


def names_on(line):
    got = parse(line)
    if not got or not got[1]:
        return ()
    return got[0]


def allowed(raw_lines, number, lint):
    """True if 1-based line `number` of `raw_lines` (the file's raw text split on
    newlines, comments intact) is kept for `lint`: the annotation is on the line
    itself, or on a comment-only line directly above it."""
    if 1 <= number <= len(raw_lines) and lint in names_on(raw_lines[number - 1]):
        return True
    if number >= 2:
        above = raw_lines[number - 2]
        if above.lstrip().startswith("//") and lint in names_on(above):
            return True
    return False


def read_baseline(path):
    """{count name: ceiling} from a ratchet baseline file (`name count` lines, # comments)."""
    base = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                line = line.split("#", 1)[0].strip()
                if line:
                    name, count = line.split()
                    base[name] = int(count)
    return base


def write_baseline(path, header, counts):
    """Rewrites a ratchet baseline: `header` comment lines, then `name count` per count."""
    lines = ["# " + h for h in header] + ["%s %d" % (name, counts[name]) for name in counts]
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def check_ceilings(label, counts, base, hint):
    """Prints each count against its ceiling; True if any rose above it."""
    failed = False
    for name, count in counts.items():
        ceiling = base.get(name)
        if ceiling is None:
            print("%s %-18s %6d  FAIL (no ceiling in the baseline)" % (label, name, count))
            failed = True
        elif count > ceiling:
            print("%s %-18s %6d  FAIL (ceiling %d)" % (label, name, count, ceiling))
            failed = True
        elif count < ceiling:
            print("%s %-18s %6d  below ceiling %d: lower it with --update" % (label, name, count, ceiling))
        else:
            print("%s %-18s %6d  ok" % (label, name, count))
    if failed:
        print("%s: a count rose above its ceiling. %s `--report` lists the sites; a justified keep "
              "takes `// ALLOW(<lint>): <reason>` (tools/ci/allow_annotations.py)." % (label, hint))
    return failed


_LINES = {}


def site_text(rel, number):
    """The whitespace-normalized text of 1-based line `number` of repo file `rel`."""
    lines = _LINES.get(rel)
    if lines is None:
        with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as handle:
            lines = _LINES[rel] = handle.read().split("\n")
    return " ".join(lines[number - 1].split()) if 1 <= number <= len(lines) else ""


def read_sites(path):
    """{rule: Counter((file, normalized line text))} from a site-fingerprint baseline.

    Lines are `rule<TAB>file<TAB>normalized line text`; `#` lines are comments. A
    fingerprint has no line number, so edits elsewhere in the file don't break it."""
    base = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                line = line.rstrip("\n")
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t", 2)
                if len(parts) != 3:
                    continue
                base.setdefault(parts[0], Counter())[(parts[1], parts[2])] += 1
    return base


def _fingerprints(sites):
    """{rule: [(rel, number, text)]} from {rule: [(rel, number, ...)]}."""
    return {rule: [(s[0], s[1], site_text(s[0], s[1])) for s in found] for rule, found in sites.items()}


def write_sites(path, header, sites, rules=None, shrink_only=True):
    """Rewrites a site-fingerprint baseline from {rule: [(rel, number, ...)]}.

    With shrink_only (the --update default) a site absent from the old baseline is not
    added: the baseline only ever loses sites. `--seed` (shrink_only=False) records every
    current site; use it only to create a baseline."""
    old = read_sites(path)
    rows = []
    for rule in (rules or sorted(sites)):
        budget = Counter(old.get(rule, Counter()))
        for rel, _number, text in sorted(_fingerprints({rule: sites.get(rule, [])})[rule]):
            key = (rel, text)
            if shrink_only:
                if budget[key] <= 0:
                    continue
                budget[key] -= 1
            rows.append("%s\t%s\t%s" % (rule, rel, text))
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(["# " + h for h in header] + rows) + "\n")
    return len(rows)


def check_sites(label, sites, path, hints, banned=()):
    """The ratchet check against a site-fingerprint baseline.

    `sites` is {rule: [(rel, number, ...)]}; `hints` is {rule: fix hint} or one string.
    Prints one line per rule, then ONLY the sites the baseline doesn't hold, as
    `file:line: [label/rule] text -- hint`. Rules in `banned` have no baseline. True on
    any new site."""
    base = read_sites(path)
    failed = False
    new_lines = []
    for rule, found in _fingerprints(sites).items():
        budget = Counter() if rule in banned else Counter(base.get(rule, Counter()))
        known = sum(budget.values())
        fresh = []
        for rel, number, text in found:
            key = (rel, text)
            if budget[key] > 0:
                budget[key] -= 1
            else:
                fresh.append((rel, number, text))
        gone = sum(budget.values())
        if fresh:
            failed = True
            status = "FAIL (%d new site%s)" % (len(fresh), "" if len(fresh) == 1 else "s")
        elif gone:
            status = "%d baselined site%s gone: shrink the baseline with --update" % (gone, "" if gone == 1 else "s")
        else:
            status = "ok"
        print("%s %-19s %6d  (baseline %d)  %s" % (label, rule, len(found), known, status))
        hint = hints.get(rule, "") if isinstance(hints, dict) else hints
        for rel, number, text in fresh:
            new_lines.append("%s:%d: [%s/%s] %s%s" % (rel, number, label, rule, text, (" -- " + hint) if hint else ""))
    if new_lines:
        print("%s: new sites (baselined legacy sites are not listed):" % label)
        for line in new_lines:
            print(line)
        print("Fix each site, or keep a justified one with `// ALLOW(<lint>): <reason>` "
              "(tools/ci/allow_annotations.py). Baselines only shrink.")
    return failed


def dm_files():
    for top in ("code", "maps"):
        for path in glob.glob(os.path.join(ROOT, top, "**", "*.dm"), recursive=True):
            yield path, os.path.relpath(path, ROOT).replace(os.sep, "/")


def main(argv):
    problems, counts = [], {name: 0 for name in LINTS}
    for path, rel in dm_files():
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        if "ALLOW(" not in text:
            continue
        for number, line in enumerate(text.split("\n"), 1):
            if "ALLOW(" not in line:
                continue
            got = parse(line)
            if not got:
                problems.append("%s:%d: malformed ALLOW annotation; write `// ALLOW(<lint>[, <lint>]): <reason>`" % (rel, number))
                continue
            names, reason = got
            if not names:
                problems.append("%s:%d: ALLOW() names no lint" % (rel, number))
            for name in sorted(names - set(LINTS)):
                problems.append("%s:%d: ALLOW(%s): unknown lint; known: %s" % (rel, number, name, ", ".join(sorted(LINTS))))
            if not reason:
                problems.append("%s:%d: ALLOW(%s) has no reason after the colon" % (rel, number, ", ".join(sorted(names))))
            for name in names & set(LINTS):
                counts[name] += 1
    if "--report" in argv:
        for name in sorted(counts):
            print("%-19s %5d" % (name, counts[name]))
    for problem in problems:
        print(problem)
    print("allow annotations: %d, %d problems" % (sum(counts.values()), len(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
