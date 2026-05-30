/* Teleportation devices.
 * Contains:
 *		Locator
 *		Hand-tele
 */

/*
 * Locator
 */
/obj/item/locator
	name = "locator"
	desc = "Used to track those with locater implants."
	icon = 'icons/obj/device.dmi'
	icon_state = "locator"
	var/frequency = TRACK_IMP_FREQ
	var/broadcasting = null
	var/listening = 1.0
	w_class = ITEMSIZE_SMALL
	item_state = "electronic"
	throw_speed = 4
	throw_range = 20
	matter = list(MAT_STEEL = 400)
	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'
	// DQEdit Start — last scan results for TGUI. Replaces the legacy `temp`
	// HTML blob with structured data.
	var/list/last_beacons = null
	var/list/last_implants = null
	var/last_location = null
	// DQEdit End

// DQEdit Start — TGUI migration. attack_self opens Locator.tsx; Topic
// frequency/refresh/clear actions move to tgui_act.
/obj/item/locator/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	tgui_interact(user)

/obj/item/locator/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Locator", "Persistent Signal Locator")
		ui.open()

/obj/item/locator/tgui_data(mob/user)
	var/list/data = list()
	data["frequency"] = format_frequency(frequency)
	data["has_scan"] = !!last_location
	data["location"] = last_location || ""
	data["beacons"] = last_beacons || list()
	data["implants"] = last_implants || list()
	return data

/obj/item/locator/proc/strength_label(distance)
	if(distance < 5)
		return "very strong"
	if(distance < 10)
		return "strong"
	if(distance < 20)
		return "weak"
	return "very weak"

/obj/item/locator/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	if(usr.stat || usr.restrained())
		return TRUE
	var/turf/current_location = get_turf(usr)
	if(!current_location || current_location.z == 3)
		to_chat(usr, "The [src] is malfunctioning.")
		return TRUE
	switch(action)
		if("freq")
			frequency += text2num(params["delta"])
			frequency = sanitize_frequency(frequency)
			return TRUE
		if("clear")
			last_beacons = null
			last_implants = null
			last_location = null
			return TRUE
		if("refresh")
			var/turf/sr = get_turf(src)
			if(!sr)
				return TRUE
			var/list/b = list()
			for(var/obj/item/radio/beacon/W in GLOB.all_beacons)
				if(W.frequency != frequency)
					continue
				var/turf/tr = get_turf(W)
				if(!tr || tr.z != sr.z)
					continue
				var/distance = max(abs(tr.x - sr.x), abs(tr.y - sr.y))
				b += list(list(
					"id" = W.code,
					"direction" = dir2text(get_dir(sr, tr)),
					"strength" = strength_label(distance),
				))
			var/list/i = list()
			for(var/obj/item/implant/tracking/W in GLOB.all_tracking_implants)
				if(!W.implanted || !(istype(W.loc, /obj/item/organ/external) || ismob(W.loc) || W.malfunction) || is_vore_jammed(W))
					continue
				var/turf/tr = get_turf(W)
				if(!tr || tr.z != sr.z)
					continue
				var/distance = max(abs(tr.x - sr.x), abs(tr.y - sr.y))
				if(distance >= 20)
					continue
				i += list(list(
					"id" = W.id,
					"direction" = dir2text(get_dir(sr, tr)),
					"strength" = strength_label(distance),
				))
			last_beacons = b
			last_implants = i
			last_location = "[sr.x], [sr.y], [sr.z]"
			return TRUE
// DQEdit End


/*
 * Hand-tele
 */
/obj/item/hand_tele
	name = "hand tele"
	desc = "A portable item using blue-space technology."
	icon = 'icons/obj/device.dmi'
	icon_state = "hand_tele"
	item_state = "electronic"
	throwforce = 5
	w_class = ITEMSIZE_SMALL
	throw_speed = 3
	throw_range = 5
	matter = list(MAT_STEEL = 10000)
	preserve_item = 1

/obj/item/hand_tele/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	var/turf/current_location = get_turf(user)//What turf is the user on?
	if(!current_location || (current_location.z in using_map.admin_levels) || current_location.block_tele)//If turf was not found or they're on z level 2 or >7 which does not currently exist.
		to_chat(user, span_notice("\The [src] is malfunctioning."))
		return
	var/list/L = list(  )
	for(var/obj/machinery/teleport/hub/R in GLOB.machines)
		var/obj/machinery/computer/teleporter/com
		var/obj/machinery/teleport/station/station
		for(var/direction in GLOB.cardinal)
			station = locate(/obj/machinery/teleport/station, get_step(R, direction))
			if(station)
				for(direction in GLOB.cardinal)
					com = locate(/obj/machinery/computer/teleporter, get_step(station, direction))
					if(com)
						break
				break
		if (istype(com, /obj/machinery/computer/teleporter) && com.teleport_control.locked && !com.one_time_use)
			if(R.icon_state == "tele1")
				L["[com.id] (Active)"] = com.teleport_control.locked
			else
				L["[com.id] (Inactive)"] = com.teleport_control.locked
	var/list/turfs = list(	)
	for(var/turf/T in orange(10))
		if(T.x>world.maxx-8 || T.x<8)	continue	//putting them at the edge is dumb
		if(T.y>world.maxy-8 || T.y<8)	continue
		if(T.block_tele) continue
		turfs += T
	if(turfs.len)
		L["None (Dangerous)"] = pick(turfs)
	var/t1 = tgui_input_list(user, "Please select a teleporter to lock in on.", "Hand Teleporter", L)
	if(!t1)
		return
	if ((user.get_active_hand() != src || user.stat || user.restrained()))
		return
	var/count = 0	//num of portals from this teleport in world
	for(var/obj/effect/portal/PO in GLOB.all_portals)
		if(PO.creator == src)	count++
	if(count >= 3)
		user.show_message(span_notice("\The [src] is recharging!"))
		return
	var/T = L[t1]
	for(var/mob/O in hearers(user, null))
		O.show_message(span_notice("Locked In."), 2)
	var/obj/effect/portal/P = new /obj/effect/portal( get_turf(src) )
	P.target = T
	P.creator = src
	P.failchance = 0 //CHOMPEdit : funny 5% chance to be spaced and die makes the hand tele kinda useless.
	src.add_fingerprint(user)
	return
