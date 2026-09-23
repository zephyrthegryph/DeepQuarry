/**
 * Window construction graph (doc/rewrite/interactions.md §10).
 *
 * The state id is worked out from the window: "u" or "a" (unanchored or
 * anchored), followed for reinforced windows by `state`: 0 out of its frame,
 * 1 pried into the frame, 2 fastened to it. So a plain window is "u" or "a",
 * a mapped reinforced window "a2". Welding cracks out is a repair
 * interaction, not a step.
 */
/obj/structure/window
	construction_graph = /datum/construction_graph/window

/datum/construction_graph/window
	id = "window"
	state_var = null
	states = list("u", "a", "u0", "a0", "u1", "a1", "u2", "a2")
	initial_states = list("u", "a", "u0", "a2")

/datum/construction_graph/window/build()
	// Plain windows: screw to the floor and back; unscrewed, the wrench takes them apart.
	add_window_edge(/datum/interaction/construction/window/anchor, "u", "a")
	add_window_edge(/datum/interaction/construction/window/anchor, "a", "u")
	add_window_edge(/datum/interaction/construction/window/dismantle, "u", CONSTRUCTION_DONE)
	// Reinforced: the same out of the frame, plus prying in and out of the frame and fastening to it.
	add_window_edge(/datum/interaction/construction/window/anchor, "u0", "a0")
	add_window_edge(/datum/interaction/construction/window/anchor, "a0", "u0")
	add_window_edge(/datum/interaction/construction/window/dismantle, "u0", CONSTRUCTION_DONE)
	for(var/anchor in list("u", "a"))
		add_window_edge(/datum/interaction/construction/window/pry, "[anchor]0", "[anchor]1")
		add_window_edge(/datum/interaction/construction/window/pry, "[anchor]1", "[anchor]0")
		add_window_edge(/datum/interaction/construction/window/fasten, "[anchor]1", "[anchor]2")
		add_window_edge(/datum/interaction/construction/window/fasten, "[anchor]2", "[anchor]1")

/datum/construction_graph/window/proc/add_window_edge(path, from_id, to_id)
	var/datum/interaction/construction/window/edge = new path
	edge.from_state = from_id
	edge.to_state = to_id
	edge.step_text = edge.step_text_for(from_id, to_id)
	return add_edge(edge)

/datum/construction_graph/window/state_of(atom/target)
	var/obj/structure/window/window = target
	if(!istype(window))
		return null
	return "[window.anchored ? "a" : "u"][window.reinf ? window.state : ""]"

/datum/construction_graph/window/set_state(atom/target, state)
	var/obj/structure/window/window = target
	if(!istype(window) || state == CONSTRUCTION_DONE)
		return
	window.anchored = copytext(state, 1, 2) == "a"
	if(window.reinf)
		window.state = text2num(copytext(state, 2))

/datum/construction_graph/window/on_traversed(atom/target, mob/actor, datum/interaction/construction/edge, before, after)
	return

/// A welder off help intent hits the window instead of repairing it.
/obj/structure/window/interaction_tool_act(mob/user, obj/item/tool, quality)
	if(quality == TOOL_WELDER && !IS_HELPING(user))
		return NONE
	return ..()

/datum/interaction/construction/window
	tool_volume = 75

/datum/interaction/construction/window/proc/step_text_for(from_id, to_id)
	return step_text

/// Screw the window (or a reinforced window's frame) to the floor, or free it.
/datum/interaction/construction/window/anchor
	tool = TOOL_SCREWDRIVER

/datum/interaction/construction/window/anchor/step_text_for(from_id, to_id)
	return copytext(to_id, 1, 2) == "a" ? "screw it to the floor" : "unscrew it from the floor"

/datum/interaction/construction/window/anchor/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/window/window = target
	window.update_nearby_tiles(need_rebuild = TRUE)
	window.update_nearby_icons()
	window.update_verbs()
	to_chat(actor, span_notice("You have [window.anchored ? "" : "un"]fastened the [window.reinf ? "frame" : "window"] [window.anchored ? "to" : "from"] the floor."))
	return TRUE

/// Pry a reinforced window into its frame, or out of it.
/datum/interaction/construction/window/pry
	tool = TOOL_CROWBAR

/datum/interaction/construction/window/pry/step_text_for(from_id, to_id)
	return copytext(to_id, 2) == "1" ? "pry the window into the frame" : "pry the window out of the frame"

/datum/interaction/construction/window/pry/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/window/window = target
	to_chat(actor, span_notice("You have pried the window [window.state ? "into" : "out of"] the frame."))
	return TRUE

/// Fasten a reinforced window to its frame, or unfasten it.
/datum/interaction/construction/window/fasten
	tool = TOOL_SCREWDRIVER

/datum/interaction/construction/window/fasten/step_text_for(from_id, to_id)
	return copytext(to_id, 2) == "2" ? "fasten the window to the frame" : "unfasten the window from the frame"

/datum/interaction/construction/window/fasten/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/window/window = target
	window.update_nearby_icons()
	to_chat(actor, span_notice("You have [window.state == 1 ? "un" : ""]fastened the window [window.state ? "from" : "to"] the frame."))
	return TRUE

/// Take a loose window apart into its glass: one sheet, four for a full tile.
/datum/interaction/construction/window/dismantle
	tool = TOOL_WRENCH
	step_text = "dismantle the window"
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/structure/window/proc/can_dismantle, "you're not sure how to dismantle it properly"))

/datum/interaction/construction/window/dismantle/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/window/window = target
	window.visible_message(span_notice("[actor] dismantles \the [window]."))
	var/obj/item/stack/material/mats = new window.glasstype(window.loc)
	if(window.is_fulltile())
		mats.set_amount(4)
	qdel(window)
	return TRUE

/obj/structure/window/proc/can_dismantle(mob/actor, atom/target, obj/item/held)
	return glasstype ? TRUE : FALSE

// ---- Repair ----

/obj/structure/window/declare_interactions(list/into)
	..()
	into += /datum/interaction/window_repair

/datum/interaction/window_repair
	id = "window_repair"
	name = "Repair the window"
	category = INTERACTION_CAT_REPAIR
	priority = 20
	default_action = INPUT_ACTION_USE
	tool = TOOL_WELDER
	tool_amount = 1
	duration = 4 SECONDS
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/structure/window/proc/is_damaged, "it is already in good condition"))
	effect = /obj/structure/window/proc/weld_repair
	message_self = "You repair %TARGET%."

/datum/interaction/window_repair/start_messages(mob/actor, atom/target, obj/item/held)
	return list("You begin repairing %TARGET%...", null)

/obj/structure/window/proc/is_damaged(mob/actor, atom/target, obj/item/held)
	return get_integrity() < max_integrity

/obj/structure/window/proc/weld_repair(mob/actor, obj/item/held, datum/interaction/interaction)
	repair_damage(max_integrity)
	update_icon()
	return TRUE
