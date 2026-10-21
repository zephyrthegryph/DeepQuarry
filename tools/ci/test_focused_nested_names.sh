#!/usr/bin/env bash
# Test for tools/dq_focused_test.sh test_types(): every test type a full-suite record can name is accepted, at any depth, whether the type is
# declared by a bare path line, by its own Run()/run_*() proc (dq_eg2/interim_nif_size_actor/answer/run_gate()), and a shared helper
# (/datum/unit_test/dq_eg2/proc/run_gate()) is not a type. This is what lets --rerun-failed=<full-run record> rerun exactly the failed set.
#
#   bash tools/ci/test_focused_nested_names.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

eval "$(sed -n '/^included_files() {/,/^}/p' "$ROOT/tools/dq_focused_test.sh")"
eval "$(sed -n '/^test_types() {/,/^}/p' "$ROOT/tools/dq_focused_test.sh")"

cd "$T" && git init -q . && mkdir -p code/modules/unit_tests
echo '#include "code\modules\unit_tests\_unit_tests.dm"' >deepquarry.dme
printf '#include "fixture.dm"\n' >code/modules/unit_tests/_unit_tests.dm
cat >code/modules/unit_tests/fixture.dm <<'DM'
/datum/unit_test/plain_top
/datum/unit_test/dq_eg2/proc/run_gate()
	return
/datum/unit_test/dq_eg2/interim_nif_size_actor
	abstract_type = /datum/unit_test/dq_eg2/interim_nif_size_actor
/datum/unit_test/dq_eg2/interim_nif_size_actor/proc/install_size(x)
	return
/datum/unit_test/dq_eg2/interim_nif_size_actor/answer/run_gate()
	return
/datum/unit_test/dq_eg2/interim_nif_size_actor/stale/run_pin()
	return
/datum/unit_test/dq_h4/deep/er/still/run_h4()
	return
/datum/unit_test/om/legacy/run_om(list/made)
	return
/datum/unit_test/old_style/Run()
	return
DM
git add -A
types="$(test_types)"
for want in plain_top dq_eg2/interim_nif_size_actor dq_eg2/interim_nif_size_actor/answer dq_eg2/interim_nif_size_actor/stale \
	dq_h4/deep/er/still om/legacy old_style; do
	grep -qxF -- "$want" <<<"$types" && ok "$want is a known test" || fail "$want is missing from test_types"
done
grep -q '/proc' <<<"$types" && fail "a helper proc leaked in as a type: $(grep proc <<<"$types")" || ok "helper procs are not types"
grep -q 'run_' <<<"$types" && fail "a run proc name stayed in a type" || ok "run procs are stripped from the names"
[ "$fails" -eq 0 ] && echo "test_focused_nested_names: all passed" || { echo "test_focused_nested_names: FAILED"; exit 1; }
