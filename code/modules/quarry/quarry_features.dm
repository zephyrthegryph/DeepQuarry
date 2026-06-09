// Concrete quarry layer features.
//
// Two broad kinds:
//   - Resource features (ore_*): add an ore to the table and a
//     delivery goal for that ore.
//   - Obstacle features (nest_*, infestation_*): add a hostile mob to
//     the table, bump the mob spawn count, and add a kill goal.
//   - Ambient features (overgrowth_*, debris_*): add decorations and
//     usually a clearance goal.
//
// Goals are built from a small helper so authoring stays declarative.

// --- helpers ------------------------------------------------------------

// Goal factories. Event-driven: each goal counts on the work event,
// not on the resulting item arriving at the surface bay.

// Mining quota: tick when a wall of the given mineral is drilled.
// `mineral_name` matches the /datum/ore's `name` field (the string
// constant, e.g. ORE_PHORON).
/proc/_quarry_make_mine_node_goal(datum/quarry_layer/L, goal_name, mineral_name, target, description)
	var/datum/quarry_goal/mine_node/G = new
	G.owner_layer = L
	G.name = goal_name
	G.description = description
	G.mineral_name = mineral_name
	G.target = target
	return G

// Pump quota: tick by units pumped of the given reagent ID. Units
// accumulate per pump tick; layer config tunes target accordingly.
/proc/_quarry_make_pump_reagent_goal(datum/quarry_layer/L, goal_name, reagent_id, target_units, description)
	var/datum/quarry_goal/pump_reagent/G = new
	G.owner_layer = L
	G.name = goal_name
	G.description = description
	G.reagent_id = reagent_id
	G.target = target_units
	return G

// Gas vent quota: tick by moles released from mined gas pockets.
/proc/_quarry_make_vent_gas_goal(datum/quarry_layer/L, goal_name, gas_id, target_moles, description)
	var/datum/quarry_goal/vent_gas/G = new
	G.owner_layer = L
	G.name = goal_name
	G.description = description
	G.gas_id = gas_id
	G.target = target_moles
	return G

// Combat: tick on mob death.
/proc/_quarry_make_kill_mob_goal(datum/quarry_layer/L, goal_name, mob_path, target, description)
	var/datum/quarry_goal/kill_mob/G = new
	G.owner_layer = L
	G.name = goal_name
	G.description = description
	G.mob_type = mob_path
	G.target = target
	return G



// === RESOURCE FEATURES ===============================================
//
// Each adds one ore type to the layer and a delivery quota goal for it.

/datum/quarry_feature/ore_hematite
	name = "Hematite Vein"
	description = "A streak of iron-rich stone runs through this layer."
	ore_contributions = list(ORE_HEMATITE = 80)

/datum/quarry_feature/ore_hematite/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Hematite Vein Worked", ORE_HEMATITE, 15,
		"Mine 15 hematite walls on this layer."))


/datum/quarry_feature/ore_copper
	name = "Copper Deposit"
	description = "Greenish veining marks the copper here."
	ore_contributions = list(ORE_COPPER = 70)

/datum/quarry_feature/ore_copper/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Copper Vein Worked", ORE_COPPER, 12,
		"Mine 12 copper walls on this layer."))


/datum/quarry_feature/ore_tin
	name = "Tin Deposit"
	description = "Soft, pale ore — easy work."
	ore_contributions = list(ORE_TIN = 60)

/datum/quarry_feature/ore_tin/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Tin Vein Worked", ORE_TIN, 12,
		"Mine 12 tin walls on this layer."))


/datum/quarry_feature/ore_carbon
	name = "Coal Seam"
	description = "Brittle black layers, easy to mine."
	ore_contributions = list(ORE_CARBON = 70)

/datum/quarry_feature/ore_carbon/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Carbon Seam Worked", ORE_CARBON, 12,
		"Mine 12 coal walls on this layer."))


/datum/quarry_feature/ore_quartz
	name = "Quartz Cluster"
	description = "Crystalline white deposits sparkle in the rock."
	ore_contributions = list(ORE_QUARTZ = 50)

/datum/quarry_feature/ore_quartz/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Quartz Cluster Worked", ORE_QUARTZ, 8,
		"Mine 8 quartz walls on this layer."))


/datum/quarry_feature/ore_bauxite
	name = "Bauxite Deposit"
	description = "Aluminum-rich red ore."
	ore_contributions = list(ORE_BAUXITE = 45)

/datum/quarry_feature/ore_bauxite/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Bauxite Deposit Worked", ORE_BAUXITE, 8,
		"Mine 8 bauxite walls on this layer."))


