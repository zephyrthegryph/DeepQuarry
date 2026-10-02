/*
 * Source-keyed CANPUSH suppression for mobs (rewrite/mobsrc, on the OM contribution store).
 *
 * status_flags's CANPUSH bit used to be flipped directly by whichever single caller last
 * touched it -- most notably robot modules (robot_modules/station.dm), which cleared it on
 * install and blindly OR'd it back on removal, clobbering any other source that also wanted
 * the mob unpushable. Each source now holds EFFECT_UNPUSHABLE on the mob under its own key
 * (object_model_core.md §8: overridable state changes only through hold/release), and CANPUSH
 * is derived from the combined value: cleared while any source holds it, restored when the
 * last one releases.
 */

/// Marks `source_key` as wanting this mob to be unpushable. Safe to call repeatedly.
/mob/living/proc/add_push_disable_source(source_key)
	om_hold(src, EFFECT_UNPUSHABLE, src, TRUE, source_key)
	sync_push_flag()

/// Withdraws `source_key`'s objection. CANPUSH comes back only once every source has withdrawn.
/mob/living/proc/remove_push_disable_source(source_key)
	om_release(src, EFFECT_UNPUSHABLE, src, source_key)
	sync_push_flag()

/// CANPUSH follows EFFECT_UNPUSHABLE.
/mob/living/proc/sync_push_flag()
	if(om_has(src, EFFECT_UNPUSHABLE))
		set_status_flags(status_flags & ~CANPUSH)
	else
		set_status_flags(status_flags | CANPUSH)
