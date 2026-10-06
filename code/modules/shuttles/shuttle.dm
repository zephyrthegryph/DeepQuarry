//shuttle moving state defines are in setup.dm

/datum/shuttle
	var/name = ""
	var/warmup_time = 0
	var/moving_status = SHUTTLE_IDLE
	/// Throttles the hyperspace progress sound during a long jump (every 4 seconds).
	COOLDOWN_DECLARE(progress_sound_cooldown)

	var/list/shuttle_area // Initial value can be either a single area type or a list of area types
	var/tmp/obj/effect/shuttle_landmark/current_location	//Set current_location_tag, not this: New() resolves the tag into the landmark.
	var/current_location_tag	// the tag it starts as; resolved into current_location at init

	EXPIRY_TMP_DECLARE(arrive_time) //the time at which the shuttle arrives when long jumping
	var/process_state = IDLE_STATE // Used with SHUTTLE_FLAGS_PROCESS, as well as to store current state. Written by set_process_state().
	var/always_process = FALSE // Automated shuttles may need idle-state checks.
	var/category = /datum/shuttle
	var/multiz = 0	//how many multiz levels, starts at 0 TODO Leshana - Are we porting this?

	var/ceiling_type // Type path of turf to roof over the shuttle when at multi-z landmarks. Ignored if null.

	var/sound_takeoff = 'sound/effects/shuttles/shuttle_takeoff.ogg'
	var/sound_landing = 'sound/effects/shuttles/shuttle_landing.ogg'

	var/knockdown = 1 //whether shuttle downs non-buckled people when it moves

	var/defer_initialisation = FALSE //If this this shuttle should be initialised automatically.
									//If set to true, you are responsible for initialzing the shuttle manually.
									//Useful for shuttles that are initialized by map_template loading, or shuttles that are created in-game or not used.

	var/mothershuttle 	//tag of mothershuttle
	var/motherdock		//tag of mothershuttle landmark, defaults to starting location

	EXPIRY_TMP_DECLARE(depart_time) //Similar to above, set when the shuttle leaves when long jumping. Used for progress bars.

	var/debug_logging = FALSE // If set to true, the shuttle will start broadcasting its debug messages to admins

	// Future Thoughts: Baystation put "docking" stuff in a subtype, leaving base type pure and free of docking stuff. Is this best?

OM_FLAG_FIELD(/datum/shuttle, shuttle_flags, SHUTTLE_FLAGS_NONE, CHANGE_DATUM_A)
OM_FIELD_SETTER(/datum/shuttle, process_state, CHANGE_DATUM_A)
/// TRUE while the shuttle has launch/move work: it processes and it is launching, moving or always processing.
OM_DERIVE_FIELD(/datum/shuttle, shuttle_working, list("shuttle_flags", "process_state"))
/// Long jump in transit. A field: the transit repeat runs while it is set. It is a flag rather than
/// the destination view itself, so a landmark destroyed mid-jump still ends the jump at arrival time
/// (falling back to the start) instead of stranding the shuttle in transit.
OM_FIELD_TYPED(/datum/shuttle, tmp, transit_active, FALSE, CHANGE_DATUM_B)
/// Long jump in transit: the destination and start landmarks (relation views), and whether the
/// landing warning was made.
/datum/shuttle/var/tmp/obj/effect/shuttle_landmark/transit_dest
/datum/shuttle/var/tmp/obj/effect/shuttle_landmark/transit_start
/datum/shuttle/var/tmp/transit_warned = FALSE
DECLARE_REPEAT(/datum/shuttle, 5, long_jump_transit, "transit_active")
/// One shuttle_step() every 2 s while it has work (code/controllers/subsystems/shuttles.dm).
DECLARE_PERIODIC_WHILE(/datum/shuttle, PERIODIC_SLOW, "shuttle_working")

/datum/shuttle/proc/shuttle_working()
	return (shuttle_flags & SHUTTLE_FLAGS_PROCESS) && (always_process || process_state != IDLE_STATE)

