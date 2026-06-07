// Quarry biomes.
//
// A biome is a per-tile content stamp. The layer's noise field
// buckets each tile into a biome (see quarry_noise_field.dm), and
// the biome controls what that tile looks like and what content can
// place on it.
//
// Layer configs declare a roster of (biome typepath, presence_weight)
// pairs. Generation buckets the noise sample at each tile into one
// roster slot weighted by the presence weights — biomes with higher
// weight claim more of the layer.
//
// Each /datum/quarry_biome is a small data bag. Author new biomes by
// subtyping and filling in the vars; no runtime hooks.

/datum/quarry_biome
	/// Display name (debug logs, future UI).
	var/name = "Generic Biome"

	/// Wall turf type for this biome's territory. Replaces the layer
	/// config's monolithic wall_turf — every tile in this biome's
	/// territory becomes this turf type at gen time.
	var/turf/simulated/mineral/wall_turf = /turf/simulated/mineral/cave/quarry

	/// Per-biome ore weights. When a wall tile in this biome is
	/// chosen to become ore-bearing, the mineral is drawn from this
	/// table. Form: list(ORE_X = weight). Subtypes override with
	/// concrete tables; base default is null so the empty `= list()`
	/// allocation on the abstract type doesn't fire per §6a.
	var/list/ore_contributions

	/// Per-biome decoration weights for floor scatter.
	var/list/decoration_contributions

	/// Per-biome mob weights for baseline mob spawn. The layer's
	/// default mob spawn pass picks tiles, then consults the biome
	/// at the tile and pulls from this table.
	var/list/mob_contributions

	/// Optional tint applied as a layer overlay so players can see
	/// "I'm in the crystal area now" at a glance. Hex string or null.
	var/ambient_color = null


// === BIOME ROSTER =====================================================
// Reusable biomes shared across multiple layer tiers. Each gets
// referenced by typepath from one or more /datum/quarry_layer_config
// biome_roster entries with a presence weight.


// --- Stone Caverns: the default biome. Common ores, light fauna.
/datum/quarry_biome/stone_caverns
	name = "Stone Caverns"
	wall_turf = /turf/simulated/mineral/cave/quarry/biome_stone
	ore_contributions = list(
		ORE_HEMATITE = 40,
		ORE_COPPER = 30,
		ORE_TIN = 20,
		ORE_CARBON = 30,
	)
	mob_contributions = list(
		/mob/living/simple_mob/vore/aggressive/lizardman = 40,
		/mob/living/simple_mob/vore/aggressive/rat = 30,
		/mob/living/simple_mob/vore/scrubble = 20,
	)


// --- Crystal Pockets: silver/diamond/void opal, harder fauna.
/datum/quarry_biome/crystal_pockets
	name = "Crystal Pockets"
	wall_turf = /turf/simulated/mineral/cave/quarry/biome_crystal
	ore_contributions = list(
		ORE_QUARTZ = 40,
		ORE_SILVER = 25,
		ORE_DIAMOND = 10,
		ORE_VOPAL = 5,
	)
	mob_contributions = list(
		/mob/living/simple_mob/vore/scrubble = 35,
		/mob/living/simple_mob/animal/giant_spider/tunneler/cave = 20,
		/mob/living/simple_mob/vore/aggressive/dino = 15,
	)
	ambient_color = "#9bd7ff"


// --- Damp Tunnels: water pools, bats, low-tier fish-like fauna.
/datum/quarry_biome/damp_tunnels
	name = "Damp Tunnels"
	wall_turf = /turf/simulated/mineral/cave/quarry/biome_damp
	ore_contributions = list(
		ORE_HEMATITE = 25,
		ORE_BAUXITE = 30,
	)
	mob_contributions = list(
		/mob/living/simple_mob/vore/bat = 50,
		/mob/living/simple_mob/vore/aggressive/rat = 25,
	)
	ambient_color = "#5fb9c8"


// --- Sulfur Caves: yellow rock, sulfuric pools, oregrubs.
/datum/quarry_biome/sulfur_caves
	name = "Sulfur Caves"
	wall_turf = /turf/simulated/mineral/cave/quarry/biome_sulfur
	ore_contributions = list(
		ORE_URANIUM = 25,
		ORE_PHORON = 15,
	)
	mob_contributions = list(
		/mob/living/simple_mob/vore/oregrub = 50,
		/mob/living/simple_mob/vore/aggressive/lizardman = 20,
	)
	ambient_color = "#d9c44b"