/datum/quarry_feature/ore_silver
	name = "Silver Lode"
	description = "Bright veining in dark rock — silver-bearing."
	ore_contributions = list(ORE_SILVER = 50)

/datum/quarry_feature/ore_silver/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Silver Lode Worked", ORE_SILVER, 8,
		"Mine 8 silver walls on this layer."))


/datum/quarry_feature/ore_gold
	name = "Gold Pocket"
	description = "Concentrated gold deposits — a payday if you can carry them up."
	ore_contributions = list(ORE_GOLD = 40)

/datum/quarry_feature/ore_gold/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Gold Pocket Worked", ORE_GOLD, 6,
		"Mine 6 gold walls on this layer."))


/datum/quarry_feature/ore_uranium
	name = "Pitchblende Streak"
	description = "Radioactive uranium-bearing ore. Carry with care."
	ore_contributions = list(ORE_URANIUM = 40)

/datum/quarry_feature/ore_uranium/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Pitchblende Streak Worked", ORE_URANIUM, 6,
		"Mine 6 pitchblende walls on this layer."))


/datum/quarry_feature/ore_phoron
	name = "Phoron Vein"
	description = "Volatile purple crystals — phoron in raw form."
	ore_contributions = list(ORE_PHORON = 35)

/datum/quarry_feature/ore_phoron/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Phoron Vein Worked", ORE_PHORON, 5,
		"Mine 5 phoron walls on this layer."))


/datum/quarry_feature/ore_diamond
	name = "Diamond Pocket"
	description = "Diamond crystals embedded in the cave wall."
	ore_contributions = list(ORE_DIAMOND = 25)

/datum/quarry_feature/ore_diamond/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Diamond Pocket Worked", ORE_DIAMOND, 4,
		"Mine 4 diamond walls on this layer."))


/datum/quarry_feature/ore_verdantium
	name = "Verdantium Bloom"
	description = "Strange green ore that hums faintly when struck."
	ore_contributions = list(ORE_VERDANTIUM = 20)

/datum/quarry_feature/ore_verdantium/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Verdantium Bloom Worked", ORE_VERDANTIUM, 4,
		"Mine 4 verdantium walls on this layer."))


/datum/quarry_feature/ore_painite
	name = "Painite Concentration"
	description = "Deep crimson crystals — rare and valuable."
	ore_contributions = list(ORE_PAINITE = 15)

/datum/quarry_feature/ore_painite/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Painite Concentration Worked", ORE_PAINITE, 3,
		"Mine 3 painite walls on this layer."))


/datum/quarry_feature/ore_void_opal
	name = "Void Opal Seam"
	description = "Iridescent black opal threads through the rock."
	ore_contributions = list(ORE_VOPAL = 12)

/datum/quarry_feature/ore_void_opal/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Void Opal Seam Worked", ORE_VOPAL, 3,
		"Mine 3 void opal walls on this layer."))


/datum/quarry_feature/ore_marble
	name = "Marble Strata"
	description = "Banded marble — quarried for sculpture and trim."
	ore_contributions = list(ORE_MARBLE = 30)

/datum/quarry_feature/ore_marble/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Marble Strata Worked", ORE_MARBLE, 5,
		"Mine 5 marble walls on this layer."))


// === OBSTACLE FEATURES ===============================================
//
// Each adds a hostile mob to the spawn table, increases the mob count,
// and adds a kill quota goal targeting that mob.

/datum/quarry_feature/rat_nest
	name = "Rat Nest"
	description = "Disturbed nesting site; aggressive rats prowl."
	mob_contributions = list(/mob/living/simple_mob/vore/aggressive/rat = 60)
	extra_mob_spawns = 3

/datum/quarry_feature/rat_nest/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_kill_mob_goal(L, "Cull the Rats", /mob/living/simple_mob/vore/aggressive/rat, 4,
		"Kill 4 aggressive rats on this layer."))


/datum/quarry_feature/bat_roost
	name = "Bat Roost"
	description = "Cave bats roost in the upper passages."
	mob_contributions = list(/mob/living/simple_mob/vore/bat = 50)
	extra_mob_spawns = 3

/datum/quarry_feature/bat_roost/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_kill_mob_goal(L, "Cull the Bats", /mob/living/simple_mob/vore/bat, 4,
		"Kill 4 cave bats on this layer."))


/datum/quarry_feature/spider_nest
	name = "Tunneler Spider Nest"
	description = "Web-choked passages; tunneler spiders patrol them."
	mob_contributions = list(/mob/living/simple_mob/animal/giant_spider/tunneler/cave = 50)
	extra_mob_spawns = 3

