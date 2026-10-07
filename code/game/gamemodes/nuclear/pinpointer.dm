/obj/item/pinpointer
	name = "pinpointer"
	icon = 'icons/obj/device.dmi'
	icon_state = "pinoff"
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_SMALL
	item_state = "electronic"
	throw_speed = 4
	throw_range = 20
	MATERIAL_BULK(MAT_STEEL, 500)
	preserve_item = 1
	var/obj/item/disk/nuclear/the_disk

	///TODO: Clear up click code entirely. This is used exclusively for attack_self
	var/nuclear = FALSE
	var/shuttle = FALSE

	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

/obj/item/pinpointer/var/active = FALSE
TRACKED(/obj/item/pinpointer, active)
CAPABILITIES(/obj/item/pinpointer)
	every(2 SECONDS, then(PROC_REF(pinpointer_step)), when = nameof(active))
	op("toggle", in_hand(), label("Toggle"), then(PROC_REF(pinpointer_toggle_op)))

/obj/item/pinpointer/proc/pinpointer_toggle_op(datum/act/op/A)
	pinpointer_toggle(A.actor)
	return OP_OK

/// The toggle itself; the nuke op and shuttle pinpointers override it and run this body first.
/obj/item/pinpointer/proc/pinpointer_toggle(mob/user)
	if(nuclear || shuttle)
		return
	if(!active)
		set_active(TRUE)
		to_chat(user, span_notice("You activate the pinpointer"))
	else
		set_active(FALSE)
		icon_state = "pinoff"
		to_chat(user, span_notice("You deactivate the pinpointer"))

/obj/item/pinpointer/proc/pinpointer_step(datum/act/timer/A)
	if(!the_disk())
		rel_set(src, nameof(the_disk), locate(/obj/item/disk/nuclear))
		if(!the_disk())
			icon_state = "pinonnull"
			return

	set_dir(get_dir(src,the_disk()))

	switch(get_dist(src,the_disk()))
		if(0)
			icon_state = "pinondirect"
		if(1 to 8)
			icon_state = "pinonclose"
		if(9 to 16)
			icon_state = "pinonmedium"
		if(16 to INFINITY)
			icon_state = "pinonfar"

