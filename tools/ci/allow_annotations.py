r"""The one justified-keep annotation every tools/ci lint reads
(doc/rewrite/object_model_core.md sec 16, "Justified keeps").

A site a lint would count or refuse is kept, with a reason, by a comment on the
site's own line or on a comment-only line directly above it:

    spawn(0) // ALLOW(scheduler): world.Export() is a blocking external call

    // ALLOW(lifecycle): the round-end sweep deletes every mob
    qdel(M)

Inside a multi-line macro, where `//` would swallow the `\` continuation, the
block form `/* ALLOW(scheduler): reason */` works the same. The reason after the
colon is required, and must be a real reason (reason_problem() below: at least
MIN_REASON characters and three words, no allowlist, no "see above", no plan-phase
label). Lint names are LINTS below. Ratchet
baselines (the *_baseline.txt files) list the unannotated legacy sites as
fingerprints (check_sites() / write_sites() below); an annotation takes its site
out of the ratchet for good.

An annotation must also be used: one whose target line no longer triggers its lint is an error
(the "Usage recording" section below; check_ratchets.sh runs it after every lint).

    python tools/ci/allow_annotations.py            # check every annotation's syntax and reason
    python tools/ci/allow_annotations.py --report   # count annotations per lint
    python tools/ci/allow_annotations.py --unused FILE   # annotations no lint used (FILE: DQ_ALLOW_USAGE rows)
"""
import atexit
import glob
import hashlib
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
    "doc_snippets": "tools/ci/doc_snippets.py (a doc/rewrite dm block calling a name that doesn't exist)",
    "decl": "tools/ci/decl_lint.py (Initialize()/on_destroy() work a lifecycle declaration now does)",
    "derived_reads": "tools/ci/derived_reads_lint.py (a derived proc reading a var derived() does not declare)",
    "init": "tools/ci/init_lint.py (Initialize() overrides that set per-instance state, not type facts)",
    "instance_list": "tools/ci/instance_list_lint.py",
    "interactions": "tools/ci/interactions_lint.py (DECLARE_INTERACTIONS replacing an ancestor's specs)",
    "latent": "tools/ci/latent_lint.py",
    "lifecycle": "tools/ci/lifecycle_counts_lint.py (qdel( sites; Destroy() overrides are banned outright)",
    "om_internal": "tools/ci/om_internal_lint.py (_om_* scheduler internals outside code/datums/om)",
    "ownership": "tools/ci/ownership_lint.py (raw writes to owned / relation vars, CALLBACK, handles in content)",
    "organ_slots": "tools/ci/organ_slots_lint.py (the deleted internal organ lists; ceiling 0)",
    "pollers": "tools/ci/pollers_lint.py",
    "radial": "tools/ci/leftovers_lints.py (radial menus that are not action pickers)",
    "registry": "tools/ci/registry_lint.py",
    "scheduler": "tools/ci/scheduler_lints.py",
    "silent_catch": "tools/ci/silent_catch_lint.py (catches that swallow an exception)",
    "spatial": "tools/ci/spatial_lint.py",
    "tracked": "tools/ci/tracked_lint.py (writes to a TRACKED var outside its setter; target 0)",
    "system_boundary": "tools/ci/system_boundary_lint.py (cross-module access to a system's private state)",
    "verb_category": "tools/ci/verb_category_lint.py (a raw verb category string)",
    "subsystem_fire": "tools/ci/subsystem_fire_lint.py (fire() outside the core allowlist)",
    "ui_actions": "tools/ci/ui_actions_lint.py (act_ parameters no act() sends, or used before validation)",
}


