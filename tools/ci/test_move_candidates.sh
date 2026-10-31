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
mk code/modules/widgets/newatom.dm '/obj/item/widget/New()
	return ..()'
mk code/modules/widgets/newatom_block.dm '/obj/item/widget
	New()
		return ..()'
mk code/modules/widgets/newdatum.dm '/datum/widget_state/New(a)
	return ..()'
mk code/modules/widgets/newdatum_block.dm '/datum/widget_state
	New(a)
		return ..()'
mk code/modules/widgets/clientverb.dm '/client/verb/poke()
	set name = "Poke"'
mk code/modules/widgets/clientverb_block.dm '/client
	verb/poke()
		set name = "Poke"'
mk code/modules/unit_tests/waits.dm '/proc/w()
	sleep(1)'
mk code/modules/admin/verbs/poke.dm '/mob/verb/poke()
	set name = "Poke"'
mk code/modules/widgets/allow_init.dm '/proc/c()
	return 1 // ALLOW(init/INSTANCE_STATE): a reason long enough to count'
mk code/modules/widgets/allow_mixed.dm '/proc/d()
	return 1 // ALLOW(instance_list, base_vars): a reason long enough to count'
mk code/controllers/globals.dm '/datum/controller/global_vars/Destroy(force)
	return QDEL_HINT_IWILLGC'
mk code/controllers/other.dm '/datum/controller/other/Destroy(force)
	return ..()'
mk code/modules/mob/say_old.dm '/mob/verb/say_verb_old(message as text)
	set name = "Say"'
mk code/modules/mob/say_new.dm '/mob/verb/say_verb_new(message as text)
	set name = "Say"'
mk code/modules/widgets/async_kept.dm '/proc/e()
	INVOKE_ASYNC(GLOBAL_PROC_REF(f)) // ALLOW(scheduler): the callee blocks on a window and has no other way to run'
mk code/modules/widgets/async_kept_above.dm '/proc/g()
	// ALLOW(scheduler): the callee blocks on a window and has no other way to run
	INVOKE_ASYNC(GLOBAL_PROC_REF(f))'
mk code/modules/widgets/async_bare.dm '/proc/h()
	INVOKE_ASYNC(GLOBAL_PROC_REF(f))'
mk 'code/modules/client/client procs.dm' '/client/Topic(href, href_list, hsrc)
	return ..()'
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
mk code/modules/widgets/inc/user.dm '#include "../clean.dm"'
mk code/modules/widgets/sys_owner.dm 'SYSTEM_DEF(gizmos)
	name = "Gizmos"'
mk code/modules/widgets/sys_owner_dirty.dm 'SYSTEM_DEF(sprockets)
	name = "Sprockets"
/obj/x/Destroy()
	return ..()'
mk code/modules/widgets/gizmos_api.dm '/datum/system/gizmos/proc/poke()
	return'
mk code/modules/widgets/sprockets_api.dm '/datum/system/sprockets/proc/poke()
	return'
mk tools/ci/thing_baseline.txt 'rule	code/modules/widgets/baselined.dm	some text'
mk tools/dm-health/baseline.json '["large-proc:code/modules/widgets/spawny.dm:182 lines"]'
mk tools/analyze/src/lints/x.rs 'Files::Under(&["code/modules/widgets/tooled/rig"])'
mk tools/ci/lint_scopes.toml 'x = ["code/modules/widgets/clean.dm"]'

tmpn="$tmp"
if command -v cygpath >/dev/null 2>&1; then tmpn="$(cygpath -m "$tmp")"; fi
out="$(bash "$here/tools/ci/move_candidates.sh" --root "$tmpn")"
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
expect code/modules/widgets/newatom.dm dirty "oldform:New() override"
expect code/modules/widgets/newatom_block.dm dirty "oldform:New() override"
expect code/modules/widgets/newdatum.dm clean ""
expect code/modules/widgets/newdatum_block.dm clean ""
expect code/modules/widgets/clientverb.dm clean ""
expect code/modules/widgets/clientverb_block.dm clean ""
expect code/modules/unit_tests/waits.dm clean ""
expect code/modules/admin/verbs/poke.dm clean ""
expect code/controllers/globals.dm clean ""
expect code/controllers/other.dm dirty "oldform:Destroy()"
expect code/modules/mob/say_old.dm clean ""
expect code/modules/mob/say_new.dm dirty "oldform:verb"
expect code/modules/widgets/async_kept.dm clean ""
expect code/modules/widgets/async_kept_above.dm clean ""
expect code/modules/widgets/async_bare.dm dirty "oldform:INVOKE_ASYNC"
expect 'code/modules/client/client procs.dm' clean ""
expect code/modules/widgets/allowed.dm clean ""
expect code/modules/widgets/allow_init.dm dirty "allow"
expect code/modules/widgets/allow_mixed.dm dirty "allow"
expect code/modules/widgets/baselined.dm dirty "baseline:code/modules/widgets/baselined.dm"
expect code/modules/widgets/tooled/rig/suit.dm dirty "toolref:code/modules/widgets/tooled/rig"
expect code/modules/widgets/uses_content.dm clean ""
expect code/modules/widgets/clean.dm clean "relinc:code/modules/widgets/inc/user.dm:1"
expect code/modules/widgets/inc/user.dm clean "relinc:code/modules/widgets/inc/user.dm:1"
expect code/modules/widgets/sprockets_api.dm dirty "systemowner:code/modules/widgets/sys_owner_dirty.dm"
expect code/modules/widgets/gizmos_api.dm clean ""
expect code/modules/power/cable.dm clean "layering:/obj/item/known"
# a defines file is not listed as a content candidate at all; lint_scopes.toml never makes a file dirty
if [ -z "$(state code/__defines/widgets.dm)" ] || [ "$(state code/__defines/widgets.dm)" = dirty ]; then ok "defines are never clean"; else bad "defines file reported clean"; fi
[ "$(target code/modules/widgets/clean.dm)" = code/content/widgets/clean.dm ] && ok "content target" || bad "content target: $(target code/modules/widgets/clean.dm)"
[ "$(target code/modules/power/cable.dm)" = code/domains/power/cable.dm ] && ok "domain target" || bad "domain target: $(target code/modules/power/cable.dm)"
if [ "$(bash "$here/tools/ci/move_candidates.sh" --root "$tmpn" --clean | wc -l)" -eq 19 ]; then ok "--clean lists the clean files"; else bad "--clean count"; fi
bash "$here/tools/ci/move_candidates.sh" --root "$tmpn" --summary | grep -q 'code/modules/widgets' && ok "--summary groups by directory" || bad "--summary"

[ $fail -eq 0 ] && echo "move_candidates: all passed"
exit $fail