/datum/shuttle/New(_name, obj/effect/shuttle_landmark/initial_location)
	..()
	if(_name)
		src.name = _name

	var/list/areas = list()
	if(!islist(shuttle_area))
		shuttle_area = list(shuttle_area)
	for(var/T in shuttle_area)
		var/area/A = locate(T)
		if(!istype(A))
			CRASH("Shuttle \"[name]\" couldn't locate area [T].")
		areas += A
	shuttle_area = areas

	if(initial_location)
		rel_set(src, nameof(current_location), initial_location)
	else
		rel_set(src, nameof(current_location), SSshuttles.get_landmark(current_location_tag))
	if(!istype(current_location(), /obj/effect/shuttle_landmark))
		// landmark missing usually means the shuttle's home map
		// was removed. Log once and skip registration so subtype New()s
		// don't trip null derefs on current_location.docking_controller.
		log_shuttle("Shuttle '[name]' could not find its starting location landmark; skipping registration.")
		return

	if(src.name in SSshuttles.shuttles)
		CRASH("A shuttle with the name '[name]' is already defined.")
	SSshuttles.shuttles[src.name] = src
	if(shuttle_flags & SHUTTLE_FLAGS_PROCESS)
		SSshuttles.process_shuttles += src
	if(shuttle_flags & SHUTTLE_FLAGS_SUPPLY)
		if(SSsupply.shuttle)
			CRASH("A supply shuttle is already defined.")
		SSsupply.shuttle = src
	// Starts DECLARE_PERIODIC_WHILE / DECLARE_REPEAT (a non-atom has no materialize). Only once
	// registered: a shuttle that skipped registration above is dropped by its creator, and a
	// started declaration would give it an OM record that keeps it alive (an ownership-audit
	// "dropped with a rec" orphan).
	lifecycle_decls_init(src)

// leaves SSshuttles and the supply shuttle slot.
/datum/shuttle/lifecycle_dematerialize()
	SSshuttles.shuttles -= src.name
	SSshuttles.process_shuttles -= src
	SSshuttles.shuttle_logs -= src
	if(SSsupply.shuttle == src)
		SSsupply.shuttle = null
	return ..()

/// The process_state setter: om_set() writes it and raises its declared channel (CHANGE_DATUM_A),
/// which also refreshes shuttle_working.
/datum/shuttle/proc/set_process_state(new_state)
	return om_set(src, "process_state", new_state)

// This is called after all shuttles have been initialized by SSshuttles, but before sectors have been initialized.
// Importantly for subtypes, all shuttles will have been initialized and mothershuttles hooked up by the time this is called.
/datum/shuttle/proc/populate_shuttle_objects()
	// Scan for shuttle consoles on them needing auto-config.
	for(var/area/A in find_childfree_areas()) // Let sub-shuttles handle their areas, only do our own.
		for(var/obj/machinery/computer/shuttle_control/SC in contents_of(A))
			if(!SC.shuttle_tag)
				SC.set_shuttle_tag(src.name)
	return

// This creates a graphical warning to where the shuttle is about to land, in approximately five seconds.
/datum/shuttle/proc/create_warning_effect(obj/effect/shuttle_landmark/destination)
	if(!destination) // No landmark, no warning to draw — callers may legitimately pass a null interim.
		return
	destination.create_warning_effect(src)

// Return false to abort a jump, before the 'warmup' phase.
/datum/shuttle/proc/pre_warmup_checks()
	return TRUE

// Ditto, but for afterwards.
/datum/shuttle/proc/post_warmup_checks()
	return TRUE

// If you need an event to occur when the shuttle jumps in short or long jump, override this.
// Keep in mind that destination is the intended destination, the shuttle may or may not actually reach it.s
/datum/shuttle/proc/on_shuttle_departure(obj/effect/shuttle_landmark/origin, obj/effect/shuttle_landmark/destination)
	return

// Similar to above, but when it finishes moving to the target. Short jump generally makes this occur immediately after the above proc.
// Keep in mind we might not actually have gotten to destination. Check current_location to be sure where we ended up.
/datum/shuttle/proc/on_shuttle_arrival(obj/effect/shuttle_landmark/origin, obj/effect/shuttle_landmark/destination)
	return

