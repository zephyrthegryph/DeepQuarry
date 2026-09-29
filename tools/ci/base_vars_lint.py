"""Base-type var and instance-list ratchet (unified plan sec 2.16, migration guide B19 / A14).

Two rules, both shrink-only:

  base_var   A var declared on a base type (BASE_TYPES below). A base type keeps only what
             every instance uses: a feature belongs to a capability (state bit or cap_data),
             a system (private state) or a flyweight (species blood, thermal profile). Every
             var already declared is baselined; a NEW one fails. A `const`/`static`/`global`
             var costs no per-instance memory and isn't counted.
  list_init  An instance var initialised with `= list()`. That allocates one list per
             instance even when it stays empty. Use `var/list/x` with the LAZY* macros
             (code/__defines/_lists.dm), or `var/static/list/x` for a shared constant table.

A justified keep is `// ALLOW(base_vars): <reason>` on the line or the comment line above it
(tools/ci/allow_annotations.py). The baseline holds each site as (file, text).

Usage:
    python tools/ci/base_vars_lint.py            # the CI check
    python tools/ci/base_vars_lint.py --report   # per base type var counts, and the list_init total
    python tools/ci/base_vars_lint.py --update   # drop fixed sites from the baseline (never adds)
    python tools/ci/base_vars_lint.py --seed     # create the baseline from the current sites
"""
import os
import re
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(__file__))
from state_schema_lint import dm_files, parse  # noqa: E402
from allow_annotations import allowed, check_sites, write_sites  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(ROOT, "tools", "ci", "base_vars_baseline.txt")

BASE_TYPES = (
    "/atom", "/atom/movable", "/obj", "/obj/item", "/obj/machinery",
    "/mob", "/mob/living", "/mob/living/carbon", "/mob/living/carbon/human",
)
NO_INSTANCE_COST = {"const", "static", "global"}
LIST_INIT = re.compile(r"=\s*list\(\s*\)\s*(?:$|//|/\*)")


def scan():
    decls, _codecs, _latent = parse(dm_files())
    base_sites, list_sites, per_type = [], [], Counter()
    raw_cache = {}
    for owner, variables in decls.items():
        for v in variables:
            if v.mods & NO_INSTANCE_COST:
                continue
            raw = raw_cache.get(v.path)
            if raw is None:
                with open(os.path.join(ROOT, v.path), encoding="utf-8", errors="replace") as handle:
                    raw = raw_cache[v.path] = handle.read().split("\n")
            if allowed(raw, v.line, "base_vars"):
                continue
            if owner in BASE_TYPES:
                base_sites.append((v.path, v.line, "%s var %s" % (owner, v.name)))
                per_type[owner] += 1
            text = raw[v.line - 1].strip() if v.line <= len(raw) else ""
            if LIST_INIT.search(text):
                list_sites.append((v.path, v.line, re.sub(r"\s+", " ", text)))
    return base_sites, list_sites, per_type


def main(argv):
    base_sites, list_sites, per_type = scan()
    sites = {"base_var": base_sites, "list_init": list_sites}
    if "--update" in argv or "--seed" in argv:
        write_sites(BASELINE, [
            "Base-type vars and `= list()` instance vars (unified plan sec 2.16). rule<TAB>file<TAB>text.",
            "tools/ci/base_vars_lint.py fails on a site not listed here. A site with",
            "`// ALLOW(base_vars): <reason>` doesn't count.",
            "Shrink-only: after a sweep, `python tools/ci/base_vars_lint.py --update`.",
        ], sites, ["base_var", "list_init"], shrink_only="--seed" not in argv)
        print("base vars baseline: %d base-type vars, %d list() initialisers" % (len(base_sites), len(list_sites)))
        return 0
    if "--report" in argv:
        for owner in BASE_TYPES:
            print("  %5d  %s" % (per_type[owner], owner))
        print("total: %d base-type vars, %d `= list()` instance vars" % (len(base_sites), len(list_sites)))
        return 0
    failed = check_sites(
        "base_vars", sites, BASELINE,
        {"base_var": "don't add a var to a base type: make it a capability's state bit / cap_data, "
                     "a system's private state or a flyweight (or `// ALLOW(base_vars): <reason>`)",
         "list_init": "use `var/list/x` + LAZYADD/LAZYLEN, or `var/static/list/x` for a shared table"})
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
