#define CHARS_PER_LINE 5
#define FONT_SIZE "5pt"
#define FONT_COLOR "#09f"
#define FONT_STYLE "Small Fonts"
#define MAX_TIMER 36000

#define PRESET_SHORT 1 MINUTES
#define PRESET_MEDIUM 5 MINUTES
#define PRESET_LONG 10 MINUTES

///////////////////////////////////////////////////////////////////////////////////////////////
// Brig Door control displays.
//  Description: This is a controls the timer for the brig doors, displays the timer on itself and
//               has a popup window when used, allowing to set the timer.
//  Code Notes: Combination of old brigdoor.dm code from rev4407 and the status_display.dm code
//  Date: 01/September/2010
//  Programmer: Veryinky
/////////////////////////////////////////////////////////////////////////////////////////////////
/obj/machinery/door_timer
	name = "Door Timer"
	icon = 'icons/obj/status_display.dmi'
	icon_state = "frame"
	layer = ABOVE_WINDOW_LAYER
	desc = "A remote control for a door."
	req_access = list(ACCESS_BRIG)
	anchored = TRUE    		// can't pick it up
	density = FALSE       		// can walk through it.
	flags = WALL_ITEM
	var/id = null     		// id of door it controls.
	EXPIRY_DECLARE(activation_time)
	var/timer_duration = 0

	var/timing = FALSE		// boolean, true/1 timer is on, false/0 means it's not timing
	var/list/obj/machinery/targets = list() // ALLOW(instance_list, object_keyed_lists): d: the timer's linked doors and flashers, filled at init

	maptext_height = 26
	maptext_width = 32

/obj/machinery/door_timer/Initialize(mapload)
	..()
	return INITIALIZE_HINT_LATELOAD

/obj/machinery/door_timer/LateInitialize()
	for(var/obj/machinery/door/window/brigdoor/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(M.id == id)
			LAZYADD(targets,M)

	for(var/obj/machinery/flasher/F in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(F.id == id)
			LAZYADD(targets,F)

	for(var/obj/structure/closet/secure_closet/brig/C in REGISTRY_MEMBERS(REGISTRY_BRIG_CLOSETS))
		if(C.id == id)
			LAZYADD(targets,C)
	for(var/atom/movable/target as anything in targets)
		om_hook(target, /datum/om/event/qdeleting, src, PROC_REF(target_deleted))

	if(!LAZYLEN(targets))
		stat_add(BROKEN)
	update_icon()

/obj/machinery/door_timer/proc/target_deleted(datum/source, datum/om/event/qdeleting/event)
	EVENT_HANDLER
	LAZYREMOVE(targets, source)

//Main door timer loop, if it's timing and time is >0 reduce time by 1.
// if it's less than 0, open door, reset timer
// update the door_timer window and the icon
/// Counts down (and redraws its display) while timing; otherwise it sleeps until timer_start(), or
/// until power returns to a timing unit.
/obj/machinery/door_timer/machine_step()
	if(!timing)
		return PROCESS_KILL
	if(!operable())
		return sleep_until_powered()
	if(ELAPSED(src, activation_time, CLOCK_WORLD) >= timer_duration)
		timer_end() // open doors, reset timer, clear status screen
	update_icon()
	if(!timing)
		return PROCESS_KILL

// open/closedoor checks if door_timer has power, if so it checks if the
// linked door is open/closed (by density) then opens it/closes it.

// Closes and locks doors, power check
/obj/machinery/door_timer/proc/timer_start()
	if(!operable())
		return 0

	EXPIRY_STAMP(src, activation_time, CLOCK_WORLD)
	timing = TRUE
	MACHINE_WAKE(src)

	for(var/obj/machinery/door/window/brigdoor/door in targets)
		if(door.density)
			continue
		door.close()

	for(var/obj/structure/closet/secure_closet/brig/C in targets)
		if(C.broken)
			continue
		if(C.opened && !C.close())
			continue
		C.locked = TRUE
		C.icon_state = "closed_locked"
	return 1

/// Opens and unlocks doors, power check
/obj/machinery/door_timer/proc/timer_end(forced = FALSE)
	if(!operable())
		return 0

	timing = FALSE
	activation_time = null
	set_timer(0)
	update_icon()

	for(var/obj/machinery/door/window/brigdoor/door in targets)
		if(!door.density)
			continue
		door.open()

	for(var/obj/structure/closet/secure_closet/brig/C in targets)
		if(C.broken)
			continue
		if(C.opened)
			continue
		C.locked = FALSE
		C.icon_state = "closed_unlocked"

	return 1

/obj/machinery/door_timer/proc/time_left(seconds = FALSE)
	. = max(0, timer_duration - (activation_time ? (world.time - activation_time) : 0))
	if(seconds)
		. /= 10

/obj/machinery/door_timer/proc/set_timer(value)
	var/new_time = clamp(value, 0, MAX_TIMER)
	. = new_time == timer_duration //return 1 on no change
	timer_duration = new_time
	if(timer_duration && activation_time && timing) // Setting it while active will reset the activation time
		EXPIRY_STAMP(src, activation_time, CLOCK_WORLD)

/obj/machinery/door_timer/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/open_ui,
	)
	..()

/obj/machinery/door_timer/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "BrigTimer", name)
		ui.open()