/datum/shuttle/proc/short_jump(obj/effect/shuttle_landmark/destination)
	if(!destination) // Jumping to nowhere would runtime in attempt_move; refuse up front.
		log_shuttle("Shuttle [src] refused short_jump(): null destination landmark.")
		return
	if(moving_status != SHUTTLE_IDLE)
		return

	if(!pre_warmup_checks())
		return

	var/obj/effect/shuttle_landmark/start_location = current_location()
	// TODO - Figure out exactly when to play sounds. Before warmup_time delay? Should there be a sleep for waiting for sounds? or no?
	moving_status = SHUTTLE_WARMUP
	publish_schedule()
	after(src, warmup_time*10, PROC_REF(short_jump_warmed_up), with = list(start_location, destination))

/datum/shuttle/proc/short_jump_warmed_up(obj/effect/shuttle_landmark/start_location, obj/effect/shuttle_landmark/destination)
	make_sounds(HYPERSPACE_WARMUP)
	create_warning_effect(destination)
	after(src, 5 SECONDS, PROC_REF(short_jump_go), with = list(start_location, destination)) // so the sound finishes.

/datum/shuttle/proc/short_jump_go(obj/effect/shuttle_landmark/start_location, obj/effect/shuttle_landmark/destination)
	if(!post_warmup_checks())
		cancel_launch(null)

	if(!fuel_check()) //fuel error (probably out of fuel) occured, so cancel the launch
		cancel_launch(null)

	if (moving_status == SHUTTLE_IDLE)
		make_sounds(HYPERSPACE_END)
		return	//someone cancelled the launch

	moving_status = SHUTTLE_INTRANSIT //shouldn't matter but just to be safe
	on_shuttle_departure(start_location, destination)

	attempt_move(destination)

	moving_status = SHUTTLE_IDLE
	on_shuttle_arrival(start_location, destination)

	make_sounds(HYPERSPACE_END)

// TODO - Far Future - Would be great if this was driven by process too.
/datum/shuttle/proc/long_jump(obj/effect/shuttle_landmark/destination, obj/effect/shuttle_landmark/interim, travel_time)
	if(!destination || !interim) // Both landmarks get dereferenced below; a null either way is a config error (e.g. a destination whose map landmark was trimmed).
		log_shuttle("Shuttle [src] refused long_jump(): destination=[destination || "null"], interim=[interim || "null"].")
		return
	if(moving_status != SHUTTLE_IDLE)
		return

	if(!pre_warmup_checks())
		return

	var/obj/effect/shuttle_landmark/start_location = current_location()
	// TODO - Figure out exactly when to play sounds. Before warmup_time delay? Should there be a sleep for waiting for sounds? or no?
	moving_status = SHUTTLE_WARMUP
	publish_schedule()
	after(src, warmup_time*10, PROC_REF(long_jump_warmed_up), with = list(start_location, destination, interim, travel_time))

/datum/shuttle/proc/long_jump_warmed_up(obj/effect/shuttle_landmark/start_location, obj/effect/shuttle_landmark/destination, obj/effect/shuttle_landmark/interim, travel_time)
	make_sounds(HYPERSPACE_WARMUP)
	create_warning_effect(interim) // Really doubt someone is gonna get crushed in the interim area but for completeness's sake we'll make the warning.
	after(src, 5 SECONDS, PROC_REF(long_jump_depart), with = list(start_location, destination, interim, travel_time)) // so the sound finishes.

/datum/shuttle/proc/long_jump_depart(obj/effect/shuttle_landmark/start_location, obj/effect/shuttle_landmark/destination, obj/effect/shuttle_landmark/interim, travel_time)
	if(!post_warmup_checks())
		cancel_launch(null)

	if (moving_status == SHUTTLE_IDLE)
		make_sounds(HYPERSPACE_END)
		return	//someone cancelled the launch

	EXPIRY_SET(src, arrive_time, travel_time*10, CLOCK_WORLD)
	EXPIRY_STAMP(src, depart_time, CLOCK_WORLD)

	moving_status = SHUTTLE_INTRANSIT
	on_shuttle_departure(start_location, destination)

	if(!attempt_move(interim, TRUE))
		long_jump_arrived(start_location, destination)
		return
	interim.shuttle_arrived()

	if(process_longjump(current_location(), destination)) // To hook custom shuttle code in
		return // It handled it for us (shuttle crash or such)

	COOLDOWN_RESET(src, progress_sound_cooldown)
	rel_set(src, nameof(transit_start), start_location)
	rel_set(src, nameof(transit_dest), destination)
	transit_warned = FALSE
	set_transit_active(TRUE) // the transit repeat runs while this is set
	long_jump_transit()

