// The deep quarry's freight elevator.
//
// One physical car. At any moment the car is parked at exactly one floor:
// the surface (depth 0), or a procedural layer (depth >= 1). The car never
// physically traverses a Z-level. Instead, its "current location" tracks
// which 3×3 floor area is the cargo bay; on a trip, the contents of those
// 9 tiles teleport (forceMove) to the destination's 9 tiles. From the
// player's perspective: doors close, 5 seconds elapse, doors open at the
// new floor.
//
// Persistence: items left inside the car travel with it. Items left on
// the surface bay or any layer's bay STAY THERE until the car returns,
// because they were on the room floor, not in the car. (Mechanically, the
// car IS the room — but only one room at a time is "the car." See
// occupied_pad below.)

#define QUARRY_ELEVATOR_TRAVEL_TIME 5 SECONDS
#define QUARRY_ELEVATOR_BAY_SIZE 3

// Scheduled departure timing. When a dispatch is requested, the
// destination is locked in immediately, the bay's z-level is told a
// departure is coming, and after this long the elevator closes its
// doors and travels. A second announcement fires 10 seconds before
// departure as a last call.
#define QUARRY_ELEVATOR_DEPARTURE_DELAY 60 SECONDS
#define QUARRY_ELEVATOR_LAST_CALL_WARNING 10 SECONDS

/datum/quarry_elevator
	// Where the car is currently parked. 0 = surface, 1+ = layer depth.
	var/current_depth = 0
	// True during the transit window; blocks new trips.
	var/traveling = FALSE

	// The 9-tile cargo bay on the surface map. Cached at world init from
	// the /obj/effect/landmark/quarry_elevator_anchor placement.
	var/list/surface_bay = list()

	// Bays on procedural layers, keyed by depth string. Populated when each
	// layer generates.
	var/list/layer_bays = list()

	// All control panels that point at this elevator. Indexed for state
	// updates after travel.
	var/list/panels = list()

	// Doors on every bay, indexed by depth string. Two doors per bay if the
	// generator placed two; only one in v1.
	var/list/doors = list()

	// Depths the elevator is currently inbound to. SSquarry's periodic
	// unload sweep skips any depth in this set, so a layer that's just
	// finished generating doesn't get snapshotted-and-wiped in the
	// window between ensure_layer returning and travel_to actually
	// teleporting players onto the z. Keyed by depth string.
	var/list/pending_arrivals = list()

// Returns the 9 turfs currently acting as the car's cargo bay.
/datum/quarry_elevator/proc/occupied_pad()
	if(current_depth == 0)
		return surface_bay
	return layer_bays["[current_depth]"]

// Returns the 9 turfs of a specified depth's bay, regardless of where the
// car currently is. Used by the carving generator and the travel proc.
/datum/quarry_elevator/proc/bay_at(depth)
	if(depth == 0)
		return surface_bay
	return layer_bays["[depth]"]

// Dispatch the car from origin_depth to target_depth. Used by interior
// panels: they pass their own depth as origin so the player's bay is
// the origin regardless of where current_depth thinks the car is.
//
// Downward dispatches (target > origin) run through the 60s scheduled
// flow with comms announcements. Upward / same-depth dispatches are
// instant — no announcement, no countdown, doors close and travel
// runs immediately.
/datum/quarry_elevator/proc/dispatch_from(origin_depth, target_depth)
	if(traveling)
		return FALSE
	if(origin_depth == target_depth)
		return FALSE
	current_depth = origin_depth
	var/going_down = target_depth > origin_depth
	// Defer the trip onto its own coroutine. travel_to does meaningful
	// work before its first sleep (the comms announcement fans out to
	// every radio in range — hundreds of milliseconds easily), so
	// running it on the click stack freezes the UI for the duration.
	// spawn(0) queues onto the next tick so the click returns instantly.
	spawn(0)
		travel_to(target_depth, instant = !going_down)
	return TRUE


// Summon the elevator to this depth (exterior call panels). Always
// instant — the request is treated as the surface-side equivalent of
// calling for the car. Rejected if a trip is already in progress.
/datum/quarry_elevator/proc/summon_to(target_depth)
	if(traveling)
		return FALSE
	if(target_depth == current_depth)
		return FALSE
	spawn(0)
		travel_to(target_depth, instant = TRUE)
	return TRUE


