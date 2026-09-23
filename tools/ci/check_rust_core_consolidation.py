#!/usr/bin/env python3
"""Rust core-consolidation lint (doc/rewrite/rust_core.md §15).

Every domain crate under verdigris/domains/*/src builds only its physics,
component/grid declarations and topology rules; the mechanisms in §15's
table (identity/handles, activity+sleep, change tracking, rate models,
thermo, FFI marshalling, presentation) live once in vg-core (or the R10
binding layer) instead of being reimplemented per domain. This is a
heuristic grep, not a type-checker: it flags patterns that are usually one
of these mechanisms being hand-rolled again, not a proof. A real hit that
isn't actually a violation is a false positive to fix by tightening the
pattern, not by allow-listing it.

Five categories, each a regex over verdigris/domains/*/src/**/*.rs
(vg-core, vg-ffi, verdigris/, tools/ are not domain crates and are exempt):

  handle      a domain-local generation-checked handle/id type, instead of
              vg_core::handle::Handle / vg_core::arena::Arena.
  revision    a domain-local `revision: u32`-style bump-on-write/bump-on-
              band counter, instead of vg_core::revision::BandRevision (or
              vg_core::watch for a registered, frame-evaluated condition).
  activity    a domain-local per-entity "is this awake / does this need
              processing" map, instead of a core activity/sleep service
              (rust_core.md §15 (2); not yet built as of this check).
  ffi_raw     positional `kind + p0..p3`-shaped FFI marshalling in a
              domain crate, instead of the R10 generator's typed
              commands/reads/queries.
  smoothing   a domain keeping its own "shown"/display-smoothed copy of a
              simulation value instead of DM reading the real value when
              it displays it.

Known current offenders are listed in
tools/ci/rust_core_consolidation_allowlist.txt, one `path:line`+pattern
name per line with the branch/plan that removes it after a `#`. A match
not on the list fails the check; a stale allow-list entry (nothing there
matches it any more) fails too, so the list only shrinks as domains
migrate (gas devices on M2, power's rewrite, heat's bind move -- see
rust_core.md §15's migration order).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOMAINS = ROOT / "verdigris" / "domains"
ALLOWLIST = Path(__file__).with_name("rust_core_consolidation_allowlist.txt")

PATTERNS: dict[str, re.Pattern[str]] = {
    "handle": re.compile(r"\bstruct\s+\w*(Handle|RawHandle)\b"),
    "revision": re.compile(
        r"\brevision\s*:\s*u32\b|\brevisions?\s*:\s*(Vec|\[)\s*<?\s*u32"
    ),
    "activity": re.compile(
        r"\bactivity\w*\s*:\s*(HashMap|BTreeMap|Vec)\s*<", re.IGNORECASE
    ),
    "ffi_raw": re.compile(r"\bfn\s+\w+\([^)]*\bp0\s*:\s*\w"),
    "smoothing": re.compile(r"\bshown_\w+\s*:|\bfn\s+\w*smooth\w*_(display|shown)\b"),
}


def rust_files() -> list[Path]:
    if not DOMAINS.is_dir():
        return []
    return sorted(p for p in DOMAINS.glob("*/src/**/*.rs") if "target" not in p.parts)


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


def main() -> int:
    allowed = load_allowlist()
    used: set[tuple[str, str]] = set()
    failures: list[str] = []

    for path in rust_files():
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8", errors="replace")
        for lineno, line in enumerate(text.splitlines(), 1):
            for category, pattern in PATTERNS.items():
                if not pattern.search(line):
                    continue
                key = (rel, category)
                if key in allowed:
                    used.add(key)
                else:
                    failures.append(f"{rel}:{lineno}: [{category}] {line.strip()}")

    for key in sorted(set(allowed) - used):
        failures.append(
            f"tools/ci/rust_core_consolidation_allowlist.txt: stale entry, nothing matches "
            f"{key[0]}:{key[1]} any more -- remove it"
        )

    if failures:
        print("Rust core-consolidation check failed:\n", file=sys.stderr)
        for f in failures:
            print(f"  {f}", file=sys.stderr)
        print(
            "\nEach mechanism above belongs once in vg-core (doc/rewrite/rust_core.md §15). "
            "Either move it there, or add an allow-list entry naming the branch/plan that will.",
            file=sys.stderr,
        )
        return 1
    print(f"Rust core-consolidation check passed ({len(used)} allow-listed offender(s)).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
