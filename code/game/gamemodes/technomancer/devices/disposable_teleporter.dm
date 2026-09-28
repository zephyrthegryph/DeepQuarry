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

DECLARE_INTERACTIONS(/obj/item/disposable_teleporter, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/disposable_teleporter/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(!uses)
		to_chat(user, span_danger("\The [src] has ran out of uses, and is now useless to you!"))
		return TRUE
	else
		om_prompt(src, user, list("kind" = "list", "message" = "Area to teleport to", "title" = "Teleportation", "choices" = GLOB.teleportlocs, "requires" = PROMPT_HELD), PROC_REF(teleport_area_chosen))
	return TRUE

/obj/item/disposable_teleporter/proc/teleport_area_chosen(mob/user, area_wanted, datum/om/prompt/ask)
	if(!uses)
		return
	var/area/A = GLOB.teleportlocs[area_wanted]
	if(!A)
		return

	if (user.stat || user.restrained())
		return

	if(!((user == loc || (in_range(src, user) && istype(src.loc, /turf)))))
		return

	var/datum/effect/effect/system/spark_spread/sparks = new /datum/effect/effect/system/spark_spread()
	sparks.set_up(5, 0, user.loc)
	sparks.attach(user)
	sparks.start()

	if(user && user?.buckled_to())
		var/atom/movable/_tmp_buck_4 = user?.buckled_to()
		_tmp_buck_4.unbuckle_mob()

	var/list/targets = list()

	//Copypasta
	valid_turfs:
		for(var/turf/simulated/T in A.contents)
			if(T.density || ismineralturf(T)) //Don't blink to vacuum or a wall
				continue
			for(var/atom/movable/stuff in T.contents)
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
		uses--
		if(uses <= 0)
			to_chat(user, span_danger("\The [src] has ran out of uses, and disintegrates from your hands."))
			consume(src, user)
