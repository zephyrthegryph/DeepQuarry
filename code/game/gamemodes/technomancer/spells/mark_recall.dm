/datum/technomancer/spell/mark
	name = "Mark"
	desc = "This function places a specific 'mark' beacon under you, which is used by the Recall function as a destination.  \
	Note that using Mark again will move the destination instead of creating a second destination, and only one destination \
	can exist, regardless of who casted Mark."
	cost = 25
	obj_path = /obj/item/spell/mark
	ability_icon_state = "tech_mark"
	category = UTILITY_SPELLS
// Multiple technomancer support
/datum/technomancer_marker
	/// Who placed the mark: a relation view.
	var/mob/caster
	var/image/I
	var/turf/T

/datum/technomancer_marker/New(mob/user)
	rel_set(src, nameof(caster), user)
	rel_set(src, nameof(T), get_turf(user))
	I = image('icons/goonstation/featherzone.dmi', T(), "spawn-wall")
	I.plane = TURF_PLANE
	I.layer = ABOVE_TURF_LAYER
	user.client?.images |= I
	after(src, 2.3 SECONDS, PROC_REF(loop_animation)) //That's just how long the animation is

// the marker image comes off its caster's client.
/datum/technomancer_marker/lifecycle_prerelease()
	..()
	caster?.client?.images -= I
	image_anchor(I, null)

//This is global, to avoid looping through a list of all objects, or god forbid, looping through world.
/// Every placed mark (owned by the antag service); one per caster.
/datum/system/antag/var/list/datum/technomancer_marker/mark_spells

CAPABILITIES(/datum/system/antag)
	owns_many(nameof(mark_spells), /datum/technomancer_marker)
	owns_many(nameof(all_antag_types))

/// `user`'s placed mark, or null.
/proc/technomancer_marker_of(mob/user)
	for(var/datum/technomancer_marker/marker as anything in antag_mark_spells())
		if(marker.caster == user)
			return marker
	return null
/obj/item/spell/mark
	name = "mark"
	icon_state = "mark"
	desc = "Marks a specific location to be used by Recall."
	cast_methods = CAST_USE
	aspect = ASPECT_TELE

/obj/item/spell/mark/on_use_cast(mob/living/user)
	if(!allowed_to_teleport()) // Otherwise you could teleport back to the admin Z-level.
		to_chat(user, span_warning("You can't teleport here!"))
		return 0
	if(pay_energy(1000))
		// Multiple technomancer support
		var/datum/technomancer_marker/marker = technomancer_marker_of(user)
		//They have one in the list
		if(istype(marker))
			own_remove(SSantag, nameof(/datum/system/antag::mark_spells), marker)
			to_chat(user, span_notice("Your mark is moved from its old position to \the [get_turf(user)] under you."))
		//They don't have one yet
		else
			to_chat(user, span_notice("You mark \the [get_turf(user)] under you."))
		rel_add(SSantag, nameof(/datum/system/antag::mark_spells), new /datum/technomancer_marker(user))
		adjust_instability(5)
		return 1
	else
		to_chat(user, span_warning("You can't afford the energy cost!"))
		return 0

//Recall

/datum/technomancer/spell/recall
	name = "Recall"
	desc = "This function teleports you to where you placed a mark using the Mark function.  Without the Mark function, this \
	function is useless.  Note that teleporting takes three seconds.  Being incapacitated while teleporting will cancel it."
	enhancement_desc = "Recall takes two seconds instead of three."
	cost = 25
	obj_path = /obj/item/spell/recall
	ability_icon_state = "tech_recall"
	category = UTILITY_SPELLS

/obj/item/spell/recall
	name = "recall"
	icon_state = "recall"
	desc = "This will bring you to your Mark."
	cast_methods = CAST_USE
	aspect = ASPECT_TELE

/obj/item/spell/recall/on_use_cast(mob/living/user)
	if(pay_energy(3000))
		var/datum/technomancer_marker/marker = technomancer_marker_of(user) // Multiple technomancer support
		if(!istype(marker))
			to_chat(user, span_danger("There's no Mark!"))
			return 0
		else
			if(!allowed_to_teleport())
				to_chat(user, span_warning("Teleportation doesn't seem to work here."))
				return
			act_message(user, null, others = span_warning("%U% starts glowing!"))
			recall_glow(user, marker, check_for_scepter() ? 2 : 3, 3)
			return 1
	else
		to_chat(user, span_warning("You can't afford the energy cost!"))
		return 0

/datum/technomancer_marker/proc/loop_animation()
	I.icon_state = "spawn-wall-loop"

/// The glow builds once a second for `time_left` seconds, then the Recall.
/obj/item/spell/recall/proc/recall_glow(mob/living/user, datum/technomancer_marker/marker, time_left, light_intensity)
	if(user.incapacitated())
		act_message(user, null, others = span_notice("%U%'s glow fades."))
		to_chat(user, span_danger("You cannot Recall while incapacitated!"))
		return
	if(time_left > 0)
		set_light(light_intensity, light_intensity, l_color = "#006AFF")
		after(src, 1 SECOND, PROC_REF(recall_glow), with = list(user, marker, time_left - 1, light_intensity + 1))
		return
	var/turf/target_turf = marker.T() // Multiple technomancer support
	var/turf/old_turf = get_turf(user)

	for(var/obj/item/grab/G in contents_of(user)) // People the Technomancer is grabbing come along for the ride.
		var/mob/living/grabbed = G?.grab_target()
		if(grabbed)
			grabbed.forceMove(locate( target_turf.x+rand(-1,1), target_turf.y+rand(-1,1), target_turf.z))
			to_chat(grabbed, span_warning("You are teleported along with [user]!"))

	user.forceMove(target_turf)
	to_chat(user, span_notice("You are teleported to your Mark."))

	play_sfx(target_turf, SFX_EFFECTS_PHASEIN, 0.25)
	play_sfx(target_turf, SFX_EFFECTS_SPARKS2)

	play_sfx(old_turf, SFX_EFFECTS_SPARKS2)

	adjust_instability(25)
	consume(src, user)


/// T (a relation view).
/datum/technomancer_marker/proc/T() as /turf
	return T