/// In transit: every half second until arrival time (DECLARE_REPEAT while transit_active is set),
/// the travel sound every four seconds (the sound file is five) and the landing warning five seconds out.
/datum/shuttle/proc/long_jump_transit()
	var/obj/effect/shuttle_landmark/start_location = transit_start
	var/obj/effect/shuttle_landmark/destination = transit_dest
	if(EXPIRY_EXPIRED(src, arrive_time, CLOCK_WORLD))
		set_transit_active(FALSE)
		rel_clear(src, nameof(transit_dest))
		rel_clear(src, nameof(transit_start))
		if(!attempt_move(destination))
			attempt_move(start_location) //try to go back to where we started. If that fails, I guess we're stuck in the interim location
		long_jump_arrived(start_location, destination)
		return
	if(COOLDOWN_FINISHED(src, progress_sound_cooldown))
		make_sounds(HYPERSPACE_PROGRESS)
		COOLDOWN_START(src, progress_sound_cooldown, 4 SECONDS)

	if(EXPIRY_LEFT(src, arrive_time, CLOCK_WORLD) <= 5 SECONDS && !transit_warned)
		transit_warned = TRUE
		create_warning_effect(destination)

/datum/shuttle/proc/long_jump_arrived(obj/effect/shuttle_landmark/start_location, obj/effect/shuttle_landmark/destination)
	moving_status = SHUTTLE_IDLE
	on_shuttle_arrival(start_location, destination)
	make_sounds(HYPERSPACE_END)

//////////////////////////////
// Forward declarations of public procs. They do nothing because this is not auto-dock.

/datum/shuttle/proc/fuel_check()
	return 1 //fuel check should always pass in non-overmap shuttles (they have magic engines)

/datum/shuttle/proc/cancel_launch(user, mob/actor)
	// If we are past warming up its too late to cancel.
	if (moving_status == SHUTTLE_WARMUP)
		moving_status = SHUTTLE_IDLE
/*
	Docking stuff
*/
/datum/shuttle/proc/dock()
	return

/datum/shuttle/proc/undock()
	return

/datum/shuttle/proc/force_undock()
	return

// Check if we are docked (or never dock) and thus have properly arrived.
/datum/shuttle/proc/check_docked()
	return TRUE

// Check if we are undocked and thus probably ready to depart.
/datum/shuttle/proc/check_undocked()
	return TRUE

/*****************
* Shuttle Moved Handling * (Observer Pattern Implementation: Shuttle Moved)
* Shuttle Pre Move Handling * (Observer Pattern Implementation: Shuttle Pre Move)
*****************/

// Move the shuttle to destination if possible.
// Returns TRUE if we actually moved, otherwise FALSE.
/datum/shuttle/proc/attempt_move(obj/effect/shuttle_landmark/destination, interim = FALSE)
	if(!destination)
		log_shuttle("Shuttle [src] aborting attempt_move(): null destination landmark.")
		return FALSE
	if(current_location() == destination)
		if(debug_logging)
			log_shuttle("Shuttle [src] attempted to move to [destination] but is already there!")
		return FALSE

	if(!destination.is_valid(src))
		if(debug_logging)
			log_shuttle("Shuttle [src] aborting attempt_move() because destination=[destination] is not valid")
		return FALSE
	if(current_location().cannot_depart(src))
		if(debug_logging)
			log_shuttle("Shuttle [src] aborting attempt_move() because current_location=[current_location()] refuses.")
		return FALSE

	// Observer pattern pre-move
	var/old_location = current_location()
	OM_EMIT(src, /datum/om/event/observer_shuttle_pre_move, old_location, destination)
	current_location().shuttle_departed(src)

	if(debug_logging)
		log_shuttle("[src] moving to [destination]. Areas are [english_list(shuttle_area)]")
	var/list/translation = list()
	for(var/area/A in shuttle_area)
		if(debug_logging)
			log_shuttle("Translating [A]")
		translation += get_turf_translation(get_turf(current_location()), get_turf(destination), A.contents)

	// Actually do it! (This never fails)
	perform_shuttle_move(destination, translation)

	// Observer pattern post-move
	destination.shuttle_arrived(src)
	OM_EMIT(src, /datum/om/event/observer_shuttle_moved, old_location, destination)

	return TRUE

