/obj/item/juke_remote/get_mechanics_info(list/additional_information)
	return ..(list("Plays only while set down in the world, not while held. Music plays by AREA, not by range; one speaker covers one area.") + additional_information)

/obj/item/juke_remote
	name ="\improper BoomTown cordless speaker"
	desc = "Once paired with a jukebox, this speaker can relay the tunes elsewhere!"

	description_fluff = "The BoomTown cordless speaker is capable of maintaining a high-quality 49kbps audio stream from a stationary jukebox and relaying the sound locally. It's like magic!"

	icon = 'icons/obj/device.dmi'
	icon_state = "bspeaker"

	var/tmp/obj/machinery/media/jukebox/paired_juke
	var/tmp/area/our_area

// Pairing
/obj/item/juke_remote/proc/pair_juke(obj/machinery/media/jukebox/juke, mob/user)
	if(paired_juke())
		to_chat(user, span_warning("The [src] is already paired to [paired_juke() == juke ? "that" : "a different"] jukebox."))
		return
	rel_set(src, "paired_juke", juke) // also lists us in the jukebox's remotes (REL_PAIR)
	to_chat(user, span_notice("You pair the [src] to the [juke]."))
	icon_state = "[initial(icon_state)]_ready"

/obj/item/juke_remote/proc/unpair_juke(mob/user)
	if(!paired_juke())
		to_chat(user, span_warning("The [src] isn't paired to anything."))
		return
	rel_clear(src, "paired_juke")
	icon_state = initial(icon_state)
	unanchor()
	detach_area()
	to_chat(user, span_notice("You unpair the [src]."))
	icon_state = "[initial(icon_state)]"

/obj/item/juke_remote/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	if(istype(target, /obj/machinery/media/jukebox))
		pair_juke(target, user)
		return
	return ..()

/// Old Reset Pairing verb: Unpair this speaker from a jukebox.
/obj/item/juke_remote/proc/juke_remote_verb_reset(mob/user, obj/item/held, datum/interaction/interaction)
	unpair_juke(user)

// Deploying
/obj/item/juke_remote/Moved(atom/old_loc, direction, forced)
	. = ..()
	if(paired_juke() && !anchored && isturf(loc))
		anchor()

DECLARE_INTERACTIONS(/obj/item/juke_remote, \
	INTERACT_HAND(null, PROC_REF(interaction_hand)), \
	INTERACT_VERB("Reset Pairing", PROC_REF(juke_remote_verb_reset), REQ_IN_INVENTORY), \
)

/// Old attack_hand.
/obj/item/juke_remote/proc/interaction_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(anchored)
		unanchor()
	return FALSE

/obj/item/juke_remote/proc/anchor()
	if(anchored)
		return
	anchored = TRUE
	if(attach_area())
		visible_message("[src] attaches to the nearest surface and bounces happily, ready to pump tunes.", runemessage = "clank")
		if(paired_juke()) // we were able to claim the area
			icon_state = "[initial(icon_state)]_playing"
		else
			icon_state = "[initial(icon_state)]"

/obj/item/juke_remote/proc/unanchor()
	detach_area()
	anchored = FALSE
	visible_message("[src] detaches from it's mounting surface, able to be moved once again.", runemessage = "clunk")
	if(paired_juke())
		icon_state = "[initial(icon_state)]_ready"
	else
		icon_state = "[initial(icon_state)]"

// Area handling
/obj/item/juke_remote/proc/attach_area()
	var/area/A = get_area(src)
	if(!A || !paired_juke())
		log_mapping("## ERROR Jukebox remote at [x],[y],[z] without paired juke tried to bind to an area.")
		return FALSE
	if(A.media_source())
		return FALSE // Already has a media source, won't overpower it with porta speaker
	our_area = A
	rel_set(A, "media_source", paired_juke())
	update_music()
	return TRUE

/obj/item/juke_remote/proc/detach_area()
	if(!our_area() || (paired_juke() && our_area().media_source() != paired_juke()))
		return
	rel_clear(our_area(), "media_source")
	update_music()
	our_area = null

// Music handling
/obj/item/juke_remote/proc/update_music()
	if(!our_area() || !paired_juke())
		return
	// Send update to clients.
	for(var/mob/M in mobs_in_area(our_area()))
		if(M?.client)
			M.update_music()

/// The area the speaker plays in (a plain var: areas never die).
/obj/item/juke_remote/proc/our_area() as /area
	return our_area

/// the paired_juke this refers to (a relation view: null once it is deleted).
/obj/item/juke_remote/proc/paired_juke() as /obj/machinery/media/jukebox
	return paired_juke

/// A paired speaker and its jukebox name each other; either one dying unpairs them.
REL_PAIR(/obj/item/juke_remote, paired_juke, remotes)
REL_PAIR_LIST(/obj/machinery/media/jukebox, remotes, paired_juke)
