// Emag without a card (doc/rewrite/systems.md section 13; the card's own op is "emag.use", code/library/access/emag.dm).

/**
 * Emags `target` without a card: runs its subvert op (the emag() capability). Returns the uses consumed (one), or EMAG_DECLINED when the target
 * declares no emag or its requirements refuse. The one entry point for every cardless emag.
 */
/proc/emag_target(atom/target, remaining_charges = 1, mob/user, obj/item/emag_source)
	if(QDELETED(target))
		return EMAG_DECLINED
	return emag_target_by_capability(target, user)

/// The emag of a target that declares it as a capability (emag(...)): the cardless subversion by key. One use is consumed, or EMAG_DECLINED when the
/// target has none or its requirements refuse.
/proc/emag_target_by_capability(atom/target, mob/user)
	if(!op_known_anywhere(user, target, null, "emag.subvert"))
		return EMAG_DECLINED
	var/datum/op_result/result = perform_op(user, target, "emag.subvert", null, ORIGIN_SYSTEM)
	return result?.outcome == ACT_COMMITTED ? 1 : EMAG_DECLINED
