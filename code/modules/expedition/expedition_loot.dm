// Expedition loot tiers, location sizing, and decoration.
//
// Three knobs drive the variety players see:
//   * TIER  — a five-band quality ladder (scrap -> exotic). Each band is a
//     weighted pool of item type paths. Higher site difficulty + size pull the
//     rolled tier up, with random spread and the occasional jackpot.
//   * SIZE  — small / medium / large. Scales how many POIs, loot drops, and how
//     big procedural buildings get.
//   * DECOR — biome-appropriate set-dressing (remains, wreckage, flora, grime).
//
// All pools are keyed by type path (numeric keys are illegal as associative
// list keys in this DM build), so pickweight() is happy.

// ---------------------------------------------------------------------------
// LOOT TIERS
// ---------------------------------------------------------------------------

// The weighted item pool for a tier. Proc-static so each list allocates once.
/proc/expedition_loot_pool(tier)
	switch(tier)
		if(EXP_LOOT_SCRAP)
			var/static/list/scrap = list(
				/obj/random/tool = 12,
				/obj/random/awayloot = 8,
				/obj/random/powercell = 5,
				/obj/item/salvage/ruin/brick = 5,
				/obj/item/salvage/ruin/carp = 4,
			)
			return scrap
		if(EXP_LOOT_UNCOMMON)
			var/static/list/uncommon = list(
				/obj/random/awayloot/looseloot = 10,
				/obj/item/aliencoin/silver = 8,
				/obj/fiftyspawner/silver = 6,
				/obj/fiftyspawner/gold = 4,
				/obj/random/contraband = 4,
				/obj/item/salvage/loot/syndicate = 5,
				/obj/item/capture_crystal = 4,
				/obj/item/stack/material/substance/random_field = 7, // raw substance alloy sheets
			)
			return uncommon
		if(EXP_LOOT_RARE)
			var/static/list/rare = list(
				/obj/item/aliencoin/gold = 8,
				/obj/random/bluespace = 6,
				/obj/item/capture_crystal/great = 5,
				/obj/fiftyspawner/platinum = 4,
				/obj/item/perfect_tele = 3,
				/obj/item/bluespace_harpoon = 3,
				/obj/item/denecrotizer = 4,
				/obj/fiftyspawner/diamond = 2,
				/obj/item/stack/material/substance/random_field = 6, // raw substance alloy sheets
			)
			return rare
		if(EXP_LOOT_EXOTIC)
			var/static/list/exotic = list(
				/obj/item/aliencoin/phoron = 6,
				/obj/fiftyspawner/phoron = 5,
				/obj/item/capture_crystal/ultra = 4,
				/obj/item/cell/infinite = 3,
				/obj/item/cell/void = 3,
				/obj/item/melee/jellyfishwhip = 2,
				/obj/item/melee/energy/tyr_sabre = 2,
				/obj/item/personal_shield_generator/belt/magnetbelt = 2,
				/obj/item/nif = 2,
				/obj/item/paicard = 2,
			)
			return exotic
	// EXP_LOOT_COMMON (default)
	var/static/list/common = list(
		/obj/random/awayloot = 12,
		/obj/random/medical = 6,
		/obj/random/tech_supply = 6,
		/obj/random/firstaid = 4,
		/obj/random/cash/big = 4,
		/obj/item/salvage/ruin/pirate = 5,
		/obj/item/aliencoin/basic = 5,
	)
	return common

// Spawn one tier-appropriate item at a turf (or inside a container).
/proc/expedition_spawn_loot(turf/where, tier = EXP_LOOT_COMMON, atom/container = null)
	var/atom/dest = container || where
	if(!dest)
		return
	var/list/pool = expedition_loot_pool(tier)
	if(!length(pool))
		return
	var/itype = pickweight(pool)
	new itype(dest)

// Roll a loot tier for a site. Difficulty + size set the centre of mass; a
// random spread keeps any site able to surprise, and a rare jackpot can drop
// exotic gear anywhere.
/proc/expedition_roll_tier(difficulty = EXP_DIFF_LOW, size = EXP_SIZE_SMALL)
	if(prob(4))
		return EXP_LOOT_EXOTIC // jackpot
	var/base = difficulty + (size - 1) // 1..5
	var/roll = base + pick(-1, 0, 0, 1)
	return clamp(roll, EXP_LOOT_SCRAP, EXP_LOOT_EXOTIC)

// ---------------------------------------------------------------------------
// LOCATION SIZE
// ---------------------------------------------------------------------------

/proc/expedition_roll_size()
	return pick(EXP_SIZE_SMALL, EXP_SIZE_SMALL, EXP_SIZE_SMALL, EXP_SIZE_MEDIUM, EXP_SIZE_MEDIUM, EXP_SIZE_LARGE)

/proc/expedition_size_name(size)
	switch(size)
		if(EXP_SIZE_SMALL)
			return "Small"
		if(EXP_SIZE_MEDIUM)
			return "Medium"
		if(EXP_SIZE_LARGE)
			return "Large"
	return "Unknown"

// ---------------------------------------------------------------------------
// DECORATION
// ---------------------------------------------------------------------------

// Biome-appropriate set-dressing pool (weighted toward cheap non-dense decals,
// with the odd structural prop).
/proc/expedition_decor_pool(datum/expedition_biome/biome)
	if(istype(biome, /datum/expedition_biome/plains))
		var/static/list/plains = list(
			/obj/effect/decal/cleanable/dirt = 8,
			/obj/effect/decal/remains/deer = 4,
			/obj/structure/flora/ausbushes = 5,
			/obj/structure/flora/bush = 4,
			/obj/structure/flora/tree/weepingcherry1 = 2,
		)
		return plains
	if(istype(biome, /datum/expedition_biome/orbital))
		var/static/list/orbital = list(
			/obj/effect/decal/cleanable/blood = 6,
			/obj/effect/decal/cleanable/ash = 6,
			/obj/effect/decal/remains/robot = 4,
			/obj/effect/decal/remains/human = 4,
			/obj/effect/decal/mecha_wreckage = 3,
			/obj/effect/decal/cleanable/blood/gibs = 3,
		)
		return orbital
	if(istype(biome, /datum/expedition_biome/asteroid))
		var/static/list/asteroid = list(
			/obj/effect/decal/cleanable/ash = 8,
			/obj/effect/decal/remains/robot = 4,
			/obj/effect/decal/remains/ribcage = 4,
			/obj/effect/decal/mecha_wreckage = 3,
		)
		return asteroid
	// cavern (default)
	var/static/list/cave = list(
		/obj/effect/decal/cleanable/dirt = 8,
		/obj/effect/decal/cleanable/cobweb = 5,
		/obj/effect/decal/remains/lizard = 4,
		/obj/effect/decal/remains/mouse = 4,
		/obj/effect/decal/remains/ribcage = 3,
		/obj/structure/flora/mushroom = 4,
		/obj/structure/flora/bush = 2,
	)
	return cave

// Scatter `count` pieces of biome-appropriate decoration on walkable floors
// within `radius` of a centre.
/proc/expedition_decorate(turf/center, radius, datum/expedition_biome/biome, count)
	if(!isturf(center))
		return
	var/list/pool = expedition_decor_pool(biome)
	if(!length(pool))
		return
	var/list/spots = list()
	for(var/turf/T in range(radius, center))
		if(expedition_is_walkable(T))
			spots += T
	for(var/i in 1 to count)
		if(!length(spots))
			break
		var/turf/T = pick_n_take(spots)
		var/dtype = pickweight(pool)
		new dtype(T)