/obj/machinery/door_timer/tgui_data()
	var/list/data = list()
	data["time_left"] = time_left()
	data["max_time_left"] = MAX_TIMER
	data["timing"] = timing
	data["flash_found"] = FALSE
	data["flash_charging"] = FALSE
	data["preset_short"] = PRESET_SHORT
	data["preset_medium"] = PRESET_MEDIUM
	data["preset_long"] = PRESET_LONG
	for(var/obj/machinery/flasher/F in targets)
		data["flash_found"] = TRUE
		if(!COOLDOWN_FINISHED(F, flash_cooldown))
			data["flash_charging"] = TRUE
			break
	return data

/obj/machinery/door_timer/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return
	. = TRUE

	if(!allowed(ui.user))
		to_chat(ui.user, span_warning("Access denied."))
		return FALSE

	switch(action)
		if("time")
			var/real_new_time = 0
			var/new_time = params["time"]
			var/list/L = splittext(new_time, ":")
			if(LAZYLEN(L))
				for(var/i in 1 to LAZYLEN(L))
					real_new_time += text2num(L[i]) * (60 ** (LAZYLEN(L) - i))
			else
				real_new_time = text2num(new_time)
			if(real_new_time)
				set_timer(real_new_time * 10)
		if("start")
			timer_start()
		if("stop")
			timer_end(forced = TRUE)
		if("flash")
			for(var/obj/machinery/flasher/F in targets)
				F.flash()
		if("preset")
			var/preset = params["preset"]
			var/preset_time = time_left()
			switch(preset)
				if("short")
					preset_time = PRESET_SHORT
				if("medium")
					preset_time = PRESET_MEDIUM
				if("long")
					preset_time = PRESET_LONG
			set_timer(timer_duration + preset_time)
			if(timing)
				EXPIRY_STAMP(src, activation_time, CLOCK_WORLD)
		else
			. = FALSE

//icon update function
// if NOPOWER, display blank
// if BROKEN, display blue screen of death icon AI uses
// if timing=true, run update display function
DECLARE_APPEARANCE_PROC(/obj/machinery/door_timer, PROC_REF(appearance_overlays), list())
/obj/machinery/door_timer/appearance_overlays()
	. = list()
	if(has_stat(NOPOWER))
		icon_state = "frame"
		return .

	if(has_stat(BROKEN))
		set_picture("ai_bsod")
		return .

	if(timing)
		var/disp1 = id
		var/timeleft = time_left(seconds = TRUE)
		var/disp2 = "[add_leading(num2text((timeleft / 60) % 60), 2, "0")]:[add_leading(num2text(timeleft % 60), 2, "0")]"
		if(length(disp2) > CHARS_PER_LINE)
			disp2 = "Error"
		update_display(disp1, disp2)
	else
		if(maptext)
			maptext = ""
	return .

// Adds an icon in case the screen is broken/off, stolen from status_display.dm
/obj/machinery/door_timer/proc/set_picture(state)
	if(maptext)
		maptext = ""
	cut_overlays()
	add_overlay(mutable_appearance('icons/obj/status_display.dmi', state))

//Checks to see if there's 1 line or 2, adds text-icons-numbers/letters over display
// Stolen from status_display
/obj/machinery/door_timer/proc/update_display(line1, line2)
	line1 = uppertext(line1)
	line2 = uppertext(line2)
	var/new_text = {"<div style="font-size:[FONT_SIZE];color:[FONT_COLOR];font:'[FONT_STYLE]';text-align:center;" valign="top">[line1]<br>[line2]</div>"}
	if(maptext != new_text)
		maptext = new_text

/obj/machinery/door_timer/cell_1
	name = "Cell 1"
	id = "Cell 1"

/obj/machinery/door_timer/cell_2
	name = "Cell 2"
	id = "Cell 2"

/obj/machinery/door_timer/cell_3
	name = "Cell 3"
	id = "Cell 3"

/obj/machinery/door_timer/cell_4
	name = "Cell 4"
	id = "Cell 4"

/obj/machinery/door_timer/cell_5
	name = "Cell 5"
	id = "Cell 5"

/obj/machinery/door_timer/cell_6
	name = "Cell 6"
	id = "Cell 6"

/obj/machinery/door_timer/tactical_pet_storage // ition
	name = "Tactical Pet Storage"
	id = "tactical_pet_storage"
	desc = "Opens and Closes on a timer. This one seals away a tactical boost in morale."

#undef FONT_SIZE
#undef FONT_COLOR
#undef FONT_STYLE
#undef CHARS_PER_LINE

#undef MAX_TIMER

#undef PRESET_SHORT
#undef PRESET_MEDIUM
#undef PRESET_LONG

DECLARE_REF(/obj/machinery/door_timer, "targets", HELD, null)
