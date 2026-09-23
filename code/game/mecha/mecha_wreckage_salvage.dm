/**
 * Exosuit wreckage salvage graph (doc/rewrite/interactions.md §10).
 *
 * One state, "wreck": each salvage step leaves it where it was, and runs out
 * with the wreck's salvage. A welder cuts sheets, rods or parts (a 70% chance
 * each time), wirecutters cut cable (70%), a crowbar pries out what the wreck
 * held.
 */
/obj/effect/decal/mecha_wreckage
	construction_graph = /datum/construction_graph/mecha_wreckage

/datum/construction_graph/mecha_wreckage
	id = "mecha_wreckage"
	state_var = null
	states = list("wreck")
	initial_states = list("wreck")
	edge_types = list(
		/datum/interaction/construction/wreckage/cut,
		/datum/interaction/construction/wreckage/snip,
		/datum/interaction/construction/wreckage/pry,
	)

/datum/construction_graph/mecha_wreckage/state_of(atom/target)
	return istype(target, /obj/effect/decal/mecha_wreckage) ? "wreck" : null

/datum/construction_graph/mecha_wreckage/set_state(atom/target, state)
	return

/datum/construction_graph/mecha_wreckage/on_traversed(atom/target, mob/actor, datum/interaction/construction/edge, before, after)
	return

/datum/interaction/construction/wreckage
	from_state = "wreck"
	to_state = "wreck"
	tool_volume = 0

/datum/interaction/construction/wreckage/cut
	step_text = "cut salvage from the wreck"
	tool = TOOL_WELDER
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/effect/decal/mecha_wreckage/proc/can_cut_salvage, null))

/datum/interaction/construction/wreckage/cut/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/effect/decal/mecha_wreckage/wreck = target
	wreck.cut_salvage(actor)
	return TRUE

/datum/interaction/construction/wreckage/snip
	step_text = "cut wiring from the wreck"
	tool = TOOL_WIRECUTTER
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/effect/decal/mecha_wreckage/proc/has_salvage_left, null))

/datum/interaction/construction/wreckage/snip/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/effect/decal/mecha_wreckage/wreck = target
	wreck.snip_salvage(actor)
	return TRUE

/datum/interaction/construction/wreckage/pry
	step_text = "pry something out of the wreck"
	tool = TOOL_CROWBAR
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/effect/decal/mecha_wreckage/proc/has_pry_salvage, "you don't see anything that can be pried out"))

/datum/interaction/construction/wreckage/pry/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/effect/decal/mecha_wreckage/wreck = target
	wreck.pry_salvage(actor)
	return TRUE

/obj/effect/decal/mecha_wreckage/proc/has_salvage_left(mob/actor, atom/target, obj/item/held)
	return salvage_num > 0 ? TRUE : "you don't see anything that can be cut with [held]"

/obj/effect/decal/mecha_wreckage/proc/can_cut_salvage(mob/actor, atom/target, obj/item/held)
	. = has_salvage_left(actor, target, held)
	if(. == TRUE && isemptylist(welder_salvage))
		return "there is nothing left to cut"

/obj/effect/decal/mecha_wreckage/proc/has_pry_salvage(mob/actor, atom/target, obj/item/held)
	return isemptylist(crowbar_salvage) ? FALSE : TRUE

/obj/effect/decal/mecha_wreckage/proc/cut_salvage(mob/user)
	var/type = prob(70) ? pick(welder_salvage) : null
	if(!type)
		to_chat(user, "You failed to salvage anything valuable from [src].")
		return
	var/N = new type(get_turf(user))
	user.visible_message("[user] cuts [N] from [src]", "You cut [N] from [src]", "You hear a sound of welder nearby")
	if(istype(N, /obj/item/mecha_parts/part))
		welder_salvage -= type
	salvage_num--

/obj/effect/decal/mecha_wreckage/proc/snip_salvage(mob/user)
	if(isemptylist(wirecutters_salvage))
		return
	var/type = prob(70) ? pick(wirecutters_salvage) : null
	if(!type)
		to_chat(user, "You failed to salvage anything valuable from [src].")
		return
	var/N = new type(get_turf(user))
	user.visible_message("[user] cuts [N] from [src].", "You cut [N] from [src].")
	salvage_num--

/obj/effect/decal/mecha_wreckage/proc/pry_salvage(mob/user)
	var/obj/S = pick(crowbar_salvage)
	if(!S)
		return
	S.loc = get_turf(user)
	crowbar_salvage -= S
	user.visible_message("[user] pries [S] from [src].", "You pry [S] from [src].")
