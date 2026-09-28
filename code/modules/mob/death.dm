//This is the proc for gibbing a mob. Cannot gib ghosts.
//added different sort of gibs and animations. N
/mob/proc/gib(anim="blank", do_gibs, gib_file = 'icons/mob/mob.dmi')
	// Everything the gib deletes on the way is destroyed as one batch (batch.dm).
	dq_destroy_collect_begin()
	if(stat != DEAD)
		death(1)
	transforming = 1
	canmove = 0
	icon = null
	invisibility = INVISIBILITY_ABSTRACT
	update_canmove()
	registry_leave(REGISTRY_DEAD_MOBS, src)

	var/atom/movable/overlay/animation = null
	animation = new(loc)
	animation.icon_state = "blank"
	animation.icon = gib_file
	animation.master = src

	flick(anim, animation)
	if(do_gibs) gibs(loc, dna)

	if (!QDELETED(src))
		ghostize()
	dq_destroy_collect_end()

	om_qdel_after(animation, 15)
	// The body and whatever is still inside it go as one batched destroy.
	om_after(src, 15, /datum/proc/om_qdel_batch_self)

//This is the proc for turning a mob into ash. Mostly a copy of gib code (above).
//Originally created for wizard disintegrate. I've removed the virus code since it's irrelevant here.
//Dusting robots does not eject the MMI, so it's a bit more powerful than gib() /N
/mob/proc/dust(anim="dust-m",remains=/obj/effect/decal/cleanable/ash)
	death(1)
	var/atom/movable/overlay/animation = null
	transforming = 1
	canmove = 0
	icon = null
	invisibility = INVISIBILITY_ABSTRACT

	animation = new(loc)
	animation.icon_state = "blank"
	animation.icon = 'icons/mob/mob.dmi'
	animation.master = src

	flick(anim, animation)
	new remains(loc)

	registry_leave(REGISTRY_DEAD_MOBS, src)

	if (!QDELETED(src))
		ghostize()

	om_qdel_after(animation, 15)
	om_qdel_after(src, 15)

/mob/proc/ash(anim="dust-m")
	death(1)
	var/atom/movable/overlay/animation = null
	transforming = 1
	canmove = 0
	icon = null
	invisibility = INVISIBILITY_ABSTRACT

	animation = new(loc)
	animation.icon_state = "blank"
	animation.icon = 'icons/mob/mob.dmi'
	animation.master = src

	flick(anim, animation)

	registry_leave(REGISTRY_DEAD_MOBS, src)

	if (!QDELETED(src))
		ghostize()

	om_qdel_after(animation, 15)
	om_qdel_after(src, 15)

// --- The death pipeline ----------------------------------------------------------------------
// death() is the one way a mob dies, and it is sealed: subtypes contribute through the hooks
// below (replace_death, death_message, death_links, play_death_sound, on_death) and listeners
// through COMSIG_MOB_DEATH / COMSIG_GLOB_MOB_DEATH. The order is fixed:
//   1. guard       - already dead or deleted: return FALSE with no side effects;
//   2. replace     - replace_death() lets a mob end some other way (vanish, split, retreat);
//   3. transition  - the one set_stat(DEAD), time of death, the living/dead lists;
//   4. effects     - message, soul links / nests / vore flags, sound, senses, drops, diseases,
//                    mind memory, respawn timer;
//   5. signals     - COMSIG_MOB_DEATH, then COMSIG_GLOB_MOB_DEATH;
//   6. on_death()  - subtype contributions (loot, remains, verbs, qdel);
//   7. refresh     - HUD, icon and vision (skipped when on_death() deleted the mob);
//   8. antag       - the game mode's win check;
//   9. final       - COMSIG_LIVING_DEATH_FINAL, once, after everything above.
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
	timeofdeath = world.time
	if(isliving(src))
		var/mob/living/dead_living = src
		dead_living.identity?.time_of_death = world.time
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
	GLOB.motiontracker_service.ping(src, 80)

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
	SEND_SIGNAL(src, COMSIG_MOB_DEATH, gibbed)
	SEND_GLOBAL_SIGNAL(COMSIG_GLOB_MOB_DEATH, src, gibbed)

	// 6. Subtype contributions.
	on_death(gibbed)

	// 7. Refresh what the dead mob shows and sees.
	if(!QDELETED(src))
		if(healths)
			healths.overlays = null
			healths.icon_state = "health6"
		update_icon()
		refresh_hud()
		refresh_vision()

	// 8. Antagonist bookkeeping.
	SSticker?.mode?.check_win()

	// 9. Final: every side effect is done. The destroy framework's delete_on_death hangs here
	// (lifecycle_on_death_finalized(), code/datums/lifecycle/verbs.dm), after the listeners.
	SEND_SIGNAL(src, COMSIG_LIVING_DEATH_FINAL, gibbed)
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

/// A mob inside something (a belly, a sleeper, a shoe, its own transformation holder) dies quietly.
/mob/proc/death_message_suppressed()
	if(istype(loc, /obj/belly) || istype(loc, /obj/item/dogborg/sleeper) || istype(loc, /obj/item/clothing/shoes))
		return TRUE
	if(isliving(loc))
		var/mob/living/L = loc
		if(L.tf_mob_holder == src)
			return TRUE
	return FALSE

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