// --- Mushroom Grottos: bioluminescent, passive + spore fauna.
/datum/quarry_biome/mushroom_grottos
	name = "Mushroom Grottos"
	wall_turf = /turf/simulated/mineral/cave/quarry/biome_mushroom
	ore_contributions = list(
		ORE_CARBON = 35,
		ORE_QUARTZ = 15,
	)
	mob_contributions = list(
		/mob/living/simple_mob/vore/aggressive/chungus = 30,
		/mob/living/simple_mob/vore/scrubble = 25,
		/mob/living/simple_mob/vore/aggressive/rat = 20,
	)
	ambient_color = "#a8e3a0"


// --- Magma Vents: red rock, deathclaws, lava-pool-style threat.
/datum/quarry_biome/magma_vents
	name = "Magma Vents"
	wall_turf = /turf/simulated/mineral/cave/quarry/biome_magma
	ore_contributions = list(
		ORE_GOLD = 25,
		ORE_PHORON = 20,
		ORE_PAINITE = 10,
	)
	mob_contributions = list(
		/mob/living/simple_mob/vore/aggressive/deathclaw = 30,
		/mob/living/simple_mob/vore/raptor = 20,
		/mob/living/simple_mob/vore/aggressive/dino = 15,
	)
	ambient_color = "#cc4a2a"


// --- Frozen Hollows: pale rock, wolves and bats, scarce but rich.
/datum/quarry_biome/frozen_hollows
	name = "Frozen Hollows"
	wall_turf = /turf/simulated/mineral/cave/quarry/biome_frozen
	ore_contributions = list(
		ORE_SILVER = 25,
		ORE_DIAMOND = 10,
	)
	mob_contributions = list(
		/mob/living/simple_mob/vore/wolf = 40,
		/mob/living/simple_mob/vore/wolf/direwolf = 15,
		/mob/living/simple_mob/vore/bat = 20,
	)
	ambient_color = "#bcd6e5"


// --- Phoron Geology: purple stone, stalkers, phoron-rich.
/datum/quarry_biome/phoron_geology
	name = "Phoron Geology"
	wall_turf = /turf/simulated/mineral/cave/quarry/biome_phoron
	ore_contributions = list(
		ORE_PHORON = 50,
		ORE_VERDANTIUM = 20,
		ORE_URANIUM = 15,
	)
	mob_contributions = list(
		/mob/living/simple_mob/vore/stalker = 35,
		/mob/living/simple_mob/animal/giant_spider/tunneler/cave = 25,
	)
	ambient_color = "#a040c0"


// --- Bone Yards: tan rock, fossil fauna, raptors.
/datum/quarry_biome/bone_yards
	name = "Bone Yards"
	wall_turf = /turf/simulated/mineral/cave/quarry/biome_bone
	ore_contributions = list(
		ORE_MARBLE = 40,
		ORE_CARBON = 20,
		ORE_GOLD = 15,
	)
	mob_contributions = list(
		/mob/living/simple_mob/vore/raptor = 40,
		/mob/living/simple_mob/vore/oregrub = 20,
		/mob/living/simple_mob/vore/aggressive/deathclaw = 15,
	)
	ambient_color = "#d4c19a"


// --- Shattered Core: black glassy rock, dragons and cryptdrakes.
/datum/quarry_biome/shattered_core
	name = "Shattered Core"
	wall_turf = /turf/simulated/mineral/cave/quarry/biome_shattered
	ore_contributions = list(
		ORE_PAINITE = 25,
		ORE_VOPAL = 25,
		ORE_DIAMOND = 25,
		ORE_VERDANTIUM = 20,
	)
	mob_contributions = list(
		/mob/living/simple_mob/vore/cryptdrake = 40,
		/mob/living/simple_mob/vore/bigdragon = 15,
		/mob/living/simple_mob/vore/greatwolf = 25,
	)
	ambient_color = "#3a2348"


// === BIOME PICKER HELPERS ============================================

/// Picks one biome from a roster based on a noise value in [0,1].
/// roster is a list of (typepath = presence_weight). Sum of weights
/// is bucketed across the [0,1] range; the value maps to whichever
/// bucket it falls into. This gives deterministic-yet-organic biome
/// borders: tiles next to each other tend to fall in the same bucket
/// because the noise sample varies smoothly.
///
/// Returns a /datum/quarry_biome instance (from a cache so we don't
/// re-allocate per tile). Returns null if the roster is empty.
GLOBAL_LIST_EMPTY(_quarry_biome_cache)

