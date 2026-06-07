// Concrete quarry layer configs. Each declares one "biome" and what
// depth band it applies to. Bands are non-overlapping — every depth
// resolves to exactly one config so each 5-layer block has a single
// distinctive tier.
//
// Block layout:
//   surface    depth 0      (entrance map)
//   shallows   depth 1-5    starter biome
//   midmines   depth 6-10   mid-tier ores, light hostiles
//   deeps      depth 11-15  rare ores, dangerous hostiles
//   abyss      depth 16-20  brutal ores, brutal hostiles
//   core       depth 21-25  rarest ores, planet-core mobs
//
// Each block's wall_turf is its own /turf/simulated/mineral/cave/quarry
// subtype (defined in quarry_turfs.dm), so the carved floor and walls
// look distinct per tier without code branching in the generator.
//
// Per-layer content (ores, mobs, decorations, goals) is composed at
// generation time by rolling N features from `feature_pool`. See
// quarry_feature.dm and quarry_features.dm for the feature framework.

/datum/quarry_layer_config/surface
	wall_density = 55
	smoothing_iterations = 4
	wall_turf = /turf/simulated/mineral/cave/quarry
	ore_density = 7
	decoration_density = 0
	mob_count = 0
	depth_weights = list(
		"0" = 100,
	)
	// Surface stays simple: a few common-ore features so the entrance
	// caves are mineable but quiet. Lower feature count so surface
	// doesn't feel as content-dense as deeper biomes.
	feature_pool = list(
		/datum/quarry_feature/ore_hematite,
		/datum/quarry_feature/ore_carbon,
		/datum/quarry_feature/ore_copper,
		/datum/quarry_feature/ore_tin,
		/datum/quarry_feature/ore_quartz,
	)
	feature_count_min = 3
	feature_count_max = 5


// Shallows: depth 1-5. Loose rock, common ores, scattered ambient
// features, no real hostiles. The intro band — players learn the
// controls here.
/datum/quarry_layer_config/shallows
	wall_density = 45
	smoothing_iterations = 4
	wall_turf = /turf/simulated/mineral/cave/quarry/shallows
	ore_density = 8
	decoration_density = 1
	biome_roster = list(
		/datum/quarry_biome/stone_caverns = 50,
		/datum/quarry_biome/damp_tunnels = 25,
		/datum/quarry_biome/mushroom_grottos = 25,
	)
	mob_count = 2500
	// Shallows: small fauna with hostile AI. Lizardmen patrol, scrubbles
	// skitter underfoot, wolves prowl in packs, dinos snap. Nothing
	// over ~100 HP — players are still learning the loop here.
	default_mob_table = list(
		/mob/living/simple_mob/vore/aggressive/lizardman = 40,
		/mob/living/simple_mob/vore/scrubble = 30,
		/mob/living/simple_mob/vore/wolf = 20,
		/mob/living/simple_mob/vore/aggressive/dino = 20,
		/mob/living/simple_mob/vore/aggressive/rat = 15,
		/mob/living/simple_mob/vore/bat = 15,
	)
	depth_weights = list(
		"1-5" = 100,
	)
	feature_pool = list(
		// Common-tier ores
		/datum/quarry_feature/ore_hematite,
		/datum/quarry_feature/ore_copper,
		/datum/quarry_feature/ore_tin,
		/datum/quarry_feature/ore_carbon,
		/datum/quarry_feature/ore_quartz,
		/datum/quarry_feature/ore_bauxite,
		// Engineering chem (entry-tier)
		/datum/quarry_feature/chem_sulfuric_pool,
		/datum/quarry_feature/chem_saltpeter,
		/datum/quarry_feature/chem_water_pool,
		/datum/quarry_feature/chem_carbon_pool,
		/datum/quarry_feature/chem_halite_pool,
		// Light pests
		/datum/quarry_feature/mouse_swarm,
		/datum/quarry_feature/rat_nest,
		/datum/quarry_feature/bat_roost,
		// Exploration
		/datum/quarry_feature/unmapped_passages,
		// Science: exotic-material veins
		/datum/quarry_feature/exotic_vein,
	)
	feature_count_min = 5
	feature_count_max = 8


