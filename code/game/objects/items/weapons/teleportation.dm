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
	MATERIAL_BULK(MAT_STEEL, 400)
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE
	// last scan results for TGUI. Replaces the legacy `temp`
	// HTML blob with structured data.
	var/list/last_beacons = null
	var/list/last_implants = null
	var/last_location = null

// TGUI migration. attack_self opens Locator.tsx; Topic
// frequency/refresh/clear actions move to tgui_act.
CAPABILITIES(/obj/item/locator)
	op("controls", in_hand(), label("Open locator"), then(PROC_REF(locator_controls_opened)))
	interface("Locator", title = "Persistent Signal Locator")
	without("ui_open")
	op("freq", ui_act("freq", arg("delta", num())), then(PROC_REF(ui_act_freq)))
	op("clear", ui_act("clear"), then(PROC_REF(ui_act_clear)))
	op("refresh", ui_act("refresh"), then(PROC_REF(ui_act_refresh)))

/obj/item/locator/proc/locator_controls_opened(datum/act/op/A)
	tgui_interact(A.actor)
	return OP_OK

/// /obj/item/locator's window data.
/obj/item/locator/ui_data(datum/act/eval/A)
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

/obj/item/locator/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	var/turf/current_location = get_turf(user)
	if(user.stat || user.restrained())
		return FALSE
	if(!current_location || current_location.z == 3)
		to_chat(user, "The [src] is malfunctioning.")
		return FALSE
	return TRUE

/obj/item/locator/proc/ui_act_freq(datum/act/op/A, delta)
	if(!ui_gate(A))
		return FALSE
	frequency += delta
	frequency = sanitize_frequency(frequency)
	return TRUE

/obj/item/locator/proc/ui_act_clear(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	last_beacons = null
	last_implants = null
	last_location = null
	return TRUE

/obj/item/locator/proc/ui_act_refresh(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	var/turf/sr = get_turf(src)
	if(!sr)
		return TRUE
	var/list/b = list()
	for(var/obj/item/radio/beacon/W in REGISTRY_MEMBERS(REGISTRY_BEACONS))
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
	for(var/obj/item/implant/tracking/W in REGISTRY_MEMBERS(REGISTRY_TRACKING_IMPLANTS))
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
	MATERIAL_BULK(MAT_STEEL, 10000)
	preserve_item = 1

CAPABILITIES(/obj/item/hand_tele)
	// the old attack_self: pick a locked-on teleporter (or a random spot nearby) and open a portal to it
	op("lock_in", in_hand(), needs(req_bool(PROC_REF(can_open_portal), because = MSG(hand_tele/malfunctioning))),
		asks(/datum/prompt/choice, fields = list("title" = "Hand Teleporter", "question" = "Please select a teleporter to lock in on.", "choices" = computed(PROC_REF(teleporter_choices)), "timeout" = 0)),
		then(PROC_REF(teleporter_chosen)))

/// Requirement: it won't work off-station or on a teleport-blocked turf.
/obj/item/hand_tele/proc/can_open_portal(datum/act/op/A)
	return hand_tele_works_at(get_turf(A.actor))

/proc/hand_tele_works_at(turf/current_location)
	READS_FROM() // where the actor stands is asked when the button is pressed
	return current_location && !(current_location.z in using_map.admin_levels) && !current_location.block_tele

MSG_DEF_SELF(hand_tele/malfunctioning, "It's malfunctioning.")

/// The teleporters this one can lock in on, by name (and a random spot nearby, which is dangerous).
/obj/item/hand_tele/proc/teleporter_choices(datum/act/A)
	var/list/L = list(  )
	for(var/obj/machinery/teleport/hub/R in REGISTRY_MEMBERS(REGISTRY_MACHINES))
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
		if (istype(com, /obj/machinery/computer/teleporter) && com.teleport_control.locked() && !com.one_time_use)
			if(R.icon_state == "tele1")
				L["[com.id] (Active)"] = com.teleport_control.locked()
			else
				L["[com.id] (Inactive)"] = com.teleport_control.locked()
	var/list/turfs = list(	)
	for(var/turf/T in orange(10))
		if(T.x>world.maxx-8 || T.x<8)	continue	//putting them at the edge is dumb
		if(T.y>world.maxy-8 || T.y<8)	continue
		if(T.block_tele) continue
		turfs += T
	if(turfs.len)
		L["None (Dangerous)"] = pick(turfs)
	return L

/// Old attack_self: a portal opens to the chosen destination (three at most at once).
/obj/item/hand_tele/proc/teleporter_chosen(datum/act/op/A)
	var/datum/prompt/choice/prompt = A.answer
	if(!prompt)
		return OP_OK
	var/mob/user = A.actor
	var/list/L = prompt.choices
	var/t1 = prompt.value
	var/count = 0	//num of portals from this teleport in world
	for(var/obj/effect/portal/PO in REGISTRY_MEMBERS(REGISTRY_PORTALS))
		if(PO.creator == src)	count++
	if(count >= 3)
		user.show_message(span_notice("\The [src] is recharging!"))
		return OP_OK
	var/T = L[t1]
	for(var/mob/O in hearers(user, null))
		O.show_message(span_notice("Locked In."), 2)
	var/obj/effect/portal/NEWP = new /obj/effect/portal( get_turf(src) )
	rel_set(NEWP, nameof(NEWP.target), T)
	NEWP.creator = src
	NEWP.failchance = 0 // funny 5% chance to be spaced and die makes the hand tele kinda useless.
	src.add_fingerprint(user)
	return OP_OK

