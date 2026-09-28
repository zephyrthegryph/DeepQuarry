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
	var/the_disk_handle
	var/active = 0

	///TODO: Clear up click code entirely. This is used exclusively for attack_self
	var/nuclear = FALSE
	var/shuttle = FALSE

	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

DECLARE_INTERACTIONS(/obj/item/pinpointer, INTERACT_USE("Toggle", PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/pinpointer/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(nuclear || shuttle)
		return
	if(!active)
		active = TRUE
		om_task_periodic(src, PERIODIC_SLOW)
		to_chat(user, span_notice("You activate the pinpointer"))
	else
		active = FALSE
		om_task_periodic_stop(src)
		icon_state = "pinoff"
		to_chat(user, span_notice("You deactivate the pinpointer"))

/obj/item/pinpointer/periodic_step()
	if(!active)
		return PROCESS_KILL

	if(!the_disk())
		the_disk_handle = om_handle(locate(/obj/item/disk/nuclear))
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
	var/location_handle
	var/target_handle

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

/obj/item/pinpointer/advpinpointer/proc/advpinpointer_toggle_mode_effect(mob/user, obj/item/held, datum/interaction/interaction)

	active = 0
	icon_state = "pinoff"
	target_handle = null
	location_handle = null

	om_ask(user, /datum/om/prompt/choice/carried_item, PROC_REF(pinpointer_mode_chosen), title = "Pinpointer Mode Select", message = "Please select the mode you want to put the pinpointer in.", choices = list("Location", "Disk Recovery", "Other Signature"), buttons = TRUE)

/// A pinpointer coordinate (x, then y: `location_x` carries the first). Re-checked: it's in view.
/datum/om/prompt/number/pinpointer_location
	title = "Location?"
	requires = list(CHECK(/datum/om/check/can_see, 1))
	var/location_x

/obj/item/pinpointer/advpinpointer/proc/pinpointer_mode_chosen(datum/om/prompt/choice/carried_item/ask)
	var/mob/user = ask.answerer
	switch(ask.choice)
		if("Location")
			mode = 1
			om_ask(user, /datum/om/prompt/number/pinpointer_location, PROC_REF(pinpointer_location_x_chosen), message = "Please input the x coordinate to search for.")
		if("Disk Recovery")
			mode = 0
			attack_self(user)
		if("Other Signature")
			mode = 2
			om_ask(user, /datum/om/prompt/choice/carried_item, PROC_REF(pinpointer_signature_chosen), title = "Signature Mode Select", message = "Search for item signature or DNA fragment?", choices = list("Item", "DNA"), buttons = TRUE)

/obj/item/pinpointer/advpinpointer/proc/pinpointer_location_x_chosen(datum/om/prompt/number/pinpointer_location/ask)
	om_ask(ask.answerer, /datum/om/prompt/number/pinpointer_location, PROC_REF(pinpointer_location_chosen), message = "Please input the y coordinate to search for.", location_x = ask.number)

/obj/item/pinpointer/advpinpointer/proc/pinpointer_location_chosen(datum/om/prompt/number/pinpointer_location/ask)
	var/mob/user = ask.answerer
	var/locationx = ask.location_x
	var/locationy = ask.number
	if(!locationx || !locationy)
		return
	var/turf/Z = get_turf(src)
	location_handle = om_handle(locate(locationx,locationy,Z.z))
	to_chat(user, "You set the pinpointer to locate [locationx],[locationy]")
	attack_self(user)

/obj/item/pinpointer/advpinpointer/proc/pinpointer_signature_chosen(datum/om/prompt/choice/carried_item/ask)
	var/static/datum/objective/steal/itemlist
	switch(ask.choice)
		if("Item")
			if(!itemlist)
				itemlist = new
			om_ask(ask.answerer, /datum/om/prompt/choice/carried_item, PROC_REF(pinpointer_item_chosen), title = "Item Mode Select", message = "Select item to search for.", choices = itemlist.possible_items)
		if("DNA")
			om_ask(ask.answerer, /datum/om/prompt/text, PROC_REF(pinpointer_dna_entered), title = "Please Enter String.", message = "Input DNA string to search for.", default = "", ask_flags = ASK_CARRIED | ASK_CAPABLE)

/obj/item/pinpointer/advpinpointer/proc/pinpointer_item_chosen(datum/om/prompt/choice/carried_item/ask)
	var/mob/user = ask.answerer
	var/targetitem = ask.choice
	var/datum/objective/steal/itemlist = new
	target_handle = om_handle(locate(itemlist.possible_items[targetitem]))
	qdel(itemlist)
	if(!target_ref())
		to_chat(user, "Failed to locate [targetitem]!")
		return
	to_chat(user, "You set the pinpointer to locate [targetitem]")
	attack_self(user)

/obj/item/pinpointer/advpinpointer/proc/pinpointer_dna_entered(datum/om/prompt/text/ask)
	var/mob/user = ask.answerer
	var/DNAstring = ask.text
	if(!DNAstring)
		return
	for(var/mob/living/carbon/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(!M.dna)
			continue
		if(M.dna.unique_enzymes == DNAstring)
			target_handle = om_handle(M)
			break
	attack_self(user)

///////////////////////
//nuke op pinpointers//
///////////////////////

/obj/item/pinpointer/nukeop
	var/mode = 0	//Mode 0 locates disk, mode 1 locates the shuttle
	var/home_handle

// ALLOW(interactions): its Toggle replaces the base pinpointer's (it runs the parent's body itself)
DECLARE_INTERACTIONS(/obj/item/pinpointer/nukeop, INTERACT_USE("Toggle", PROC_REF(nukeop_interaction_self)))

/// Old attack_self. The old override ran the parent's body first (its ..()), so this does too.
/obj/item/pinpointer/nukeop/proc/nukeop_interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	interaction_self(user, held, interaction)
	if(!active)
		active = 1
		om_task_periodic(src, PERIODIC_SLOW)
		if(!mode)
			workdisk()
			to_chat(user, span_notice("Authentication Disk Locator active."))
		else
			worklocation()
			to_chat(user, span_notice("Shuttle Locator active."))
	else
		active = 0
		om_task_periodic_stop(src)
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

	if(!the_disk())
		the_disk_handle = om_handle(locate(/obj/item/disk/nuclear))
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
		playsound(src, 'sound/machines/twobeep.ogg', 50, 1)
		visible_message(span_notice("Authentication Disk Locator active."))
		return

	if(!home())
		home_handle = om_handle(locate(/obj/machinery/computer/shuttle_control/multi/syndicate))
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
	var/our_shuttle_handle

// ALLOW(interactions): its Toggle replaces the base pinpointer's (it runs the parent's body itself)
DECLARE_INTERACTIONS(/obj/item/pinpointer/shuttle, INTERACT_USE("Toggle", PROC_REF(shuttle_interaction_self)))

/// Old attack_self. The old override ran the parent's body first (its ..()), so this does too.
/obj/item/pinpointer/shuttle/proc/shuttle_interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	interaction_self(user, held, interaction)
	if(!active)
		active = TRUE
		om_task_periodic(src, PERIODIC_SLOW)
		to_chat(user, span_notice("Shuttle Locator active."))
	else
		active = FALSE
		om_task_periodic_stop(src)
		icon_state = "pinoff"
		to_chat(user, span_notice("You deactivate the pinpointer."))

/obj/item/pinpointer/shuttle/periodic_step()
	if(!active)
		return PROCESS_KILL

	if(!our_shuttle())
		for(var/obj/machinery/computer/shuttle_control/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
			if(S.shuttle_tag == shuttle_comp_id) // Shuttle tags are used so that it will work if the computer path changes, as it does on the southern cross map.
				our_shuttle_handle = om_handle(S)
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

/// LC-refs: the disk -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/pinpointer/proc/the_disk() as /obj/item/disk/nuclear
	return om_resolve(the_disk_handle)

/// LC-refs: location -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/pinpointer/advpinpointer/proc/get_location() as /turf
	return om_resolve(location_handle)

/// LC-refs: target -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/pinpointer/advpinpointer/proc/target_ref() as /obj
	return om_resolve(target_handle)

/// LC-refs: home -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/pinpointer/nukeop/proc/home() as /obj/machinery/computer/shuttle_control/multi/syndicate
	return om_resolve(home_handle)

/// LC-refs: our shuttle -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/pinpointer/shuttle/proc/our_shuttle() as /obj/machinery/computer/shuttle_control
	return om_resolve(our_shuttle_handle)

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/pinpointer/advpinpointer, \
	INTERACT_VERB("Toggle Pinpointer Mode", PROC_REF(advpinpointer_toggle_mode_effect)), \
)
