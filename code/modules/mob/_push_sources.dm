/*
 * Source-keyed CANPUSH suppression for mobs.
 *
 * status_flags's CANPUSH bit used to be flipped directly by whichever single
 * caller last touched it -- most notably robot modules
 * (code/modules/mob/living/silicon/robot/robot_modules/station.dm), which
 * cleared it on install and blindly OR'd it back on removal. That's fine as
 * long as exactly one thing on the mob ever cares about pushability, but the
 * unconditional restore clobbers any OTHER concurrently active source that
 * also wants the mob unpushable (a module swap re-enabling pushing out from
 * under, say, an anchoring effect). This gives every such source a key
 * instead: CANPUSH stays cleared as long as at least one source is disabling
 * it, and only gets restored once none are left.
 */

/mob/living
	/// Lazy list of source keys currently suppressing CANPUSH. Absent when
	/// nothing is suppressing pushability.
	var/list/push_disable_sources

/**
 * Marks `source_key` as wanting this mob to be unpushable, clearing
 * status_flags's CANPUSH bit. Safe to call repeatedly with the same key.
 */
/mob/living/proc/add_push_disable_source(source_key)
	LAZYDISTINCTADD(push_disable_sources, source_key)
	status_flags &= ~CANPUSH

/**
 * Withdraws `source_key`'s objection to this mob being pushed. CANPUSH is
 * only restored once every source has withdrawn -- so one source going away
 * never re-enables pushing while another is still active.
 */
/mob/living/proc/remove_push_disable_source(source_key)
	if(!LAZYLEN(push_disable_sources))
		return
	LAZYREMOVE(push_disable_sources, source_key)
	if(!LAZYLEN(push_disable_sources))
		push_disable_sources = null
		status_flags |= CANPUSH
