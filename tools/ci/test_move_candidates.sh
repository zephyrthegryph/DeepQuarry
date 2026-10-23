#!/usr/bin/env bash
# Self-test of tools/ci/move_candidates.sh on a fixture tree (no compiler, no world).
#   bash tools/ci/test_move_candidates.sh
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$here/data/test_move_candidates.$$"
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

mk() { mkdir -p "$tmp/$(dirname "$1")"; printf '%s\n' "$2" > "$tmp/$1"; }
mk code/modules/widgets/clean.dm '/obj/item/widget
	name = "widget"'
mk code/modules/widgets/comment_only.dm '// Destroy() and spawn(1) in a comment are fine
/obj/item/gadget'
mk code/modules/widgets/destroy.dm '/obj/item/widget/Destroy()
	return ..()'
mk code/modules/widgets/spawny.dm '/proc/a()
	spawn(1)
		return'
mk code/modules/widgets/init.dm '/obj/item/widget/Initialize(mapload)
	. = ..()'
mk code/modules/widgets/verby.dm '/obj/item/widget/verb/poke()
	set name = "Poke"'
mk code/modules/widgets/allowed.dm '/proc/b()
	return 1 // ALLOW(scheduler): a reason long enough to count'
mk code/modules/widgets/baselined.dm '/obj/item/widget/baselined'
mk code/modules/widgets/tooled/rig/suit.dm '/obj/item/widget/rig'
mk code/__defines/widgets.dm '#define WIDGET 1'
mk code/modules/power/cable.dm '/obj/item/widget/cable
	var/y = /obj/item/known'
mk code/content/widgets/known.dm '/obj/item/known'
mk code/modules/widgets/uses_content.dm '/obj/item/other
	var/x = /obj/item/known'
mk tools/ci/thing_baseline.txt 'rule	code/modules/widgets/baselined.dm	some text'
mk tools/dm-health/baseline.json '["large-proc:code/modules/widgets/spawny.dm:182 lines"]'
mk tools/analyze/src/lints/x.rs 'Files::Under(&["code/modules/widgets/tooled/rig"])'
mk tools/ci/lint_scopes.toml 'x = ["code/modules/widgets/clean.dm"]'

out="$(bash "$here/tools/ci/move_candidates.sh" --root "$tmp")"
state() { printf '%s\n' "$out" | awk -F'\t' -v f="$1" '$2 == f { print $1 }'; }
why() { printf '%s\n' "$out" | awk -F'\t' -v f="$1" '$2 == f { print $4 }'; }
target() { printf '%s\n' "$out" | awk -F'\t' -v f="$1" '$2 == f { print $3 }'; }
expect() { # file state reason-substring
  local s w
  s="$(state "$1")"; w="$(why "$1")"
  if [ "$s" = "$2" ] && [[ "$w" == *"$3"* ]]; then ok "$1 is $2 ($3)"; else bad "$1: got '$s' '$w', wanted $2 '$3'"; fi
}
expect code/modules/widgets/clean.dm clean ""
expect code/modules/widgets/comment_only.dm clean ""
expect code/modules/widgets/destroy.dm dirty "oldform:Destroy()"
expect code/modules/widgets/spawny.dm dirty "oldform:spawn"
expect code/modules/widgets/spawny.dm dirty "baseline:code/modules/widgets/spawny.dm"
expect code/modules/widgets/init.dm dirty "oldform:Initialize"
expect code/modules/widgets/verby.dm dirty "oldform:verb"
expect code/modules/widgets/allowed.dm dirty "allow"
expect code/modules/widgets/baselined.dm dirty "baseline:code/modules/widgets/baselined.dm"
expect code/modules/widgets/tooled/rig/suit.dm dirty "toolref:code/modules/widgets/tooled/rig"
expect code/modules/widgets/uses_content.dm clean ""
expect code/modules/power/cable.dm clean "layering:/obj/item/known"
# a defines file is not listed as a content candidate at all; lint_scopes.toml never makes a file dirty
if [ -z "$(state code/__defines/widgets.dm)" ] || [ "$(state code/__defines/widgets.dm)" = dirty ]; then ok "defines are never clean"; else bad "defines file reported clean"; fi
[ "$(target code/modules/widgets/clean.dm)" = code/content/widgets/clean.dm ] && ok "content target" || bad "content target: $(target code/modules/widgets/clean.dm)"
[ "$(target code/modules/power/cable.dm)" = code/domains/power/cable.dm ] && ok "domain target" || bad "domain target: $(target code/modules/power/cable.dm)"
if [ "$(bash "$here/tools/ci/move_candidates.sh" --root "$tmp" --clean | wc -l)" -eq 4 ]; then ok "--clean lists the clean files"; else bad "--clean count"; fi
bash "$here/tools/ci/move_candidates.sh" --root "$tmp" --summary | grep -q 'code/modules/widgets' && ok "--summary groups by directory" || bad "--summary"

[ $fail -eq 0 ] && echo "move_candidates: all passed"
exit $fail
