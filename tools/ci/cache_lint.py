#!/usr/bin/env python3
"""Shared caches go through DECLARE_SHARED_CACHE (doc/rewrite/caching.md).

A hand-rolled keyed cache (a `var/static/list/...cache...`, a global
`GLOBAL_LIST_*(...cache...)` or a top-level `var/list/...cache...`) has its own key
format, no invalidation, no stats and no mutation guard. Declare one with
DECLARE_SHARED_CACHE(name, builder, policy) and read it with CACHED(name, key).

Typecaches (constant `typecacheof()` tables, names containing `typecache`) are not
caches in this sense and are not counted. A justified keep carries
`// ALLOW(cache): <reason>` on its line or on a comment line directly above.
Ceiling: 0.
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from allow_annotations import allowed  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
PATTERNS = [
    re.compile(r'\bvar/static/list/(\w*cache\w*)', re.I),
    re.compile(r'\bGLOBAL_LIST_(?:EMPTY|INIT|EMPTY_TYPED|INIT_TYPED)\(\s*(\w*cache\w*)', re.I),
    re.compile(r'^var/(?:global/)?list/(\w*cache\w*)', re.I),
    re.compile(r'\bvar/global/list/(\w*cache\w*)', re.I),
]
# The framework itself.
EXEMPT_FILES = {
    'code/__defines/shared_cache.dm',
    'code/datums/shared_cache/shared_cache.dm',
}


def scan():
    found = []
    for path in sorted((ROOT / 'code').rglob('*.dm')):
        rel = path.relative_to(ROOT).as_posix()
        if rel in EXEMPT_FILES:
            continue
        raw = path.read_text(encoding='utf-8', errors='ignore').splitlines()
        for n, line in enumerate(raw, 1):
            code = line.split('//', 1)[0]
            for pat in PATTERNS:
                m = pat.search(code)
                if not m:
                    continue
                if 'typecache' in m.group(1).lower():
                    break
                if allowed(raw, n, 'cache'):
                    break
                found.append('%s:%d %s' % (rel, n, line.strip()))
                break
    return found


def main():
    found = scan()
    if found:
        print('cache lint: %d hand-rolled shared caches (ceiling 0). Use DECLARE_SHARED_CACHE / '
              'CACHED() (doc/rewrite/caching.md), or annotate a genuine exception with '
              '`// ALLOW(cache): <reason>`:' % len(found))
        for entry in found:
            print('  ' + entry)
        return 1
    print('cache lint: OK (0 hand-rolled shared caches)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
