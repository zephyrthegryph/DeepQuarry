/**
 * Machinery interactions (I7, doc/rewrite/interactions.md §13).
 *
 * The machinery domain's attackby, attack_hand, click_alt, MouseDrop_T and
 * object verbs are interaction definitions. The abstract types here carry the
 * shared parts:
 *
 * - /datum/interaction/machine_hand: a touch (the old attack_hand). It runs
 *   from /atom/proc/attack_hand, behind /obj/machinery/hand_gate() (power,
 *   posture, dexterity), so every caller of attack_hand (hands, the AI and
 *   cyborgs through silicon_use, telekinesis) still reaches it.
 * - /datum/interaction/machine_item: an item used on the machine (the old
 *   attackby). It runs from /atom/proc/attackby, before the attack chain's
 *   signal, where the override used to run.
 * - /datum/interaction/machine_alt and machine_drag: click_alt and MouseDrop_T.
 * - /datum/interaction/machine_verb: a former object verb, offered in the Menu
 *   and under its category key.
 *
 * Types declare their own interactions before calling ..(), in the order the
 * old handler tested them, so they come before their parents' as an override
 * came before ..().
 */

/// Abstract: a machine's touch, the old attack_hand.
/datum/interaction/machine_hand
	entry = INTERACTION_ENTRY_HAND
	default_action = INPUT_ACTION_USE
	category = INTERACTION_CAT_CONFIGURE
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null))

/// Abstract: a touch whose old attack_hand never called ..(): no gate, so it works unpowered.
/datum/interaction/machine_hand/ungated
	behind_gate = FALSE
	requires = list(REQ_INTERACTION_REACH)

/// Abstract: an item used on a machine, the old attackby.
/datum/interaction/machine_item
	entry = INTERACTION_ENTRY_ITEM
	default_action = INPUT_ACTION_USE
	category = INTERACTION_CAT_INSERT
	requires = list(REQ_INTERACTION_REACH)

/// Abstract: an alt-click on a machine, the old click_alt.
/datum/interaction/machine_alt
	entry = INTERACTION_ENTRY_ALT
	default_action = INPUT_ACTION_ALTERNATE
	category = INTERACTION_CAT_TOGGLE
	requires = list(REQ_INTERACTION_REACH)

/// Abstract: something dragged onto a machine, the old MouseDrop_T. `held` is the dragged atom.
/datum/interaction/machine_drag
	entry = INTERACTION_ENTRY_DRAG
	category = INTERACTION_CAT_INSERT
	requires = list(REQ_INTERACTION_REACH)

/// Abstract: a former object verb. Menu and category key only.
/datum/interaction/machine_verb
	category = INTERACTION_CAT_CONFIGURE
	requires = list(REQ_INTERACTION_REACH, REQ_PROC(/proc/dq_actor_can_act, "you can't do that right now"))

// ---- Requirement clauses ----

/**
 * The machinery hand gate as a requirement, for the Menu and category keys
 * (hand_gate() already ran on the attack_hand path). No side effects: the
 * gate's random neural fumble and its click sound stay in hand_gate().
 */
/obj/machinery/proc/can_operate_by_hand(mob/actor, atom/target, obj/item/held)
	if(!operable(MAINT))
		return "it isn't working"
	if(actor.lying || actor.stat)
		return "you can't reach it like this"
	if(!actor.IsAdvancedToolUser())
		return "you don't have the dexterity"
	return TRUE
