MATERIAL_MIX(/obj/item/geiger, list(/datum/material/steel = SHEET_MATERIAL_AMOUNT * 1.5, /datum/material/glass = SHEET_MATERIAL_AMOUNT * 1.5))
/obj/item/geiger //DISCLAIMER: I know nothing about how real-life Geiger counters work. This will not be realistic. ~Xhuis
	name = "\improper Geiger counter"
	desc = "A handheld device used for detecting and measuring radiation pulses."
	icon = 'icons/obj/devices/scanner.dmi'
	icon_state = "geiger_off"
	item_state = "multitool"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/inhands/equipment/tools_lefthand.dmi',
		slot_r_hand_str = 'icons/mob/inhands/equipment/tools_righthand.dmi',
		)
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_BELT
	item_flags = NOBLUDGEON

	var/last_perceived_radiation_danger = null
	///How strong the last radiation pulse was, at the source.
	var/last_radiation_strength = null
	///How much insulation we're lacking.
	var/insulation_deficit = null

	var/scanning = FALSE

	var/mounted = FALSE

TRACKED(/obj/item/geiger, scanning)
TRACKED(/obj/item/geiger, last_perceived_radiation_danger)

CAPABILITIES(/obj/item/geiger)
	owns_one(nameof(geiger_sound), /datum/geiger_sound)
	op("toggle", in_hand(), then(PROC_REF(toggled)))
	op("reset", hand(), gesture(GESTURE_ALT), label("Reset"), needs(req_bool(PROC_REF(is_scanning), because = MSG(geiger/off))), then(PROC_REF(reset_counts)))

MSG_DEF_SELF(geiger/off, "It must be on to reset its radiation level.")

REGISTRY_MEMBERSHIP(/obj/item/geiger, REGISTRY_GEIGER_COUNTERS)

/obj/item/geiger/Initialize(mapload)
	. = ..()
	observe(src, /datum/notice/in_range_of_irradiation, src, then(PROC_REF(on_pre_potential_irradiation)))

/obj/item/geiger/examine(mob/user)
	. = ..()
	if(!scanning)
		return
	. += span_info("Alt-click it to clear stored radiation levels.")
	switch(last_perceived_radiation_danger)
		if(null)
			. += span_notice("Ambient radiation level count reports that all is well. It is ") + span_green("safe ") + span_notice("here.")
		if(PERCEIVED_RADIATION_DANGER_LOW)
			. += span_notice("Ambient radiation levels slightly above average. It is ") + span_green("safe ") + span_notice("here.")
		if(PERCEIVED_RADIATION_DANGER_MEDIUM)
			. += span_notice("Ambient radiation levels above average. It is ") + span_green("safe ") + span_notice("here.")
		if(PERCEIVED_RADIATION_DANGER_HIGH)
			. += span_suicide("Ambient radiation levels highly above average. It is ") + span_warning("unsafe ") + span_suicide("here.")
		if(PERCEIVED_RADIATION_DANGER_EXTREME)
			. += span_suicide("Ambient radiation levels reaching critical levels! It is ") + span_warning("extremely unsafe ") + span_suicide("here.")
	if(last_radiation_strength)
		. += span_notice("Maximum strength at source of radioactive pulse: ") + span_warning("[last_radiation_strength]")
	if(insulation_deficit)
		. += span_warning("Insulation deficit: [insulation_deficit]")

/// 0 while not scanning, else 1..5 by the last perceived danger (null reads as 1).
/obj/item/geiger/proc/geiger_level()
	if(!scanning)
		return 0
	switch(last_perceived_radiation_danger)
		if(null)
			return 1
		if(PERCEIVED_RADIATION_DANGER_LOW)
			return 2
		if(PERCEIVED_RADIATION_DANGER_MEDIUM)
			return 3
		if(PERCEIVED_RADIATION_DANGER_HIGH)
			return 4
		if(PERCEIVED_RADIATION_DANGER_EXTREME)
			return 5
	return -1

/obj/item/geiger/draw(datum/look/look)
	..()
	look.state(level_icon_state(geiger_level()))

/// The icon state of a level (0 is off, 1 to 5 by the danger).
/obj/item/geiger/proc/level_icon_state(level)
	if(level <= 0)
		return "geiger_off"
	return "geiger_on_[min(level, 5)]"

/// The in-hand use: switch it on or off.
/obj/item/geiger/proc/toggled(datum/act/op/A)
	var/mob/user = A.actor
	set_scanning(!scanning)

	if (scanning)
		if(!geiger_sound)
			rel_set(src, nameof(geiger_sound), new /datum/geiger_sound(src))
	else
		rel_clear(src, nameof(geiger_sound))

	balloon_alert(user, "switch [scanning ? "on" : "off"]")
	return OP_OK

/obj/item/geiger/afterattack(atom/interacting_with, mob/user, proximity_flag, click_parameters, stance = I_HURT)
	. = ..()
	if(SHOULD_SKIP_INTERACTION(interacting_with, src, stance))
		return NONE
	return attack_at_range(interacting_with, user, proximity_flag, click_parameters)

