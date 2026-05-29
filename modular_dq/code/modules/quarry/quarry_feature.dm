// Quarry layer features.
//
// A feature is a roll-time content "package" that a layer might
// include. Each feature declares what it adds:
//   - ores it wants in the ore_table (with weights)
//   - hostile mobs it wants in the mob_table (with weights)
//   - decorations it wants in the decoration_table (with weights)
//   - goals it spawns on the layer (factory: see build_goals)
//   - flat counts: extra mob spawns or decoration multipliers
//
// At generation time the layer rolls N features from its biome's
// feature_pool. The aggregated tables drive ore / mob / decoration
// placement; each feature's goals attach to the layer.
//
// Authoring a new feature is pure data — subtype /datum/quarry_feature,
// fill in vars, override build_goals if the feature spawns specific
// goals. No runtime code beyond the goal factory.

/datum/quarry_feature
	/// Human-readable name. Surfaces in scanners / debug logs.
	var/name = "Unnamed Feature"
	/// One-line description; not currently surfaced but kept for
	/// future tooltips on the elevator UI ("Why is this here?").
	var/description = ""

	/// Ores this feature contributes to the layer's ore_table.
	/// Form: list(ORE_DEFINE = weight). The generator merges all
	/// selected features' ore contributions and picks from the union.
	var/list/ore_contributions = list()

	/// Hostile mob types this feature contributes to the layer's
	/// mob_table. Form: list(typepath = weight).
	var/list/mob_contributions = list()

	/// Decorations this feature contributes to the layer's
	/// decoration_table. Form: list(typepath = weight).
	var/list/decoration_contributions = list()

	/// Optional flat additions to the layer's counts. These stack
	/// across features. So picking three "rat nest" features that each
	/// add 2 mobs means 6 extra rats on the layer.
	var/extra_mob_spawns = 0
	var/extra_decoration_density = 0  // percentage points added to cfg.decoration_density

	/// Vein clustering for resource placement. The generator picks
	/// vein_count distinct seed tiles for this feature and flood-fills
	/// out to roughly vein_size connected tiles each. So a feature
	/// with vein_count=12, vein_size=20 paints twelve clusters of up
	/// to 20 tiles each — ~240 wall tiles, roughly 1% of a 256² layer.
	///
	/// Authoring guideline: a typical layer rolls 5-8 wall features,
	/// each placing ~vein_count*vein_size walls. Aim for ~10-15% of
	/// total walls to carry ore across all features combined so the
	/// cave feels mineable but not paved.
	///
	/// Used by both wall placements (the cluster becomes ore-bearing
	/// walls) and pool placements (the cluster becomes a connected
	/// liquid pool). Pool features should override these with smaller
	/// values since pools are floor turfs and look weirder at scale.
	var/vein_count = 12
	var/vein_size = 20

	/// Where this feature lives on the layer:
	///   "wall" — ore-bearing mineral walls (default; ore_contributions
	///            entries pick the wall mineral)
	///   "pool" — floor tiles changed to pool_turf, forming a connected
	///            liquid surface that pumps reagents
	var/placement_type = "wall"

	/// For placement_type = "pool": the floor turf type that the
	/// generator paints onto the carved cluster. Should be a subtype
	/// of /turf/simulated/floor with a pump_reagents override so the
	/// upstream /obj/machinery/pump can extract from it.
	var/pool_turf = null

/// Factory: build and return a list of /datum/quarry_goal instances
/// that this feature contributes to the layer. Default: none. Override
/// per-feature to declare what completing this feature means.
/datum/quarry_feature/proc/build_goals(datum/quarry_layer/L)
	return list()

/// Per-layer setup hook called after instantiation, before any tables
/// are read by the placer. Lets features with depth-dependent state
/// (e.g. exotic_vein, which pulls the band's rolled materials) populate
/// their contributions when they know which layer they're on. Default:
/// no-op.
/datum/quarry_feature/proc/on_layer_setup(datum/quarry_layer/L)
	return


