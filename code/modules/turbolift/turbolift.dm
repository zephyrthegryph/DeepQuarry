// Lift master datum. One per turbolift.
/datum/turbolift
	var/tmp/datum/turbolift_floor/target_floor	// Where are we going?
	var/tmp/datum/turbolift_floor/current_floor	// Where is the lift currently?
	var/list/doors                                      // Doors inside the lift structure (REL_PAIR_LIST with each door's lift).
	var/list/queued_floors                     // Where are we moving to next?
	// ALLOW(instance_list): d: filled when the lift is built
	var/list/floors = list()                            // All floors in this system.
	var/move_delay = 30                                 // Time between floor changes.
	var/floor_wait_delay = 85                           // Time to wait at floor stops.
	var/obj/structure/lift/panel/control_panel_interior // Lift control panel.
	var/doors_closing = 0								// Whether doors are in the process of closing
	var/static/list/music = list('sound/music/elevator.ogg')	// Elevator music to set on areas
	var/priority_mode = FALSE							// Flag to block buttons from calling the elevator if in priority mode.
	var/fire_mode = FALSE								// Flag to indicate firefighter mode is active.

	var/tmp/moving_upwards
	EXPIRY_TMP_DECLARE(next_process) // world.time process() should next do something

CAPABILITIES(/datum/turbolift)
	owns_one(nameof(control_panel_interior), /obj/structure/lift/panel)
	owns_many(nameof(floors))

/// Used for controller processing: periodic_step() drives the lift while set (DECLARE_PERIODIC_WHILE).
OM_FIELD_TYPED(/datum/turbolift, tmp, busy_state, null, CHANGE_DATUM_A)
DECLARE_PERIODIC_WHILE(/datum/turbolift, PERIODIC_SECOND, "busy_state")

/datum/turbolift/New()
	..()
	lifecycle_decls_init(src) // starts the declaration (a non-atom has no materialize)

/datum/turbolift/proc/emergency_stop()
	cancel_pending_floors()
	rel_clear(src, nameof(target_floor))
	if(!fire_mode)
		open_doors()

// Enter priority mode, blocking all calls for awhile
/datum/turbolift/proc/priority_mode(time = 30 SECONDS)
	priority_mode = TRUE
	cancel_pending_floors()
	update_ext_panel_icons()
	control_panel_interior.audible_message(span_info("This turbolift is responding to a priority call.  Please exit the lift when it stops and make way."), runemessage = "BUZZ")
	after(src, time, PROC_REF(end_priority_mode))

/datum/turbolift/proc/update_fire_mode(new_fire_mode)
	if(fire_mode == new_fire_mode)
		return
	fire_mode = new_fire_mode
	if(new_fire_mode)
		cancel_pending_floors()

	// Turn the lights red and kill the music
	for(var/datum/turbolift_floor/F in floors)
		var/area/turbolift/A = locate(F.area_ref)
		if(new_fire_mode)
			if(A.forced_ambience)
				A.forced_ambience.Cut()
			A.fire_alert()
		else
			if(music)
				A.forced_ambience = music.Copy()
			A.fire_reset()
		for(var/mob/living/M in mobs_in_area(A))
			if(M.mind)
				A.play_ambience(M)
		// Disable safeties on the doors during firemode, reset when done
		for(var/obj/machinery/door/airlock/door in F.doors)
			turbolift_fire_safeties(door, src, new_fire_mode)

	// Disable safeties on the doors during firemode, reset when done
	for(var/obj/machinery/door/airlock/door in doors)
		turbolift_fire_safeties(door, src, new_fire_mode)
	update_ext_panel_icons()
	control_panel_interior.update_icon()

// Cancel all pending calls
/// Fire mode holds a door's safeties off for the lift; out of fire mode the lift lets go (the door's own safeties are back).
/proc/turbolift_fire_safeties(obj/machinery/door/airlock/door, datum/turbolift/lift, fire_mode)
	if(fire_mode)
		hold(door, STAT_SAFE, null, lift)
	else
		release(door, STAT_SAFE, lift)

/datum/turbolift/proc/cancel_pending_floors()
	for(var/datum/turbolift_floor/floor in queued_floors)
		if(floor.ext_panel)
			floor.ext_panel.reset()
	rel_clear(src, nameof(queued_floors))

// Update the icons of all exterior panels (after we change modes etc)
/datum/turbolift/proc/update_ext_panel_icons()
	for(var/datum/turbolift_floor/floor in floors)
		if(floor.ext_panel)
			changed(floor.ext_panel) // the button draws the lift's modes, which publish nothing

/datum/turbolift/proc/doors_are_open(datum/turbolift_floor/use_floor)
	if(!use_floor)
		use_floor = current_floor()
	for(var/obj/machinery/door/airlock/door in (list() + doors + use_floor?.doors))
		if(!door.density)
			return 1
	return 0

/datum/turbolift/proc/open_doors(datum/turbolift_floor/use_floor)
	if(!use_floor)
		use_floor = current_floor()
	for(var/obj/machinery/door/airlock/door in (list() + doors + use_floor?.doors))
		door.open()
	return

/datum/turbolift/proc/close_doors(datum/turbolift_floor/use_floor)
	if(!use_floor)
		use_floor = current_floor()
	for(var/obj/machinery/door/airlock/door in (list() + doors + use_floor?.doors))
		door.close()
	return

