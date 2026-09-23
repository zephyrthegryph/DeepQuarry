#!/bin/bash
set -euo pipefail

RED="\033[0;31m"
NC="\033[0m"

# A TEST_FOCUS(...) line makes the unit-test run execute only the focused tests.
# dq_focus.dm is the scratch file for local focused runs and must be committed
# empty; anywhere else, TEST_FOCUS must sit inside an #if/#ifdef block so it is
# only active for opt-in builds.
if ! python3 - <<'PY'
import glob, re, sys
bad = []
for path in glob.glob("code/**/*.dm", recursive=True):
    depth = 0
    with open(path, encoding="utf-8", errors="ignore") as f:
        for number, line in enumerate(f, 1):
            s = line.strip()
            if s.startswith("#if"):
                depth += 1
            elif s.startswith("#endif"):
                depth = max(0, depth - 1)
            elif s.startswith("TEST_FOCUS("):
                if path.replace("\\", "/").endswith("unit_tests/dq_focus.dm") or depth == 0:
                    bad.append(f"{path}:{number}: {s}")
if bad:
    print("\n".join(bad))
    sys.exit(1)
PY
then
	echo -e "${RED}ERROR: committed TEST_FOCUS found. Empty code/modules/unit_tests/dq_focus.dm or guard the line with #ifdef.${NC}"
	exit 1
fi
echo "No committed test focus."
