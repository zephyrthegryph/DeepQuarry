// Emag as an interaction (doc/rewrite/systems.md section 13, macros in code/__defines/sys_emag.dm).

TYPE_TABLE_DECLARE(/atom, emag_decl, null)

/**
 * Emags `target`: runs its declared effect with `remaining_charges` uses on offer.
 * Returns the uses consumed, or EMAG_DECLINED when the target declares no emag, refuses
 * this one, or (gated) is already emagged. The one entry point for every emag, card or not.
 */
/proc/emag_target(atom/target, remaining_charges = 1, mob/user, obj/item/emag_source)
	if(QDELETED(target))
		return EMAG_DECLINED
	var/list/decl = EMAG_DECL(target)
	if(!decl)
		return EMAG_DECLINED
	var/gated = decl[EMAG_DECL_GATED]
	if(gated && dq_req_field_value(target, "emagged"))
		return EMAG_DECLINED
	var/used = call(target, decl[EMAG_DECL_PROC])(remaining_charges, user, emag_source)
	if(used == EMAG_DECLINED)
		return EMAG_DECLINED
	used = isnum(used) ? max(used, 0) : 0
	if(used && !QDELETED(target))
		if(gated)
			emag_mark_emagged(target)
		if(user && decl[EMAG_DECL_MSG])
			to_chat(user, span_warning(decl[EMAG_DECL_MSG]))
	return used

/// Sets the `emagged` field after a gated emag, through the setter where the field has one.
/proc/emag_mark_emagged(atom/target)
	if(ismachinery(target))
		var/obj/machinery/machine = target
		machine.set_emagged(TRUE)
		return
	if(!target.vars["emagged"])
		target.vars["emagged"] = TRUE

/// The Emag interaction target offers, or null when it declares no emag.
/proc/emag_interaction_for(atom/target)
	var/list/decl = EMAG_DECL(target)
	if(!decl)
		return null
	return decl[EMAG_DECL_GATED] ? INTERACTION(/datum/interaction/emag/gated) : INTERACTION(/datum/interaction/emag)

/// Used with a cryptographic sequencer: the target's declared emag effect (DECLARE_EMAG_REPEATABLE).
/// Added to every declaring type's candidates by build_interaction_candidates().
/datum/interaction/emag
	id = "emag"
	name = "Emag"
	category = INTERACTION_CAT_LOCK
	entry = INTERACTION_ENTRY_ITEM
	default_action = INPUT_ACTION_USE
	/// Ahead of the target's own item interactions, as the card acted before the target's attackby.
	priority = 50
	held_type = /obj/item/card/emag
	requires = list(REQ_INTERACTION_REACH)

/datum/interaction/emag/applies_to(atom/target)
	var/list/decl = EMAG_DECL(target)
	return decl && !decl[EMAG_DECL_GATED]

/datum/interaction/emag/run_effect(mob/actor, atom/target, obj/item/held)
	var/obj/item/card/emag/card = held
	if(!istype(card) || !card.can_emag(actor))
		return FALSE
	var/used = emag_target(target, card.uses, actor, card)
	if(used == EMAG_DECLINED)
		return FALSE
	card.spend(actor, target, used)
	return TRUE

/// DECLARE_EMAG: the same, refused once the target is emagged.
/datum/interaction/emag/gated
	id = "emag_gated"
	also_requires = list(REQ_NOT_EMAGGED)

/datum/interaction/emag/gated/applies_to(atom/target)
	var/list/decl = EMAG_DECL(target)
	return decl && decl[EMAG_DECL_GATED]
