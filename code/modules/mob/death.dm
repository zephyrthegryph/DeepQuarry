/// The one body-destruction path behind gib(), dust() and ash(): kill the mob, hide it behind
/// an animation overlay flicking `anim` from `anim_file`, leave `remains` (a type) and optionally
/// gibs, ghostize, then delete the overlay and the body after DISINTEGRATE_DELAY. Subtypes
/// customise through their gib()/dust()/ash() overrides, which end by calling ..().
#define DISINTEGRATE_DELAY (1.5 SECONDS)
/mob/proc/disintegrate(anim, remains, do_gibs, anim_file = 'icons/mob/mob.dmi')
	// Everything deleted on the way is destroyed as one batch (batch.dm).
	dq_destroy_collect_begin()
	if(stat != DEAD)
		death(1)
	set_transforming(1)
	canmove = 0
	icon = null
	invisibility = INVISIBILITY_ABSTRACT
	update_canmove()
	registry_leave(REGISTRY_DEAD_MOBS, src)

	var/atom/movable/overlay/animation = new(loc)
	animation.icon_state = "blank"
	animation.icon = anim_file
	rel_set(animation, nameof(animation.master), src)
	flick(anim, animation)

	if(remains)
		new remains(loc)
	if(do_gibs)
		gibs(loc, dna)

	if(!QDELETED(src))
		ghostize()
	dq_destroy_collect_end()

	animation.expire(DISINTEGRATE_DELAY)
	// The body and whatever is still inside it go as one batched destroy.
	after(src, DISINTEGRATE_DELAY, /datum/proc/om_qdel_batch_self)
#undef DISINTEGRATE_DELAY

/// Gib: burst into gibs. Cannot gib ghosts.
/mob/proc/gib(anim="blank", do_gibs, gib_file = 'icons/mob/mob.dmi')
	disintegrate(anim, null, do_gibs, gib_file)

/// Dust: crumble into `remains`. Dusting robots does not eject the MMI.
/mob/proc/dust(anim="dust-m",remains=/obj/effect/decal/cleanable/ash)
	disintegrate(anim, remains, FALSE)

/// Ash: burn away with no remains of its own.
/mob/proc/ash(anim="dust-m")
	disintegrate(anim, null, FALSE)

// --- The death pipeline ----------------------------------------------------------------------
// death() is the one way a mob dies, and it is sealed: subtypes contribute through the hooks
// below (replace_death, death_message, death_links, play_death_sound, on_death) and listeners
// through /datum/om/event/mob_death / /datum/om/event/world_mob_death (OM_EMIT_WORLD). The order is fixed:
//   1. guard       - already dead or deleted: return FALSE with no side effects;
//   2. replace     - replace_death() lets a mob end some other way (vanish, split, retreat);
//   3. transition  - the one set_stat(DEAD), time of death, the living/dead lists;
//   4. effects     - message, soul links / nests / vore flags, sound, senses, drops, diseases,
//                    mind memory, respawn timer;
//   5. signals     - /datum/om/event/mob_death, then /datum/om/event/world_mob_death (OM_EMIT_WORLD);
//   6. on_death()  - subtype contributions (loot, remains, verbs, qdel);
//   7. refresh     - HUD, icon and vision (skipped when on_death() deleted the mob);
//   8. antag       - the game mode's win check;
//   9. final       - /datum/om/event/living_death_final, once, after everything above.
// The way back is /mob/living/proc/return_from_death() (code/modules/body/revival.dm).

