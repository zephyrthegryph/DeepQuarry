/datum/quarry_layer
	var/depth = 0
	var/z = 0
	var/loaded = FALSE
	// Set TRUE while the async snapshot+wipe is in flight, so the
	// periodic empty-sweep doesn't try to unload the same layer twice
	// while the first unload is still working.
	var/unloading = FALSE
	// The biome config that generated this layer. Kept for diagnostics and
	// future features that may want to inspect a layer's flavor at runtime.
	var/datum/quarry_layer_config/config
	// The floor archetype that decides this layer's objective + clear
	// condition (gas pocket, lava, hive, siege, ...). Selected at roll
	// time, persisted on the snapshot, and consulted by
	// SSquarry.recompute_unlocked_depth via archetype.is_cleared().
	var/datum/quarry_floor_archetype/archetype
	// The layer's objective goals, supplied by the archetype's
	// build_goals(). Each tracks its own progress; the layer unlocks the
	// next-deeper depth once every goal is satisfied (archetype.is_cleared).
	var/list/datum/quarry_goal/goals
	// Archetype objective structures placed on this layer (gas fissures,
	// lava vents, hive cores, ...). Cached so the archetype's per-tick
	// ambient hazard doesn't rescan 65k tiles. Lazily (re)built by
	// _quarry_get_objectives — null means "not scanned yet this load".
	var/list/objectives
	// Cached walkable-floor tiles captured at generation/restore (the
	// generator already buckets these as floor_candidates). Runtime event
	// tile-picks reuse this instead of walking the 65k-tile block() each
	// call. Mining/cave-ins can make it slightly stale, so consumers
	// re-validate each picked turf is still an eligible floor. null = not
	// captured yet (fall back to a block() scan).
	var/list/floor_cache
	// Cheap per-layer event gates, computed once from the rolled features at
	// generation/restore. Let machine/pool-dependent events (gas_leak,
	// pump_malfunction) early-out before scanning GLOB.machines / the z grid.
	// has_pools: any pool feature rolled (pumps only matter on pool layers).
	// has_gas_pools: any pool feature whose pool_turf is a gas_crack subtype
	//   (gas_leak amplifies those).
	var/has_pools = FALSE
	var/has_gas_pools = FALSE
	// Typepaths of /datum/quarry_feature rolled at layer generation.
	// Kept so restore_layer rebuilds the same ore/mob/decoration content
	// after a snapshot instead of re-rolling a different set.
	var/list/feature_types
	// Danger level 0..100. Accrues from time loaded, walls mined,
	// machinery running, gas vents popped, mob kills. Decays slowly
	// when the layer has no live players. At thresholds the danger
	// system spawns hostile mob waves and other effects.
	// See SSquarry.fire() for accrual + effect dispatch.
	var/danger = 0
	// world.time of the last danger-driven mob wave on this layer. Used
	// to throttle waves at critical danger.
	var/last_danger_wave = 0
	// The currently-active stalker mob on this layer, if any. The
	// stalker event refuses to spawn a second one while this ref
	// still resolves to a living mob. Cleared via /mob/living/death
	// in the quarry death hook.
	var/mob/living/active_stalker = null

/datum/quarry_layer/New(_depth)
	depth = _depth
	goals = list()
	feature_types = list()

/datum/quarry_layer/Destroy()
	// Goals are owned by the layer; qdel them so they don't outlive it.
	if(goals)
		for(var/datum/quarry_goal/G as anything in goals)
			qdel(G)
		goals = null
	// The remaining refs are not owned here (configs/archetypes are shared
	// singletons; the stalker/objectives/feature instances are owned
	// elsewhere or already gone) — just null them so the layer doesn't
	// pin them.
	config = null
	archetype = null
	active_stalker = null
	objectives = null
	feature_types = null
	floor_cache = null
	return ..()
