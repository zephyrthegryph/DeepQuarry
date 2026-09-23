#!/usr/bin/env python3
"""Rust core-consolidation lint (doc/rewrite/rust_architecture.md §2, §15).

A domain crate (verdigris/domains/*/src) contains only component/kind
declarations, laws and their tests (§2). It may not depend on byondapi, or
contain thread_local!/static mut/#[bind]; construct a Sim, pace itself, keep
key/handle maps, revision counters or dirty sets, or diff display state;
return Vec<f32> or hand-encode anything for DM; or define a unit constant or
re-implement a core kernel. This is a heuristic grep, not a type-checker: it
flags patterns that are *usually* one of these violations, not a proof. A
real hit that isn't actually a violation is a false positive to fix by
tightening the pattern, not by allow-listing it.

Two kinds of check:

1. Source-grep categories, over verdigris/domains/*/src/**/*.rs (vg-core,
   vg-ffi, verdigris/, tools/ are not domain crates and are exempt, EXCEPT
   `reexport_shim`, which applies everywhere -- see below):

     handle           a domain-local generation-checked handle/id type,
                       instead of vg_core::handle::Handle / vg_core::arena::Arena.
     revision         a domain-local `revision: u32`-style bump counter,
                       instead of vg_core::watch::revision (§4.7).
     dirty_set        a domain-local dirty-tracking set/type (gas's old
                       Signature/Dirty), instead of vg_core::watch.
     activity         a domain-local per-entity awake/asleep map, instead of
                       vg_core::activity::Activity (§4.4).
     smoothing        a domain's own "shown"/display-smoothed copy of a
                       value, instead of DM reading the real value (§4.7).
     ffi_raw          positional `kind + p0..p3`-shaped FFI marshalling,
                       instead of the R10 generator's typed commands (§4.8).
     vec_f32_return   a function returning/taking `Vec<f32>` for DM instead
                       of typed events/LawCtx::emit (§4.8, §4.3).
     thread_local     `thread_local!` -- domains hold no global state (§2).
     static_mut       `static mut` -- ditto.
     bind_attr        `#[bind]`/`#[auxmacros::bind]` -- FFI binds belong in
                       vg-ffi (+vg-macros), not a domain crate (§2, §5).
     sim_construct    a domain building its own `Sim`/`SimBuilder`, instead
                       of the one per-DLL driver (§4.3).
     key_map          a `HashMap<u32, _>`/`HashMap<u16, _>`-shaped identity
                       table, instead of `EntityTable` (§4.1, Core B).
     unit_const_redefine  a domain-local `pub const T0C/TCMB/T20C = ...`
                       instead of re-exporting `vg_core::units::consts` (§4.11).

2. `reexport_shim`: over verdigris/core, verdigris/domains, verdigris/ffi
   (everywhere -- this is the no-shims rule, not a domains-only one). A
   `pub use crate::.../Item;`/`pub use super::.../Item;` naming a specific
   item through a fully-qualified path is almost always "X moved, so keep
   the old path compiling instead of updating callers" -- exactly the shim
   `AGENTS.md` forbids ("No shims: delete what you replace"). A deliberate
   public-API re-export of your own direct submodule normally reads
   `pub use submodule::Item;` (no `crate::`/`super::` qualifier needed for
   that), which this pattern does not match.

3. `byondapi_dep`: not a source grep -- each domain crate's Cargo.toml is
   checked for a `byondapi` dependency line (§2's "a domain may not depend
   on byondapi").

Known current offenders are listed in
tools/ci/rust_core_consolidation_allowlist.txt, one `path:category` per
line with the branch/plan that removes it after a `#`. A match not on the
list fails the check; a stale allow-list entry (nothing there matches it
any more) fails too, so the list only shrinks as domains migrate (gas
devices on M2, power's rewrite, heat's bind move -- rust_architecture.md
§7's migration order). The goal (§7 "definition of done") is an **empty**
allow-list.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERDIGRIS = ROOT / "verdigris"
DOMAINS = VERDIGRIS / "domains"
ALLOWLIST = Path(__file__).with_name("rust_core_consolidation_allowlist.txt")

# Categories scoped to domain crates only (verdigris/domains/*/src/**/*.rs).
DOMAIN_PATTERNS: dict[str, re.Pattern[str]] = {
    "handle": re.compile(r"\bstruct\s+\w*(Handle|RawHandle)\b"),
    "revision": re.compile(
        r"\brevision\s*:\s*u32\b|\brevisions?\s*:\s*(Vec|\[)\s*<?\s*u32"
    ),
    "dirty_set": re.compile(
        r"\bstruct\s+(Signature|Dirty\w*)\b|\bdirty\w*\s*:\s*(HashSet|BTreeSet|DenseBitSet)\s*<"
    ),
    "activity": re.compile(
        r"\bactivity\w*\s*:\s*(HashMap|BTreeMap|Vec)\s*<", re.IGNORECASE
    ),
    "smoothing": re.compile(r"\bshown_\w+\s*:|\bfn\s+\w*smooth\w*_(display|shown)\b"),
    "ffi_raw": re.compile(r"\bfn\s+\w+\([^)]*\bp0\s*:\s*\w"),
    "vec_f32_return": re.compile(
        r"->\s*Vec\s*<\s*f32\s*>|&mut\s+Vec\s*<\s*f32\s*>\s*\)"
    ),
    "thread_local": re.compile(r"\bthread_local!\s*[{(]"),
    "static_mut": re.compile(r"\bstatic\s+mut\s+\w"),
    "bind_attr": re.compile(r"#\[\s*(auxmacros::)?bind(_raw_args)?\s*[\](]"),
    "sim_construct": re.compile(r"\bSim(Builder)?::(new|replay)\s*\("),
    "key_map": re.compile(r"\bHashMap\s*<\s*u(32|16)\s*,"),
    "unit_const_redefine": re.compile(
        r"\bpub\s+const\s+(T0C|TCMB|T20C)\s*:\s*f(32|64)\s*="
    ),
}

# `reexport_shim` applies crate-wide (core, domains, ffi), not just domains --
# the no-shims rule isn't a domains-only concern.
REEXPORT_SHIM = re.compile(r"^\s*pub(\(\w+\))?\s+use\s+(crate|self|super)::[\w:]+::\w+\s*;\s*$")

# Domain Cargo.tomls exempt from the byondapi-dependency check while they're
# mid-migration (allow-listed below like any other category, so this list is
# just where to look, not a decision).
DOMAIN_CRATE_DIRS = [p for p in (DOMAINS.iterdir() if DOMAINS.is_dir() else []) if p.is_dir()]


def domain_rust_files() -> list[Path]:
    if not DOMAINS.is_dir():
        return []
    return sorted(p for p in DOMAINS.glob("*/src/**/*.rs") if "target" not in p.parts)


def crate_wide_rust_files() -> list[Path]:
    roots = [VERDIGRIS / "core" / "src", DOMAINS, VERDIGRIS / "ffi"]
    files: list[Path] = []
    for root in roots:
        if root.is_dir():
            files.extend(p for p in root.glob("**/*.rs") if "target" not in p.parts)
    return sorted(set(files))


def load_allowlist() -> dict[tuple[str, str], str]:
    """(relative_path, category) -> reason. Missing file is fine (empty)."""
    entries: dict[tuple[str, str], str] = {}
    if not ALLOWLIST.exists():
        return entries
    for lineno, raw in enumerate(ALLOWLIST.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "#" not in line:
            print(f"{ALLOWLIST}:{lineno}: missing '# reason' comment: {raw}", file=sys.stderr)
            sys.exit(2)
        spec, _reason = line.split("#", 1)
        spec = spec.strip()
        if ":" not in spec:
            print(f"{ALLOWLIST}:{lineno}: expected 'path:category', got {spec!r}", file=sys.stderr)
            sys.exit(2)
        path, category = spec.rsplit(":", 1)
        entries[(path, category)] = raw
    return entries


def check_byondapi_deps(allowed: dict[tuple[str, str], str], used: set[tuple[str, str]]) -> list[str]:
    failures: list[str] = []
    dep_line = re.compile(r"^\s*byondapi\s*=")
    for crate_dir in DOMAIN_CRATE_DIRS:
        cargo_toml = crate_dir / "Cargo.toml"
        if not cargo_toml.is_file():
            continue
        text = cargo_toml.read_text(encoding="utf-8", errors="replace")
        if not any(dep_line.match(line) for line in text.splitlines()):
            continue
        rel = cargo_toml.relative_to(ROOT).as_posix()
        key = (rel, "byondapi_dep")
        if key in allowed:
            used.add(key)
        else:
            failures.append(f"{rel}: [byondapi_dep] domain crate depends on byondapi")
    return failures


def main() -> int:
    allowed = load_allowlist()
    used: set[tuple[str, str]] = set()
    failures: list[str] = []

    for path in domain_rust_files():
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8", errors="replace")
        for lineno, line in enumerate(text.splitlines(), 1):
            for category, pattern in DOMAIN_PATTERNS.items():
                if not pattern.search(line):
                    continue
                key = (rel, category)
                if key in allowed:
                    used.add(key)
                else:
                    failures.append(f"{rel}:{lineno}: [{category}] {line.strip()}")

    for path in crate_wide_rust_files():
        rel = path.relative_to(ROOT).as_posix()
        if path.name == "lib.rs":
            continue  # a crate root re-exporting its own public surface is normal
        text = path.read_text(encoding="utf-8", errors="replace")
        for lineno, line in enumerate(text.splitlines(), 1):
            if not REEXPORT_SHIM.search(line):
                continue
            key = (rel, "reexport_shim")
            if key in allowed:
                used.add(key)
            else:
                failures.append(f"{rel}:{lineno}: [reexport_shim] {line.strip()}")

    failures.extend(check_byondapi_deps(allowed, used))

    for key in sorted(set(allowed) - used):
        failures.append(
            f"tools/ci/rust_core_consolidation_allowlist.txt: stale entry, nothing matches "
            f"{key[0]}:{key[1]} any more -- remove it"
        )

    if failures:
        print("Rust core-consolidation check failed:\n", file=sys.stderr)
        for f in sorted(failures):
            print(f"  {f}", file=sys.stderr)
        print(
            "\nEach mechanism above belongs once in vg-core (doc/rewrite/rust_architecture.md "
            "§2/§4). Either move it there (deleting the old copy -- no shims), or add an "
            "allow-list entry naming the branch/plan that will.",
            file=sys.stderr,
        )
        return 1
    print(f"Rust core-consolidation check passed ({len(used)} allow-listed offender(s)).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
