#!/usr/bin/env bash
# Does a branch carry a lane-ready stamp that is still good for the master it is about to merge into?
#
#   bash tools/dq_lane_check.sh [--fetch] [--master REF] <branch-or-commit>...
#
# One line per ref on stdout, then the exit status:
#   LANE <ref> VALID <why>           the stamp covers this merge: the branch's own tests need not run again
#   LANE <ref> INVALID <why>         a stamp exists but master moved under the branch's files or tests (or the stamp is a failure)
#   LANE <ref> UNSTAMPED <why>       no stamp: run tools/dq_lane_ready.sh in the lane, or name its tests to the gates
# Each line ends with `tests=a,b,c` (the stamp's list, empty when unstamped). Exit 0 when every ref is VALID, else 1.
#
# The stamp is a git note on the branch commit (refs/notes/lane-ready, written by tools/dq_lane_ready.sh; all worktrees of this
# clone share it, `--fetch` also fetches the remote's). It records the master commit the lane merged and tested against, the
# tests, and that gen, the production compile, DreamChecker, the ratchets and the tests all passed. It is VALID against the
# current master (origin/master unless --master) when
#   1. the lane's base is current: the stamp's master commit is the master tip, or
#   2. the stamp's master commit is an ancestor of master and what master changed since touches nothing the stamp's tests can
#      depend on: the files the branch changed, the directories they sit in, the stamp's `covers` globs, the files that define
#      its tests, and the global paths of tools/ci/lane_ready_global.txt (the test harness, the kernel, the analyzer, the build).
# Commits after the stamped one are fine when they touch only html/changelogs/, doc/, data/ or a markdown file at the repo root.
# Whatever passes this still goes through the combined gates and the cross-branch smoke set (tools/dq_merge_gates.sh --lanes).
set -uo pipefail
cd "$(dirname "$0")/.."
exec node tools/dq_lane_check.js "$@"
