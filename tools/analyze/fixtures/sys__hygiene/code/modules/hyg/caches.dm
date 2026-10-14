/obj/machinery/cacher
	var/cached_a
	var/cached_b = null
	var/list/cached_c = list()
	var/static/cached_d = 4
	var/global/cached_e
	var/const/cached_f = 7
	var/static/list/cached_g
	var/cachedname
	var/cached
	var/cached_declared
	var/cached_declared2
	var/some/typed/cached_h
	var/not_cached_x
	var/obj/item/cached_item

/obj/machinery/cacher/proc/recompute()
	var/cached_local = 5
	cached_a = compute()
	cached_b = null
	src.cached_a = compute2()
	cached_a += 1
	cached_a -= 1
	cached_a |= 2
	cached_a == 3
	cached_b = null // a comment
	cached_a = "text // not a comment"
	cached_declared = null
	cached_declared = compute()
	cached_declared2 = null
	src.cached_declared = null
	other.cached_a = null
	xcached_a = null
	// cached_a = compute()
	cached_a=null
	cached_a = ( null )
	cached_a = null;

/obj/machinery/cacher/proc/declared_caches()
	return list(
		"cached_declared" = CACHE_ON_MOVE,
		["cached_declared"] = CACHE_ON_TURF,
		["cached_declared2"] = CACHE_ON_STATE
	)

/obj/machinery/cacher/proc/nested()
	var/cached_in_proc = 1
	var/list/cached_list_in_proc

/obj/machinery/cacher/proc/more()
	return cached_in_proc

/obj/machinery/cacher/nested_no_proc_kw()
	var/cached_in_proc2 = 1

/datum/other
	var/cached_o
	proc/old_style_proc()
		var/cached_old_style = 1
	var/cached_after_old_proc

/datum/other/proc/uses()
	cached_o = 1
	cached_old_style = null

/obj/pathvar/var/cached_p = 1
/obj/pathvar/var/static/cached_q = 1
/obj/pathvar/var/list/cached_r
/obj/pathvar/var/global/cached_s
/obj/pathvar/proc/uses_p()
	cached_p = null
	cached_q = 5
	cached_r += 1

DEFINE_THING_DEF(foo)
	var/cached_macro_block
	var/cached_macro_block2

/datum/macro_user
	var/cached_in_macro_user

#define MACRO_THING var/cached_define

/datum/after_define
	var/cached_after

/datum/commented  // trailing comment on the block header
	var/cached_commented_header

/datum/tab_indented_two
	var/cached_ok
		var/cached_too_deep

/datum/allowed
	var/cached_allowed // ALLOW(sys_cached_var): memoizes a pure function
	// ALLOW(sys_cached_var): memoizes another pure function
	var/cached_allowed2

/datum/allowed/proc/use_it()
	cached_allowed = 1 // ALLOW(sys_cached_var): memoizes
	cached_allowed = 2
	cached_allowed2 = null
