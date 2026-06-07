// DQ LINDA turf glue: the previous build of this file existed because
// /turf/simulated didn't inherit from /turf/open and had to be hand-bridged
// for air persistence + hotspots. That bridge has been replaced by a
// `parent_type = /turf/open` declaration on /turf/simulated (code/game/turfs/
// simulated.dm) and /turf/space (code/game/turfs/space/space.dm), so the
// full LINDA atmos engine (process_cell, share/excited groups, update_visuals,
// adjacency, spacewind) now runs on simulated turfs the same as it does on
// /turf/open subtypes in /tg/.
//
// What's left in this file: the SSair init-time hook that fires per-turf
// adjacency calculation, and the CHOMP-side lingering-fire procs (which
// don't exist on /turf/open and so are not provided by the reparent).

// /turf/open is what SSair.setup_allturfs() expects to walk and call
// Initalize_Atmos() on. The base /turf/proc/Initalize_Atmos in
// tg_infra_compat.dm is a no-op; we override it on /turf/open here to do the
// /tg/-canonical thing — build the adjacency graph and seed current_cycle.
/turf/open/Initalize_Atmos(times_fired)
	// Set current_cycle BEFORE building adjacency — init_immediate_calculate_adjacent_turfs
	// reads current_cycle on both sides to decide "have I already done this neighbor?".
	// SSair.setup_allturfs passes a negative (decrementing) times_fired so the very
	// first turf has current_cycle = -1 and untouched neighbors still default to 0;
	// "0 <= -1" is FALSE so they get added. With the order swapped (our own
	// current_cycle still 0 when the calc runs) every neighbor gets skipped and
	// atmos_adjacent_turfs comes out empty — gases never spread.
	current_cycle = times_fired
	init_immediate_calculate_adjacent_turfs()


// === CHOMP lingering-fire bridge ===
//
// Several CHOMP atmos callers expect /turf/proc/lingering_fire,
// /turf/proc/feed_lingering_fire, and /turf/proc/create_fire. /turf/open
// doesn't supply these; provide them in terms of LINDA's hotspot model so
// CHOMP-originated igniters/candles/cigs/runes/etc. light fires on
// /turf/open subtypes (which now include /turf/simulated and /turf/space).

/turf/open/lingering_fire()
	return active_hotspot

/turf/open/feed_lingering_fire(intensity = 1)
	var/temp = T0C + 300 * max(0.1, intensity)
	hotspot_expose(temp, CELL_VOLUME * 0.5, soh = TRUE)
	SSair.add_to_active(src)

/turf/open/create_fire(temp = T0C + 300)
	hotspot_expose(temp, CELL_VOLUME, soh = FALSE)
	SSair.add_to_active(src)