/obj/item/geiger/proc/attack_at_range(atom/interacting_with, mob/living/user, proximity_flag, click_parameters) //This is ranged_interact_with_atom on TG but we don't have that yet.
	if(!CAN_IRRADIATE(interacting_with))
		return NONE

	act_message(user, src, MSG_SELF(span_notice("You scan [interacting_with]'s radiation levels with %T%...")), MSG_OTHERS(span_notice("%U% scans [interacting_with] with %T%.")))
	var/scan_key = "geiger_scan:[interacting_with ? SHARED_CACHE_UID(interacting_with) : "-"]:[user ? SHARED_CACHE_UID(user) : "-"]"
	if(!after_pending(src, scan_key))
		after(src, 2 SECONDS, PROC_REF(scan), key = scan_key, with = list(interacting_with, user)) // Let's not have spamming GetAllContents
	return ITEM_INTERACT_SUCCESS

/obj/item/geiger/equipped(mob/user, slot, initial)
	. = ..()

	observe(user, /datum/notice/in_range_of_irradiation, src, then(PROC_REF(on_pre_potential_irradiation)))

/obj/item/geiger/dropped(mob/user, equipping, slot)
	. = ..()

	unobserve(user, /datum/notice/in_range_of_irradiation, src)

/obj/item/geiger/proc/on_pre_potential_irradiation(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/in_range_of_irradiation/event = N
	var/datum/radiation_pulse_information/pulse_information = event.pulse_information
	var/insulation_to_target = event.insulation_to_target

	set_last_perceived_radiation_danger(get_perceived_radiation_danger(pulse_information, insulation_to_target))
	last_radiation_strength = pulse_information.strength
	if(insulation_to_target > pulse_information.threshold)
		insulation_deficit = round(insulation_to_target - pulse_information.threshold, 0.1)
	else
		insulation_deficit = null
	after(src, TIME_WITHOUT_RADIATION_BEFORE_RESET, PROC_REF(reset_perceived_danger), key = "geiger_perceived_danger_reset")


/obj/item/geiger/proc/reset_perceived_danger()
	set_last_perceived_radiation_danger(null)
	last_radiation_strength = null
	insulation_deficit = null

/obj/item/geiger/proc/scan(atom/target, mob/user)
	var/datum/act/geiger_scan/scan = ACT_TRY(target, geiger_scan, user, src)
	if(!scan)
		return // the target answered the scan itself
	act_cancel(scan)

	if(isliving(target))
		var/mob/living/living_target = target
		if(living_target.radiation)
			to_chat(user, span_notice("[icon2html(src, user)] [living_target] is reporting a radiation level of [living_target.radiation]."))
			return

	to_chat(user, span_notice("[icon2html(src, user)] [isliving(target) ? "Subject" : "Target"] is free of radioactive contamination."))

/// A running counter can be told to forget what it measured.
/obj/item/geiger/proc/is_scanning(datum/act/A)
	return scanning

/// The alt-click: flush the stored radiation levels.
/obj/item/geiger/proc/reset_counts(datum/act/op/A)
	to_chat(A.actor, span_notice("You flush [src]'s radiation counts, resetting it to normal."))
	set_last_perceived_radiation_danger(null)
	return OP_OK

/obj/item/geiger/wall
	name = "mounted geiger counter"
	desc = "A wall mounted device used for detecting and measuring radiation in an area."
	icon = 'icons/obj/device.dmi'
	icon_state = "geiger_wall"
	item_state = "geiger_wall"
	anchored = TRUE
	scanning = TRUE
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER
	w_class = ITEMSIZE_LARGE
	flags = NOBLOODY|WALL_ITEM
	var/circuit = /obj/item/circuitboard/geiger
	var/number = 0
	var/last_tick //used to delay the powercheck
	var/wiresexposed = FALSE
	mounted = TRUE

/obj/item/geiger/wall/Initialize(mapload)
	. = ..()
	if(scanning)
		if(!geiger_sound)
			rel_set(src, nameof(geiger_sound), new /datum/geiger_sound/wall(src)) // ALLOW(decl): the sound is made only while the geiger is scanning, which a declaration cannot condition

CAPABILITIES(/obj/item/geiger/wall)
	op("wall_toggle", inputs(hand(), remote()), then(PROC_REF(wall_toggled)))

/// The wall counter keeps its own icon states.
/obj/item/geiger/wall/level_icon_state(level)
	if(level <= 0)
		return "geiger_wall-p"
	return "geiger_level_[min(level, 5)]"

/// An empty hand, or a silicon from afar, switches it like using it in the hand.
/obj/item/geiger/wall/proc/wall_toggled(datum/act/op/A)
	add_fingerprint(A.actor)
	toggled(A)
	return OP_OK

/obj/item/geiger/wall/north
	pixel_y = 28
	dir = SOUTH

/obj/item/geiger/wall/south
	pixel_y = -28
	dir = NORTH

/obj/item/geiger/wall/east
	pixel_x = 28
	dir = EAST

/obj/item/geiger/wall/west
	pixel_x = -28
	dir = WEST
