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
	var/obj/item/disk/nuclear/the_disk = null
	var/active = 0

	///TODO: Clear up click code entirely. This is used exclusively for attack_self
	var/nuclear = FALSE
	var/shuttle = FALSE

	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

/obj/item/pinpointer/Destroy()
	active = 0
	return ..()

/obj/item/pinpointer/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(nuclear || shuttle)
		return
	if(!active)
		active = TRUE
		PERIODIC_START(src, PERIODIC_SLOW)
		to_chat(user, span_notice("You activate the pinpointer"))
	else
		active = FALSE
		PERIODIC_STOP(src)
		icon_state = "pinoff"
		to_chat(user, span_notice("You deactivate the pinpointer"))

/obj/item/pinpointer/periodic_step()
	if(!active)
		return PROCESS_KILL

	if(!the_disk)
		the_disk = locate()
		if(!the_disk)
			icon_state = "pinonnull"
			return

	set_dir(get_dir(src,the_disk))

	switch(get_dist(src,the_disk))
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
	var/turf/location = null
	var/obj/target = null

/obj/item/pinpointer/advpinpointer/periodic_step()
	if(!active)
		return PROCESS_KILL
	if(mode == 0)
		..()
	if(mode == 1)
		worklocation()
	if(mode == 2)
		workobj()

/obj/item/pinpointer/advpinpointer/proc/worklocation()
	if(!location)
		icon_state = "pinonnull"
		return

	set_dir(get_dir(src,location))

	switch(get_dist(src,location))
		if(0)
			icon_state = "pinondirect"
		if(1 to 8)
			icon_state = "pinonclose"
		if(9 to 16)
			icon_state = "pinonmedium"
		if(16 to INFINITY)
			icon_state = "pinonfar"

/obj/item/pinpointer/advpinpointer/proc/workobj()
	if(!target)
		icon_state = "pinonnull"
		return

	set_dir(get_dir(src,target))

	switch(get_dist(src,target))
		if(0)
			icon_state = "pinondirect"
		if(1 to 8)
			icon_state = "pinonclose"
		if(9 to 16)
			icon_state = "pinonmedium"
		if(16 to INFINITY)
			icon_state = "pinonfar"

/obj/item/pinpointer/advpinpointer/verb/toggle_mode()
	set category = "Object"
	set name = "Toggle Pinpointer Mode"
	set src in view(1)

	active = 0
	icon_state = "pinoff"
	target=null
	location = null

	om_prompt(src, usr, list("message" = "Please select the mode you want to put the pinpointer in.", "title" = "Pinpointer Mode Select", "choices" = list("Location", "Disk Recovery", "Other Signature"), "requires" = PROMPT_HELD), PROC_REF(pinpointer_mode_chosen))

/obj/item/pinpointer/advpinpointer/proc/pinpointer_mode_chosen(mob/user, choice, datum/om/prompt/ask)
	switch(choice)
		if("Location")
			mode = 1
			om_prompt_sequence(src, user, list(
				list("key" = "x", "kind" = "number", "message" = "Please input the x coordinate to search for.", "title" = "Location?"),
				list("key" = "y", "kind" = "number", "message" = "Please input the y coordinate to search for.", "title" = "Location?"),
			), PROC_REF(pinpointer_location_chosen), list("requires" = list(CHECK(/datum/om/check/can_see, 1))))
		if("Disk Recovery")
			mode = 0
			attack_self(user)
		if("Other Signature")
			mode = 2
			om_prompt_chain(ask, list("message" = "Search for item signature or DNA fragment?", "title" = "Signature Mode Select", "choices" = list("Item", "DNA")), PROC_REF(pinpointer_signature_chosen))

/obj/item/pinpointer/advpinpointer/proc/pinpointer_location_chosen(mob/user, datum/om/prompt/ask)
	var/locationx = ask.get("x")
	var/locationy = ask.get("y")
	if(!locationx || !locationy)
		return
	var/turf/Z = get_turf(src)
	location = locate(locationx,locationy,Z.z)
	to_chat(user, "You set the pinpointer to locate [locationx],[locationy]")
	attack_self(user)