/datum/quarry_feature/spider_nest/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_kill_mob_goal(L, "Clear the Nest", /mob/living/simple_mob/animal/giant_spider/tunneler/cave, 4,
		"Kill 4 tunneler spiders on this layer."))


/datum/quarry_feature/oregrub_infestation
	name = "Oregrub Infestation"
	description = "Mineral-eating grubs swarm — they'll chew through ore caches."
	mob_contributions = list(/mob/living/simple_mob/vore/oregrub = 50)
	extra_mob_spawns = 4

/datum/quarry_feature/oregrub_infestation/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_kill_mob_goal(L, "Exterminate Oregrubs", /mob/living/simple_mob/vore/oregrub, 6,
		"Kill 6 oregrubs on this layer."))


/datum/quarry_feature/stalker_pack
	name = "Stalker Pack"
	description = "Apex predators have moved in."
	mob_contributions = list(/mob/living/simple_mob/vore/stalker = 40)
	extra_mob_spawns = 2

/datum/quarry_feature/stalker_pack/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_kill_mob_goal(L, "Hunt the Stalkers", /mob/living/simple_mob/vore/stalker, 3,
		"Kill 3 stalkers on this layer."))


/datum/quarry_feature/mouse_swarm
	name = "Mouse Warren"
	description = "Tiny rodents underfoot — mostly harmless."
	mob_contributions = list(/mob/living/simple_mob/animal/passive/mouse/rat = 80)
	extra_mob_spawns = 4
// No kill goal — passive critters; they're flavour, not threat.


// === CHEMISTRY FEATURES ==============================================
//
// Engineering-extractable raw chemistry. Three forms:
//   solid   — drops a stackable raw_chem item; goal counts items
//   liquid  — drops a sealed flask of reagent; goal counts flasks
//   gas     — venting wall releases gas into the local atmosphere;
//             goal counts moles of that gas in tanks in the bay
// All forms ride the same ore-placement pipeline as regular ore
// features — only the dropped item type differs.

/datum/quarry_feature/chem_sulfuric_pool
	name = "Sulfuric Pool"
	description = "A pale-yellow pool of mineralised water. Bring a fluid pump and a battery."
	placement_type = "pool"
	pool_turf = /turf/simulated/floor/water/quarry_sulfuric
	vein_count = 2
	vein_size = 7

/datum/quarry_feature/chem_sulfuric_pool/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_pump_reagent_goal(L, "Sulfuric Acid Extraction", REAGENT_ID_SACID, 60,
		"Pump 60 units of sulfuric acid from the pool."))


/datum/quarry_feature/chem_saltpeter
	name = "Saltpeter Bed"
	description = "Pale, gritty deposits — potassium nitrate, useful as an oxidiser."
	ore_contributions = list(ORE_RAWCHEM_SALTPETER = 55)

/datum/quarry_feature/chem_saltpeter/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Saltpeter Bed Worked", ORE_RAWCHEM_SALTPETER, 10,
		"Mine 10 saltpeter walls on this layer."))


/datum/quarry_feature/chem_lithium
	name = "Lithium Pocket"
	description = "Soft silver nodules — lithium-bearing rock."
	ore_contributions = list(ORE_RAWCHEM_LITHIUM = 40)

/datum/quarry_feature/chem_lithium/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Lithium Pocket Worked", ORE_RAWCHEM_LITHIUM, 8,
		"Mine 8 lithium walls on this layer."))


/datum/quarry_feature/chem_copper_sulfate
	name = "Copper Sulfate Crystals"
	description = "Bright blue chalcanthite crystals line the rock."
	ore_contributions = list(ORE_RAWCHEM_COPPER_SULFATE = 35)

/datum/quarry_feature/chem_copper_sulfate/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_mine_node_goal(L, "Copper Sulfate Vein Worked", ORE_RAWCHEM_COPPER_SULFATE, 6,
		"Mine 6 copper sulfate walls on this layer."))


/datum/quarry_feature/chem_water_pool
	name = "Freshwater Pool"
	description = "Cold drillwater seeps up from the rock. Bring a fluid pump and a battery."
	placement_type = "pool"
	pool_turf = /turf/simulated/floor/water/quarry_freshwater
	vein_count = 2
	vein_size = 8

/datum/quarry_feature/chem_water_pool/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_pump_reagent_goal(L, "Drillwater Extraction", REAGENT_ID_WATER, 100,
		"Pump 100 units of drillwater from the pool."))


