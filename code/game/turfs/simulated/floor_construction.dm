/**
 * Floor construction graph (doc/rewrite/interactions.md §10).
 *
 * "floored" (a floor covering) -> "plating" by prying, unscrewing or
 * unwrenching the covering (which one depends on its flooring flags);
 * "damaged" plating -> "plating" by welding the dents out; "plating" -> gone
 * by cutting through it to the base turf. The state is worked out from the
 * floor itself (is_plating(), broken, burnt): nothing extra is stored.
 * Laying a covering on plating stays with the stack (attackby).
 */
/turf/simulated/floor
	construction_graph = /datum/construction_graph/floor

/datum/construction_graph/floor
	id = "floor"
	states = list("floored", "damaged", "plating")
	initial_states = list("floored", "damaged", "plating")
	state_var = null
	edge_types = list(
		/datum/interaction/construction/floor/pry_covering,
		/datum/interaction/construction/floor/unscrew_covering,
		/datum/interaction/construction/floor/unwrench_covering,
		/datum/interaction/construction/floor/weld_dents,
		/datum/interaction/construction/floor/cut_plating,
	)

/datum/construction_graph/floor/state_of(atom/target)
	var/turf/simulated/floor/floor = target
	if(!istype(floor))
		return null
	if(!floor.is_plating())
		return "floored"
	if(floor.broken || floor.burnt)
		return "damaged"
	return "plating"

// The floor's own vars hold the state; the edges' effects change them.
/datum/construction_graph/floor/set_state(atom/target, state)
	return

/datum/construction_graph/floor/on_traversed(atom/target, mob/actor, datum/interaction/construction/edge, before, after)
	return

/// Floors do their tool work only on help intent; otherwise the tool attacks the tile (attackby).
/turf/simulated/floor/interaction_tool_act(mob/user, obj/item/tool, quality)
	if(isliving(user))
		var/mob/living/L = user
		if(!IS_HELPING(L))
			return NONE
	return ..()

/datum/interaction/construction/floor
	tool_volume = 80

/datum/interaction/construction/floor/pry_covering
	from_state = "floored"
	to_state = "plating"
	step_text = "pry off the floor covering"
	tool = TOOL_CROWBAR

/datum/interaction/construction/floor/pry_covering/available_on(atom/target)
	var/turf/simulated/floor/floor = target
	return floor.broken || floor.burnt || (floor.flooring.flags & (TURF_IS_FRAGILE | TURF_REMOVE_CROWBAR))

/datum/interaction/construction/floor/pry_covering/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/turf/simulated/floor/floor = target
	floor.pry_covering(actor)
	return TRUE

/datum/interaction/construction/floor/unscrew_covering
	from_state = "floored"
	to_state = "plating"
	step_text = "unscrew the floor covering"
	tool = TOOL_SCREWDRIVER

/datum/interaction/construction/floor/unscrew_covering/available_on(atom/target)
	var/turf/simulated/floor/floor = target
	return !floor.broken && !floor.burnt && (floor.flooring.flags & TURF_REMOVE_SCREWDRIVER)

/datum/interaction/construction/floor/unscrew_covering/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/turf/simulated/floor/floor = target
	to_chat(actor, span_notice("You unscrew and remove the [floor.flooring.descriptor]."))
	floor.make_plating(TRUE)
	return TRUE

/datum/interaction/construction/floor/unwrench_covering
	from_state = "floored"
	to_state = "plating"
	step_text = "unwrench the floor covering"
	tool = TOOL_WRENCH

/datum/interaction/construction/floor/unwrench_covering/available_on(atom/target)
	var/turf/simulated/floor/floor = target
	return floor.flooring.flags & TURF_REMOVE_WRENCH

/datum/interaction/construction/floor/unwrench_covering/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/turf/simulated/floor/floor = target
	to_chat(actor, span_notice("You unwrench and remove the [floor.flooring.descriptor]."))
	floor.make_plating(TRUE)
	return TRUE

/datum/interaction/construction/floor/weld_dents
	from_state = "damaged"
	to_state = "plating"
	step_text = "weld the dents out of the plating"
	tool = TOOL_WELDER
	requires = list(REQ_REACH_ADJACENT, REQ_PROC(/proc/dq_held_welder_lit, "the welding tool must be on"))
	message_self = "You fix some dents on the broken plating."

/datum/interaction/construction/floor/weld_dents/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/turf/simulated/floor/floor = target
	floor.icon_state = "plating"
	floor.burnt = null
	floor.broken = null
	return TRUE

/datum/interaction/construction/floor/cut_plating
	from_state = "plating"
	to_state = CONSTRUCTION_DONE
	step_text = "cut through the plating"
	tool = TOOL_WELDER
	tool_amount = 5
	tool_volume = 0
	// Slow because cutting into space in the middle of the bar is a hostile act. The tool's speed doesn't help.
	duration = 10 SECONDS
	tool_scaled = FALSE
	requires = list(
		REQ_REACH_ADJACENT,
		REQ_PROC(/proc/dq_held_welder_lit, "the welding tool must be on"),
		REQ_ON(PRED_TARGET, /turf/simulated/floor/proc/plating_cut_blocker, null),
	)
	start_self = "You begin cutting through %TARGET%."
	start_others = "%ACTOR% begins cutting through %TARGET%."
	tags = list(INTERACTION_TAG_CONSTRUCTION, INTERACTION_TAG_HOSTILE)

/datum/interaction/construction/floor/cut_plating/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/turf/simulated/floor/floor = target
	playsound(floor, held.usesound, 80, 1)
	floor.do_remove_plating(get_base_turf_by_area(floor))
	return TRUE

/// TRUE when the plating can be cut through to what's under it, else why not.
/turf/simulated/floor/proc/plating_cut_blocker(mob/actor, atom/target, obj/item/held)
	var/base_type = get_base_turf_by_area(src)
	if(type == base_type || !base_type)
		return "there's nothing under [src] to expose by cutting"
	if(locate(/obj/structure) in contents)
		return "[src] has structures that must be removed before cutting"
	return TRUE

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
