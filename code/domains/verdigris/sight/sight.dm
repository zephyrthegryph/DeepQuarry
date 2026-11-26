// The world opacity layer (was nowhere: BYOND's view() was the only sight). Every turf's directional_opacity (its own opacity
// and its opaque movables) is mirrored into the Rust grid's Opacity faces, so sight users (lighting, AI line of sight, atmos
// probes) can ask Rust instead of calling view(). Turfs mark themselves dirty when their opacity changes; the dirty set goes
// over in one call before any read and every tick. The API is in api.dm.
SYSTEM_DEF(sight)
	name = "Sight"
	periodic_runlevels = RUNLEVELS_DEFAULT | RUNLEVEL_LOBBY
	/// Turfs whose opacity changed since the last flush: a set of locations (turf -> TRUE), not entity references; emptied by
	/// every flush.
	var/list/dirty_turfs = list()
	/// Cumulative counters (flushes, cells sent, view reads).
	var/flushes = 0
	var/cells_sent = 0
	var/views = 0

/datum/system/sight/reactions()
	. = ..()
	. += every(WORK_EVERY_TICK, PROC_REF(sight_step), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/datum/system/sight/proc/sight_step(dt)
	if(length(dirty_turfs))
		flush()
	return STEP_DONE

/// Sends every dirty turf's opacity mask to the Rust layer in one call.
/datum/system/sight/proc/flush()
	var/list/turfs = dirty_turfs
	if(!length(turfs))
		return
	dirty_turfs = list()
	var/list/cells = new /list(length(turfs) * 4)
	var/i = 0
	for(var/turf/T as anything in turfs)
		cells[++i] = T.x
		cells[++i] = T.y
		cells[++i] = T.z
		cells[++i] = T.directional_opacity
	flushes++
	cells_sent += length(turfs)
	vg_sight_set_cells(cells)

/datum/system/sight/stat_entry(msg)
	return "[msg]Dirty:[length(dirty_turfs)] Sent:[cells_sent]"
