// ---- taking a floor apart, declared ----
//
// A floor covering comes up by prying, unscrewing or unwrenching it (which one depends on its flooring flags); damaged plating is welded back
// to plating; plating is cut through to the base turf. The floor's own vars hold the state (is_plating(), broken, burnt): nothing extra is stored,
// and the steps are ops that read them. floor_construction() is listed in the floor's CAPABILITIES block (floor_acts.dm). Floor tool work is the
// help stance's; in any other stance the tool is an item used on the tile (floor_item_*). Laying a covering on plating stays with the stack.

MSG_DEF_SELF(floor/dents_fixed, "You fix some dents on the broken plating.")
MSG_DEF(floor/cut_begins, "You begin cutting through %T%.", "%U% begins cutting through %T%.")
MSG_DEF_SELF(floor/nothing_under, "There is nothing under it to expose by cutting.")
MSG_DEF_SELF(floor/structures_on, "It has structures that must be removed before cutting.")

/// The ops that take a floor apart.
/turf/simulated/floor/proc/floor_construction()
	return list(
		op("pry_covering", tool(TOOL_CROWBAR), stance(I_HELP), when(TYPE_PROC_REF(/turf/simulated/floor, can_pry_covering)), label("Pry off the floor covering"), wait(0), then(TYPE_PROC_REF(/turf/simulated/floor, covering_pried))),
		op("unscrew_covering", tool(TOOL_SCREWDRIVER), stance(I_HELP), when(TYPE_PROC_REF(/turf/simulated/floor, can_unscrew_covering)), label("Unscrew the floor covering"), wait(0), then(TYPE_PROC_REF(/turf/simulated/floor, covering_unscrewed))),
		op("unwrench_covering", tool(TOOL_WRENCH), stance(I_HELP), when(TYPE_PROC_REF(/turf/simulated/floor, can_unwrench_covering)), label("Unwrench the floor covering"), wait(0), then(TYPE_PROC_REF(/turf/simulated/floor, covering_unwrenched))),
		op("weld_dents", lit_welder(fuel = 0), stance(I_HELP), priority(OP_PRIORITY_PART + 1), when(TYPE_PROC_REF(/turf/simulated/floor, plating_bare)), when(any_of(req_is(nameof(broken)), req_is(nameof(burnt)))), label("Weld the dents out of the plating"), wait(0), says(MSG(floor/dents_fixed)), then(TYPE_PROC_REF(/turf/simulated/floor, dents_welded))),
		// slow because cutting into space in the middle of the bar is a hostile act; the tool's speed doesn't help
		op("cut_plating", lit_welder(fuel = 5), stance(I_HELP), when(TYPE_PROC_REF(/turf/simulated/floor, plating_bare)), when(req_is(nameof(broken), FALSE)), when(req_is(nameof(burnt), FALSE)), needs(req(TYPE_PROC_REF(/turf/simulated/floor, plating_has_base), because = MSG(floor/nothing_under)), req(TYPE_PROC_REF(/turf/simulated/floor, plating_clear), because = MSG(floor/structures_on))), label("Cut through the plating"), wait(10 SECONDS), begins(MSG(floor/cut_begins)), then(TYPE_PROC_REF(/turf/simulated/floor, plating_cut))))

/// Bare plating (broken and burnt are tracked and tested by req_is).
/turf/simulated/floor/proc/plating_bare(datum/act/A)
	return read_once(is_plating())

/turf/simulated/floor/proc/can_pry_covering(datum/act/A)
	return read_once(!is_plating() && (broken || burnt || (flooring.flags & (TURF_IS_FRAGILE | TURF_REMOVE_CROWBAR))))

/turf/simulated/floor/proc/can_unscrew_covering(datum/act/A)
	return read_once(!is_plating() && !broken && !burnt && (flooring.flags & TURF_REMOVE_SCREWDRIVER))

/turf/simulated/floor/proc/can_unwrench_covering(datum/act/A)
	return read_once(!is_plating() && (flooring.flags & TURF_REMOVE_WRENCH))

/turf/simulated/floor/proc/covering_pried(datum/act/op/A)
	pry_covering(A.actor)
	return OP_OK

/turf/simulated/floor/proc/covering_unscrewed(datum/act/op/A)
	to_chat(A.actor, span_notice("You unscrew and remove the [flooring.descriptor]."))
	make_plating(TRUE)
	return OP_OK

/turf/simulated/floor/proc/covering_unwrenched(datum/act/op/A)
	to_chat(A.actor, span_notice("You unwrench and remove the [flooring.descriptor]."))
	make_plating(TRUE)
	return OP_OK

/turf/simulated/floor/proc/dents_welded(datum/act/op/A)
	set_broken(null)
	set_burnt(null)
	set_scorch_state(null)
	restore_floor_integrity()
	return OP_OK

/// There is a base turf under the plating to expose.
/turf/simulated/floor/proc/plating_has_base(datum/act/A)
	return read_once(get_base_turf_by_area(src) && type != get_base_turf_by_area(src))

/// No structure stands on the plating.
/turf/simulated/floor/proc/plating_clear(datum/act/A)
	return !locate_within(src, /obj/structure)

/turf/simulated/floor/proc/plating_cut(datum/act/op/A)
	var/obj/item/held = A.held
	playsound(src, held.usesound, 80, 1)
	do_remove_plating(get_base_turf_by_area(src))
	return OP_OK

/// Pries the covering off: broken or fragile coverings are destroyed, others come up whole.
/turf/simulated/floor/proc/pry_covering(mob/user)
	if(broken || burnt)
		to_chat(user, span_notice("You remove the broken [flooring.descriptor]."))
		make_plating(FALSE)
	else if(flooring.flags & TURF_IS_FRAGILE)
		to_chat(user, span_danger("You forcefully pry off the [flooring.descriptor], destroying them in the process."))
		make_plating(FALSE)
	else
		to_chat(user, span_notice("You lever off the [flooring.descriptor]."))
		make_plating(TRUE)