def _sys_rules():
    """The generic-systems rules (`sys_<rule>`, tools/ci/sys_lint.py), one module per system in
    tools/ci/sys_rules/. Loaded here directly (no import of sys_lint, which imports this file)."""
    import importlib.util
    out = {}
    for path in sorted(glob.glob(os.path.join(os.path.dirname(__file__), "sys_rules", "*.py"))):
        name = os.path.splitext(os.path.basename(path))[0]
        if name.startswith("_"):
            continue
        spec = importlib.util.spec_from_file_location("sys_rules_" + name, path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        for rule in getattr(mod, "RULES", {}):
            out["sys_" + rule] = "tools/ci/sys_rules/%s.py" % name
        # A module may read one ALLOW name for several rules (appearance: sys_update_icon).
        for alias in getattr(mod, "ALLOW_NAMES", {}):
            out["sys_" + alias] = "tools/ci/sys_rules/%s.py" % name
    return out


LINTS.update(_sys_rules())

# Paths no ratchet lint counts (the lints that import exempt_path()): unit tests and benchmarks build
# the forbidden things on purpose to test or measure them, and the vendored tgstation-server DMAPI is
# kept verbatim. A site there needs no annotation.
EXEMPT_DIRS = ("code/modules/unit_tests/", "code/modules/benchmarks/", "code/modules/tgs/")
EXEMPT_FILES = ("code/__defines/tgs.dm",)


def exempt_path(rel):
    """True for a repo-relative path under EXEMPT_DIRS or EXEMPT_FILES."""
    return rel.startswith(EXEMPT_DIRS) or rel in EXEMPT_FILES


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
        _record(raw_lines, number, lint)
        return True
    if number >= 2:
        above = raw_lines[number - 2]
        if above.lstrip().startswith("//") and lint in names_on(above):
            _record(raw_lines, number - 1, lint)
            return True
    return False


def allowed_here(raw_lines, number, lint):
    """True if 1-based line `number` itself carries an annotation for `lint` (a lint that also
    accepts an annotation on a neighbouring line, such as the first line of a catch block)."""
    if 1 <= number <= len(raw_lines) and lint in names_on(raw_lines[number - 1]):
        _record(raw_lines, number, lint)
        return True
    return False


# ---------------------------------------------------------------------------------------------
# Usage recording, for the "unused ALLOW" check (`--unused`).
#
# An annotation whose target line no longer triggers its lint is stale: it hides nothing and only
# misleads. Every lint asks `allowed()` about a site it would otherwise count, so when a lint run
# sets DQ_ALLOW_USAGE=<file>, allowed() appends one `lint<TAB>file digest<TAB>annotation line` row
# to that file for each annotation that actually kept a site. check_ratchets.sh sets the variable
# for the whole run and then calls `allow_annotations.py --unused <file>`, which reports every
# annotation no lint used. The digest (not a path) names the file because the lints pass allowed()
# the file's lines, not its name.
#
# A lint must therefore only ask allowed() about a site it would count: ask after the pattern
# matched and the file/directory exemptions passed, not for every line. A lint that asks for every
# line makes every annotation look used (a miss for this check, never a false report).
# ---------------------------------------------------------------------------------------------
USAGE_ENV = "DQ_ALLOW_USAGE"
_used = set()
_digests = {}
_flush_registered = False


def digest_of(lines):
    """Content digest of a file given as its lines (CR and trailing blank lines don't matter)."""
    text = "\n".join(line.rstrip("\r") for line in lines).rstrip("\n")
    return hashlib.sha1(text.encode("utf-8", "replace")).hexdigest()


def _record(raw_lines, annotation_line, lint):
    global _flush_registered
    if not os.environ.get(USAGE_ENV):
        return
    held = _digests.get(id(raw_lines))
    if held is None or held[0] is not raw_lines:
        held = _digests[id(raw_lines)] = (raw_lines, digest_of(raw_lines))
    _used.add((lint, held[1], annotation_line))
    if not _flush_registered:
        _flush_registered = True
        atexit.register(_flush_usage)


def _flush_usage():
    path = os.environ.get(USAGE_ENV)
    if not path or not _used:
        return
    with open(path, "a", encoding="utf-8", newline="\n") as handle:
        for lint, digest, number in sorted(_used):
            handle.write("%s\t%s\t%d\n" % (lint, digest, number))


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


# ---------------------------------------------------------------------------------------------
# Reason quality. The reason is what a reader sees at the site, so it has to say why the site must
# stay, in the site's own terms. These are the shapes that have stood in for one.
# ---------------------------------------------------------------------------------------------
MIN_REASON = 20
MIN_REASON_WORDS = 3
VAGUE_REASONS = (
    (re.compile(r"\ballowlist(?:s|ed)?\b", re.I), "there is no allowlist: say why this site stays"),
    (re.compile(r"\b(?:see|as) (?:above|below)\b", re.I), "say the reason here, not on another line"),
    (re.compile(r"\bnot edited here\b", re.I), "a deferred conversion is not a reason: convert the site or say why it must stay"),
    (re.compile(r"\bS\d+\b|\bwave F\d+|\bsec(?:tion)? \d|\bphase \d", re.I), "a plan-phase label names the plan, not the reason"),
    (re.compile(r"\b[A-Z]\d{1,2}[a-z]?(?:/[A-Z]?\d{1,2}[a-z]?)*\b"), "a plan item code (M1a, C9, P3, ...) names the plan, not the reason"),
)


def reason_problem(reason):
    """Why `reason` is not a reason (text), or None."""
    text = reason.strip()
    if len(text) < MIN_REASON or len(text.split()) < MIN_REASON_WORDS:
        return "reason %r is too short to explain anything (at least %d characters and %d words)" % (text, MIN_REASON, MIN_REASON_WORDS)
    for pattern, why in VAGUE_REASONS:
        if pattern.search(text):
            return "reason %r: %s" % (text if len(text) <= 70 else text[:67] + "...", why)
    return None


# Lints whose annotations the usage check cannot observe: check_grep.sh is a shell script (same
# line only) and doc_snippets reads the design docs, not the .dm tree.
UNOBSERVED = {"check_grep", "doc_snippets"}


def unused(usage_path):
    """Prints and returns the annotations no lint run used. `usage_path` holds the rows
    allowed() appended during the run (DQ_ALLOW_USAGE)."""
    used, seen_lints, files = set(), set(), {}
    with open(usage_path, encoding="utf-8") as handle:
        for row in handle:
            parts = row.rstrip("\n").split("\t")
            if len(parts) == 3:
                used.add((parts[0], parts[1], int(parts[2])))
                seen_lints.add(parts[0])
    annotations = []
    for path, rel in dm_files():
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        if "ALLOW(" not in text:
            continue
        lines = text.split("\n")
        digest = digest_of(lines)
        files[digest] = rel
        for number, line in enumerate(lines, 1):
            got = parse(line) if "ALLOW(" in line else None
            if got:
                annotations.append((rel, number, digest, got[0]))
    # Rows whose file digest names no file are lints that handed allowed() text that is not a
    # file's content (a fixture, a doc): a lint with such rows is not trusted to be complete.
    stray = Counter(lint for lint, digest, _n in used if digest not in files)
    matched = Counter(lint for lint, digest, _n in used if digest in files)
    untrusted = sorted(lint for lint in stray if not matched[lint])
    problems, quiet = [], Counter()
    for rel, number, digest, names in annotations:
        for name in sorted(names & set(LINTS)):
            if name in UNOBSERVED or name in untrusted:
                continue
            if name not in seen_lints:
                quiet[name] += 1
                continue
            if (name, digest, number) not in used:
                problems.append("%s:%d: ALLOW(%s) is unused: no longer triggers %s; delete the annotation (or the "
                                "site's reason is stale)" % (rel, number, name, LINTS[name].split(" (")[0]))
    for name, count in sorted(quiet.items()):
        problems.append("ALLOW(%s): %d annotation%s, but no lint run used any: %s is not run by check_ratchets.sh, "
                        "or every one of them is stale" % (name, count, "" if count == 1 else "s", LINTS[name].split(" (")[0]))
    for name in untrusted:
        print("allow annotations: not checking ALLOW(%s): its lint asked allowed() about text that is not a .dm file" % name)
    for problem in problems:
        print(problem)
    print("allow annotations: %d used, %d unused" % (len(annotations) - len(problems), len(problems)))
    return problems


def main(argv):
    if "--unused" in argv:
        return 1 if unused(argv[argv.index("--unused") + 1]) else 0
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
            else:
                weak = reason_problem(reason)
                if weak:
                    problems.append("%s:%d: ALLOW(%s): %s" % (rel, number, ", ".join(sorted(names)), weak))
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
