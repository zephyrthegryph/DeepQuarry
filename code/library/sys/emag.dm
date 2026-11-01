// Emag by key (doc/rewrite/final_api.html section 11, the emag capability in code/library/access/emag.dm).

/**
 * Emags `target` with no card in hand: runs the "emag.subvert" op of its emag capability with `remaining_charges` uses on offer.
 * Returns the uses consumed (one), or EMAG_DECLINED when the target declares no emag, refuses this one, or was subverted already.
 * The one entry point for every emag that is not a card swipe (an event, a changeling's pick, a pAI toolkit, a spirit).
 */
/proc/emag_target(atom/target, remaining_charges = 1, mob/user, obj/item/emag_source)
	if(QDELETED(target))
		return EMAG_DECLINED
	if(!op_known_anywhere(user, target, null, "emag.subvert"))
		return EMAG_DECLINED
	var/datum/op_result/result = perform_op(user, target, "emag.subvert", null, ORIGIN_SYSTEM)
	return result?.outcome == ACT_COMMITTED ? 1 : EMAG_DECLINED
