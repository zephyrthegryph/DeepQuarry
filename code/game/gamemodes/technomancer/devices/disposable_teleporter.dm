/datum/technomancer/consumable/disposable_teleporter
	name = "Disposable Teleporter"
	desc = "An ultra-safe teleportation device that can directly teleport you to a number of locations at minimal risk, however \
	it has a limited amount of charges."
	cost = 50
	obj_path = /obj/item/disposable_teleporter

/obj/item/disposable_teleporter
	name = "disposable teleporter"
	desc = "A very compact personal teleportation device.  It's very precise and safe, however it can only be used a few times."
	icon = 'icons/obj/device.dmi'
	icon_state = "hand_tele" //temporary
	var/uses = 3.0
	w_class = ITEMSIZE_TINY
	item_state = "paper"

//This one is what the wizard starts with.  The above is a better version that can be purchased.
/obj/item/disposable_teleporter/free
	name = "complimentary disposable teleporter"
	desc = "A very compact personal teleportation device.  It's very precise and safe, however it can only be used once.  This \
	one has been provided to allow you to leave your hideout."
	uses = 1

/obj/item/disposable_teleporter/examine(mob/user)
	. = ..()
	. += "[uses] uses remaining."

CAPABILITIES(/obj/item/disposable_teleporter)
	op("self", in_hand(),
		asks(/datum/prompt/choice/technomancer_carried, fields = list("title" = "Teleportation", "question" = "Area to teleport to", "choices" = computed(PROC_REF(teleport_area_choices))), step = "area", when = PROC_REF(has_uses)),
		then(PROC_REF(interaction_self)))

/obj/item/disposable_teleporter/proc/has_uses(datum/act/op/A)
	return uses > 0

/obj/item/disposable_teleporter/proc/teleport_area_choices(datum/act/op/A)
	return GLOB.teleportlocs

/// Old attack_self: with uses left, teleports to the area the question was answered with.
/obj/item/disposable_teleporter/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!uses)
		to_chat(user, span_danger("\The [src] has ran out of uses, and is now useless to you!"))
		return TRUE
	var/datum/prompt/ask = A.answer
	if(!ask)
		return TRUE
	var/area/A_area = GLOB.teleportlocs[ask.value]
	if(!A_area)
		return TRUE
	teleport_to_area(user, A_area)
	return TRUE

/obj/item/disposable_teleporter/proc/teleport_to_area(mob/user, area/A)

	fx_sparks(user, 5, FALSE)

	if(user && user?.buckled_to())
		var/atom/movable/_tmp_buck_4 = user?.buckled_to()
		_tmp_buck_4.unbuckle_mob()

	var/list/targets = list()

	//Copypasta
	valid_turfs:
		for(var/turf/simulated/T in contents_of(A))
			if(T.density || ismineralturf(T)) //Don't blink to vacuum or a wall
				continue
			for(var/atom/movable/stuff in contents_of(T))
				if(stuff.density)
					continue valid_turfs
			targets.Add(T)

	if(!targets.len)
		to_chat(user, "\The [src] was unable to locate a suitable teleport destination, as all the possibilities \
		were nonexistant or hazardous. Try a different area.")
		return
	var/turf/simulated/destination = null

	destination = pick(targets)

	if(destination)
		user.forceMove(destination)
		to_chat(user, span_notice("You are teleported to \the [A]."))
		set_uses(uses - 1)
		if(uses <= 0)
			to_chat(user, span_danger("\The [src] has ran out of uses, and disintegrates from your hands."))
			consume(src, user)
