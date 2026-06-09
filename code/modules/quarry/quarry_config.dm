// Per-layer configuration for the deep quarry generator.
//
// Each /datum/quarry_layer_config describes one "biome" — what rock the
// layer is made of, how dense it is, what ores it has, what decorations
// scatter on the floor, and what hostile mobs spawn. SSquarry picks one
// config per generated layer using weighted depth bands declared on the
// config itself.
//
// A config is data-only. The generator reads its vars; it never executes.

/datum/quarry_layer_config
	// Cellular-automaton parameters. wall_density is the initial probability
	// a cell is a wall (0-100). Higher = more solid stone, smaller caves.
	// smoothing_iterations is how many CA passes refine the shape.
	var/wall_density = 50
	var/smoothing_iterations = 4

	// Turf type used for both walls and floors. The generator ChangeTurfs the
	// loaded substrate to this type before carving. Must be a subtype of
	// /turf/simulated/mineral so make_floor() / make_wall() work in place.
	//
	// Soft-deprecated in favor of biome_roster: if biome_roster is set,
	// each tile gets its biome's wall_turf instead. wall_turf is now a
	// fallback when no roster is declared.
	var/turf/simulated/mineral/wall_turf = /turf/simulated/mineral/cave

	// Biome roster for this layer. Form: list(biome_typepath = weight).
	// At generation a smooth noise field is bucketed by these weights;
	// each tile's biome controls its wall_turf, ore/mob/decoration
	// tables, and ambient color. Higher weight = more of the layer.
	// If null/empty, the layer falls back to the monolithic wall_turf +
	// feature pool behavior. Base default null per §6a — subtypes
	// override with concrete rosters.
	var/list/biome_roster

	// Baseline ore density (percent of wall tiles that carry ore).
	// Feature-pool rolls populate the ore_table at generation time.
	var/ore_density = 6
	// Baseline decoration density (percent of floors that get a decoration).
	// Feature-pool rolls add to this via extra_decoration_density.
	var/decoration_density = 2
	// Baseline hostile-mob spawn count for the layer. Feature-pool rolls
	// add to this via extra_mob_spawns on the picked features.
	var/mob_count = 0
	// Baseline mob spawn table used when no mob feature rolls — keeps
	// the layer from feeling sterile if the random feature picks
	// happen to skip all mob features. Form: list(typepath = weight).
	// Subtypes override per §6a; default null.
	var/list/default_mob_table

	// Depth weights. Keys are range strings, values are pickweight values.
	// Range syntax:
	//   "1-3"  inclusive band
	//   "5"    exact depth
	//   "7+"   open-ended downward (7, 8, 9, ...)
	// At selection time SSquarry queries each config for its weight at the
	// target depth, and pickweights across all non-zero-weight configs.
	// Subtypes override; default null per §6a.
	var/list/depth_weights

	// Pool of /datum/quarry_feature typepaths this biome can roll. At
	// layer generation time the generator picks `feature_count_min` to
	// `feature_count_max` distinct features from this pool. Each feature
	// contributes ores, mobs, decorations, and goals (see
	// /datum/quarry_feature). Subtypes override; default null per §6a.
	var/list/feature_pool
	// Min/max features to roll per layer. Inclusive on both ends. Default
	// 5-10 — enough variety per layer to feel different per visit.
	var/feature_count_min = 5
	var/feature_count_max = 10


// Returns this config's selection weight at the given depth, or 0 if it
// does not apply. The first matching range key wins; ranges should not
// overlap within a single config.
/datum/quarry_layer_config/proc/weight_at(depth)
	for(var/key in depth_weights)
		if(range_contains(key, depth))
			return depth_weights[key]
	return 0


// Parse a range string and report whether it includes the given depth.
// Accepts "N", "N-M", or "N+". Unrecognized formats return FALSE.
/proc/range_contains(range_key, depth)
	if(!istext(range_key))
		return FALSE

	// "N+" form: open-ended downward.
	var/plus_pos = findtext(range_key, "+")
	if(plus_pos)
		var/min_str = copytext(range_key, 1, plus_pos)
		var/min_val = text2num(min_str)
		if(isnull(min_val))
			return FALSE
		return depth >= min_val

	// "N-M" form: inclusive band.
	var/dash_pos = findtext(range_key, "-")
	if(dash_pos)
		var/min_str = copytext(range_key, 1, dash_pos)
		var/max_str = copytext(range_key, dash_pos + 1)
		var/min_val = text2num(min_str)
		var/max_val = text2num(max_str)
		if(isnull(min_val) || isnull(max_val))
			return FALSE
		return depth >= min_val && depth <= max_val

	// "N" form: exact match.
	var/exact = text2num(range_key)
	if(isnull(exact))
		return FALSE
	return depth == exact
