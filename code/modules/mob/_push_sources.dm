/*
 * Source-held CANPUSH suppression for mobs: the stat unpushable.
 *
 * status_flags's CANPUSH bit used to be flipped directly by whichever single caller last touched it -- most notably robot
 * modules (robot_modules/station.dm), which cleared it on install and blindly OR'd it back on removal, clobbering any other
 * source that also wanted the mob unpushable. Each source holds unpushable (ANY) on the mob, and CANPUSH is derived from it:
 * cleared while any source holds it, restored when the last one releases.
 */

STAT(/mob/living, unpushable, ANY, virtual = TRUE)
SOURCE_DEF(push_robot_module)

/// Marks `source` (an SRC_PUSH_* id or a datum) as wanting this mob to be unpushable. Safe to call repeatedly.
/mob/living/proc/add_push_disable_source(source)
	hold(src, STAT_UNPUSHABLE, TRUE, source)
	sync_push_flag()

/// Withdraws `source`'s objection. CANPUSH comes back only once every source has withdrawn.
/mob/living/proc/remove_push_disable_source(source)
	release(src, STAT_UNPUSHABLE, source)
	sync_push_flag()

/// CANPUSH follows the unpushable stat.
/mob/living/proc/sync_push_flag()
	if(stat_value(src, STAT_UNPUSHABLE))
		set_status_flags(status_flags & ~CANPUSH)
	else
		set_status_flags(status_flags | CANPUSH)
