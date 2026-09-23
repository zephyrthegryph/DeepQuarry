/**
 * Girder construction graph (doc/rewrite/interactions.md §10).
 *
 * The state is worked out from the girder: "displaced" (unanchored),
 * "anchored", "reinforced" (struts secured, `state` 2) and "struts_loose"
 * (`state` 1). Plating it into a wall and adding reinforcement take a stack of
 * material and stay with the stack (attackby); the screwdriver chooses which
 * one a stack does.
 */
/obj/structure/girder
	construction_graph = /datum/construction_graph/girder

/datum/construction_graph/girder
	id = "girder"
	state_var = null
	states = list("displaced", "anchored", "reinforced", "struts_loose")
	initial_states = list("anchored", "displaced", "reinforced")
	edge_types = list(
		/datum/interaction/construction/girder/secure,
		/datum/interaction/construction/girder/dislodge,
		/datum/interaction/construction/girder/disassemble,
		/datum/interaction/construction/girder/toggle_reinforcing,
		/datum/interaction/construction/girder/unsecure_struts,
		/datum/interaction/construction/girder/remove_struts,
	)

/datum/construction_graph/girder/state_of(atom/target)
	var/obj/structure/girder/girder = target
	if(!istype(girder))
		return null
	if(!girder.anchored)
		return "displaced"
	switch(girder.state)
		if(2)
			return "reinforced"
		if(1)
			return "struts_loose"
	return "anchored"

// The girder's own vars hold the state; the edges' effects change them.
/datum/construction_graph/girder/set_state(atom/target, state)
	return

/datum/construction_graph/girder/on_traversed(atom/target, mob/actor, datum/interaction/construction/edge, before, after)
	return

/datum/interaction/construction/girder
	tool_volume = 100

/datum/interaction/construction/girder/secure
	from_state = "displaced"
	to_state = "anchored"
	step_text = "secure the girder"
	tool = TOOL_WRENCH
	duration = 4 SECONDS
	start_self = "Now securing the girder..."
	message_self = "You secured the girder!"

/datum/interaction/construction/girder/secure/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/girder/girder = target
	girder.reset_girder()
	return TRUE

/datum/interaction/construction/girder/dislodge
	from_state = "anchored"
	to_state = "displaced"
	step_text = "dislodge the girder"
	tool = TOOL_CROWBAR
	duration = 4 SECONDS
	start_self = "Now dislodging the girder..."
	message_self = "You dislodged the girder!"

/datum/interaction/construction/girder/dislodge/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/girder/girder = target
	girder.displace()
	return TRUE

/datum/interaction/construction/girder/disassemble
	from_state = "anchored"
	to_state = CONSTRUCTION_DONE
	step_text = "disassemble the girder"
	tool = TOOL_WRENCH
	start_self = "Now disassembling the girder..."
	message_self = "You dissasembled the girder!"

/datum/interaction/construction/girder/disassemble/available_on(atom/target)
	var/obj/structure/girder/girder = target
	return !girder.reinf_material

/// 3.5 seconds plus a tick for every 50 integrity.
/datum/interaction/construction/girder/disassemble/base_duration(mob/actor, atom/target)
	var/obj/structure/girder/girder = target
	return 35 + round(girder.max_integrity / 50)

/datum/interaction/construction/girder/disassemble/duration_for(mob/actor, atom/target, obj/item/held)
	return tool_delay(actor, held, base_duration(actor, target), tool)

/datum/interaction/construction/girder/disassemble/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/girder/girder = target
	girder.dismantle()
	return TRUE

/// Chooses whether a stack of material reinforces the girder or plates it into a wall.
/datum/interaction/construction/girder/toggle_reinforcing
	from_state = "anchored"
	to_state = "anchored"
	step_text = "switch between reinforcing and plating"
	tool = TOOL_SCREWDRIVER
	priority = 5

/datum/interaction/construction/girder/toggle_reinforcing/available_on(atom/target)
	var/obj/structure/girder/girder = target
	return !girder.reinf_material

/datum/interaction/construction/girder/toggle_reinforcing/display_name(mob/actor, atom/target)
	var/obj/structure/girder/girder = target
	return girder.reinforcing ? "Prepare for plating" : "Prepare for reinforcing"

/datum/interaction/construction/girder/toggle_reinforcing/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/girder/girder = target
	girder.reinforcing = !girder.reinforcing
	to_chat(actor, span_notice("\The [girder] can now be [girder.reinforcing ? "reinforced" : "constructed"]!"))
	return TRUE

/datum/interaction/construction/girder/unsecure_struts
	from_state = "reinforced"
	to_state = "struts_loose"
	step_text = "unsecure the support struts"
	tool = TOOL_SCREWDRIVER
	duration = 4 SECONDS
	start_self = "Now unsecuring support struts..."
	message_self = "You unsecured the support struts!"

/datum/interaction/construction/girder/unsecure_struts/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/girder/girder = target
	girder.state = 1
	return TRUE

/datum/interaction/construction/girder/remove_struts
	from_state = "struts_loose"
	to_state = "anchored"
	step_text = "remove the support struts"
	tool = TOOL_WIRECUTTER
	duration = 4 SECONDS
	start_self = "Now removing support struts..."
	message_self = "You removed the support struts!"

/datum/interaction/construction/girder/remove_struts/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/girder/girder = target
	girder.reinf_material.place_dismantled_product(get_turf(girder))
	girder.reinf_material = null
	girder.reset_girder()
	return TRUE

// ---- Cult columns: the wrench takes them apart, nothing else. ----

/obj/structure/girder/cult
	construction_graph = /datum/construction_graph/girder_cult

/datum/construction_graph/girder_cult
	id = "girder_cult"
	state_var = null
	states = list("column")
	initial_states = list("column")
	edge_types = list(/datum/interaction/construction/girder/cult_disassemble)

/datum/construction_graph/girder_cult/state_of(atom/target)
	return istype(target, /obj/structure/girder/cult) ? "column" : null

/datum/construction_graph/girder_cult/set_state(atom/target, state)
	return

/datum/construction_graph/girder_cult/on_traversed(atom/target, mob/actor, datum/interaction/construction/edge, before, after)
	return

/datum/interaction/construction/girder/cult_disassemble
	from_state = "column"
	to_state = CONSTRUCTION_DONE
	step_text = "disassemble the column"
	tool = TOOL_WRENCH
	duration = 4 SECONDS
	start_self = "Now disassembling the girder..."
	message_self = "You disassembled the girder!"

/datum/interaction/construction/girder/cult_disassemble/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/girder/girder = target
	girder.dismantle()
	return TRUE