// Midmines: depth 6-10. Denser stone, mid-tier ores, a few rats and
// bats. The middle of the quarry — serious work but survivable.
/datum/quarry_layer_config/midmines
	wall_density = 55
	smoothing_iterations = 4
	wall_turf = /turf/simulated/mineral/cave/quarry/midmines
	ore_density = 10
	decoration_density = 2
	biome_roster = list(
		/datum/quarry_biome/stone_caverns = 35,
		/datum/quarry_biome/crystal_pockets = 30,
		/datum/quarry_biome/damp_tunnels = 15,
		/datum/quarry_biome/sulfur_caves = 10,
		/datum/quarry_biome/frozen_hollows = 10,
	)
	mob_count = 3000
	// Midmines: mid-tier hostiles. Tunneler spiders show up, xenos
	// patrol packs, chungus rumble through the corridors, and the
	// occasional panther stalks the deeper rooms. 100-200 HP range.
	default_mob_table = list(
		/mob/living/simple_mob/animal/giant_spider/tunneler/cave = 30,
		/mob/living/simple_mob/vore/xeno_defanged = 25,
		/mob/living/simple_mob/vore/aggressive/chungus = 20,
		/mob/living/simple_mob/vore/aggressive/panther = 15,
		/mob/living/simple_mob/vore/aggressive/corrupthound = 15,
		/mob/living/simple_mob/vore/aggressive/lizardman = 15,
	)
	depth_weights = list(
		"6-10" = 100,
	)
	feature_pool = list(
		// Holdover common ores
		/datum/quarry_feature/ore_hematite,
		/datum/quarry_feature/ore_copper,
		// Mid-tier ores
		/datum/quarry_feature/ore_silver,
		/datum/quarry_feature/ore_gold,
		/datum/quarry_feature/ore_uranium,
		/datum/quarry_feature/ore_bauxite,
		// Engineering chem (mid-tier)
		/datum/quarry_feature/chem_sulfuric_pool,
		/datum/quarry_feature/chem_saltpeter,
		/datum/quarry_feature/chem_lithium,
		/datum/quarry_feature/chem_copper_sulfate,
		/datum/quarry_feature/chem_water_pool,
		/datum/quarry_feature/chem_oxygen_pool,
		/datum/quarry_feature/chem_nitrogen_pool,
		/datum/quarry_feature/chem_carbon_pool,
		/datum/quarry_feature/chem_halite_pool,
		// Hostiles (light combat)
		/datum/quarry_feature/rat_nest,
		/datum/quarry_feature/bat_roost,
		/datum/quarry_feature/spider_nest,
		// Exploration
		/datum/quarry_feature/unmapped_passages,
		// Science: exotic-material veins
		/datum/quarry_feature/exotic_vein,
	)
	feature_count_min = 6
	feature_count_max = 9


// Deeps: depth 11-15. Very dense rock, rare and high-value ores,
// real hostile mobs. Bring a weapon.
/datum/quarry_layer_config/deeps
	wall_density = 62
	smoothing_iterations = 5
	wall_turf = /turf/simulated/mineral/cave/quarry/deeps
	ore_density = 14
	decoration_density = 2
	biome_roster = list(
		/datum/quarry_biome/crystal_pockets = 25,
		/datum/quarry_biome/sulfur_caves = 25,
		/datum/quarry_biome/phoron_geology = 20,
		/datum/quarry_biome/magma_vents = 15,
		/datum/quarry_biome/bone_yards = 15,
	)
	mob_count = 3500
	// Deeps: dangerous fauna. Raptors hunt in flocks, direwolves
	// pack-charge, stalkers pick off stragglers, deathclaws guard the
	// rare seams. 200-500 HP, real combat encounters.
	default_mob_table = list(
		/mob/living/simple_mob/animal/giant_spider/tunneler/cave = 30,
		/mob/living/simple_mob/vore/raptor = 25,
		/mob/living/simple_mob/vore/wolf/direwolf = 20,
		/mob/living/simple_mob/vore/aggressive/deathclaw = 15,
		/mob/living/simple_mob/vore/oregrub = 15,
		/mob/living/simple_mob/vore/stalker = 15,
		/mob/living/simple_mob/vore/aggressive/panther = 10,
	)
	depth_weights = list(
		"11-15" = 100,
	)
	feature_pool = list(
		// High-value ores
		/datum/quarry_feature/ore_silver,
		/datum/quarry_feature/ore_gold,
		/datum/quarry_feature/ore_uranium,
		/datum/quarry_feature/ore_phoron,
		/datum/quarry_feature/ore_diamond,
		/datum/quarry_feature/ore_verdantium,
		// Engineering chem (rarer)
		/datum/quarry_feature/chem_lithium,
		/datum/quarry_feature/chem_copper_sulfate,
		/datum/quarry_feature/chem_phoron_gas,
		/datum/quarry_feature/chem_oxygen_pool,
		/datum/quarry_feature/chem_nitrogen_pool,
		/datum/quarry_feature/chem_hydrogen_pool,
		/datum/quarry_feature/chem_chlorine_pool,
		// Real hostiles
		/datum/quarry_feature/spider_nest,
		/datum/quarry_feature/oregrub_infestation,
		/datum/quarry_feature/stalker_pack,
		/datum/quarry_feature/rat_nest,
		// Exploration
		/datum/quarry_feature/unmapped_passages,
		// Science: exotic-material veins
		/datum/quarry_feature/exotic_vein,
	)
	feature_count_min = 6
	feature_count_max = 9


