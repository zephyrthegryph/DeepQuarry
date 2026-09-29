/datum/technomancer/spell/track
	name = "Track"
	desc = "Acts as directional guidance towards an object that belongs to you or your team.  It can also point towards your allies.  \
	Wonderful if you're worried someone will steal your valuables, like a certain shiny Scepter..."
	enhancement_desc = "You will be able to track most other entities in addition to your belongings and allies."
	cost = 25
	obj_path = /obj/item/spell/track
	ability_icon_state = "tech_track"
	category = UTILITY_SPELLS

// This stores a ref to all important items that belong to a Technomancer, in case of theft.  Used by the spell below.
// I feel dirty for adding yet another global list used by one thing, but the only alternative is to loop through world, and yeahhh.

REGISTRY_MEMBERSHIP(/obj, REGISTRY_TECHNOMANCER_BELONGINGS)

/obj/item/spell/track
	name = "track"
	icon_state = "track"
	desc = "Never lose your stuff again!"
	cast_methods = CAST_USE
	aspect = ASPECT_TELE
	var/atom/movable/tracked // The thing to point towards.
	var/tracking = 0 // If one, points towards tracked.

/obj/item/spell/track/on_use_cast(mob/user)
	if(tracking)
		tracking = 0
		to_chat(user, span_notice("You stop tracking for \the [tracked()]'s whereabouts."))
		rel_clear(src, "tracked")
		return

	var/can_track_non_allies = 0
	var/list/object_choices = REGISTRY_COPY(REGISTRY_TECHNOMANCER_BELONGINGS)
	if(check_for_scepter())
		can_track_non_allies = 1
	var/list/mob_choices = list()
	for(var/mob/living/L in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(!is_ally(L) && !can_track_non_allies)
			continue
		if(L == user)
			continue
		mob_choices += L
	om_ask(user, /datum/om/prompt/choice/carried_item, PROC_REF(track_target_chosen), title = "Tracking", message = "Decide what or who to track.", choices = (object_choices + mob_choices))

/obj/item/spell/track/proc/track_target_chosen(datum/om/prompt/choice/carried_item/ask)
	if(ask.choice)
		rel_set(src, "tracked", ask.choice)
		tracking = 1
		track()

/obj/item/spell/track/proc/track()
	if(!tracking)
		icon_state = "track"
		return

	if(!tracked())
		icon_state = "track_unknown"

	if(tracked().z != owner_ref().z)
		icon_state = "track_unknown"

	else
		set_dir(get_dir(src,get_turf(tracked())))

		switch(get_dist(src,get_turf(tracked())))
			if(0)
				icon_state = "track_direct"
			if(1 to 8)
				icon_state = "track_close"
			if(9 to 16)
				icon_state = "track_medium"
			if(16 to INFINITY)
				icon_state = "track_far"

	om_after(src, 5, PROC_REF(track))

/// LC-refs: tracked -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/spell/track/proc/tracked() as /atom/movable
	return tracked
