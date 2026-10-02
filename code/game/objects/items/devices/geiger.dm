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

REGISTRY_MEMBERSHIP(/obj/item/geiger, REGISTRY_GEIGER_COUNTERS)

/obj/item/geiger/Initialize(mapload)
	. = ..()
	om_hook(src, /datum/om/event/before/in_range_of_irradiation, src, PROC_REF(on_pre_potential_irradiation))

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
/obj/item/geiger/proc/appearance_geiger_level()
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

DECLARE_APPEARANCE(/obj/item/geiger, "appearance_geiger_level", list( \
	"0" = list(APPEARANCE_ICON_STATE = "geiger_off"), \
	"1" = list(APPEARANCE_ICON_STATE = "geiger_on_1"), \
	"2" = list(APPEARANCE_ICON_STATE = "geiger_on_2"), \
	"3" = list(APPEARANCE_ICON_STATE = "geiger_on_3"), \
	"4" = list(APPEARANCE_ICON_STATE = "geiger_on_4"), \
	"5" = list(APPEARANCE_ICON_STATE = "geiger_on_5") \
))

DECLARE_INTERACTIONS(/obj/item/geiger, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ALT("Reset", PROC_REF(interaction_alt), REQ_BECAUSE(REQ_FIELD("scanning"), "it must be on to reset its radiation level")), \
)

/obj/item/geiger/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	scanning = !scanning

	if (scanning)
		if(!geiger_sound)
			own_set(src, nameof(geiger_sound), new /datum/geiger_sound(src))
	else
		own_clear(src, nameof(geiger_sound), OWN_DELETE)

	update_icon()
	balloon_alert(user, "switch [scanning ? "on" : "off"]")

/obj/item/geiger/afterattack(atom/interacting_with, mob/user, proximity_flag, click_parameters, stance = I_HURT)
	. = ..()
	if(SHOULD_SKIP_INTERACTION(interacting_with, src, stance))
		return NONE
	return attack_at_range(interacting_with, user, proximity_flag, click_parameters)

/obj/item/geiger/proc/attack_at_range(atom/interacting_with, mob/living/user, proximity_flag, click_parameters) //This is ranged_interact_with_atom on TG but we don't have that yet.
	if(!CAN_IRRADIATE(interacting_with))
		return NONE

	act_message(user, src, MSG_SELF(span_notice("You scan [interacting_with]'s radiation levels with %T%...")), MSG_OTHERS(span_notice("%U% scans [interacting_with] with %T%.")))
	om_after_unique(src, 20, PROC_REF(scan), interacting_with, user) // Let's not have spamming GetAllContents
	return ITEM_INTERACT_SUCCESS

/obj/item/geiger/equipped(mob/user, slot, initial)
	. = ..()

	om_hook(user, /datum/om/event/before/in_range_of_irradiation, src, PROC_REF(on_pre_potential_irradiation))

/obj/item/geiger/dropped(mob/user, equipping, slot)
	. = ..()

	om_unhook(user, /datum/om/event/before/in_range_of_irradiation, src)

/obj/item/geiger/proc/on_pre_potential_irradiation(datum/source, datum/om/event/before/in_range_of_irradiation/event)
	EVENT_HANDLER
	var/datum/radiation_pulse_information/pulse_information = event.pulse_information
	var/insulation_to_target = event.insulation_to_target

	last_perceived_radiation_danger = get_perceived_radiation_danger(pulse_information, insulation_to_target)
	last_radiation_strength = pulse_information.strength
	if(insulation_to_target > pulse_information.threshold)
		insulation_deficit = round(insulation_to_target - pulse_information.threshold, 0.1)
	else
		insulation_deficit = null
	om_after_replace(src, TIME_WITHOUT_RADIATION_BEFORE_RESET, PROC_REF(reset_perceived_danger))

	if (scanning)
		update_icon()

/obj/item/geiger/proc/reset_perceived_danger()
	last_perceived_radiation_danger = null
	last_radiation_strength = null
	insulation_deficit = null
	if (scanning)
		update_icon()

/obj/item/geiger/proc/scan(atom/target, mob/user)
	if (OM_EMIT(target, /datum/om/event/before/geiger_counter_scan, user, src) & GEIGER_COUNTER_SCAN_SUCCESSFUL)
		return

	if(isliving(target))
		var/mob/living/living_target = target
		if(living_target.radiation)
			to_chat(user, span_notice("[icon2html(src, user)] [living_target] is reporting a radiation level of [living_target.radiation]."))
			return

	to_chat(user, span_notice("[icon2html(src, user)] [isliving(target) ? "Subject" : "Target"] is free of radioactive contamination."))

/obj/item/geiger/proc/interaction_alt(mob/living/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("You flush [src]'s radiation counts, resetting it to normal."))
	last_perceived_radiation_danger = null
	update_icon()
	return TRUE

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
			own_set(src, nameof(geiger_sound), new /datum/geiger_sound/wall(src)) // ALLOW(decl): the sound is made only while the geiger is scanning, which a declaration cannot condition

DECLARE_APPEARANCE(/obj/item/geiger/wall, "appearance_geiger_level", list( \
	"0" = list(APPEARANCE_ICON_STATE = "geiger_wall-p"), \
	"1" = list(APPEARANCE_ICON_STATE = "geiger_level_1"), \
	"2" = list(APPEARANCE_ICON_STATE = "geiger_level_2"), \
	"3" = list(APPEARANCE_ICON_STATE = "geiger_level_3"), \
	"4" = list(APPEARANCE_ICON_STATE = "geiger_level_4"), \
	"5" = list(APPEARANCE_ICON_STATE = "geiger_level_5") \
))

EXTEND_INTERACTIONS(/obj/item/geiger/wall, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)), \
	INTERACT_SILICON("Toggle", PROC_REF(geiger_wall_silicon_use)), \
)

/// Old attack_ai: toggle it remotely.
/obj/item/geiger/wall/proc/geiger_wall_silicon_use(mob/user, obj/item/held, datum/interaction/interaction)
	src.add_fingerprint(user)
	om_after(src, 0, PROC_REF(attack_self), user)
	return TRUE

/// Old attack_hand.
/obj/item/geiger/wall/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	src.add_fingerprint(user)
	om_after(src, 0, PROC_REF(attack_self), user)
	return TRUE

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