// Abyss: depth 16-20. Tighter caves, denser ore concentrations,
// significantly more hostile spawns. Pre-core danger band.
/datum/quarry_layer_config/abyss
	wall_density = 66
	smoothing_iterations = 5
	wall_turf = /turf/simulated/mineral/cave/quarry/abyss
	ore_density = 16
	decoration_density = 2
	biome_roster = list(
		/datum/quarry_biome/magma_vents = 25,
		/datum/quarry_biome/phoron_geology = 25,
		/datum/quarry_biome/bone_yards = 20,
		/datum/quarry_biome/sulfur_caves = 15,
		/datum/quarry_biome/crystal_pockets = 15,
	)
	mob_count = 4000
	// Abyss: brutal. Greatwolves and gryphons patrol, cryptdrakes
	// guard ore veins, raptor flocks ambush. 500-1000 HP boss-tier
	// fauna mixed with tougher mid-tier. Don't go alone.
	default_mob_table = list(
		/mob/living/simple_mob/vore/greatwolf = 30,
		/mob/living/simple_mob/vore/gryphon = 25,
		/mob/living/simple_mob/vore/raptor = 25,
		/mob/living/simple_mob/vore/aggressive/deathclaw = 20,
		/mob/living/simple_mob/vore/stalker = 15,
		/mob/living/simple_mob/vore/cryptdrake = 5,
	)
	depth_weights = list(
		"16-20" = 100,
	)
	feature_pool = list(
		// Rare ores
		/datum/quarry_feature/ore_phoron,
		/datum/quarry_feature/ore_diamond,
		/datum/quarry_feature/ore_verdantium,
		/datum/quarry_feature/ore_painite,
		/datum/quarry_feature/ore_void_opal,
		/datum/quarry_feature/ore_marble,
		// Engineering chem (heaviest)
		/datum/quarry_feature/chem_phoron_gas,
		/datum/quarry_feature/chem_copper_sulfate,
		/datum/quarry_feature/chem_hydrogen_pool,
		/datum/quarry_feature/chem_chlorine_pool,
		// Brutal hostiles
		/datum/quarry_feature/spider_nest,
		/datum/quarry_feature/oregrub_infestation,
		/datum/quarry_feature/stalker_pack,
		// Exploration
		/datum/quarry_feature/unmapped_passages,
		// Science: exotic-material veins
		/datum/quarry_feature/exotic_vein,
	)
	feature_count_min = 7
	feature_count_max = 10


// Core: depth 21-25. The bottom of the quarry. Maximum ore values,
// maximum mob density, hardest hostiles. End-tier rewards.
/datum/quarry_layer_config/core
	wall_density = 70
	smoothing_iterations = 6
	wall_turf = /turf/simulated/mineral/cave/quarry/core
	ore_density = 18
	decoration_density = 1
	biome_roster = list(
		/datum/quarry_biome/shattered_core = 50,
		/datum/quarry_biome/magma_vents = 20,
		/datum/quarry_biome/phoron_geology = 15,
		/datum/quarry_biome/bone_yards = 15,
	)
	mob_count = 4500
	// Core: end-tier. Cryptdrakes everywhere, deathclaw dens, big
	// dragons, gryphon flocks. 800+ HP boss monsters mixed in.
	// Going down here is supposed to feel like a raid.
	default_mob_table = list(
		/mob/living/simple_mob/vore/cryptdrake = 25,
		/mob/living/simple_mob/vore/gryphon = 25,
		/mob/living/simple_mob/vore/greatwolf = 20,
		/mob/living/simple_mob/vore/aggressive/deathclaw/den = 15,
		/mob/living/simple_mob/vore/bigdragon = 10,
		/mob/living/simple_mob/vore/raptor = 15,
	)
	depth_weights = list(
		"21-25" = 100,
	)
	feature_pool = list(
		// Top-tier ores
		/datum/quarry_feature/ore_diamond,
		/datum/quarry_feature/ore_verdantium,
		/datum/quarry_feature/ore_painite,
		/datum/quarry_feature/ore_void_opal,
		/datum/quarry_feature/ore_marble,
		/datum/quarry_feature/ore_phoron,
		// Heaviest hostiles
		/datum/quarry_feature/spider_nest,
		/datum/quarry_feature/oregrub_infestation,
		/datum/quarry_feature/stalker_pack,
		// Exploration
		/datum/quarry_feature/unmapped_passages,
		// Science: exotic-material veins
		/datum/quarry_feature/exotic_vein,
	)
	feature_count_min = 7
	feature_count_max = 10
