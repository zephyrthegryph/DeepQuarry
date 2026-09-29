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
	/// Brig closets sharing our id, found at LateInitialize (a relation view: they leave when they die).
	var/list/obj/targets
	/// Brig doors and flashers sharing our id (keyed: linked when either end materializes).
	var/list/obj/machinery/door/window/brigdoor/brig_doors
	var/list/obj/machinery/flasher/brig_flashers

	maptext_height = 26
	maptext_width = 32

/obj/machinery/door_timer/Initialize(mapload)
	..()
	return INITIALIZE_HINT_LATELOAD

REL_LIST(/obj/machinery/door_timer, targets)
REL_KEYED_LIST(/obj/machinery/door_timer, brig_doors, id, /obj/machinery/door/window/brigdoor)
REL_KEYED_LIST(/obj/machinery/door_timer, brig_flashers, id, /obj/machinery/flasher)

/obj/machinery/door_timer/LateInitialize()
	// Brig closets are objects without a keyed index (outside this scope): still found by scan.
	for(var/obj/structure/closet/secure_closet/brig/C in REGISTRY_MEMBERS(REGISTRY_BRIG_CLOSETS))
		if(C.id == id)
			rel_add(src, "targets", C)

	if(!LAZYLEN(targets) && !LAZYLEN(brig_doors) && !LAZYLEN(brig_flashers))
		stat_add(BROKEN)
	update_icon()

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

// has the door power situation changed, if so update icon.
/obj/machinery/door_timer/power_change()
	. = ..()
	update_icon()

// open/closedoor checks if door_timer has power, if so it checks if the
// linked door is open/closed (by density) then opens it/closes it.

// Closes and locks doors, power check
/obj/machinery/door_timer/proc/timer_start()
	if(!operable())
		return 0

	EXPIRY_STAMP(src, activation_time, CLOCK_WORLD)
	timing = TRUE
	MACHINE_WAKE(src)

	for(var/obj/machinery/door/window/brigdoor/door as anything in brig_doors)
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

	for(var/obj/machinery/door/window/brigdoor/door as anything in brig_doors)
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

DECLARE_UI(/obj/machinery/door_timer, "BrigTimer")

UI_DATA_REPLACE(/obj/machinery/door_timer, "timing:num", "merge:ui_data_obj_machinery_door_timer{time_left:unknown,max_time_left:num,flash_found:bool,flash_charging:bool,preset_short:unknown,preset_medium:unknown,preset_long:unknown}")

/// The computed part of /obj/machinery/door_timer's window data (declared on its UI_DATA row).
/obj/machinery/door_timer/proc/ui_data_obj_machinery_door_timer(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["time_left"] = time_left()
	data["max_time_left"] = MAX_TIMER
	data["flash_found"] = FALSE
	data["flash_charging"] = FALSE
	data["preset_short"] = PRESET_SHORT
	data["preset_medium"] = PRESET_MEDIUM
	data["preset_long"] = PRESET_LONG
	for(var/obj/machinery/flasher/F as anything in brig_flashers)
		data["flash_found"] = TRUE
		if(!COOLDOWN_FINISHED(F, flash_cooldown))
			data["flash_charging"] = TRUE
			break
	return data

/obj/machinery/door_timer/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!allowed(ui.user))
		to_chat(ui.user, span_warning("Access denied."))
		return FALSE
	return TRUE

UI_ACT(/obj/machinery/door_timer, "time", ui_act_time, UI_ARG_NUM("time"))
UI_ACT_PROC(/obj/machinery/door_timer, ui_act_time)
	. = TRUE
	var/real_new_time = 0
	var/new_time = params["time"]
	if(isnum(new_time))
		real_new_time = new_time
	else
		var/list/L = splittext(new_time, ":")
		for(var/i in 1 to LAZYLEN(L))
			real_new_time += text2num(L[i]) * (60 ** (LAZYLEN(L) - i))
	if(real_new_time)
		set_timer(real_new_time * 10)

UI_ACT(/obj/machinery/door_timer, "start", ui_act_start)
UI_ACT_PROC(/obj/machinery/door_timer, ui_act_start)
	. = TRUE
	timer_start()

UI_ACT(/obj/machinery/door_timer, "stop", ui_act_stop)
UI_ACT_PROC(/obj/machinery/door_timer, ui_act_stop)
	. = TRUE
	timer_end(forced = TRUE)

UI_ACT(/obj/machinery/door_timer, "flash", ui_act_flash)
UI_ACT_PROC(/obj/machinery/door_timer, ui_act_flash)
	. = TRUE
	for(var/obj/machinery/flasher/F as anything in brig_flashers)
		F.flash()

UI_ACT(/obj/machinery/door_timer, "preset", ui_act_preset, UI_ARG_TEXT("preset"))
UI_ACT_PROC(/obj/machinery/door_timer, ui_act_preset)
	. = TRUE
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

//icon update function
// if NOPOWER, display blank
// if BROKEN, display blue screen of death icon AI uses
// if timing=true, run update display function
/obj/machinery/door_timer/update_icon()
	if(has_stat(NOPOWER))
		icon_state = "frame"
		return

	if(has_stat(BROKEN))
		set_picture("ai_bsod")
		return

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
	return

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