/proc/_quarry_pick_biome_for_value(list/roster, value)
	if(!length(roster) || !isnum(value))
		return null
	var/total = 0
	for(var/typepath in roster)
		total += roster[typepath]
	if(total <= 0)
		return null
	var/target = value * total
	var/cursor = 0
	for(var/typepath in roster)
		cursor += roster[typepath]
		if(target <= cursor)
			return _quarry_biome_instance(typepath)
	// Fallback (shouldn't reach due to float rounding edge case).
	return _quarry_biome_instance(roster[1])


/proc/_quarry_biome_instance(typepath)
	if(!ispath(typepath, /datum/quarry_biome))
		return null
	if(!GLOB._quarry_biome_cache[typepath])
		GLOB._quarry_biome_cache[typepath] = new typepath
	return GLOB._quarry_biome_cache[typepath]


/// Build the biome map for a layer: returns an assoc list keyed
/// "x|y" -> /datum/quarry_biome. Used during generation to look up
/// the biome at each placement tile (ore vein seed, mob spawn tile,
/// decoration tile). Computed once at gen time and discarded.
///
/// `seed` is used for noise hashing so re-generating the same depth
/// produces the same map. Pass `depth` for stability across visits.
/proc/_quarry_build_biome_map(seed, list/roster, x_min, y_min, x_max, y_max)
	var/list/map = list()
	var/list/biome_counts = list()

	// Pre-compute the coarse-cell hash grid once: every tile's noise
	// sample only needs 4 corner values, and the same corner serves
	// QUARRY_NOISE_CELL_SIZE^2 tiles. Avoids 4*65k = 260k proc calls.
	var/cx_min = round(x_min / QUARRY_NOISE_CELL_SIZE)
	var/cy_min = round(y_min / QUARRY_NOISE_CELL_SIZE)
	var/cx_max = round(x_max / QUARRY_NOISE_CELL_SIZE) + 1
	var/cy_max = round(y_max / QUARRY_NOISE_CELL_SIZE) + 1
	var/hash_w = (cx_max - cx_min) + 1
	var/list/hash_grid = new(hash_w * ((cy_max - cy_min) + 1))
	for(var/cx in cx_min to cx_max)
		for(var/cy in cy_min to cy_max)
			hash_grid[(cx - cx_min) * hash_w + (cy - cy_min) + 1] = _quarry_noise_hash(seed, cx, cy)

	for(var/x in x_min to x_max)
		var/cx = round(x / QUARRY_NOISE_CELL_SIZE)
		var/fx = (x - cx * QUARRY_NOISE_CELL_SIZE) / QUARRY_NOISE_CELL_SIZE
		// Smoothstep once per column.
		fx = fx * fx * (3 - 2 * fx)
		var/cxi = (cx - cx_min) * hash_w
		var/cxi_next = cxi + hash_w
		for(var/y in y_min to y_max)
			var/cy = round(y / QUARRY_NOISE_CELL_SIZE)
			var/fy = (y - cy * QUARRY_NOISE_CELL_SIZE) / QUARRY_NOISE_CELL_SIZE
			fy = fy * fy * (3 - 2 * fy)
			var/yi = cy - cy_min + 1
			var/v00 = hash_grid[cxi + yi]
			var/v10 = hash_grid[cxi_next + yi]
			var/v01 = hash_grid[cxi + yi + 1]
			var/v11 = hash_grid[cxi_next + yi + 1]
			var/top = v00 * (1 - fx) + v10 * fx
			var/bot = v01 * (1 - fx) + v11 * fx
			var/v = top * (1 - fy) + bot * fy
			var/datum/quarry_biome/B = _quarry_pick_biome_for_value(roster, v)
			if(B)
				map["[x]|[y]"] = B
				biome_counts["[B.type]"] = (biome_counts["[B.type]"] || 0) + 1
	var/log_parts = "BIOME MAP seed=[seed]: "
	for(var/t in biome_counts)
		log_parts += "[t]=[biome_counts[t]] "
	log_game(log_parts)
	return map


/proc/_quarry_biome_at(list/biome_map, turf/T)
	if(!biome_map || !isturf(T))
		return null
	return biome_map["[T.x]|[T.y]"]