//just moves the shuttle from A to B
//A note to anyone overriding move in a subtype. perform_shuttle_move() must absolutely not, under any circumstances, fail to move the shuttle.
//If you want to conditionally cancel shuttle launches, that logic must go in short_jump() or long_jump()
/datum/shuttle/proc/perform_shuttle_move(obj/effect/shuttle_landmark/destination, list/turf_translation)
	if(debug_logging)
		log_shuttle("perform_shuttle_move() current=[current_location()] destination=[destination]")

	ASSERT(current_location() != destination)
	// If shuttle has no internal gravity, update our gravity with destination gravity
	if((shuttle_flags & SHUTTLE_FLAGS_ZERO_G))
		var/new_grav = 1
		if(destination.flags & SLANDMARK_FLAG_ZERO_G)
			var/area/new_area = get_area(destination)
			new_grav = new_area.get_gravity()
		for(var/area/our_area in shuttle_area)
			if(our_area.get_gravity() != new_grav)
				our_area.gravitychange(new_grav)

	// TODO - Old code used to throw stuff out of the way instead of squashing. Should we?

	// Move, gib, or delete everything in our way! Everything crushed goes as
	// one batched destroy (code/datums/lifecycle/batch.dm).
	dq_destroy_collect_begin()
	for(var/turf/src_turf in turf_translation)
		var/turf/dst_turf = turf_translation[src_turf]
		if(src_turf.is_solid_structure()) // in case someone put a hole in the shuttle and you were lucky enough to be under it
			for(var/atom/movable/AM in turf_contents_of_type(dst_turf, /atom/movable))
				//if(AM.movable_flags & MOVABLE_FLAG_DEL_SHUTTLE)
				//	qdel(AM)
				//	continue
				if(!AM.simulated)
					continue
				if(isobserver(AM) || isEye(AM))
					continue
				if(isliving(AM))
					var/mob/living/bug = AM
					bug.gib()
				else
					spent(AM) //it just gets atomized I guess? TODO throw it into space somewhere, prevents people from using shuttles as an atom-smasher
	dq_destroy_collect_end()
	var/list/radios = list()
	for(var/area/A in shuttle_area)
		// If there was a zlevel above our origin and we own the ceiling, erase our ceiling now we're leaving
		if(ceiling_type && HasAbove(current_location().z))
			for(var/turf/TO in contents_of(A))
				var/turf/TA = GetAbove(TO)
				if(istype(TA, ceiling_type))
					TA.ChangeTurf(get_base_turf_by_area(TA), 1, 1)
		if(knockdown)
			for(var/mob/living/M in contents_of(A))
				if(M.is_incorporeal())
					continue
				if(M?.buckled_to())
					to_chat(M, span_red("Sudden acceleration presses you into \the [M?.buckled_to()]!"))
					shake_camera(M, 3, 1)
				else
					to_chat(M, span_red("The floor lurches beneath you!"))
					shake_camera(M, 10, 1)
					// TODO - tossing?
					//M.visible_message(span_warning("[M.name] is tossed around by the sudden acceleration!"))
					//M.throw_at_random(FALSE, 4, 1)
					if(istype(M, /mob/living/carbon))
						M.status_at_least(STAT_WEAKENED, 3)
						if(move_direction)
							throw_a_mob(M,move_direction)
		for(var/obj/item/radio/intercom/I in contents_of(A))
			radios |= I

	// Update our base turfs before we move, so that transparent turfs look good.
	var/new_base = destination.base_turf || /turf/space
	for(var/area/A as anything in shuttle_area)
		A.base_turf = new_base

	// Actually do the movement of everything - This replaces origin.move_contents_to(destination)
	translate_turfs(turf_translation, current_location().landing_area(), current_location().base_turf)
	rel_set(src, nameof(current_location), destination)

	// If there's a zlevel above our destination, paint in a ceiling on it so we retain our air
	if(ceiling_type && HasAbove(current_location().z))
		for(var/area/A in shuttle_area)
			for(var/turf/TD in contents_of(A))
				var/turf/TA = GetAbove(TD)
				if(istype(TA, get_base_turf_by_area(TA)) || isopenspace(TA))
					if(get_area(TA) in shuttle_area)
						continue
					TA.ChangeTurf(ceiling_type, TRUE, TRUE, TRUE)

	// translate_turfs() moves objects by loc, so cables and power machines send
	// their new turfs to the power network here (one commit).
	var/list/moved_turfs = list()
	for(var/turf/source in turf_translation)
		moved_turfs += turf_translation[source]
	SSmachines.power_reregister(moved_turfs)
	for(var/obj/item/radio/intercom/I in radios)
		if(istype(I))
			I.update_broadcast_tiles()
	// Adjust areas of mothershuttle so it doesn't try and bring us with it if it jumps while we aren't on it.
	if(mothershuttle)
		var/datum/shuttle/MS = SSshuttles.shuttles[mothershuttle]
		if(MS)
			if(current_location().landmark_tag == motherdock)
				MS.shuttle_area |= shuttle_area // We are now on mothershuttle! Bring us along!
			else
				MS.shuttle_area -= shuttle_area // We have left mothershuttle! Don't bring us along!

	return

