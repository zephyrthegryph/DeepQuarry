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
	// All stabilization goals rolled at layer generation. Each goal
	// tracks its own progress independently. The layer is "stabilised"
	// (and unlocks the next-deeper depth) when at least
	// QUARRY_STABILITY_THRESHOLD percent of goals are individually
	// satisfied — see SSquarry.layer_stability_percent().
	var/list/datum/quarry_goal/goals
	// Typepaths of /datum/quarry_feature rolled at layer generation.
	// Kept so restore_layer can rebuild the same goals after a
	// snapshot — without this the restored layer would re-roll a
	// different set of features and the goals players were chasing
	// would change between visits.
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
