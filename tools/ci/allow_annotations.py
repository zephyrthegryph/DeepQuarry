r"""The one justified-keep annotation every tools/ci lint reads
(doc/rewrite/object_model_core.md sec 16, "Justified keeps").

A site a lint would count or refuse is kept, with a reason, by a comment on the
site's own line or on a comment-only line directly above it:

    spawn(0) // ALLOW(scheduler): world.Export() is a blocking external call

    // ALLOW(lifecycle, declared_refs): the ledger is the containment engine itself
    /datum/ledger/Destroy()

Inside a multi-line macro, where `//` would swallow the `\` continuation, the
block form `/* ALLOW(scheduler): reason */` works the same. The reason after the
colon is required. Lint names are LINTS below. Ratchet
ceilings (the *_baseline.txt files) still hold the count of unannotated legacy
sites; an annotation takes its site out of the count for good.

    python tools/ci/allow_annotations.py            # check every annotation's syntax
    python tools/ci/allow_annotations.py --report   # count annotations per lint
"""
import glob
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Every lint that reads the annotation, by the name the annotation uses.
LINTS = {
    "api": "tools/ci/api_lints.py",
    "check_grep": "tools/ci/check_grep.sh (same line only)",
    "containment": "tools/ci/containment_lint.py",
    "cooldown": "tools/ci/cooldown_lint.py",
    "declared_refs": "tools/ci/declared_refs_lint.py (undeclared object-typed vars)",
    "handle_kinds": "tools/ci/handle_kinds_lint.py (handles to singletons; handles that are a new datum's only owner)",
    "instance_list": "tools/ci/instance_list_lint.py",
    "latent": "tools/ci/latent_lint.py",
    "lifecycle": "tools/ci/lifecycle_counts_lint.py (Destroy() overrides and qdel( sites)",
    "object_keyed_lists": "tools/ci/declared_refs_lint.py (object-keyed instance lists)",
    "ownership_cycle": "tools/ci/ownership_cycle_lint.py (type-level REF_OWNED cycles)",
    "pollers": "tools/ci/pollers_lint.py",
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