/// Roll N distinct feature typepaths from cfg.feature_pool. N is
/// clamped to [cfg.feature_count_min, cfg.feature_count_max] and
/// further to the pool size — a 3-feature pool with count_max=10
/// returns 3 features, not 10.
///
/// Returns a list of /datum/quarry_feature typepaths.
/proc/_quarry_roll_feature_types(datum/quarry_layer_config/cfg)
	if(!cfg || !length(cfg.feature_pool))
		return list()
	var/want = rand(cfg.feature_count_min, cfg.feature_count_max)
	want = min(want, length(cfg.feature_pool))
	if(want <= 0)
		return list()
	var/list/pool = cfg.feature_pool.Copy()
	var/list/picked = list()
	while(length(picked) < want && length(pool))
		var/idx = rand(1, length(pool))
		picked += pool[idx]
		pool.Cut(idx, idx + 1)
	return picked


/// Given a list of feature typepaths, aggregate their contributions
/// into the form the generator already expects: ore_table /
/// decoration_table / mob_table (each a weight map), plus extra mob
/// spawn count and extra decoration density. Goals are produced by
/// calling build_goals on each feature with the supplied layer.
///
/// Returns an assoc list:
///   ore_table          list(ORE_X = weight, ...)
///   mob_table          list(typepath = weight, ...)
///   decoration_table   list(typepath = weight, ...)
///   extra_mob_spawns   integer
///   extra_decoration_density integer
///   goals              list(/datum/quarry_goal, ...)
/proc/_quarry_aggregate_features(list/feature_types, datum/quarry_layer/L)
	var/list/mob_table = list()
	var/list/decoration_table = list()
	var/extra_mob_spawns = 0
	var/extra_decoration_density = 0
	var/list/raw_goals = list()
	var/list/instances = list()
	for(var/feat_type in feature_types)
		if(!ispath(feat_type, /datum/quarry_feature))
			continue
		var/datum/quarry_feature/F = new feat_type
		F.on_layer_setup(L)
		instances += F
		for(var/k in F.mob_contributions)
			mob_table[k] = (mob_table[k] || 0) + F.mob_contributions[k]
		for(var/k in F.decoration_contributions)
			decoration_table[k] = (decoration_table[k] || 0) + F.decoration_contributions[k]
		extra_mob_spawns += F.extra_mob_spawns
		extra_decoration_density += F.extra_decoration_density
		var/list/built = F.build_goals(L)
		if(islist(built))
			raw_goals += built

	// Merge goals that target the same underlying resource. Two
	// phoron-vein features rolling on the same layer become one
	// "mine N phoron walls" goal with summed targets, instead of two
	// independent quotas. Key is "<typepath>|<merge_key()>" so we
	// never merge across goal subtypes.
	var/list/by_key = list()
	var/list/goals = list()
	for(var/datum/quarry_goal/G as anything in raw_goals)
		if(!G)
			continue
		var/key = "[G.type]|[G.merge_key()]"
		var/datum/quarry_goal/existing = by_key[key]
		if(existing)
			qdel(G)
		else
			by_key[key] = G
			goals += G

	return list(
		"instances" = instances,
		"mob_table" = mob_table,
		"decoration_table" = decoration_table,
		"extra_mob_spawns" = extra_mob_spawns,
		"extra_decoration_density" = extra_decoration_density,
		"goals" = goals,
	)


/// Flood-fill from a seed tile through tiles matching a predicate, up
/// to a maximum cluster size. Returns a list of contributing turfs in
/// the order they were visited. The seed itself is the first entry.
///
/// `match_callback` is a CALLBACK that returns TRUE for tiles eligible
/// to join the cluster. The seed is checked too; pass a seed that
/// already passes, and the predicate filters neighbours.
/proc/_quarry_flood_cluster(turf/seed, max_size, datum/callback/match_callback)
	var/list/out = list()
	if(!isturf(seed) || max_size <= 0)
		return out
	var/list/queue = list(seed)
	var/list/seen = list()
	seen["[seed.x]|[seed.y]"] = TRUE
	while(length(queue) && length(out) < max_size)
		var/turf/T = queue[1]
		queue.Cut(1, 2)
		if(!match_callback.Invoke(T))
			continue
		out += T
		for(var/dir in GLOB.cardinal)
			var/turf/N = get_step(T, dir)
			if(!isturf(N))
				continue
			var/key = "[N.x]|[N.y]"
			if(seen[key])
				continue
			seen[key] = TRUE
			queue += N
	return out


