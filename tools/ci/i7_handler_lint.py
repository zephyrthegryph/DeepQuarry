#!/usr/bin/env python3
"""I7 ratchet: legacy input-handler overrides per domain (doc/rewrite/interactions.md sec 13).

Converted handlers are interactions (DECLARE_INTERACTIONS / EXTEND_INTERACTIONS in
code/__defines/interactions.dm). This counts the attackby / attack_hand / attack_self /
click_alt / MouseDrop_T overrides still defined on each domain's types and fails when a
count rises above its ceiling. Lower the ceiling when you convert more.

Files other work owns (the body rewrite's medical code, cooking, vore, resleeving) and
test fixtures are not counted; tools/ci/check_grep.sh holds the per-domain bans for
domains that are fully converted.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
HANDLER = re.compile(r'^(/obj/(?:machinery|structure|item))(/[\w/]*)?/(attackby|attack_hand|attack_self|click_alt|MouseDrop_T)\(', re.M)
EXCLUDED = re.compile(r'^code/(modules/unit_tests/|modules/resleeving/|modules/food/kitchen/|modules/vore/)')

# Ceilings: the count may fall, never rise.
CEILINGS = {
    '/obj/machinery': 37,
    '/obj/structure': 2,
    '/obj/item': 394,
}


def main():
    counts = {domain: [] for domain in CEILINGS}
    for path in sorted((ROOT / 'code').rglob('*.dm')):
        rel = path.relative_to(ROOT).as_posix()
        if EXCLUDED.match(rel):
            continue
        text = path.read_text(encoding='utf-8', errors='ignore')
        for m in HANDLER.finditer(text):
            if '/proc' in (m.group(2) or ''):
                continue
            line = text.count('\n', 0, m.start()) + 1
            counts[m.group(1)].append('%s:%d %s%s/%s' % (rel, line, m.group(1), m.group(2) or '', m.group(3)))
    failed = False
    for domain, found in counts.items():
        ceiling = CEILINGS[domain]
        if len(found) > ceiling:
            failed = True
            print('%s: %d legacy handler overrides, ceiling %d. Declare interactions instead '
                  '(DECLARE_INTERACTIONS / EXTEND_INTERACTIONS, code/__defines/interactions.dm):' % (domain, len(found), ceiling))
            for entry in found:
                print('  ' + entry)
        else:
            note = ' (lower the ceiling to %d)' % len(found) if len(found) < ceiling else ''
            print('%s: %d legacy handler overrides, ceiling %d%s' % (domain, len(found), ceiling, note))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
