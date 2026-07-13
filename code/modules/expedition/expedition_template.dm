// Blank mineral substrate a fresh expedition site is carved out of. Loaded onto
// a freshly-allocated z-level by SSexpedition; the carver below then digs the
// walkable cave network into it.
/datum/map_template/expedition_site
	name = "Expedition Site"
	mappath = "maps/expedition/expedition_blank.dmm"

// The substrate turf the blank map is filled with: an ordinary cave-mineral
// wall whose Initialize-time decor is skipped (pregen_substrate) — the carver
// re-rolls ore and repaints every touched cell right after load, so the skip
// saves ~65k redundant update_icon/neighbor scans per generated site.
/turf/simulated/mineral/cave/pregen
	pregen_substrate = TRUE

// A real, pre-piped thermoelectric engine bay (TEG + circulators + burn chamber
// + phoron/nitrogen canisters) reused from the Southern Cross engine submaps.
// Stamped onto a site for the "commission the engine" objective: the crew must
// fuel the burn chamber, start the loop, and bring the generator online.
/datum/map_template/expedition_engine
	name = "Derelict Engine Bay"
	mappath = "maps/submaps/engine_submaps/southern_cross/engine_sme.dmm"
	annihilate = TRUE

// Cave carver for an expedition site.
//
// Reuses the base /datum/random_map/automata/cave_system wholesale — it carves
// the walkable space out of the /turf/simulated/mineral substrate, marks ore on
// the remaining walls, and seeds mining-fauna spawners — and layers on the two
// performance overrides the old quarry generator relied on:
//   * break-on-success generate(), so a sane map isn't re-rolled needlessly
//     (the parent New() runs generate() max_attempts times unconditionally);
//   * a CHECK_TICK apply pass instead of the parent's per-cell sleep(-1), which
//     would otherwise spend ~1ms * 65k cells of pure scheduler overhead.
/datum/random_map/automata/cave_system/expedition
	descriptor = "expedition site"
	make_cracked_turfs = FALSE
	iterations = 4
	initial_wall_cell = 45
	max_attempts = 5
	/// TRUE once a sane map has been applied; guards the parent's unconditional
	/// attempt loop from redoing the work over an already-good map.
	var/succeeded = FALSE

/datum/random_map/automata/cave_system/expedition/generate()
	if(succeeded)
		return 1
	seed_map()
	generate_map()
	if(check_map_sanity())
		cleanup()
		if(auto_apply)
			apply_to_map()
		succeeded = TRUE
		return 1
	return 0

// Tight apply loop: keep the base cave_system apply_to_turf (ore + fauna), but
// drop the parent's per-cell sleep(-1) in favor of CHECK_TICK so the run only
// yields when the MC tick is already over budget.
/datum/random_map/automata/cave_system/expedition/apply_to_map()
	if(!origin_x) origin_x = 1
	if(!origin_y) origin_y = 1
	if(!origin_z) origin_z = 1

	for(var/x = 1, x <= limit_x, x++)
		for(var/y = 1, y <= limit_y, y++)
			apply_to_turf(x, y)
		CHECK_TICK

	var/i = 0
	for(var/turf/simulated/mineral/T as anything in turfs_changed)
		T.update_icon(1, turfs_changed)
		if(++i % 1000 == 0)
			CHECK_TICK

	LAZYCLEARLIST(turfs_changed)
