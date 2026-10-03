#define CHARS_PER_LINE 5
#define FONT_SIZE "5pt"
#define FONT_COLOR "#09f"
#define FONT_STYLE "Small Fonts"

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
	/// Counting down: true while the timer runs.
	var/timing = FALSE

	/// Brig closets sharing our id, found at LateInitialize (a relation view: they leave when they die).
	var/list/obj/targets
	/// Brig doors and flashers sharing our id (keyed: linked when either end materializes).
	var/list/obj/machinery/door/window/brigdoor/brig_doors
	var/list/obj/machinery/flasher/brig_flashers

	maptext_height = 26
	maptext_width = 32

TRACKED(/obj/machinery/door_timer, timing)

// ---- what a door timer is, declared ----
//
// It closes and locks the brig doors and closets of its cell for as long as it is set to, then lets them go, and counts down on its display. Its
// window sets the time (to a number of seconds or a preset added on), starts and stops it and fires the cell's flashers, for whoever has access.

MSG_DEF_SELF(door_timer/denied, "Access denied.")

CAPABILITIES(/obj/machinery/door_timer, \
	ref_many(nameof(targets), /obj/structure/closet/secure_closet/brig), \
	ref_many(nameof(brig_doors), /obj/machinery/door/window/brigdoor, by = nameof(id)), \
	ref_many(nameof(brig_flashers), /obj/machinery/flasher, by = nameof(id)), \
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(count_down)), when = nameof(timing)), \
	interface("BrigTimer", title = "Door Timer"), \
	op("time", ui_act("time", arg("time", int(0, MAX_TIMER))), then(PROC_REF(ui_time))), \
	op("start", ui_act("start"), then(PROC_REF(ui_start))), \
	op("stop", ui_act("stop"), then(PROC_REF(ui_stop))), \
	op("flash", ui_act("flash"), then(PROC_REF(ui_flash))), \
	op("preset", ui_act("preset", arg("preset", enum(list("short", "medium", "long")))), then(PROC_REF(ui_preset))), \
	extend(TAG_UI, needs(req(PROC_REF(timer_access), because = MSG(door_timer/denied)))))

/// Whoever has access works its window.
/obj/machinery/door_timer/proc/timer_access(datum/act/op/A)
	return allowed(A.actor) // ALLOW(reads): access is read when the button is pressed

/obj/machinery/door_timer/Initialize(mapload)
	..()
	return INITIALIZE_HINT_LATELOAD

/obj/machinery/door_timer/LateInitialize()
	// Brig closets are objects without a keyed index (outside this scope): still found by scan.
	for(var/obj/structure/closet/secure_closet/brig/C in REGISTRY_MEMBERS(REGISTRY_BRIG_CLOSETS))
		if(C.id == id)
			rel_add(src, nameof(targets), C)

	if(!LAZYLEN(targets) && !LAZYLEN(brig_doors) && !LAZYLEN(brig_flashers))
		atom_break()
	update_icon()

//Main door timer loop, if it's timing and time is >0 reduce time by 1.
// if it's less than 0, open door, reset timer
// update the door_timer window and the icon
/// Counts down (and redraws its display) while timing: when the time is up the doors open and the timer resets. A timer with no power waits.
/obj/machinery/door_timer/proc/count_down(datum/act/A)
	if(!operable())
		return
	if(ELAPSED(src, activation_time, CLOCK_WORLD) >= timer_duration)
		timer_end() // open doors, reset timer, clear status screen
	update_icon()

// open/closedoor checks if door_timer has power, if so it checks if the
// linked door is open/closed (by density) then opens it/closes it.

// Closes and locks doors, power check
/obj/machinery/door_timer/proc/timer_start()
	if(!operable())
		return 0

	EXPIRY_STAMP(src, activation_time, CLOCK_WORLD)
	set_timing(TRUE)

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

	set_timing(FALSE)
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

/// The computed part of the window data.
/obj/machinery/door_timer/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["timing"] = !!timing
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

/// Sets the time, in seconds.
/obj/machinery/door_timer/proc/ui_time(datum/act/op/A)
	var/new_time = A.args["time"]
	if(isnum(new_time) && new_time)
		set_timer(new_time * 10)
	return OP_OK

/obj/machinery/door_timer/proc/ui_start(datum/act/op/A)
	timer_start()
	return OP_OK

/obj/machinery/door_timer/proc/ui_stop(datum/act/op/A)
	timer_end(forced = TRUE)
	return OP_OK

/obj/machinery/door_timer/proc/ui_flash(datum/act/op/A)
	for(var/obj/machinery/flasher/F as anything in brig_flashers)
		F.flash()
	return OP_OK

/// A preset is added to the time left.
/obj/machinery/door_timer/proc/ui_preset(datum/act/op/A)
	var/preset_time = time_left()
	switch(A.args["preset"])
		if("short")
			preset_time = PRESET_SHORT
		if("medium")
			preset_time = PRESET_MEDIUM
		if("long")
			preset_time = PRESET_LONG
	set_timer(timer_duration + preset_time)
	if(timing)
		EXPIRY_STAMP(src, activation_time, CLOCK_WORLD)
	return OP_OK

//icon update function
// if NOPOWER, display blank
// if BROKEN, display blue screen of death icon AI uses
// if timing=true, run update display function
DECLARE_APPEARANCE_PROC(/obj/machinery/door_timer, TYPE_PROC_REF(/atom, appearance_overlays), list())
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

#undef PRESET_SHORT
#undef PRESET_MEDIUM
#undef PRESET_LONG