/datum/quarry_feature/chem_phoron_gas
	name = "Pressurised Phoron Pocket"
	description = "Mining these walls releases volatile phoron gas. Bring a tank."
	ore_contributions = list(ORE_RAWCHEM_PHORON_GAS = 25)

/datum/quarry_feature/chem_phoron_gas/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_vent_gas_goal(L, "Phoron Gas Capture", GAS_PHORON, 30,
		"Mine 30 moles of phoron gas from the pockets."))


// Pool-pump features for chemistry staples. Each places a small
// cluster of /turf/simulated/floor/gas_crack/* (upstream) so the
// existing /obj/machinery/pump pulls the reagent directly — no
// tank/distillery loop required. Players bring a pump down, anchor
// it on the cluster, attach a beaker. Goals count reagent units
// delivered to the bay.

/datum/quarry_feature/chem_oxygen_pool
	name = "Oxygen-Rich Seep"
	description = "A cracked patch of rock vents cold oxygen-rich gas."
	placement_type = "pool"
	pool_turf = /turf/simulated/floor/gas_crack/oxygen/quarry
	vein_count = 2
	vein_size = 5

/datum/quarry_feature/chem_oxygen_pool/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_pump_reagent_goal(L, "Oxygen Extraction", REAGENT_ID_OXYGEN, 40,
		"Pump 40 units of oxygen from the seep."))


/datum/quarry_feature/chem_nitrogen_pool
	name = "Nitrogen Seep"
	description = "Inert nitrogen wells up from a fissure in the rock."
	placement_type = "pool"
	pool_turf = /turf/simulated/floor/gas_crack/nitrogen/quarry
	vein_count = 2
	vein_size = 5

/datum/quarry_feature/chem_nitrogen_pool/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_pump_reagent_goal(L, "Nitrogen Extraction", REAGENT_ID_NITROGEN, 40,
		"Pump 40 units of nitrogen from the seep."))


/datum/quarry_feature/chem_hydrogen_pool
	name = "Hydrogen Seep"
	description = "A dry fissure that hisses faintly — hydrogen gas wells up."
	placement_type = "pool"
	pool_turf = /turf/simulated/floor/gas_crack/hydrogen
	vein_count = 2
	vein_size = 4

/datum/quarry_feature/chem_hydrogen_pool/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_pump_reagent_goal(L, "Hydrogen Extraction", REAGENT_ID_HYDROGEN, 30,
		"Pump 30 units of hydrogen from the seep."))


/datum/quarry_feature/chem_carbon_pool
	name = "Carbon Vent"
	description = "Warm carbon dioxide breathes from a crack in the floor."
	placement_type = "pool"
	pool_turf = /turf/simulated/floor/gas_crack/carbon/quarry
	vein_count = 2
	vein_size = 5

/datum/quarry_feature/chem_carbon_pool/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_pump_reagent_goal(L, "Carbon Extraction", REAGENT_ID_CARBON, 40,
		"Pump 40 units of carbon from the vent."))


/datum/quarry_feature/chem_halite_pool
	name = "Halite Salt Bed"
	description = "Pale crystalline salt encrusts a wide crack — sodium chloride."
	placement_type = "pool"
	pool_turf = /turf/simulated/floor/gas_crack/halite
	vein_count = 3
	vein_size = 5

/datum/quarry_feature/chem_halite_pool/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_pump_reagent_goal(L, "Halite Extraction", REAGENT_ID_SODIUMCHLORIDE, 50,
		"Pump 50 units of table salt from the bed."))


/datum/quarry_feature/chem_chlorine_pool
	name = "Chlorine Seep"
	description = "Yellow-green stained rock leaks pungent chlorine gas. Don't breathe deep."
	placement_type = "pool"
	pool_turf = /turf/simulated/floor/gas_crack/chlorine
	vein_count = 2
	vein_size = 4

/datum/quarry_feature/chem_chlorine_pool/build_goals(datum/quarry_layer/L)
	return list(_quarry_make_pump_reagent_goal(L, "Chlorine Extraction", REAGENT_ID_CHLORINE, 30,
		"Pump 30 units of chlorine from the seep."))


// === EXPLORATION FEATURE =============================================
//
// One generic exploration goal that any layer config can include.

/datum/quarry_feature/unmapped_passages
	name = "Unmapped Passages"
	description = "The cave layout is unfamiliar; cartography would help."

/datum/quarry_feature/unmapped_passages/build_goals(datum/quarry_layer/L)
	var/datum/quarry_goal/map_tiles/G = new
	G.owner_layer = L
	G.name = "Survey the Layer"
	G.description = "Walk 120 distinct floor tiles to map the cave."
	G.target = 120
	return list(G)