#define LIFT_MOVING    1	// Lift will try moving.
#define LIFT_WAITING_A 2	// Waiting 15ds after arrival to announce, then goto LIFT_WAITING_B
#define LIFT_WAITING_B 3	// Waiting floor_wait_delay after announcement before potentially moving again.

/datum/turbolift/periodic_step()
	if(EXPIRY_ACTIVE(src, next_process, CLOCK_WORLD))
		return
	switch(busy_state)
		if(LIFT_MOVING)
			if(!do_move())
				if(target_floor())
					// TODO - This logic copied from old processor.  Would be better to have error states.
					target_floor().ext_panel.reset()
					rel_clear(src, nameof(target_floor))
				set_busy_state(null)
				return
			else if(!next_process)
				log_runtime("Turbolift [src] do_move() returned 1 but next_process = null; busy_state=[busy_state]")
				set_busy_state(null)
				return
		if(LIFT_WAITING_A)
			var/area/turbolift/origin = locate(current_floor().area_ref)
			control_panel_interior.visible_message(span_infoplain(span_bold("The elevator") + " announces, \"[origin.lift_announce_str]\""))
			EXPIRY_SET(src, next_process, floor_wait_delay, CLOCK_WORLD)
			set_busy_state(LIFT_WAITING_B)
		if(LIFT_WAITING_B)
			if(length(queued_floors))
				set_busy_state(LIFT_MOVING)
			else
				set_busy_state(null)
		else
			log_runtime("Turbolift [src] process() called with unknown busy_state='[busy_state]'")
			set_busy_state(null)

// Called by process when in LIFT_MOVING
/datum/turbolift/proc/do_move()
	next_process = null

	var/current_floor_index = floors.Find(current_floor())

	if(!target_floor())
		if(!queued_floors || !length(queued_floors))
			return 0
		rel_set(src, nameof(target_floor), LAZYACCESS(queued_floors, 1))
		rel_remove(src, nameof(queued_floors), target_floor())
		if(current_floor_index < floors.Find(target_floor()))
			moving_upwards = 1
		else
			moving_upwards = 0

	if(doors_are_open())
		if(!doors_closing)
			close_doors()
			doors_closing = 1
			EXPIRY_SET(src, next_process, 1 SECOND, CLOCK_WORLD) // Wait for doors to close
			return 1
		else // We failed to close the doors - probably, someone is blocking them; stop trying to move
			doors_closing = 0
			if(!fire_mode)
				open_doors()
			control_panel_interior.audible_message("\The [current_floor().ext_panel] buzzes loudly.", runemessage = "BUZZ")
			playsound(control_panel_interior, "sound/machines/buzz-two.ogg", 50, 1)
			return 0

	doors_closing = 0 // The doors weren't open, so they are done closing

	GLOB.turbo_lift_floors_moved_roundstat++

	var/area/turbolift/origin = locate(current_floor().area_ref)

	if(target_floor() == current_floor())

		playsound(control_panel_interior, origin.arrival_sound, 50, 1)
		target_floor().arrived(src)
		rel_clear(src, nameof(target_floor))

		EXPIRY_SET(src, next_process, 15, CLOCK_WORLD)
		set_busy_state(LIFT_WAITING_A)
		return 1

	// Work out where we're headed.
	var/datum/turbolift_floor/next_floor
	if(moving_upwards)
		next_floor = floors[current_floor_index+1]
	else
		next_floor = floors[current_floor_index-1]

	var/area/turbolift/destination = locate(next_floor.area_ref)

	if(!istype(origin) || !istype(destination) || (origin == destination))
		return 0

	for(var/turf/T in area_contents_of_type(destination, /turf))
		for(var/atom/movable/AM in contents_of(T))
			if(isliving(AM) && !(AM.is_incorporeal()))
				var/mob/living/M = AM
				M.gib()
			else if(AM.simulated && !(istype(AM, /mob/observer)) && !(AM.is_incorporeal()))
				spent(AM)

	origin.move_contents_to(destination)

	if((locate_in_area(destination, /obj/machinery/power)) || (locate_in_area(destination, /obj/structure/cable)))
		SSmachines.power_reregister(get_area_turfs(destination))

	rel_set(src, nameof(current_floor), next_floor)
	control_panel_interior.visible_message("The elevator [moving_upwards ? "rises" : "descends"] smoothly.")

	EXPIRY_SET(src, next_process, (next_floor.delay_time || move_delay), CLOCK_WORLD)
	return 1

/datum/turbolift/proc/queue_move_to(datum/turbolift_floor/floor)
	if(!floor || !(floor in floors) || (floor in queued_floors))
		return // STOP PRESSING THE BUTTON.
	floor.pending_move(src)
	rel_add(src, nameof(queued_floors), floor)
	set_busy_state(LIFT_MOVING)

// TODO: dummy machine ('lift mechanism') in powered area for functionality/blackout checks.
/datum/turbolift/proc/is_functional()
	return 1

#undef LIFT_MOVING
#undef LIFT_WAITING_A
#undef LIFT_WAITING_B

/datum/turbolift/proc/end_priority_mode()
	priority_mode = FALSE
	update_ext_panel_icons()


/// Where are we going? (a relation view: it reads null once the target is deleted).
/datum/turbolift/proc/target_floor() as /datum/turbolift_floor
	return target_floor

/// Where is the lift currently? (a relation view: it reads null once the target is deleted).
/datum/turbolift/proc/current_floor() as /datum/turbolift_floor
	return current_floor