/// Place a wall feature: pick vein_count seed walls from the layer's
/// wall pool, flood-fill each into a vein_size cluster, assign the
/// ore mineral. The mineral pick is weighted across the feature's
/// own ore_contributions only — so a vein of "Phoron Vein" is all
/// phoron, not a random ore from the layer's aggregate table.
/proc/_quarry_place_wall_feature(datum/quarry_feature/F, list/wall_candidates)
	if(!F || !length(F.ore_contributions) || !length(wall_candidates))
		return 0
	var/placed = 0
	var/datum/callback/match_cb = CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_quarry_match_unclaimed_wall))
	for(var/v in 1 to F.vein_count)
		var/list/eligible = list()
		for(var/turf/simulated/mineral/W in wall_candidates)
			if(W.mineral || W.ignore_mapgen || W.ignore_oregen)
				continue
			eligible += W
		if(!length(eligible))
			break
		var/turf/simulated/mineral/seed = pick(eligible)
		var/list/cluster = _quarry_flood_cluster(seed, F.vein_size, match_cb)
		for(var/turf/simulated/mineral/T in cluster)
			if(T.mineral || T.ignore_mapgen || T.ignore_oregen)
				continue
			var/mineral_name = pickweight(F.ore_contributions)
			if(mineral_name && (mineral_name in GLOB.ore_data))
				T.mineral = GLOB.ore_data[mineral_name]
				T.UpdateMineral()
				placed++
	return placed


/// Place a pool feature: pick vein_count seed floors from the layer's
/// floor pool, flood-fill each into a vein_size cluster, ChangeTurf
/// to the feature's pool_turf type. Returns the count of turfs
/// painted. The painted turfs are removed from floor_candidates so
/// later decoration/mob passes don't try to use them as walkable
/// floor.
/proc/_quarry_place_pool_feature(datum/quarry_feature/F, list/floor_candidates)
	if(!F?.pool_turf || !length(floor_candidates))
		return 0
	var/painted = 0
	var/datum/callback/match_cb = CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_quarry_match_clean_floor))
	for(var/v in 1 to F.vein_count)
		var/list/eligible = list()
		for(var/turf/simulated/floor/T as anything in floor_candidates)
			if(istype(T, F.pool_turf))
				continue
			var/blocked = FALSE
			for(var/atom/movable/AM in T)
				if(_quarry_is_real_obstacle(AM))
					blocked = TRUE
					break
			if(blocked)
				continue
			eligible += T
		if(!length(eligible))
			break
		var/turf/simulated/floor/seed = pick(eligible)
		var/list/cluster = _quarry_flood_cluster(seed, F.vein_size, match_cb)
		for(var/turf/simulated/floor/T as anything in cluster)
			if(!istype(T))
				continue
			if(istype(T, F.pool_turf))
				continue
			T = T.ChangeTurf(F.pool_turf)
			floor_candidates -= T
			painted++
	return painted


/proc/_quarry_match_unclaimed_wall(turf/T)
	if(!istype(T, /turf/simulated/mineral))
		return FALSE
	var/turf/simulated/mineral/M = T
	if(!M.density)
		return FALSE
	if(M.mineral || M.ignore_mapgen || M.ignore_oregen)
		return FALSE
	return TRUE


/proc/_quarry_match_clean_floor(turf/T)
	if(!istype(T, /turf/simulated/floor))
		return FALSE
	// Skip if a real movable is on the tile (player, mob, item).
	// Lighting overlays and other invisibles are skipped by the
	// is_real_obstacle filter so freshly-carved cave floors still
	// qualify.
	for(var/atom/movable/AM in T)
		if(_quarry_is_real_obstacle(AM))
			return FALSE
	return TRUE


/// TRUE if a movable should disqualify a tile from being painted
/// into a pool. Lighting overlays, effects, and observers don't
/// block painting; mobs and items do.
/proc/_quarry_is_real_obstacle(atom/movable/AM)
	if(istype(AM, /atom/movable/lighting_overlay))
		return FALSE
	if(istype(AM, /obj/effect))
		return FALSE
	if(istype(AM, /mob/observer))
		return FALSE
	return TRUE


/// TRUE if a turf falls inside a player-built safe room — defined as
/// an area with a powered APC. Mob spawn passes (initial layer gen,
/// restore respawn, runtime events) skip these tiles so the rooms
/// players build don't become free hostile dispensers.
/proc/_quarry_tile_is_safe(turf/T)
	if(!isturf(T))
		return FALSE
	var/area/A = get_area(T)
	if(!A?.apc)
		return FALSE
	// "Powered" = the APC is actually on. Broken / unpowered APCs
	// don't count as a safe room.
	return A.apc.operating && !A.apc.shorted && A.apc.cell?.charge
