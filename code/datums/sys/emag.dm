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
		return emag_target_by_capability(target, user)
	var/gated = decl[EMAG_DECL_GATED]
	if(gated && dq_req_field_value(target, "emagged"))
		if(user && decl[EMAG_DECL_ALREADY])
			to_chat(user, span_warning(decl[EMAG_DECL_ALREADY]))
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

/// The emag of a target that declares it as a capability (emag(...)): the cardless subversion by key. One use is consumed, or EMAG_DECLINED when the
/// target has none or its requirements refuse.
/proc/emag_target_by_capability(atom/target, mob/user)
	if(!op_known_anywhere(user, target, null, "emag.subvert"))
		return EMAG_DECLINED
	var/datum/op_result/result = perform_op(user, target, "emag.subvert", null, ORIGIN_SYSTEM)
	return result?.outcome == ACT_COMMITTED ? 1 : EMAG_DECLINED

/// Sets the `emagged` field after a gated emag, through the setter where the field has one.
/proc/emag_mark_emagged(atom/target)
	target.mark_emagged()

/// Records a successful gated emag on this atom. Every DECLARE_EMAG type overrides it next to its
/// declaration (machinery through its generated set_emagged() setter).
/atom/proc/mark_emagged()
	CRASH("mark_emagged: [type] declares a gated emag but does not override mark_emagged()")

/obj/machinery/mark_emagged()
	set_emagged(TRUE)

/// The legacy Emag interaction a DECLARE_EMAG target offers, or null when it declares none. A type that declares the emag capability
/// (emag(...) in its CAPABILITIES) has no interaction: its card op is "emag.use" (perform_op(user, target, "emag.use", card)).
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
	effect = /atom/proc/emag_interaction_effect

/datum/interaction/emag/applies_to(atom/target)
	var/list/decl = EMAG_DECL(target)
	return decl && !decl[EMAG_DECL_GATED]

/// The Emag interaction's effect, on the target (like every interaction effect): runs its declared
/// emag with the card's remaining uses and spends what it consumed.
/atom/proc/emag_interaction_effect(mob/actor, obj/item/held, datum/interaction/interaction)
	var/obj/item/card/emag/card = held
	if(!istype(card) || !card.can_emag(actor))
		return FALSE
	var/used = emag_target(src, card.uses, actor, card)
	if(used == EMAG_DECLINED)
		return FALSE
	card.spend(actor, src, used)
	return TRUE

/// DECLARE_EMAG: the same, refused once the target is emagged.
/datum/interaction/emag/gated
	id = "emag_gated"
	also_requires = list(REQ_NOT_EMAGGED)

/// The type's own "already" text (DECLARE_EMAG's ALREADY) in place of the generic refusal.
/datum/interaction/emag/gated/tell_blocked(mob/actor, atom/target, reason)
	var/list/decl = EMAG_DECL(target)
	if(decl?[EMAG_DECL_ALREADY] && dq_req_field_value(target, "emagged"))
		to_chat(actor, span_warning(decl[EMAG_DECL_ALREADY]))
		return
	return ..()

/datum/interaction/emag/gated/applies_to(atom/target)
	var/list/decl = EMAG_DECL(target)
	return decl && decl[EMAG_DECL_GATED]
