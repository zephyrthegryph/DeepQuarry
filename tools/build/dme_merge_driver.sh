#!/usr/bin/env bash
# Git merge driver for deepquarry.dme (.gitattributes: merge=dq-dme). The manifest is generated (tools/build/gen_dme.py), so a merge
# never resolves its text: it merges the three include sets (a side's addition kept, a side's removal kept) and writes them in the
# spec's order, which is what regenerating over the merged tree gives. A lane whose manifest was hand-edited merges the same way.
#
#   dme_merge_driver.sh BASE OURS THEIRS [PATH]     # git passes %O %A %B %P; the result is written over OURS
#
# Installed per command by tools/dq_git_safe.sh (sourced by every merge tool), like the baseline driver. If the generator cannot run
# (no python3, a broken spec on our side) it falls back to a union merge, which never conflicts; the merge tools and the build
# regenerate the manifest from the files on disk after every merge in any case (tools/dq_merge_master.sh, tools/dq_merge_gates.sh).
set -u
O="$1"; A="$2"; B="$3"
PY="${PYTHON:-python3}"
if "$PY" tools/build/gen_dme.py --merge "$O" "$A" "$B"; then
	exit 0
fi
echo "dme_merge_driver: the generator failed; union merge (regenerate after the merge: python3 tools/build/gen_dme.py)" >&2
git merge-file --union -L ours -L base -L theirs "$A" "$O" "$B"
exit 0