//returns 1 if the shuttle has a valid arrive time
/datum/shuttle/proc/has_arrive_time()
	return (moving_status == SHUTTLE_INTRANSIT)

/datum/shuttle/proc/make_sounds(sound_type)
	var/sound_to_play = null
	switch(sound_type)
		if(HYPERSPACE_WARMUP)
			sound_to_play = SFX_EFFECTS_SHUTTLES_HYPERSPACE_BEGIN
		if(HYPERSPACE_PROGRESS)
			sound_to_play = SFX_EFFECTS_SHUTTLES_HYPERSPACE_PROGRESS
		if(HYPERSPACE_END)
			sound_to_play = SFX_EFFECTS_SHUTTLES_HYPERSPACE_END
	for(var/area/A in shuttle_area)
		for(var/obj/machinery/door/E in contents_of(A))	//dumb, I know, but playing it on the engines doesn't do it justice
			playsound(E, sound_to_play, 50, FALSE)

/datum/shuttle/proc/message_passengers(message)
	for(var/area/A in shuttle_area)
		for(var/mob/M in contents_of(A))
			M.show_message(message, 2)

/datum/shuttle/proc/find_children()
	. = list()
	for(var/shuttle_name in SSshuttles.shuttles)
		var/datum/shuttle/shuttle = SSshuttles.shuttles[shuttle_name]
		if(shuttle.mothershuttle == name)
			. += shuttle

//Returns the areas in shuttle_area that are not actually child shuttles.
/datum/shuttle/proc/find_childfree_areas()
	. = shuttle_area.Copy()
	for(var/datum/shuttle/child in find_children())
		. -= child.shuttle_area

/datum/shuttle/proc/get_location_name()
	if(moving_status == SHUTTLE_INTRANSIT)
		return "In transit"
	return current_location().name

/// Wakes the status displays that show this shuttle's schedule (KEY_SHUTTLE_SCHEDULE).
/datum/shuttle/proc/publish_schedule()
	if(src == SSemergency_shuttle?.shuttle)
		changed(SSemergency_shuttle, CHANGE_SHUTTLE_SCHEDULE)
	else if(src == SSsupply?.shuttle)
		changed(SSsupply, CHANGE_SHUTTLE_SCHEDULE)

/// Set current_location_tag, not this: New() resolves the tag into the landmark.
/datum/shuttle/proc/current_location() as /obj/effect/shuttle_landmark
	return current_location
