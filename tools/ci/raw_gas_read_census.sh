#!/usr/bin/env bash
# Report-only census of raw gas reads in content (nothing gates on it; a later ratchet is decided from these numbers).
#
# A raw gas read is a call that crosses into Rust for one value of a mixture: return_pressure(), return_temperature(), total_moles(),
# get_moles(), return_volume(), heat_capacity(). Reactive code (a draw, a requirement, an on_change, a stat input) reads a gas value through
# watched(A, WATCH_GAS, levels, channel =, air =) (code/domains/heat/watched.dm) instead; a loop that reads several mixtures in one pass uses
# read_gas_mixtures() (one FFI call for the list). This prints, per read function and per area of the tree, how many sites remain, and which
# files hold the most. Tests, benchmarks and the engine/domain layers that implement the reads are left out.
#
#   bash tools/ci/raw_gas_read_census.sh            the table
#   bash tools/ci/raw_gas_read_census.sh --files    also the top files in each area
cd "$(dirname "$0")/../.." || exit 1
reads='\.?(return_pressure|return_temperature|total_moles|get_moles|return_volume|heat_capacity)\('
mapfile -t hits < <(git grep -nE "$reads" -- 'code/content/*.dm' 'code/library/*.dm' 'code/modules/*.dm' 'code/game/*.dm' 'code/datums/*.dm' 2>/dev/null \
	| grep -Ev '^[^:]*:[0-9]+:\s*//' | grep -Ev '^code/(tests|modules/unit_tests|modules/benchmarks)/')
echo "raw gas read census: ${#hits[@]} sites"
echo
echo "by read:"
printf '%s\n' "${hits[@]}" | grep -oE "(return_pressure|return_temperature|total_moles|get_moles|return_volume|heat_capacity)\(" | sort | uniq -c | sort -rn | sed 's/^/  /'
echo
echo "by area:"
printf '%s\n' "${hits[@]}" | cut -d: -f1 | awk -F/ '{ if (NF >= 3) print $1 "/" $2 "/" $3; else print $1 "/" $2 }' | sort | uniq -c | sort -rn | head -25 | sed 's/^/  /'
if [ "$1" = "--files" ]; then
	echo
	echo "top files:"
	printf '%s\n' "${hits[@]}" | cut -d: -f1 | sort | uniq -c | sort -rn | head -40 | sed 's/^/  /'
fi
