/**
 * Abstract parents for converted legacy handlers (I7, doc/rewrite/interactions.md §13).
 *
 * Each old override became an interaction that runs from the old proc, now
 * the entry point (see run_interaction_entry()):
 * - entry_item: attackby. Runs from /atom/proc/attackby, before the signal.
 * - entry_hand: attack_hand. Runs from /atom/proc/attack_hand, behind the
 *   type's hand_gate() unless `behind_gate` is FALSE.
 * - entry_alt: click_alt.
 * - entry_drag: MouseDrop_T; `held` is the dragged atom.
 * - entry_self: attack_self; `held` is the item itself.
 * - entry_verb: a former object verb, in the Menu and under its category key.
 *
 * Machinery has its own parents with the machinery gate as a requirement
 * (code/game/machinery/machinery_interactions.dm).
 */
/datum/interaction/entry_item
	entry = INTERACTION_ENTRY_ITEM
	default_action = INPUT_ACTION_USE
	category = INTERACTION_CAT_INSERT
	requires = list(REQ_INTERACTION_REACH)

/datum/interaction/entry_hand
	entry = INTERACTION_ENTRY_HAND
	default_action = INPUT_ACTION_USE
	category = INTERACTION_CAT_OPEN
	requires = list(REQ_INTERACTION_REACH)

/// A touch whose old attack_hand never called ..(): no gate, no signal, no unbuckling first.
/datum/interaction/entry_hand/ungated
	behind_gate = FALSE

/datum/interaction/entry_alt
	entry = INTERACTION_ENTRY_ALT
	default_action = INPUT_ACTION_ALTERNATE
	category = INTERACTION_CAT_TOGGLE
	requires = list(REQ_INTERACTION_REACH)

/datum/interaction/entry_drag
	entry = INTERACTION_ENTRY_DRAG
	category = INTERACTION_CAT_INSERT
	requires = list(REQ_INTERACTION_REACH)

/datum/interaction/entry_self
	entry = INTERACTION_ENTRY_SELF
	default_action = INPUT_ACTION_USE
	category = INTERACTION_CAT_TOGGLE
	requires = list(REQ_TARGET_IN_HAND)

/datum/interaction/entry_verb
	category = INTERACTION_CAT_CONFIGURE
	requires = list(REQ_INTERACTION_REACH, REQ_PROC(/proc/dq_actor_can_act, "you can't do that right now"))

/// Requirement clause: the actor is alive, conscious and not incapacitated (the old verbs' usr checks).
/proc/dq_actor_can_act(mob/actor, atom/target, obj/item/held)
	if(!isliving(actor))
		return FALSE
	return !actor.incapacitated()