/obj/item/pinpointer/advpinpointer/proc/pinpointer_signature_chosen(mob/user, choice, datum/om/prompt/ask)
	var/static/datum/objective/steal/itemlist
	switch(choice)
		if("Item")
			if(!itemlist)
				itemlist = new
			om_prompt_chain(ask, list("kind" = "list", "message" = "Select item to search for.", "title" = "Item Mode Select", "choices" = itemlist.possible_items), PROC_REF(pinpointer_item_chosen))
		if("DNA")
			om_prompt_chain(ask, list("kind" = "text", "message" = "Input DNA string to search for.", "title" = "Please Enter String.", "default" = ""), PROC_REF(pinpointer_dna_entered))

/obj/item/pinpointer/advpinpointer/proc/pinpointer_item_chosen(mob/user, targetitem, datum/om/prompt/ask)
	var/datum/objective/steal/itemlist = new
	target = locate(itemlist.possible_items[targetitem])
	qdel(itemlist)
	if(!target)
		to_chat(user, "Failed to locate [targetitem]!")
		return
	to_chat(user, "You set the pinpointer to locate [targetitem]")
	attack_self(user)

/obj/item/pinpointer/advpinpointer/proc/pinpointer_dna_entered(mob/user, DNAstring, datum/om/prompt/ask)
	if(!DNAstring)
		return
	for(var/mob/living/carbon/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(!M.dna)
			continue
		if(M.dna.unique_enzymes == DNAstring)
			target = M
			break
	attack_self(user)


///////////////////////
//nuke op pinpointers//
///////////////////////


/obj/item/pinpointer/nukeop
	var/mode = 0	//Mode 0 locates disk, mode 1 locates the shuttle
	var/obj/machinery/computer/shuttle_control/multi/syndicate/home = null

/obj/item/pinpointer/nukeop/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(!active)
		active = 1
		PERIODIC_START(src, PERIODIC_SLOW)
		if(!mode)
			workdisk()
			to_chat(user, span_notice("Authentication Disk Locator active."))
		else
			worklocation()
			to_chat(user, span_notice("Shuttle Locator active."))
	else
		active = 0
		PERIODIC_STOP(src)
		icon_state = "pinoff"
		to_chat(user, span_notice("You deactivate the pinpointer."))

/obj/item/pinpointer/nukeop/periodic_step()
	if(!active)
		return PROCESS_KILL

	switch(mode)
		if(0)
			workdisk()
		if(1)
			worklocation()

/obj/item/pinpointer/nukeop/proc/workdisk()
	if(GLOB.bomb_set)	//If the bomb is set, lead to the shuttle
		mode = 1	//Ensures worklocation() continues to work
		playsound(src, 'sound/machines/twobeep.ogg', 50, 1)	//Plays a beep
		visible_message(span_notice("Shuttle Locator active."))			//Lets the mob holding it know that the mode has changed
		return		//Get outta here

	if(!the_disk)
		the_disk = locate()
		if(!the_disk)
			icon_state = "pinonnull"
			return

	set_dir(get_dir(src, the_disk))

	switch(get_dist(src, the_disk))
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
		playsound(src, 'sound/machines/twobeep.ogg', 50, 1)
		visible_message(span_notice("Authentication Disk Locator active."))
		return

	if(!home)
		home = locate()
		if(!home)
			icon_state = "pinonnull"
			return

	if(loc.z != home.z)	//If you are on a different z-level from the shuttle
		icon_state = "pinonnull"

	else
		set_dir(get_dir(src, home))

		switch(get_dist(src, home))
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
	var/obj/machinery/computer/shuttle_control/our_shuttle = null

/obj/item/pinpointer/shuttle/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(!active)
		active = TRUE
		PERIODIC_START(src, PERIODIC_SLOW)
		to_chat(user, span_notice("Shuttle Locator active."))
	else
		active = FALSE
		PERIODIC_STOP(src)
		icon_state = "pinoff"
		to_chat(user, span_notice("You deactivate the pinpointer."))

/obj/item/pinpointer/shuttle/periodic_step()
	if(!active)
		return PROCESS_KILL

	if(!our_shuttle)
		for(var/obj/machinery/computer/shuttle_control/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
			if(S.shuttle_tag == shuttle_comp_id) // Shuttle tags are used so that it will work if the computer path changes, as it does on the southern cross map.
				our_shuttle = S
				break

		if(!our_shuttle)
			icon_state = "pinonnull"
			return

	if(loc.z != our_shuttle.z)	//If you are on a different z-level from the shuttle
		icon_state = "pinonnull"

	else
		set_dir(get_dir(src, our_shuttle))

		switch(get_dist(src, our_shuttle))
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