/obj/item/pinpointer/examine(mob/user)
	. = ..()
	for(var/obj/machinery/nuclearbomb/bomb in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(bomb.timing)
			. += "Extreme danger.  Arming signal detected.   Time remaining: [bomb.timeleft]"

/obj/item/pinpointer/advpinpointer
	name = "Advanced Pinpointer"
	icon = 'icons/obj/device.dmi'
	desc = "A larger version of the normal pinpointer, this unit features a helpful quantum entanglement detection system to locate various objects that do not broadcast a locator signal."
	var/mode = 0  // Mode 0 locates disk, mode 1 locates coordinates.
	var/turf/location
	var/obj/target

/obj/item/pinpointer/advpinpointer/pinpointer_step(datum/act/timer/A)
	if(mode == 0)
		..()
	if(mode == 1)
		worklocation()
	if(mode == 2)
		workobj()

/obj/item/pinpointer/advpinpointer/proc/worklocation()
	if(!get_location())
		icon_state = "pinonnull"
		return

	set_dir(get_dir(src,get_location()))

	switch(get_dist(src,get_location()))
		if(0)
			icon_state = "pinondirect"
		if(1 to 8)
			icon_state = "pinonclose"
		if(9 to 16)
			icon_state = "pinonmedium"
		if(16 to INFINITY)
			icon_state = "pinonfar"

/obj/item/pinpointer/advpinpointer/proc/workobj()
	if(!target_ref())
		icon_state = "pinonnull"
		return

	set_dir(get_dir(src,target_ref()))

	switch(get_dist(src,target_ref()))
		if(0)
			icon_state = "pinondirect"
		if(1 to 8)
			icon_state = "pinonclose"
		if(9 to 16)
			icon_state = "pinonmedium"
		if(16 to INFINITY)
			icon_state = "pinonfar"

/obj/item/pinpointer/advpinpointer/proc/advpinpointer_toggle_mode_effect(datum/act/op/A)
	var/mob/user = A.actor

	set_active(FALSE)
	icon_state = "pinoff"
	rel_clear(src, nameof(target))
	rel_clear(src, nameof(location))

	open_request(src, /datum/prompt/choice/pinpointer_carried, PROC_REF(pinpointer_mode_chosen), answerer = user, title = "Pinpointer Mode Select", question = "Please select the mode you want to put the pinpointer in.", choices = list("Location", "Disk Recovery", "Other Signature"), buttons = TRUE)


/obj/item/pinpointer/advpinpointer/proc/pinpointer_mode_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/pinpointer_carried/ask = context.answer
	var/mob/user = ask.answerer
	switch(ask.value)
		if("Location")
			mode = 1
			open_request(src, /datum/prompt/number/pinpointer_coordinate, PROC_REF(pinpointer_location_x_chosen), answerer = user, question = "Please input the x coordinate to search for.")
		if("Disk Recovery")
			mode = 0
			attack_self(user)
		if("Other Signature")
			mode = 2
			open_request(src, /datum/prompt/choice/pinpointer_carried, PROC_REF(pinpointer_signature_chosen), answerer = user, title = "Signature Mode Select", question = "Search for item signature or DNA fragment?", choices = list("Item", "DNA"), buttons = TRUE)

/obj/item/pinpointer/advpinpointer/proc/pinpointer_location_x_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/number/pinpointer_coordinate/ask = context.answer
	open_request(src, /datum/prompt/number/pinpointer_coordinate, PROC_REF(pinpointer_location_chosen), answerer = ask.answerer, question = "Please input the y coordinate to search for.", location_x = ask.value)

/obj/item/pinpointer/advpinpointer/proc/pinpointer_location_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/number/pinpointer_coordinate/ask = context.answer
	var/mob/user = ask.answerer
	var/locationx = ask.location_x
	var/locationy = ask.value
	if(!locationx || !locationy)
		return
	var/turf/Z = get_turf(src)
	rel_set(src, nameof(location), locate(locationx,locationy,Z.z))
	to_chat(user, "You set the pinpointer to locate [locationx],[locationy]")
	attack_self(user)

/obj/item/pinpointer/advpinpointer/proc/pinpointer_signature_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/pinpointer_carried/ask = context.answer
	var/static/datum/objective/steal/itemlist
	switch(ask.value)
		if("Item")
			if(!itemlist)
				itemlist = new
			open_request(src, /datum/prompt/choice/pinpointer_carried, PROC_REF(pinpointer_item_chosen), answerer = ask.answerer, title = "Item Mode Select", question = "Select item to search for.", choices = itemlist.possible_items?.Copy())
		if("DNA")
			open_request(src, /datum/prompt/text, PROC_REF(pinpointer_dna_entered), answerer = ask.answerer, title = "Please Enter String.", question = "Input DNA string to search for.", default = "", ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)

/obj/item/pinpointer/advpinpointer/proc/pinpointer_item_chosen(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/pinpointer_carried/ask = context.answer
	var/mob/user = ask.answerer
	var/targetitem = ask.value
	var/datum/objective/steal/itemlist = new
	rel_set(src, nameof(target), locate(itemlist.possible_items[targetitem]))
	spent(itemlist)
	if(!target_ref())
		to_chat(user, "Failed to locate [targetitem]!")
		return
	to_chat(user, "You set the pinpointer to locate [targetitem]")
	attack_self(user)

/obj/item/pinpointer/advpinpointer/proc/pinpointer_dna_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/DNAstring = A.answer.value
	if(!DNAstring)
		return
	for(var/mob/living/carbon/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(!M.dna)
			continue
		if(M.dna.unique_enzymes == DNAstring)
			rel_set(src, nameof(target), M)
			break
	attack_self(user)

///////////////////////
//nuke op pinpointers//
///////////////////////

/obj/item/pinpointer/nukeop
	var/mode = 0	//Mode 0 locates disk, mode 1 locates the shuttle
	var/obj/machinery/computer/shuttle_control/multi/syndicate/home

/// The old override ran the parent's body first (its ..()), so this does too.
/obj/item/pinpointer/nukeop/pinpointer_toggle(mob/user)
	..()
	if(!active)
		set_active(TRUE)
		if(!mode)
			workdisk()
			to_chat(user, span_notice("Authentication Disk Locator active."))
		else
			worklocation()
			to_chat(user, span_notice("Shuttle Locator active."))
	else
		set_active(FALSE)
		icon_state = "pinoff"
		to_chat(user, span_notice("You deactivate the pinpointer."))

/obj/item/pinpointer/nukeop/pinpointer_step(datum/act/timer/A)
	switch(mode)
		if(0)
			workdisk()
		if(1)
			worklocation()

/obj/item/pinpointer/nukeop/proc/workdisk()
	if(GLOB.bomb_set)	//If the bomb is set, lead to the shuttle
		mode = 1	//Ensures worklocation() continues to work
		play_sfx(src, SFX_MACHINES_TWOBEEP)	//Plays a beep
		visible_message(span_notice("Shuttle Locator active."))			//Lets the mob holding it know that the mode has changed
		return		//Get outta here

	if(!the_disk())
		rel_set(src, nameof(the_disk), locate(/obj/item/disk/nuclear))
		if(!the_disk())
			icon_state = "pinonnull"
			return

	set_dir(get_dir(src, the_disk()))

	switch(get_dist(src, the_disk()))
		if(0)
			icon_state = "pinondirect"
		if(1 to 8)
			icon_state = "pinonclose"
		if(9 to 16)
			icon_state = "pinonmedium"
		if(16 to INFINITY)
			icon_state = "pinonfar"

/obj/item/pinpointer/nukeop/proc/worklocation()
	if(!GLOB.bomb_set)
		mode = 0
		play_sfx(src, SFX_MACHINES_TWOBEEP)
		visible_message(span_notice("Authentication Disk Locator active."))
		return

	if(!home())
		rel_set(src, nameof(home), locate(/obj/machinery/computer/shuttle_control/multi/syndicate))
		if(!home())
			icon_state = "pinonnull"
			return

	if(loc.z != home().z)	//If you are on a different z-level from the shuttle
		icon_state = "pinonnull"

	else
		set_dir(get_dir(src, home()))

		switch(get_dist(src, home()))
			if(0)
				icon_state = "pinondirect"
			if(1 to 8)
				icon_state = "pinonclose"
			if(9 to 16)
				icon_state = "pinonmedium"
			if(16 to INFINITY)
				icon_state = "pinonfar"

// This one only points to the ship.  Useful if there is no nuking to occur today.
/obj/item/pinpointer/shuttle
	var/shuttle_comp_id = null
	var/obj/machinery/computer/shuttle_control/our_shuttle

/// The old override ran the parent's body first (its ..()), so this does too.
/obj/item/pinpointer/shuttle/pinpointer_toggle(mob/user)
	..()
	if(!active)
		set_active(TRUE)
		to_chat(user, span_notice("Shuttle Locator active."))
	else
		set_active(FALSE)
		icon_state = "pinoff"
		to_chat(user, span_notice("You deactivate the pinpointer."))

/obj/item/pinpointer/shuttle/pinpointer_step(datum/act/timer/A)
	if(!our_shuttle())
		for(var/obj/machinery/computer/shuttle_control/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
			if(S.shuttle_tag == shuttle_comp_id) // Shuttle tags are used so that it will work if the computer path changes, as it does on the southern cross map.
				rel_set(src, nameof(our_shuttle), S)
				break

		if(!our_shuttle())
			icon_state = "pinonnull"
			return

	if(loc.z != our_shuttle().z)	//If you are on a different z-level from the shuttle
		icon_state = "pinonnull"

	else
		set_dir(get_dir(src, our_shuttle()))

		switch(get_dist(src, our_shuttle()))
			if(0)
				icon_state = "pinondirect"
			if(1 to 8)
				icon_state = "pinonclose"
			if(9 to 16)
				icon_state = "pinonmedium"
			if(16 to INFINITY)
				icon_state = "pinonfar"

/obj/item/pinpointer/shuttle/merc
	shuttle_comp_id = "Mercenary"

/obj/item/pinpointer/shuttle/heist
	shuttle_comp_id = "Skipjack"

/// The disk (a relation view).
/obj/item/pinpointer/proc/the_disk() as /obj/item/disk/nuclear
	return the_disk

/// Location (a relation view).
/obj/item/pinpointer/advpinpointer/proc/get_location() as /turf
	return location

/// Target (a relation view).
/obj/item/pinpointer/advpinpointer/proc/target_ref() as /obj
	return target

/// Home (a relation view).
/obj/item/pinpointer/nukeop/proc/home() as /obj/machinery/computer/shuttle_control/multi/syndicate
	return home

/// Our shuttle (a relation view).
/obj/item/pinpointer/shuttle/proc/our_shuttle() as /obj/machinery/computer/shuttle_control
	return our_shuttle

/// Old object verbs.
CAPABILITIES(/obj/item/pinpointer/advpinpointer)
	op("advpinpointer_toggle_mode_effect", menu(), label("Toggle Pinpointer Mode"), then(PROC_REF(advpinpointer_toggle_mode_effect)))

/datum/prompt/choice/pinpointer_carried
	ask_flags = ASK_CARRIED | ASK_CAPABLE
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/pinpointer_carried/recheck_extra()
	var/mob/user = answerer
	return !istype(user) || QDELETED(user) ? "gone" : null

/datum/prompt/number/pinpointer_coordinate
	title = "Location?"
	timeout = 0
	recheck_on_open = TRUE
	var/location_x

/datum/prompt/number/pinpointer_coordinate/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title, default || 0, INFINITY, 0, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/number/pinpointer_coordinate/recheck_extra()
	var/mob/user = answerer
	var/obj/item/pinpointer/advpinpointer/device = owner
	if(!istype(user) || QDELETED(user) || !istype(device) || QDELETED(device))
		return "gone"
	return can_see(user, device, 1) ? null : "can't see it"