// Execute a trip to target_depth. If `instant`, doors close and travel
// runs immediately. Otherwise broadcasts a 60s departure schedule on
// the common comms channel, waits with doors open, fires a 10s last
// call, then runs the trip.
//
// Non-instant trips kick off layer loading in the background as soon
// as the schedule announcement fires, so the ~25s procgen runs
// concurrently with the 60s countdown. The doors-close → arrival
// window remains just the 5s travel sleep. For instant trips the
// load runs synchronously before doors close.
/datum/quarry_elevator/proc/travel_to(target_depth, instant = FALSE)
	if(traveling)
		return FALSE
	if(target_depth == current_depth)
		return FALSE
	var/list/origin_bay = occupied_pad()
	if(!length(origin_bay))
		return FALSE

	traveling = TRUE
	var/target_key = "[target_depth]"
	pending_arrivals[target_key] = TRUE
	var/origin_label = current_depth == 0 ? "the surface" : "depth [current_depth]"
	var/target_label = target_depth == 0 ? "the surface" : "depth [target_depth]"

	var/needs_load = target_depth >= 1 && !length(bay_at(target_depth))

	if(!instant)
		// Scheduled departure: comms broadcast on the Common channel
		// so anyone on the layer (or surface) can race for the bay.
		announce_via_comms(
			"Elevator at [origin_label] scheduled to depart for [target_label] in [QUARRY_ELEVATOR_DEPARTURE_DELAY / 10] seconds.",
			"Quarry Elevator",
		)
		if(needs_load)
			// Kick off the load in the background; it runs concurrently
			// with the countdown. pending_arrivals[target_key] keeps the
			// unload sweep off the layer while we wait. spawn(0) (rather
			// than INVOKE_ASYNC) queues onto the next tick instead of
			// running synchronously on the caller's stack until the
			// callee first sleeps — ensure_layer's load_new_z doesn't
			// sleep, which would freeze the click handler for a second
			// or two without spawn().
			spawn(0)
				SSquarry.ensure_layer(target_depth)
		sleep(QUARRY_ELEVATOR_DEPARTURE_DELAY - QUARRY_ELEVATOR_LAST_CALL_WARNING)
		announce_via_comms(
			"Elevator at [origin_label] departing for [target_label] in [QUARRY_ELEVATOR_LAST_CALL_WARNING / 10] seconds. Final boarding call.",
			"Quarry Elevator",
		)
		sleep(QUARRY_ELEVATOR_LAST_CALL_WARNING)
		// At this point the layer should be ready. If it isn't, wait
		// up to 30s more before giving up. Stays in the pending_arrivals
		// set so the unload sweep keeps off it.
		if(needs_load && !length(bay_at(target_depth)))
			var/waited = 0
			while(!length(bay_at(target_depth)) && waited < 30 SECONDS)
				sleep(1 SECONDS)
				waited += 1 SECONDS
	else if(needs_load)
		// Instant trip: still has to load, but synchronously.
		SSquarry.ensure_layer(target_depth)

	announce_to_bay(origin_bay, span_warning("The elevator doors slide closed."))
	close_doors_at(current_depth)

	var/list/dest_bay = bay_at(target_depth)
	if(!length(dest_bay))
		announce_to_bay(origin_bay, span_warning("The elevator can't reach that depth. The shaft groans."))
		open_doors_at(current_depth)
		pending_arrivals -= target_key
		traveling = FALSE
		return FALSE
	if(length(origin_bay) != length(dest_bay))
		log_game("SSquarry elevator: bay size mismatch origin=[length(origin_bay)] dest=[length(dest_bay)]")
		open_doors_at(current_depth)
		pending_arrivals -= target_key
		traveling = FALSE
		return FALSE

	sleep(QUARRY_ELEVATOR_TRAVEL_TIME)

	// Move cargo from origin to corresponding destination tile. Skip anchored
	// atoms — the elevator's own structure (panels, lights, doors, cables)
	// is anchored and belongs to the room, not the car. Also skip observers.
	// Both bay lists are kept in matched order (top-left to bottom-right).
	for(var/i in 1 to length(origin_bay))
		var/turf/src_t = origin_bay[i]
		var/turf/dst_t = dest_bay[i]
		if(!isturf(src_t) || !isturf(dst_t))
			continue
		for(var/atom/movable/AM in src_t)
			if(istype(AM, /mob/observer))
				continue
			if(AM.anchored)
				continue
			AM.forceMove(dst_t)

	current_depth = target_depth
	open_doors_at(target_depth)
	announce_to_bay(dest_bay, span_info("The elevator doors slide open."))
	pending_arrivals -= target_key
	traveling = FALSE
	return TRUE

// Broadcast a message on the Common comms channel as if the elevator
// were on the announcer radio. Used for the scheduled-departure
// countdown — players hear it through headsets / consoles the same
// way they hear join announcements.
/datum/quarry_elevator/proc/announce_via_comms(msg, sender = "Quarry Elevator")
	if(!GLOB.global_announcer)
		return
	GLOB.global_announcer.autosay(msg, sender, CHANNEL_COMMON, list(0))

/datum/quarry_elevator/proc/announce_to_bay(list/turfs, msg)
	for(var/turf/T as anything in turfs)
		for(var/mob/M in T)
			to_chat(M, msg)

/datum/quarry_elevator/proc/close_doors_at(depth)
	// Note: airlock close is overridden in two places. The active override
	// (airlock_control.dm) has signature close(forced, ignore_safties, ...).
	// Pass forced positionally.
	for(var/obj/machinery/door/airlock/lift/D in doors["[depth]"])
		spawn(0)
			D.close(1)

/datum/quarry_elevator/proc/open_doors_at(depth)
	// Note: airlock open is overridden in two places. The active override
	// (airlock_control.dm) has signature open(surpress_send) — NOT
	// open(forced=0). Passing positionally, the value falls through ..()
	// to /obj/machinery/door/open's forced parameter, which bypasses the
	// power check we need to bypass (the quarry rooms become powered only
	// after the APC is online).
	for(var/obj/machinery/door/airlock/lift/D in doors["[depth]"])
		spawn(0)
			D.open(1)