/// Kill this mob. Returns TRUE if it went from alive to dead, FALSE otherwise (already dead,
/// deleted, or replace_death() took over). `deathmessage` overrides get_death_message(gibbed).
/mob/proc/death(gibbed, deathmessage)
	SHOULD_NOT_OVERRIDE(TRUE)
	// 1. Guard. A repeated call must not repeat any side effect.
	if(stat == DEAD || QDELETED(src))
		return FALSE

	// 2. A mob that ends some other way takes over here and never becomes DEAD through us.
	if(replace_death(gibbed))
		if(mind || ckey)
			log_game("DEATH: [key_name(src)] ([type]) replaced death at [AREACOORD(src)].")
		return FALSE

	var/mob/living/simple_mob/animal/borer/has_worm = has_brain_worms()
	if(has_worm) // This is our host's problem to deal with
		has_worm.detatch()

	if(isnull(deathmessage))
		deathmessage = get_death_message(gibbed)
	if(death_message_suppressed())
		deathmessage = DEATHGASP_NO_MESSAGE

	// 3. The one stat transition.
	set_stat(DEAD)
	EXPIRY_STAMP(src, timeofdeath, CLOCK_WORLD)
	if(isliving(src))
		var/mob/living/dead_living = src
		dead_living.identity()?.time_of_death = EXPIRY_AT(null, CLOCK_WORLD, 0)
	registry_leave(REGISTRY_LIVING_MOBS, src)
	registry_join(REGISTRY_DEAD_MOBS, src)
	if(mind || ckey)
		log_game("DEATH: [key_name(src)] ([type]) died[gibbed ? " (gibbed)" : ""] at [AREACOORD(src)].")

	// 4. Ordered side effects.
	facing_dir = null
	if(!gibbed && deathmessage != DEATHGASP_NO_MESSAGE)
		visible_message(span_infoplain(span_bold("\The [name]") + " [deathmessage]"))
	death_links(gibbed)
	play_death_sound(gibbed)
	SSmotiontracker.ping(src, 80)

	update_canmove()
	layer = MOB_LAYER
	sight |= SEE_TURFS|SEE_MOBS|SEE_OBJS
	see_in_dark = 8
	see_invisible = SEE_INVISIBLE_LEVEL_TWO

	drop_r_hand()
	drop_l_hand()

	for(var/datum/affliction/contagion/D as anything in get_contagions())
		D.OnDeath()

	mind?.store_memory("Time of death: [stationtime2text()]", 0)
	set_respawn_timer()

	// 5. Signals.
	PUBLISH_LEGACY(src, /datum/notice/mob_death, gibbed)
	PUBLISH_LEGACY(OM_WORLD, /datum/notice/world_mob_death, src, gibbed)

	// 6. Subtype contributions.
	on_death(gibbed)

	// 7. Refresh what the dead mob shows and sees.
	if(!QDELETED(src))
		if(healths)
			healths.overlays = null
			healths.icon_state = "health6"
		// The HUD and sight follow set_stat(DEAD) by themselves (it published nameof(stat)).
		update_icon()

	// 8. Antagonist bookkeeping.
	SSticker?.mode?.check_win()

	// 9. Final: every side effect is done. The destroy framework's delete_on_death hangs here
	// (lifecycle_on_death_finalized(), code/datums/lifecycle/verbs.dm), after the listeners.
	PUBLISH_LEGACY(src, /datum/notice/living_death_final, gibbed)
	if(isliving(src) && !QDELETED(src))
		var/mob/living/finalized = src
		finalized.lifecycle_on_death_finalized()
	return TRUE

/// Return TRUE to end this mob some other way instead of dying (it vanishes, splits, retreats).
/// Runs after the guard and before any side effect; the mob must not become DEAD through death().
/mob/proc/replace_death(gibbed)
	return FALSE

/// The visible death message ("\The [src] <message>"), or DEATHGASP_NO_MESSAGE.
/mob/proc/get_death_message(gibbed)
	return death_message

/// A mob dies quietly when the thing holding it says so (muffles_death_of()): the core asks
/// its container instead of knowing every kind of container.
/mob/proc/death_message_suppressed()
	return loc?.muffles_death_of(src)

/// Does this container keep `occupant`'s death message quiet? Bellies, sleepers, shoes and a
/// transformation holder answer TRUE.
/atom/proc/muffles_death_of(mob/occupant)
	return FALSE

/// Does being here numb `occupant`'s pain? Asked by can_feel_pain(); digesting bellies and
/// enzyme pools answer for occupants who opted out of digestion pain.
/atom/proc/numbs_pain_of(mob/living/occupant)
	return FALSE

/mob/living/muffles_death_of(mob/occupant)
	return tf_mob_holder == occupant

/// Notify what this mob is bound to: soul links, nests, vore death flags. Runs once per death.
/mob/proc/death_links(gibbed)
	return

/// The death sound. Runs once per death.
/mob/proc/play_death_sound(gibbed)
	return

/// Subtype contributions to death: remains, loot, verbs, machinery. The mob is already DEAD and
/// listed as dead. It may qdel itself; the pipeline checks for that afterwards.
/mob/proc/on_death(gibbed)
	SHOULD_CALL_PARENT(TRUE)
	return
