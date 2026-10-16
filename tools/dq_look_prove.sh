#!/usr/bin/env bash
# Proves that an incremental look-pin run produces the same rows as a larger (full-like) run on the same tree, on a stratified sample.
#
#   bash tools/dq_look_prove.sh [--stride N] [--dir DIR]
#
# A type's rows must not depend on which other types the run probes. Two runs on the same compiled tree, in different orders:
#   BIG    every Nth type of the analyzer plan, reverse order (a full-like sweep over a superset)
#   SMALL  every 2Nth type (a subset of BIG), shuffled order: the shape of an incremental run, which probes only the unverified types
# Both are made by marking exactly those types unverified (a scratch look_keys.txt that lists every other type as verified, manifest off),
# so the run is the real incremental path; the scratch file is put back from HEAD afterwards and no key is recorded (an ordered run records
# none). The proof is that every row SMALL wrote is byte-identical to a row BIG wrote (`comm -23` empty) and that both runs passed against the
# committed snapshots. Dumps land in DIR/{big,small}/merged. A complete full sweep (every type) costs hours at today's per-type cost
# (tools/dq_look_prove.sh reports the measured seconds per type), so this samples across every root instead.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
stride=40; dir="data/look-prove"
while [ $# -gt 0 ]; do
	case "$1" in --stride) shift; stride="${1:?}" ;; --dir) shift; dir="${1:?}" ;; *) echo "unknown argument: $1" >&2; exit 2 ;; esac
	shift
done
K=code/modules/unit_tests/snapshots/look_keys.txt
bin="$(bash tools/ci/analyze.sh)" || exit 1
"$bin" look-keys --out data/look-plan.tsv >/dev/null || exit 1
rm -rf "$dir"; mkdir -p "$dir"
awk -F'\t' -v s="$stride" 'NR % s == 0 { print $1 }' data/look-plan.tsv >"$dir/big.types"
awk -F'\t' -v s="$((stride * 2))" 'NR % s == 0 { print $1 }' data/look-plan.tsv >"$dir/small.types"
echo "sample: big $(wc -l <"$dir/big.types") types, small $(wc -l <"$dir/small.types") types (stride $stride)"
export DQ_LOOK_MANIFEST=off
run_one() { # <name> <order>
	local name="$1" order="$2" t0
	# the scratch record: every plan type verified except the sample
	awk -F'\t' 'NR == FNR { skip[$1] = 1; next } !($1 in skip) { print $1 "\t" $2 "\t" $3 }' "$dir/$name.types" data/look-plan.tsv >"$K"
	t0=$(date +%s)
	bash tools/dq_focused_test.sh --force --look-order="$order" --look-dump="$dir/$name" dq_look_state_pin dq_look_tree_pin >"$dir/$name.log" 2>&1
	echo "$? $(( $(date +%s) - t0 ))" >"$dir/$name.rc"
	git show "HEAD:$K" >"$K"   # the real record, back in place
}
run_one big reverse
run_one small shuffle:7
read -r brc bsec <"$dir/big.rc"; read -r src ssec <"$dir/small.rc"
echo "big: exit $brc in ${bsec}s ($(grep -h '^FOCUSED RESULT' "$dir/big.log" | tail -n 1)); small: exit $src in ${ssec}s ($(grep -h '^FOCUSED RESULT' "$dir/small.log" | tail -n 1))"
echo "seconds per type (world-time, 1 world per shard): big $(awk -v s="$bsec" -v n="$(wc -l <"$dir/big.types")" 'BEGIN{printf "%.2f", s/n}') wall"
[ "$brc" -eq 0 ] && [ "$src" -eq 0 ] || { echo "dq_look_prove: a run failed; see $dir/*.log" >&2; exit 1; }
fail=0; checked=0
for f in "$dir"/small/merged/*/*.txt; do
	[ -f "$f" ] || continue
	rel="${f#"$dir"/small/merged/}"
	g="$dir/big/merged/$rel"
	[ -f "$g" ] || { echo "MISSING in big: $rel"; fail=1; continue; }
	extra="$(comm -23 "$f" "$g" | head -n 3)"
	checked=$((checked + $(wc -l <"$f")))
	[ -z "$extra" ] || { echo "DIFFERENT rows in $rel:"; echo "$extra"; fail=1; }
done
[ "$checked" -gt 0 ] || { echo "dq_look_prove: the small run dumped no rows" >&2; exit 1; }
if [ "$fail" -eq 0 ]; then echo "dq_look_prove: PASS: all $checked rows of the incremental (small) run are byte-identical to the larger run's rows"; else echo "dq_look_prove: FAIL" >&2; exit 1; fi
