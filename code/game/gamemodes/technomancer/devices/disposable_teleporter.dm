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
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/disposable_teleporter/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!uses)
		to_chat(user, span_danger("\The [src] has ran out of uses, and is now useless to you!"))
		return TRUE
	else
		open_request(src, /datum/prompt/choice/technomancer_carried, PROC_REF(teleport_area_chosen), answerer = user, subject = src, title = "Teleportation", question = "Area to teleport to", choices = GLOB.teleportlocs)
	return TRUE

/obj/item/disposable_teleporter/proc/teleport_area_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/result/result = safe_call(PROC_REF(teleport_area_chosen_apply), A)
	if(!result.ok)
		stack_trace("technomancer teleport_area_chosen: [result.error]")
	return result.value

/obj/item/disposable_teleporter/proc/teleport_area_chosen_apply(datum/act/request/request_act)
	var/datum/prompt/choice/technomancer_carried/ask = request_act.answer
	var/mob/user = ask.answerer
	if(!uses)
		return
	var/area/A = GLOB.teleportlocs[ask.answer_value]
	if(!A)
		return

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
		uses--
		if(uses <= 0)
			to_chat(user, span_danger("\The [src] has ran out of uses, and disintegrates from your hands."))
			consume(src, user)
